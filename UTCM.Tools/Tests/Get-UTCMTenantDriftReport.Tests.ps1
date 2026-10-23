# Updated tests for the orchestrator Get-UTCMTenantDriftReport
Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe "Get-UTCMTenantDriftReport (orchestrator) with bind-time validation" {
    BeforeAll {
        Mock -ModuleName UTCM.Tools Ensure-GraphConnection {}
        Mock -ModuleName UTCM.Tools Get-UTCMAvailableSnapshot {
            @([pscustomobject]@{ id='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; displayName='Snap'; createdDateTime='2026-02-08T10:00:00Z'; status='succeeded'})
        }
        Mock -ModuleName UTCM.Tools New-UTCMSnapshot {
            [pscustomobject]@{ id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; status = 'succeeded'; resourceLocation = 'https://graph.microsoft.com/v1.0/test' }
        }
        Mock -ModuleName UTCM.Tools Get-UTCMSnapshot -ParameterFilter { $SnapshotId -eq 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' } {
            [pscustomobject]@{ id='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; displayName='Snap'; createdDateTime='2026-02-08T10:00:00Z'; status='succeeded'; resources=@('x','emptyType'); configurationItems = @([pscustomobject]@{id='1'; displayName='A'; type='x'; data=[pscustomobject]@{x=1}}) }
        }
        Mock -ModuleName UTCM.Tools Get-UTCMSnapshot -ParameterFilter { $SnapshotId -eq '11111111-1111-1111-1111-111111111111' } {
            [pscustomobject]@{ id='11111111-1111-1111-1111-111111111111'; displayName='Snap2'; createdDateTime='2026-02-08T11:00:00Z'; status='succeeded'; configurationItems = @([pscustomobject]@{id='2'; displayName='B'; type='x'; data=[pscustomobject]@{x=2}}) }
        }
        Mock -ModuleName UTCM.Tools Get-UTCMCurrentStateSnapshot {
            [pscustomobject]@{ id='11111111-1111-1111-1111-111111111111'; status='succeeded'; configurationItems = @(@{id='2'; displayName='B'; type='x'; data=@{x=2}}) }
        }

        # For re-fetch within Compare call:
        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -ParameterFilter { $Uri -match 'snapshotJobs\/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' } {
            @{ configurationItems = @(@{id='1'; displayName='A'; type='x'; data=@{x=1}}) }
        }
        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -ParameterFilter { $Uri -match 'snapshotJobs\/11111111-1111-1111-1111-111111111111' } {
            @{ configurationItems = @(@{id='2'; displayName='B'; type='x'; data=@{x=2}}) }
        }

        Mock -ModuleName UTCM.Tools Resolve-OutputPath { param($Path) return $Path }
        Mock -ModuleName UTCM.Tools New-UTCMDriftReport { @{ HtmlPath='x.html'; CsvPath='y.csv' } }
    }

    It "Throws early if invalid SnapshotId is passed" {
        { Get-UTCMTenantDriftReport -SnapshotId 'not-a-guid' } | Should -Throw
    }

    It "Runs end-to-end with -CreateSnapshot and returns diff (no prompt)" {
        $res = Get-UTCMTenantDriftReport -CreateSnapshot -CompareToCurrent -NoPrompt
        $res | Should -Not -BeNullOrEmpty
    }

    It "Throws when no snapshot and -NoPrompt set (no interactive selection)" {
        { Get-UTCMTenantDriftReport -NoPrompt } | Should -Throw
    }

    It "Still renders a report when the comparison finds no drift" {
        Mock -ModuleName UTCM.Tools Compare-UTCMConfiguration { }
        $res = Get-UTCMTenantDriftReport -SnapshotId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -CompareToCurrent -Dashboard -NoPrompt
        $res | Should -BeNullOrEmpty
        Should -Invoke -ModuleName UTCM.Tools New-UTCMDriftReport -Times 1 -ParameterFilter { @($Diff).Count -eq 0 }
    }

    It "Defaults to read-only scopes when listing existing snapshots" {
        Get-UTCMTenantDriftReport -ListSnapshots
        Should -Invoke -ModuleName UTCM.Tools Ensure-GraphConnection -Times 1 -Exactly -ParameterFilter {
            $Scopes.Count -eq 1 -and $Scopes[0] -eq 'ConfigurationMonitoring.Read.All'
        }
    }

    It "Retains write scopes when creating the current-state snapshot" {
        Get-UTCMTenantDriftReport -SnapshotId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -CompareToCurrent -NoPrompt
        Should -Invoke -ModuleName UTCM.Tools Ensure-GraphConnection -Times 1 -Exactly -ParameterFilter {
            $Scopes -contains 'ConfigurationMonitoring.ReadWrite.All'
        }
    }

    It "Preserves explicitly supplied GraphScopes in a read-only workflow" {
        Get-UTCMTenantDriftReport -ListSnapshots -GraphScopes @('ConfigurationMonitoring.ReadWrite.All')
        Should -Invoke -ModuleName UTCM.Tools Ensure-GraphConnection -Times 1 -Exactly -ParameterFilter {
            $Scopes -contains 'ConfigurationMonitoring.ReadWrite.All'
        }
    }

    It "Resolves AllSupported only when explicitly selected for the current-state comparison" {
        Mock -ModuleName UTCM.Tools Get-UTCMPresetSearchPaths {
            Join-Path (Get-Module UTCM.Tools).ModuleBase 'Presets\resource-presets.json'
        }
        Get-UTCMTenantDriftReport -SnapshotId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -CompareToCurrent -ComparePreset AllSupported -NoPrompt | Out-Null
        Should -Invoke -ModuleName UTCM.Tools Get-UTCMCurrentStateSnapshot -Times 1 -Exactly -ParameterFilter {
            $allowed = (Get-Content -LiteralPath (Join-Path (Get-Module UTCM.Tools).ModuleBase 'Presets\supported-resource-types.json') -Raw | ConvertFrom-Json).resourceTypes
            $Resources.Count -eq 244 -and @(Compare-Object $Resources $allowed).Count -eq 0
        }
    }

    It "Keeps all originally requested baseline types, including empty types, as the default scope" {
        Get-UTCMTenantDriftReport -SnapshotId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -CompareToCurrent -NoPrompt | Out-Null
        Should -Invoke -ModuleName UTCM.Tools Get-UTCMCurrentStateSnapshot -Times 1 -Exactly -ParameterFilter {
            $Resources.Count -eq 2 -and $Resources -contains 'x' -and $Resources -contains 'emptyType'
        }
    }

    It "Keeps explicit comparison resources ahead of a comparison preset" {
        Mock -ModuleName UTCM.Tools Resolve-UTCMResources { throw 'The preset must not be resolved' }
        Get-UTCMTenantDriftReport -SnapshotId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -CompareToCurrent `
            -CompareResources @('microsoft.entra.securitydefaults') -ComparePreset AllSupported -NoPrompt | Out-Null
        Should -Invoke -ModuleName UTCM.Tools Get-UTCMCurrentStateSnapshot -Times 1 -Exactly -ParameterFilter {
            $Resources.Count -eq 1 -and $Resources[0] -eq 'microsoft.entra.securitydefaults'
        }
    }

    It "Compares a fully empty successful baseline using requested metadata" {
        Mock -ModuleName UTCM.Tools Get-UTCMSnapshot -ParameterFilter { $SnapshotId -eq 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' } {
            [pscustomobject]@{ id='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; status='succeeded'; resources=@('x','emptyType'); configurationItems=@() }
        }
        $diff = @(Get-UTCMTenantDriftReport -SnapshotId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -CompareToCurrent -NoPrompt)
        $diff.Count | Should -Be 1
        $diff[0].SideIndicator | Should -Be '=>'
        Should -Invoke -ModuleName UTCM.Tools Get-UTCMCurrentStateSnapshot -Times 1 -Exactly -ParameterFilter { $Resources.Count -eq 2 }
    }

    It "Rejects missing requested scope instead of silently using populated types" {
        Mock -ModuleName UTCM.Tools Get-UTCMSnapshot -ParameterFilter { $SnapshotId -eq 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' } {
            [pscustomobject]@{ id='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; status='succeeded'; configurationItems=@(@{id='1'; displayName='A'; type='x'; data=@{x=1}}) }
        }
        { Get-UTCMTenantDriftReport -SnapshotId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -CompareToCurrent -NoPrompt } |
            Should -Throw '*original requested resources*'
        Should -Invoke -ModuleName UTCM.Tools Get-UTCMCurrentStateSnapshot -Times 0 -Exactly
    }

    It "Still permits an explicit resource scope when original requested metadata is unavailable" {
        Mock -ModuleName UTCM.Tools Get-UTCMSnapshot -ParameterFilter { $SnapshotId -eq 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' } {
            [pscustomobject]@{ id='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; status='succeeded'; configurationItems=@(@{id='1'; displayName='A'; type='x'; data=@{x=1}}) }
        }
        Get-UTCMTenantDriftReport -SnapshotId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -CompareToCurrent -CompareResources @('x') -NoPrompt | Out-Null
        Should -Invoke -ModuleName UTCM.Tools Get-UTCMCurrentStateSnapshot -Times 1 -Exactly -ParameterFilter { $Resources.Count -eq 1 -and $Resources[0] -eq 'x' }
    }

    It "Rejects a partial baseline before creating a comparison job" {
        Mock -ModuleName UTCM.Tools Get-UTCMSnapshot -ParameterFilter { $SnapshotId -eq 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' } {
            [pscustomobject]@{ id='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; status='partiallySuccessful'; resources=@('x'); errorDetails=@('Synthetic baseline failure') }
        }
        { Get-UTCMTenantDriftReport -SnapshotId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -CompareToCurrent -NoPrompt } |
            Should -Throw '*Baseline*partiallySuccessful*Synthetic baseline failure*'
        Should -Invoke -ModuleName UTCM.Tools Get-UTCMCurrentStateSnapshot -Times 0 -Exactly
        Should -Invoke -ModuleName UTCM.Tools New-UTCMSnapshot -Times 0 -Exactly
    }

    It "Revalidates the baseline artifact before creating a comparison job" {
        Mock -ModuleName UTCM.Tools Get-UTCMSnapshot -ParameterFilter { $SnapshotId -eq 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -and $IncludeItems } {
            [pscustomobject]@{ id='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; status='partiallySuccessful'; resources=@('x','emptyType'); errorDetails=@('Synthetic later baseline failure'); configurationItems=@() }
        }
        { Get-UTCMTenantDriftReport -SnapshotId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -CompareToCurrent -NoPrompt } |
            Should -Throw '*Synthetic later baseline failure*'
        Should -Invoke -ModuleName UTCM.Tools Get-UTCMCurrentStateSnapshot -Times 0 -Exactly
    }

    It "Does not create a second job if a freshly created baseline is partial" {
        Mock -ModuleName UTCM.Tools New-UTCMSnapshot { [pscustomobject]@{ id='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; status='partiallySuccessful' } }
        Mock -ModuleName UTCM.Tools Get-UTCMSnapshot -ParameterFilter { $SnapshotId -eq 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' } {
            [pscustomobject]@{ id='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; status='partiallySuccessful'; resources=@('x'); errorDetails=@('Synthetic baseline failure') }
        }
        { Get-UTCMTenantDriftReport -CreateSnapshot -CompareToCurrent -NoPrompt } | Should -Throw '*partiallySuccessful*'
        Should -Invoke -ModuleName UTCM.Tools New-UTCMSnapshot -Times 1 -Exactly
        Should -Invoke -ModuleName UTCM.Tools Get-UTCMCurrentStateSnapshot -Times 0 -Exactly
    }

    It "Rejects a partial current-state job before comparing or rendering" {
        Mock -ModuleName UTCM.Tools Get-UTCMCurrentStateSnapshot {
            [pscustomobject]@{ id='11111111-1111-1111-1111-111111111111'; status='partiallySuccessful'; errorDetails=@('Synthetic current failure') }
        }
        Mock -ModuleName UTCM.Tools Compare-UTCMConfiguration {}
        { Get-UTCMTenantDriftReport -SnapshotId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -CompareToCurrent -Dashboard -NoPrompt } |
            Should -Throw '*Comparison*partiallySuccessful*Synthetic current failure*'
        Should -Invoke -ModuleName UTCM.Tools Compare-UTCMConfiguration -Times 0 -Exactly
        Should -Invoke -ModuleName UTCM.Tools New-UTCMDriftReport -Times 0 -Exactly
    }

    It "Propagates the explicit partial override and both jobs' diagnostics to the dashboard" {
        Mock -ModuleName UTCM.Tools Get-UTCMSnapshot -ParameterFilter { $SnapshotId -eq 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' } {
            [pscustomobject]@{ id='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; status='partiallySuccessful'; resources=@('x','emptyType'); errorDetails=@('Synthetic baseline failure'); configurationItems=@() }
        }
        Mock -ModuleName UTCM.Tools Get-UTCMCurrentStateSnapshot {
            [pscustomobject]@{ id='11111111-1111-1111-1111-111111111111'; status='partiallySuccessful'; resources=@('x','emptyType'); errorDetails=@('Synthetic current failure'); configurationItems=@() }
        }
        Mock -ModuleName UTCM.Tools Compare-UTCMConfiguration {}
        Get-UTCMTenantDriftReport -SnapshotId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -CompareToCurrent -Dashboard `
            -AllowPartialComparison -NoPrompt | Out-Null
        Should -Invoke -ModuleName UTCM.Tools Get-UTCMCurrentStateSnapshot -Times 1 -Exactly -ParameterFilter { $AllowPartialComparison }
        Should -Invoke -ModuleName UTCM.Tools Compare-UTCMConfiguration -Times 1 -Exactly -ParameterFilter { $AllowPartialComparison }
        Should -Invoke -ModuleName UTCM.Tools New-UTCMDriftReport -Times 1 -Exactly -ParameterFilter {
            $SnapshotDiagnostics.Count -eq 2 -and
            @($SnapshotDiagnostics | Where-Object status -eq 'partiallySuccessful').Count -eq 2 -and
            $SnapshotDiagnostics[1].errorDetails -contains 'Synthetic current failure'
        }
    }

    It "Keeps partial baseline export available without requesting a comparison override" {
        Mock -ModuleName UTCM.Tools Get-UTCMSnapshot {
            [pscustomobject]@{ id='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; status='partiallySuccessful'; resources=@('x'); errorDetails=@('Synthetic baseline failure') }
        }
        Mock -ModuleName UTCM.Tools Export-UTCMSnapshot {}
        Get-UTCMTenantDriftReport -SnapshotId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -ExportJson -NoPrompt | Out-Null
        Should -Invoke -ModuleName UTCM.Tools Export-UTCMSnapshot -Times 1 -Exactly
        Should -Invoke -ModuleName UTCM.Tools Get-UTCMCurrentStateSnapshot -Times 0 -Exactly
    }
}