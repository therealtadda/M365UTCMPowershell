Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe "Get-UTCMTenantDriftReport (orchestrator)" {
    BeforeAll {
        Mock Ensure-GraphConnection {}
        Mock Get-UTCMAvailableSnapshot { @(@{ id='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; displayName='Snap'; createdDateTime='2026-02-08'; status='completed'}) }
        Mock New-UTCMSnapshot { 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' }
        Mock Get-UTCMSnapshot { @{ configurationItems = @(@{id='1'; displayName='A'; type='x'; data=@{x=1}}) } }
        Mock Get-UTCMCurrentStateSnapshot { @{ id='11111111-1111-1111-1111-111111111111'; configurationItems = @(@{id='2'; displayName='B'; type='x'; data=@{x=2}}) } }

        # For Compare inside orchestrator (re-fetch)
        Mock Invoke-GraphRequestWithRetry -ParameterFilter { $Uri -match 'snapshotJobs\/aaaaaaaa' } {
            @{ configurationItems = @(@{id='1'; displayName='A'; type='x'; data=@{x=1}}) }
        }
        Mock Invoke-GraphRequestWithRetry -ParameterFilter { $Uri -match 'snapshotJobs\/11111111' } {
            @{ configurationItems = @(@{id='2'; displayName='B'; type='x'; data=@{x=2}}) }
        }

        Mock Resolve-OutputPath { param($Path) return $Path }
        Mock New-UTCMDriftReport { @{ HtmlPath='x.html'; CsvPath='y.csv' } }
    }

    It "Runs with CreateSnapshot and returns diff" {
        $res = Get-UTCMTenantDriftReport -CreateSnapshot -CompareToCurrent -NoPrompt
        $res | Should -Not -BeNullOrEmpty
    }

    It "Throws when no snapshot and -NoPrompt set" {
        { Get-UTCMTenantDriftReport -NoPrompt } | Should -Throw
    }
}