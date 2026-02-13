# Updated tests for New-UTCMSnapshot
Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe "New-UTCMSnapshot" {
    BeforeAll {
        Mock -ModuleName UTCM.Tools Ensure-GraphConnection {}

        # Create job (POST)
        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -ParameterFilter { $Method -eq 'POST' } {
            @{ id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' }
        }

        # Polling status (two inProgress then completed)
        $script:pollCount = 0
        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -ParameterFilter { $Method -eq 'GET' -and $Uri -match 'snapshotJobs\/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' } {
            $script:pollCount++
            if ($script:pollCount -lt 3) { return @{ status = 'inProgress' } }
            else                         { return @{ status = 'completed' } }
        }
    }

    It "Returns snapshot ID after completion" {
        $id = New-UTCMSnapshot -PollingIntervalSeconds 1
        $id | Should -Be 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
    }
}