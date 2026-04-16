# Tests for New-UTCMMonitor
Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe "New-UTCMMonitor" {
    BeforeAll {
        Mock -ModuleName UTCM.Tools Ensure-GraphConnection {}

        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -ParameterFilter { $Method -eq 'POST' } {
            @{
                id = 'monitor-aaa-bbb'
                displayName = 'Exchange Monitor'
                status = 'active'
                monitorRunFrequencyInHours = 6
                mode = 'monitorOnly'
                createdDateTime = '2026-03-24T09:00:44Z'
            }
        }
    }

    It "Creates a monitor and returns the result" {
        $resources = @(
            @{
                displayName  = 'TestSharedMailbox Resource'
                resourceType = 'microsoft.exchange.sharedmailbox'
                properties   = @{
                    DisplayName = 'TestSharedMailbox'
                    Ensure      = 'Present'
                }
            }
        )

        $result = New-UTCMMonitor -DisplayName 'Exchange Monitor' -BaselineResources $resources
        $result.id | Should -Be 'monitor-aaa-bbb'
        $result.status | Should -Be 'active'
    }

    It "Passes the correct body to the POST request" {
        $resources = @(
            @{
                displayName  = 'Accepted Domain'
                resourceType = 'microsoft.exchange.accepteddomain'
                properties   = @{
                    Identity   = 'contoso.onmicrosoft.com'
                    DomainType = 'InternalRelay'
                    Ensure     = 'Present'
                }
            }
        )

        New-UTCMMonitor -DisplayName 'Domain Monitor' -Description 'Test' -BaselineResources $resources

        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -ParameterFilter {
            $Method -eq 'POST' -and $Uri -match 'configurationMonitors' -and
            $Body.displayName -eq 'Domain Monitor' -and
            $Body.baseline.resources.Count -eq 1
        }
    }

    It "Rejects resources missing required keys" {
        $bad = @( @{ displayName = 'Bad'; resourceType = 'foo' } )  # missing properties
        { New-UTCMMonitor -DisplayName 'Bad Monitor' -BaselineResources $bad } | Should -Throw
    }
}
