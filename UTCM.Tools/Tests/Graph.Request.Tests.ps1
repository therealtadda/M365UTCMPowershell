Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe 'Graph URL trust' {
    BeforeAll {
        Mock -ModuleName UTCM.Tools Get-MgContext { [pscustomobject]@{ Environment = 'Global' } }
    }

    It 'Resolves root-relative and absolute HTTPS Graph URLs without losing query parameters' {
        InModuleScope UTCM.Tools {
            Resolve-UTCMGraphUri '/v1.0/admin/configurationManagement/configurationDrifts?$skiptoken=a%2Bb' |
                Should -Be 'https://graph.microsoft.com/v1.0/admin/configurationManagement/configurationDrifts?$skiptoken=a%2Bb'
            Resolve-UTCMGraphUri 'https://graph.microsoft.com/v1.0/test' |
                Should -Be 'https://graph.microsoft.com/v1.0/test'
        }
    }

    It 'Rejects unsafe URLs: <Label>' -ForEach @(
        @{ Label = 'HTTP'; Uri = 'http://graph.microsoft.com/v1.0/test' }
        @{ Label = 'external host'; Uri = 'https://example.invalid/file' }
        @{ Label = 'host suffix'; Uri = 'https://graph.microsoft.com.example.invalid/file' }
        @{ Label = 'credentials'; Uri = 'https://user:password@graph.microsoft.com/file' }
        @{ Label = 'fragment'; Uri = 'https://graph.microsoft.com/file#fragment' }
        @{ Label = 'port'; Uri = 'https://graph.microsoft.com:8443/file' }
        @{ Label = 'network path'; Uri = '//example.invalid/file' }
        @{ Label = 'backslash'; Uri = '/\example.invalid/file' }
        @{ Label = 'file scheme'; Uri = 'file:///C:/test.json' }
        @{ Label = 'ambiguous relative path'; Uri = 'v1.0/test' }
        @{ Label = 'control characters'; Uri = "/v1.0/test`r`nheader:value" }
    ) {
        InModuleScope UTCM.Tools -Parameters @{ Candidate = $Uri } {
            { Resolve-UTCMGraphUri $Candidate } | Should -Throw
        }
    }

    It 'Uses the connected environment instead of a hard-coded global host' {
        Mock -ModuleName UTCM.Tools Get-MgContext { [pscustomobject]@{ Environment = 'USGov' } }
        InModuleScope UTCM.Tools {
            Resolve-UTCMGraphUri '/v1.0/test' | Should -Be 'https://graph.microsoft.us/v1.0/test'
            { Resolve-UTCMGraphUri 'https://graph.microsoft.com/v1.0/test' } | Should -Throw '*connected HTTPS Graph endpoint*'
        }
    }
}

