# Updated tests for New-UTCMSnapshot
Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe "New-UTCMSnapshot" {
    BeforeAll {
        Mock -ModuleName UTCM.Tools Ensure-GraphConnection {}

        # Create job (POST)
        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -ParameterFilter { $Method -eq 'POST' } {
            @{ id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' }
        }

        # Polling status (two running then succeeded)
        $script:pollCount = 0
        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -ParameterFilter { $Method -eq 'GET' -and $Uri -match 'snapshotJobs\/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' } {
            $script:pollCount++
            if ($script:pollCount -lt 3) { return @{ id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; status = 'running' } }
            else                         { return @{ id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; status = 'succeeded'; resourceLocation = 'https://graph.microsoft.com/beta/test' } }
        }
    }

    It "Returns snapshot job object after completion" {
        $result = New-UTCMSnapshot -PollingIntervalSeconds 5
        $result.id | Should -Be 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        $result.status | Should -Be 'succeeded'
    }
}