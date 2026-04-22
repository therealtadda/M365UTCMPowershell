# Tests for Get-UTCMMonitoringResult
Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe "Get-UTCMMonitoringResult" {
    BeforeAll {
        Mock -ModuleName UTCM.Tools Ensure-GraphConnection {}

        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry {
            @{
                value = @(
                    @{
                        id = 'run-1'
                        monitorId = 'mon-1'
                        tenantId = 'tenant-1'
                        driftsCount = 3
                        runStatus = 'successful'
                        runInitiationDateTime = '2026-03-24T12:00:00Z'
                        runCompletionDateTime = '2026-03-24T12:05:00Z'
                    },
                    @{
                        id = 'run-2'
                        monitorId = 'mon-1'
                        tenantId = 'tenant-1'
                        driftsCount = 0
                        runStatus = 'successful'
                        runInitiationDateTime = '2026-03-24T06:00:00Z'
                        runCompletionDateTime = '2026-03-24T06:04:00Z'
                    }
                )
            }
        }
    }

    It "Returns monitoring results sorted by runInitiationDateTime descending" {
        $r = Get-UTCMMonitoringResult
        $r.Count | Should -Be 2
        $r[0].id | Should -Be 'run-1'
        $r[0].driftsCount | Should -Be 3
    }

    It "Limits results with -Top" {
        $r = Get-UTCMMonitoringResult -Top 1
        $r.Count | Should -Be 1
    }

    It "Returns JSON when -AsJson is used" {
        $json = Get-UTCMMonitoringResult -AsJson
        $json | Should -Match '"driftsCount".*3'
    }

    It "Filters by monitor ID via URI" {
        Get-UTCMMonitoringResult -MonitorId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -ParameterFilter {
            $Uri -match 'filter.*monitorId'
        }
    }
}
