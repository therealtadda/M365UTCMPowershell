# Tests for Get-UTCMMonitor
Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe "Get-UTCMMonitor" {
    BeforeAll {
        Mock -ModuleName UTCM.Tools Ensure-GraphConnection {}

        # List monitors (no MonitorId)
        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -ParameterFilter { $Method -eq 'GET' -and $Uri -notmatch '[0-9a-f]{8}-' } {
            @{
                value = @(
                    @{
                        id = 'mon-1'
                        displayName = 'Exchange Monitor'
                        status = 'active'
                        mode = 'monitorOnly'
                        monitorRunFrequencyInHours = 6
                        createdDateTime = '2026-03-24T09:00:00Z'
                        lastModifiedDateTime = '2026-03-24T09:00:00Z'
                    },
                    @{
                        id = 'mon-2'
                        displayName = 'Teams Monitor'
                        status = 'active'
                        mode = 'monitorOnly'
                        monitorRunFrequencyInHours = 6
                        createdDateTime = '2026-03-23T09:00:00Z'
                        lastModifiedDateTime = '2026-03-23T09:00:00Z'
                    }
                )
            }
        }

        # Single monitor by ID
        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -ParameterFilter { $Method -eq 'GET' -and $Uri -match 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' } {
            @{
                id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
                displayName = 'Exchange Monitor'
                status = 'active'
                mode = 'monitorOnly'
                monitorRunFrequencyInHours = 6
            }
        }
    }

    It "Lists all monitors sorted by createdDateTime descending" {
        $r = Get-UTCMMonitor
        $r.Count | Should -Be 2
        $r[0].id | Should -Be 'mon-1'
    }

    It "Returns a single monitor by ID" {
        $r = Get-UTCMMonitor -MonitorId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        $r.id | Should -Be 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
    }

    It "Returns JSON when -AsJson is used" {
        $json = Get-UTCMMonitor -AsJson
        $json | Should -Match '"displayName".*Exchange Monitor'
    }
}
