# Updated tests for the orchestrator Get-UTCMTenantDriftReport
Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe "Get-UTCMTenantDriftReport (orchestrator) with bind-time validation" {
    BeforeAll {
        Mock -ModuleName UTCM.Tools Ensure-GraphConnection {}
        Mock -ModuleName UTCM.Tools Get-UTCMAvailableSnapshot {
            @([pscustomobject]@{ id='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; displayName='Snap'; createdDateTime='2026-02-08T10:00:00Z'; status='succeeded'})
        }
        Mock -ModuleName UTCM.Tools New-UTCMSnapshot {
            [pscustomobject]@{ id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; status = 'succeeded'; resourceLocation = 'https://graph.microsoft.com/beta/test' }
        }
        Mock -ModuleName UTCM.Tools Get-UTCMSnapshot -ParameterFilter { $SnapshotId -eq 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' } {
            [pscustomobject]@{ id='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; displayName='Snap'; createdDateTime='2026-02-08T10:00:00Z'; status='succeeded'; configurationItems = @([pscustomobject]@{id='1'; displayName='A'; type='x'; data=[pscustomobject]@{x=1}}) }
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
}