Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe "Snapshot lifecycle projections and partial diagnostics" {
    BeforeAll {
        Mock -ModuleName UTCM.Tools Ensure-GraphConnection {}
        Mock -ModuleName UTCM.Tools Start-Sleep {}
        Mock -ModuleName UTCM.Tools Write-Log {}
    }

    BeforeEach {
        $script:diagnosticStatus = 'succeeded'
        $script:diagnosticErrors = @()
        $script:diagnosticPayload = '{"resources":[{"resourceType":"microsoft.entra.securitydefaults","displayName":"Synthetic default","properties":{"Id":"synthetic-one","Enabled":true}}]}'
        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry {
            param($Method, $Uri, $Headers, $OutputFilePath)
            if ($Method -eq 'POST') {
                return @{ id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' }
            }
            if ($OutputFilePath) {
                Set-Content -LiteralPath $OutputFilePath -Value $script:diagnosticPayload
                return
            }
            $job = [ordered]@{
                id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
                status = $script:diagnosticStatus
                createdDateTime = [datetime]::UtcNow.ToString('o')
                completedDateTime = [datetime]::UtcNow.ToString('o')
            }
            $decoded = [uri]::UnescapeDataString($Uri)
            if ($decoded -match '\$select=.*resourceLocation') { $job.resourceLocation = 'https://graph.microsoft.com/v1.0/synthetic-snapshot' }
            if ($decoded -match '\$select=.*errorDetails') { $job.errorDetails = $script:diagnosticErrors }
            if ($decoded -match '\$select=.*resources') { $job.resources = @('microsoft.entra.securitydefaults', 'microsoft.exchange.transportrule') }
            if ($job.status -eq 'partiallySuccessful' -and $Headers.Prefer -ne 'include-unknown-enum-members') {
                $job.status = 'unknownFutureValue'
            }
            return $job
        }
    }

    It "Selects resourceLocation, errorDetails and resources before a current-state artifact is used" {
        $snapshot = InModuleScope UTCM.Tools {
            Get-UTCMCurrentStateSnapshot -Resources @('microsoft.entra.securitydefaults', 'microsoft.exchange.transportrule') -PollingIntervalSeconds 5
        }
        $snapshot.configurationItems.Count | Should -Be 1
        $snapshot.configurationItems[0].id | Should -Be 'synthetic-one'
        $snapshot.configurationItems[0].data.Enabled | Should -BeTrue
        $snapshot.rawConfiguration.resources[0].properties.Id | Should -Be 'synthetic-one'
        $snapshot.resources.Count | Should -Be 2
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -Times 2 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and -not $OutputFilePath -and
            [uri]::UnescapeDataString($Uri) -match '\$select=.*resourceLocation.*errorDetails' -and
            [uri]::UnescapeDataString($Uri) -match '\$select=.*resources' -and
            $Headers.Prefer -eq 'include-unknown-enum-members'
        }
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -Times 1 -Exactly -ParameterFilter { $OutputFilePath }
    }

    It "Returns rich partial job metadata and warns instead of logging a green completion" {
        $script:diagnosticStatus = 'partiallySuccessful'
        $script:diagnosticErrors = @('Synthetic resource access denied', "Synthetic extraction line 1`r`nline 2")
        $warnings = @()
        $snapshot = New-UTCMSnapshot -Resources @('microsoft.entra.securitydefaults') -PollingIntervalSeconds 5 `
            -WarningVariable warnings -WarningAction SilentlyContinue
        $snapshot.status | Should -Be 'partiallySuccessful'
        $snapshot.resources.Count | Should -Be 2
        $snapshot.errorDetails | Should -Be $script:diagnosticErrors
        $snapshot.resourceLocation | Should -Be 'https://graph.microsoft.com/v1.0/synthetic-snapshot'
        ($warnings -join ' ') | Should -Match 'extraction is incomplete'
        ($warnings -join ' ') | Should -Match 'Synthetic resource access denied'
        Should -Invoke -ModuleName UTCM.Tools Write-Log -Times 0 -Exactly -ParameterFilter { $Color -eq 'Green' -and $Message -match 'completed' }
        Should -Invoke -ModuleName UTCM.Tools Write-Log -Times 1 -Exactly -ParameterFilter { $Color -eq 'Yellow' -and $Message -match 'completed' }
    }

    It "States explicitly when a partial job has no extraction error details" {
        $script:diagnosticStatus = 'partiallySuccessful'
        $warnings = @()
        New-UTCMSnapshot -Resources @('microsoft.entra.securitydefaults') -PollingIntervalSeconds 5 `
            -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null
        ($warnings -join ' ') | Should -Match 'failure reasons are unavailable'
    }

    It "Retains projected service error details when creation fails" {
        $script:diagnosticStatus = 'failed'
        $script:diagnosticErrors = @('Synthetic extraction denied by workload')
        { New-UTCMSnapshot -Resources @('microsoft.entra.securitydefaults') -PollingIntervalSeconds 5 } |
            Should -Throw '*failed*Synthetic extraction denied by workload*'
    }

    It "Rejects partial current-state extraction before downloading the incomplete artifact" {
        $script:diagnosticStatus = 'partiallySuccessful'
        $script:diagnosticErrors = @('Synthetic extraction denied')
        InModuleScope UTCM.Tools {
            { Get-UTCMCurrentStateSnapshot -Resources @('microsoft.entra.securitydefaults') -PollingIntervalSeconds 5 -WarningAction SilentlyContinue } |
                Should -Throw '*Current-state*partiallySuccessful*Synthetic extraction denied*'
        }
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -Times 0 -Exactly -ParameterFilter { $OutputFilePath }
    }

    It "Revalidates current-state metadata returned with the downloaded items" {
        Mock -ModuleName UTCM.Tools New-UTCMSnapshot {
            [pscustomobject]@{ id='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; status='succeeded' }
        }
        Mock -ModuleName UTCM.Tools Get-UTCMSnapshot {
            [pscustomobject]@{ id='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; status='partiallySuccessful'; errorDetails=@('Synthetic later current-state failure'); configurationItems=@() }
        }
        InModuleScope UTCM.Tools {
            { Get-UTCMCurrentStateSnapshot -Resources @('microsoft.entra.securitydefaults') } |
                Should -Throw '*Synthetic later current-state failure*'
        }
    }

    It "Keeps partial artifacts downloadable with an explicit comparison override" {
        $script:diagnosticStatus = 'partiallySuccessful'
        $script:diagnosticErrors = @('Synthetic extraction denied')
        $snapshot = InModuleScope UTCM.Tools {
            Get-UTCMCurrentStateSnapshot -Resources @('microsoft.entra.securitydefaults') -PollingIntervalSeconds 5 `
                -AllowPartialComparison -WarningAction SilentlyContinue
        }
        $snapshot.status | Should -Be 'partiallySuccessful'
        $snapshot.errorDetails | Should -Contain 'Synthetic extraction denied'
        $snapshot.configurationItems.Count | Should -Be 1
    }

    It "Normalizes an empty successful artifact to an empty array: <Label>" -ForEach @(
        @{ Label = 'resources'; Payload = '{"resources":[]}' }
        @{ Label = 'configurationItems'; Payload = '{"configurationItems":[]}' }
        @{ Label = 'top-level array'; Payload = '[]' }
    ) {
        $script:diagnosticPayload = $Payload
        $snapshot = Get-UTCMSnapshot -SnapshotId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -IncludeItems
        $snapshot.configurationItems.GetType().FullName | Should -Be 'System.Object[]'
        $snapshot.configurationItems.Count | Should -Be 0
        $snapshot.resources.Count | Should -Be 2
    }

    It "Reads failed snapshot diagnostics correctly from a dictionary response" {
        $script:diagnosticStatus = 'failed'
        $script:diagnosticErrors = @('Synthetic dictionary extraction failure')
        { Get-UTCMSnapshot -SnapshotId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -IncludeItems } |
            Should -Throw '*Synthetic dictionary extraction failure*'
    }

    It "Requests evolvable status values on every page of snapshot listings" {
        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry {
            if ($Uri -like '*synthetic-page*') { @{ value = @(); '@odata.nextLink' = $null } }
            else {
                @{ value = @(); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/synthetic-page' }
            }
        }
        Get-UTCMAvailableSnapshot | Out-Null
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -Times 2 -Exactly -ParameterFilter {
            $Headers.Prefer -eq 'include-unknown-enum-members'
        }
    }
}