Describe 'Graph retries and downloads' {
    BeforeAll {
        Mock -ModuleName UTCM.Tools Get-MgContext { $null }
        Mock -ModuleName UTCM.Tools Ensure-GraphConnection {}
        Mock -ModuleName UTCM.Tools Write-Log {}
        Mock -ModuleName UTCM.Tools Start-Sleep {}
    }

    It 'Throws after the last attempt without sleeping again for HTTP <Status>' -ForEach @(
        @{ Status = 429 }, @{ Status = 503 }, @{ Status = 500 }
    ) {
        Mock -ModuleName UTCM.Tools Invoke-MgGraphRequest {
            $exception = [Exception]::new('Service temporarily unavailable')
            $exception | Add-Member ResponseStatusCode $Status
            throw $exception
        }
        InModuleScope UTCM.Tools {
            { Invoke-GraphRequestWithRetry -Method GET -Uri '/v1.0/test' -MaxRetries 3 } |
                Should -Throw '*failed after 3 attempts*'
        }
        Should -Invoke -ModuleName UTCM.Tools Invoke-MgGraphRequest -Times 3 -Exactly
        Should -Invoke -ModuleName UTCM.Tools Start-Sleep -Times 2 -Exactly
    }

    It 'Does not retry a nontransient client error' {
        Mock -ModuleName UTCM.Tools Invoke-MgGraphRequest {
            $exception = [Exception]::new('Not authorized')
            $exception | Add-Member ResponseStatusCode 403
            throw $exception
        }
        InModuleScope UTCM.Tools {
            { Invoke-GraphRequestWithRetry -Method GET -Uri '/v1.0/test' } | Should -Throw '*HTTP 403*'
        }
        Should -Invoke -ModuleName UTCM.Tools Invoke-MgGraphRequest -Times 1 -Exactly
        Should -Invoke -ModuleName UTCM.Tools Start-Sleep -Times 0 -Exactly
    }

    It 'Returns the successful response after a transient failure' {
        $script:recoveryAttempts = 0
        Mock -ModuleName UTCM.Tools Invoke-MgGraphRequest {
            $script:recoveryAttempts++
            if ($script:recoveryAttempts -eq 1) {
                $exception = [Exception]::new('Throttled')
                $exception | Add-Member ResponseStatusCode 429
                throw $exception
            }
            @{ value = @('recovered') }
        }
        InModuleScope UTCM.Tools {
            (Invoke-GraphRequestWithRetry -Method GET -Uri '/v1.0/test').value | Should -Be @('recovered')
        }
        Should -Invoke -ModuleName UTCM.Tools Invoke-MgGraphRequest -Times 2 -Exactly
        Should -Invoke -ModuleName UTCM.Tools Start-Sleep -Times 1 -Exactly
    }

    It 'Does not echo sensitive query parameters in its own error context' {
        Mock -ModuleName UTCM.Tools Invoke-MgGraphRequest {
            $exception = [Exception]::new('Denied')
            $exception | Add-Member ResponseStatusCode 403
            throw $exception
        }
        InModuleScope UTCM.Tools {
            try {
                Invoke-GraphRequestWithRetry -Method GET -Uri '/v1.0/test?token=sensitive-query-value'
            } catch {
                $_.Exception.Message | Should -Not -Match 'sensitive-query-value'
                $_.Exception.Message | Should -Match 'HTTP 403'
                return
            }
            throw 'Expected an error'
        }
    }

    It 'Passes hashtable bodies, headers, output paths, and terminating error behavior to the SDK' {
        Mock -ModuleName UTCM.Tools Invoke-MgGraphRequest {}
        InModuleScope UTCM.Tools {
            Invoke-GraphRequestWithRetry -Method POST -Uri '/v1.0/test' -Body @{ resources = @('x') } `
                -Headers @{ Prefer = 'include-unknown-enum-members' } -OutputFilePath 'test.json'
        }
        Should -Invoke -ModuleName UTCM.Tools Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Body -is [hashtable] -and $Body.resources[0] -eq 'x' -and
            $Headers.Prefer -eq 'include-unknown-enum-members' -and
            $OutputFilePath -eq 'test.json' -and $ErrorAction -eq 'Stop'
        }
    }

    It 'Rejects a zero-attempt configuration' {
        InModuleScope UTCM.Tools {
            { Invoke-GraphRequestWithRetry -Method GET -Uri '/v1.0/test' -MaxRetries 0 } | Should -Throw
        }
    }

    It 'Propagates exhausted retries through <Command> instead of returning an empty result' -ForEach @(
        @{ Command = 'Get-UTCMDrift' }
        @{ Command = 'Get-UTCMMonitor' }
        @{ Command = 'Get-UTCMMonitoringResult' }
        @{ Command = 'Get-UTCMAvailableSnapshot' }
    ) {
        Mock -ModuleName UTCM.Tools Invoke-MgGraphRequest {
            $exception = [Exception]::new('Unavailable')
            $exception | Add-Member ResponseStatusCode 503
            throw $exception
        }
        { & $Command } | Should -Throw '*failed after 5 attempts*'
        Should -Invoke -ModuleName UTCM.Tools Invoke-MgGraphRequest -Times 5 -Exactly
    }

    It 'Rejects an external nextLink before a second SDK call' {
        Mock -ModuleName UTCM.Tools Invoke-MgGraphRequest {
            @{ value = @(); '@odata.nextLink' = 'https://example.invalid/collect' }
        }
        { Get-UTCMDrift } | Should -Throw '*External hosts are not supported*'
        Should -Invoke -ModuleName UTCM.Tools Invoke-MgGraphRequest -Times 1 -Exactly
    }

    It 'Downloads Get-UTCMSnapshot artifacts with Graph authentication, not Invoke-WebRequest' {
        Mock -ModuleName UTCM.Tools Invoke-WebRequest { throw 'Unauthenticated download must not be used' }
        Mock -ModuleName UTCM.Tools Invoke-MgGraphRequest {
            param($OutputFilePath)
            if ($OutputFilePath) {
                '{"configurationItems":[{"id":"one","displayName":"Item","type":"microsoft.entra.x","data":{"v":1}}]}' |
                    Set-Content -LiteralPath $OutputFilePath
            } else {
                [pscustomobject]@{
                    id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
                    status = 'succeeded'
                    createdDateTime = [datetime]::UtcNow.ToString('o')
                    completedDateTime = [datetime]::UtcNow.ToString('o')
                    resourceLocation = 'https://graph.microsoft.com/v1.0/test'
                }
            }
        }
        $snapshot = Get-UTCMSnapshot -SnapshotId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -IncludeItems
        $snapshot.configurationItems[0].id | Should -Be 'one'
        Should -Invoke -ModuleName UTCM.Tools Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter { $OutputFilePath }
        Should -Invoke -ModuleName UTCM.Tools Invoke-WebRequest -Times 0 -Exactly
    }

    It 'Rejects an external snapshot URL passed directly to Export before calling the SDK' {
        Mock -ModuleName UTCM.Tools Invoke-MgGraphRequest { throw 'Must not contact external hosts' }
        $snapshot = [pscustomobject]@{
            id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
            status = 'succeeded'; resourceLocation = 'https://example.invalid/snapshot.json'
        }
        { Export-UTCMSnapshot -Snapshot $snapshot -Path $TestDrive -Format JSON } |
            Should -Throw '*External hosts are not supported*'
        Should -Invoke -ModuleName UTCM.Tools Invoke-MgGraphRequest -Times 0 -Exactly
    }

    It 'Rejects an external current-state snapshot URL before downloading' {
        Mock -ModuleName UTCM.Tools Invoke-MgGraphRequest {
            [pscustomobject]@{
                id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
                status = 'succeeded'; resourceLocation = 'https://example.invalid/snapshot.json'
            }
        }
        InModuleScope UTCM.Tools {
            { Get-UTCMCurrentStateSnapshot -Resources @('microsoft.entra.securitydefaults') } |
                Should -Throw '*External hosts are not supported*'
        }
        Should -Invoke -ModuleName UTCM.Tools Invoke-MgGraphRequest -Times 3 -Exactly
        Should -Invoke -ModuleName UTCM.Tools Invoke-MgGraphRequest -Times 0 -Exactly -ParameterFilter { $OutputFilePath }
    }
}
