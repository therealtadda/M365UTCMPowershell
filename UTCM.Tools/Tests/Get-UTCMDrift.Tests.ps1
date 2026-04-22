# Tests for Get-UTCMDrift
Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe "Get-UTCMDrift" {
    BeforeAll {
        Mock -ModuleName UTCM.Tools Ensure-GraphConnection {}

        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry {
            @{
                value = @(
                    @{
                        id = 'drift-1'
                        monitorId = 'mon-1'
                        tenantId = 'tenant-1'
                        resourceType = 'microsoft.exchange.accepteddomain'
                        baselineResourceDisplayName = 'Accepted Domain'
                        firstReportedDateTime = '2026-03-15T09:00:00Z'
                        status = 'active'
                        resourceInstanceIdentifier = @{ Identity = 'contoso.onmicrosoft.com' }
                        driftedProperties = @(
                            @{
                                propertyName = 'Ensure'
                                currentValue = 'Absent'
                                desiredValue = 'Present'
                            }
                        )
                    },
                    @{
                        id = 'drift-2'
                        monitorId = 'mon-1'
                        tenantId = 'tenant-1'
                        resourceType = 'microsoft.exchange.mailcontact'
                        baselineResourceDisplayName = 'Mail Contact'
                        firstReportedDateTime = '2026-03-14T06:00:00Z'
                        status = 'fixed'
                    }
                )
            }
        }
    }

    It "Returns drifts sorted by firstReportedDateTime descending" {
        $r = Get-UTCMDrift
        $r.Count | Should -Be 2
        $r[0].id | Should -Be 'drift-1'
        $r[1].id | Should -Be 'drift-2'
    }

    It "Can filter by status" {
        $r = Get-UTCMDrift -Status active
        # The mock always returns the same data, but verify the URI contains the filter
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -ParameterFilter {
            $Uri -match 'filter.*status'
        }
    }

    It "Returns JSON when -AsJson is used" {
        $json = Get-UTCMDrift -AsJson
        $json | Should -Match '"id".*drift-1'
    }

    It "Includes driftedProperties when -IncludeDetails is used" {
        $r = Get-UTCMDrift -IncludeDetails
        $r[0].driftedProperties | Should -Not -BeNullOrEmpty
        $r[0].driftedProperties[0].propertyName | Should -Be 'Ensure'
    }

    It "Limits results with -Top" {
        $r = Get-UTCMDrift -Top 1
        $r.Count | Should -Be 1
    }
}
