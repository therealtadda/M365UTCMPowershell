# Updated tests for Compare-UTCMConfiguration (bind-time GUID validation)
Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe "Compare-UTCMConfiguration (bind-time GUID validation)" {
    BeforeAll {
        Mock -ModuleName UTCM.Tools Ensure-GraphConnection {}

        # Mock Get-UTCMSnapshot -IncludeItems (called internally by Compare-UTCMConfiguration)
        Mock -ModuleName UTCM.Tools Get-UTCMSnapshot -ParameterFilter { $SnapshotId -eq '00000000-0000-0000-0000-000000000000' } {
            [pscustomobject]@{
                id = '00000000-0000-0000-0000-000000000000'
                status = 'succeeded'
                configurationItems = @(
                    [pscustomobject]@{ id='1'; displayName='A'; type='caPolicy'; data=@{ prop='valueA' } }
                )
            }
        }

        Mock -ModuleName UTCM.Tools Get-UTCMSnapshot -ParameterFilter { $SnapshotId -eq '11111111-1111-1111-1111-111111111111' } {
            [pscustomobject]@{
                id = '11111111-1111-1111-1111-111111111111'
                status = 'succeeded'
                configurationItems = @(
                    [pscustomobject]@{ id='1'; displayName='A'; type='caPolicy'; data=@{ prop='valueA-changed' } },
                    [pscustomobject]@{ id='2'; displayName='B'; type='caPolicy'; data=@{ prop='new' } }
                )
            }
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