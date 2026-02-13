# Updated tests for Compare-UTCMConfiguration (bind-time GUID validation)
Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe "Compare-UTCMConfiguration (bind-time GUID validation)" {
    BeforeAll {
        Mock -ModuleName UTCM.Tools Ensure-GraphConnection {}

        # Baseline snapshot
        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -ParameterFilter { $Uri -match 'snapshotJobs\/00000000-0000-0000-0000-000000000000' } {
            @{ configurationItems = @(
                @{ id='1'; displayName='A'; type='caPolicy'; data=@{ prop='valueA' } }
            )}
        }

        # Compare snapshot
        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -ParameterFilter { $Uri -match 'snapshotJobs\/11111111-1111-1111-1111-111111111111' } {
            @{ configurationItems = @(
                @{ id='1'; displayName='A'; type='caPolicy'; data=@{ prop='valueA-changed' } },
                @{ id='2'; displayName='B'; type='caPolicy'; data=@{ prop='new' } }
            )}
        }
    }

    It "Throws early on invalid BaselineSnapshotId" {
        { Compare-UTCMConfiguration -BaselineSnapshotId 'invalid' -CompareSnapshotId '11111111-1111-1111-1111-111111111111' } | Should -Throw
    }

    It "Throws early on invalid CompareSnapshotId" {
        { Compare-UTCMConfiguration -BaselineSnapshotId '00000000-0000-0000-0000-000000000000' -CompareSnapshotId 'invalid' } | Should -Throw
    }

    It "Detects drift between two valid snapshots" {
        $diff = Compare-UTCMConfiguration -BaselineSnapshotId '00000000-0000-0000-0000-000000000000' -CompareSnapshotId '11111111-1111-1111-1111-111111111111'
        $diff.Count | Should -BeGreaterThan 0
    }
}