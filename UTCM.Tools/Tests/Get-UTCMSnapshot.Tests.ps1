# Updated tests for Get-UTCMSnapshot (bind-time GUID validation)
Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe "Get-UTCMSnapshot (GUID validation at binding)" {
    BeforeAll {
        Mock -ModuleName UTCM.Tools Ensure-GraphConnection {}
        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry {
            @{ id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; configurationItems = @(@{id='x'}) }
        }
    }

    It "Throws early on invalid SnapshotId" {
        { Get-UTCMSnapshot -SnapshotId 'not-a-guid' } | Should -Throw
    }

    It "Returns snapshot object on valid GUID" {
        $o = Get-UTCMSnapshot -SnapshotId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        $o.configurationItems.Count | Should -Be 1
    }
}