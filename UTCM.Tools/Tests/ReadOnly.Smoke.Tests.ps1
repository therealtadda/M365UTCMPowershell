Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe 'Read-only tenant smoke test' {
    BeforeAll {
        $script:smokeScript = Join-Path $PSScriptRoot '..\..\Test-UTCMReadOnly.ps1'
        $script:expectedTenant = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        $script:existingSnapshot = '11111111-2222-3333-4444-555555555555'
    }

    BeforeEach {
        $script:smokeState = @{
            Context = [pscustomobject]@{
                TenantId = $script:expectedTenant
                Environment = 'Global'
                AuthType = 'Delegated'
                Scopes = @('ConfigurationMonitoring.Read.All')
            }
            ArtifactPath = $null
            TenantId = $script:expectedTenant
            SnapshotId = $script:existingSnapshot
        }
        $state = $script:smokeState
        Mock Get-MgContext -MockWith ({ $state.Context }.GetNewClosure())
        Mock -ModuleName UTCM.Tools Get-MgContext -MockWith ({ $state.Context }.GetNewClosure())
        Mock Connect-MgGraph { throw 'Smoke tests must not sign in.' }
        Mock -ModuleName UTCM.Tools Connect-MgGraph { throw 'Smoke tests must not sign in.' }
        Mock Invoke-MgGraphRequest { throw 'Smoke tests must not call a live tenant.' }
        Mock -ModuleName UTCM.Tools Invoke-MgGraphRequest { throw 'Smoke tests must not call a live tenant.' }
        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -MockWith ({
            param($Method, $Uri, $OutputFilePath)
            if ($OutputFilePath) {
                $state.ArtifactPath = $OutputFilePath
                return
            }
            if ($Uri -match "/configurationSnapshotJobs/$($state.SnapshotId)\?") {
                return [pscustomobject]@{
                    id = $state.SnapshotId
                    status = 'succeeded'
                    completedDateTime = [datetimeoffset]::UtcNow.ToString('o')
                    resourceLocation = 'https://graph.microsoft.com/v1.0/test-artifact'
                }
            }
            @{
                value = @([pscustomobject]@{
                    id = 'synthetic-resource'
                    displayName = 'Must not appear in summary'
                    status = 'active'
                    mode = 'monitorOnly'
                    monitorRunFrequencyInHours = 6
                    createdDateTime = '2026-10-20T12:00:00Z'
                    lastModifiedDateTime = '2026-10-20T12:00:00Z'
                    createdBy = 'synthetic'
                    resources = @()
                    tenantId = $state.TenantId
                    monitorId = 'synthetic-monitor'
                    driftsCount = 0
                    runStatus = 'successful'
                    runInitiationDateTime = '2026-10-20T12:00:00Z'
                    runCompletionDateTime = '2026-10-20T12:01:00Z'
                    resourceType = 'microsoft.entra.test'
                    baselineResourceDisplayName = 'Synthetic baseline'
                    firstReportedDateTime = '2026-10-20T12:00:00Z'
                })
            }
        }.GetNewClosure())
        Mock -ModuleName UTCM.Tools Get-Content {
            '{"configurationItems":[{"id":"one","resourceType":"microsoft.entra.test","properties":{"Name":"Synthetic"}},{"id":"two","properties":{}}]}'
        } -ParameterFilter { $Raw }
    }

    AfterEach {
        Should -Invoke Connect-MgGraph -Times 0 -Exactly
        Should -Invoke -ModuleName UTCM.Tools Connect-MgGraph -Times 0 -Exactly
        Should -Invoke Invoke-MgGraphRequest -Times 0 -Exactly
        Should -Invoke -ModuleName UTCM.Tools Invoke-MgGraphRequest -Times 0 -Exactly
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -Times 0 -Exactly -ParameterFilter {
            $Method -ne 'GET'
        }
    }

    It 'Reads all four endpoint families and returns only a summary' {
        $result = & $script:smokeScript -TenantId $script:expectedTenant
        $result.TenantId | Should -Be $script:expectedTenant
        $result.Environment | Should -Be 'Global'
        $result.AuthType | Should -Be 'Delegated'
        $result.ModuleVersion | Should -Be (Get-Module UTCM.Tools).Version.ToString()
        $result.CheckedAtUtc.Offset | Should -Be ([timespan]::Zero)
        $result.Checks.Name | Should -Be @(
            'Snapshot jobs', 'Monitors', 'Monitoring results (last 7 days)', 'Drifts', 'Snapshot artifact items'
        )
        $result.Checks.Status | Should -Be @('Passed', 'Passed', 'Passed', 'Passed', 'Skipped')
        ($result.Checks[0..3] | Select-Object -ExpandProperty Count) | Should -Be @(1, 1, 1, 1)
        $result.Checks[4].Count | Should -BeNullOrEmpty
        ($result | ConvertTo-Json -Depth 5) | Should -Not -Match 'synthetic-resource|Must not appear|Synthetic baseline'
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -Times 4 -Exactly
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -Times 1 -Exactly -ParameterFilter {
            $Uri -like '*/configurationMonitoringResults?*' -and
            [uri]::UnescapeDataString($Uri) -match '\$filter=runInitiationDateTime ge '
        }
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -Times 0 -Exactly -ParameterFilter {
            $OutputFilePath
        }
    }

    It 'Accepts empty collections while explicitly skipping artifact validation' {
        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry { @{ value = @() } }
        $result = & $script:smokeScript -TenantId $script:expectedTenant
        ($result.Checks[0..3] | Select-Object -ExpandProperty Count) | Should -Be @(0, 0, 0, 0)
        $result.Checks[0..3].Status | Should -Be @('Passed', 'Passed', 'Passed', 'Passed')
        $result.Checks[4].Status | Should -Be 'Skipped'
    }

    It 'Rejects a missing connection before any read instead of connecting' {
        $script:smokeState.Context = $null
        { & $script:smokeScript -TenantId $script:expectedTenant } | Should -Throw '*No existing Microsoft Graph connection*'
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -Times 0 -Exactly
    }

    It 'Rejects a different tenant before any read' {
        $script:smokeState.Context.TenantId = 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff'
        { & $script:smokeScript -TenantId $script:expectedTenant } | Should -Throw '*does not match the expected tenant*'
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -Times 0 -Exactly
    }

    It 'Rejects an invalid tenant in the cached context' {
        $script:smokeState.Context.TenantId = 'not-a-guid'
        { & $script:smokeScript -TenantId $script:expectedTenant } | Should -Throw '*does not expose a valid tenant GUID*'
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -Times 0 -Exactly
    }

    It 'Rejects a missing environment before any read' {
        $script:smokeState.Context.Environment = ''
        { & $script:smokeScript -TenantId $script:expectedTenant } | Should -Throw '*does not expose an environment*'
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -Times 0 -Exactly
    }

    It 'Stops if the connection disappears between operations' {
        $state = $script:smokeState
        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -MockWith ({
            $state.Context = $null
            @{ value = @() }
        }.GetNewClosure())
        { & $script:smokeScript -TenantId $script:expectedTenant } | Should -Throw '*No existing Microsoft Graph connection*'
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -Times 1 -Exactly
    }

    It 'Stops if the tenant changes between operations' {
        $state = $script:smokeState
        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -MockWith ({
            $state.Context.TenantId = 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff'
            @{ value = @() }
        }.GetNewClosure())
        { & $script:smokeScript -TenantId $script:expectedTenant } | Should -Throw '*does not match the expected tenant*'
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -Times 1 -Exactly
    }

    It 'Stops if the environment changes between operations' {
        $state = $script:smokeState
        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -MockWith ({
            $state.Context.Environment = 'USGov'
            @{ value = @() }
        }.GetNewClosure())
        { & $script:smokeScript -TenantId $script:expectedTenant } | Should -Throw '*environment changed*'
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -Times 1 -Exactly
    }

    It 'Uses the module scope validation and fails without reconnecting' {
        $script:smokeState.Context.Scopes = @('User.Read')
        { & $script:smokeScript -TenantId $script:expectedTenant } | Should -Throw '*missing required scope*ConfigurationMonitoring.Read.All*'
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -Times 0 -Exactly
    }

    It 'Retains an existing read/write connection without altering its scopes' {
        $script:smokeState.Context.Scopes = @('ConfigurationMonitoring.ReadWrite.All')
        $result = & $script:smokeScript -TenantId $script:expectedTenant
        $result.Checks[0].Status | Should -Be 'Passed'
        $script:smokeState.Context.Scopes | Should -Be @('ConfigurationMonitoring.ReadWrite.All')
    }

    It 'Retains an existing <AuthType> connection' -ForEach @(
        @{ AuthType = 'AppOnly' }, @{ AuthType = 'UserProvidedAccessToken' }
    ) {
        $script:smokeState.Context.AuthType = $AuthType
        $script:smokeState.Context.Scopes = @()
        $result = & $script:smokeScript -TenantId $script:expectedTenant
        $result.AuthType | Should -Be $AuthType
        $result.Checks[0].Status | Should -Be 'Passed'
    }

    It 'Propagates API failure rather than returning a successful summary' {
        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry { throw 'Synthetic HTTP 403' }
        { & $script:smokeScript -TenantId $script:expectedTenant } | Should -Throw '*Synthetic HTTP 403*'
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -Times 1 -Exactly
    }

    It 'Downloads only an explicitly requested existing snapshot and counts normalized items' {
        $result = & $script:smokeScript -TenantId $script:expectedTenant -SnapshotId $script:existingSnapshot
        $result.Checks[4].Status | Should -Be 'Passed'
        $result.Checks[4].Count | Should -Be 2
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -Times 1 -Exactly -ParameterFilter {
            $Uri -match "/configurationSnapshotJobs/$($script:existingSnapshot)\?" -and
            [uri]::UnescapeDataString($Uri) -match 'resourceLocation'
        }
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://graph.microsoft.com/v1.0/test-artifact' -and $OutputFilePath
        }
        Test-Path -LiteralPath $script:smokeState.ArtifactPath | Should -BeFalse
    }

    It 'Counts an empty snapshot artifact as zero items' {
        Mock -ModuleName UTCM.Tools Get-Content { '{"configurationItems":[]}' } -ParameterFilter { $Raw }
        $result = & $script:smokeScript -TenantId $script:expectedTenant -SnapshotId $script:existingSnapshot
        $result.Checks[4].Status | Should -Be 'Passed'
        $result.Checks[4].Count | Should -Be 0
    }

    It 'Rejects invalid or empty GUID arguments: <Label>' -ForEach @(
        @{ Label = 'tenant domain'; Arguments = @{ TenantId = 'tadda.org' } }
        @{ Label = 'empty tenant'; Arguments = @{ TenantId = [guid]::Empty } }
        @{ Label = 'invalid snapshot'; Arguments = @{ TenantId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; SnapshotId = 'invalid' } }
        @{ Label = 'empty snapshot'; Arguments = @{ TenantId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; SnapshotId = [guid]::Empty } }
    ) {
        { & $script:smokeScript @Arguments } | Should -Throw
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -Times 0 -Exactly
    }
}
