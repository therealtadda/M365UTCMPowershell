# Tests for Remove-UTCMSnapshot
Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe "Remove-UTCMSnapshot" {
    BeforeAll {
        Mock -ModuleName UTCM.Tools Ensure-GraphConnection {}
        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry {}
    }

    It "Calls DELETE on the correct URI" {
        Remove-UTCMSnapshot -SnapshotId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -Confirm:$false

        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -ParameterFilter {
            $Method -eq 'DELETE' -and $Uri -match 'configurationSnapshotJobs/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        }
    }

    It "Rejects an invalid GUID" {
        { Remove-UTCMSnapshot -SnapshotId 'not-a-guid' -Confirm:$false } | Should -Throw
    }

    It "Supports pipeline input via id property" {
        $obj = [pscustomobject]@{ id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' }
        $obj | Remove-UTCMSnapshot -Confirm:$false

        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -ParameterFilter {
            $Method -eq 'DELETE'
        }
    }
}
