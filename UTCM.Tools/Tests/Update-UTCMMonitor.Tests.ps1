# Tests for Update-UTCMMonitor and Remove-UTCMMonitor
Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe "UTCM monitor lifecycle" {
    BeforeAll {
        Mock -ModuleName UTCM.Tools Ensure-GraphConnection {}
        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry {
            @{ id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; displayName = 'Updated'; status = 'active' }
        }
        Mock -ModuleName UTCM.Tools Get-UTCMMonitor {
            @{ id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; displayName = 'Updated'; status = 'active' }
        }
    }

    It "Updates a monitor by PATCH" {
        $r = Update-UTCMMonitor -MonitorId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -DisplayName 'Updated'
        $r.id | Should -Be 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -ParameterFilter {
            $Method -eq 'PATCH' -and $Uri -match '/configurationMonitors/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        }
    }

    It "Requires at least one update property" {
        { Update-UTCMMonitor -MonitorId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' } | Should -Throw '*at least one property*'
    }

    It "Deletes a monitor by DELETE" {
        Remove-UTCMMonitor -MonitorId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -Confirm:$false
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -ParameterFilter {
            $Method -eq 'DELETE' -and $Uri -match '/configurationMonitors/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        }
    }
}
