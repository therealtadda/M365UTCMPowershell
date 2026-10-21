Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe 'Graph connection permission handling' {
    InModuleScope UTCM.Tools {
        BeforeEach {
            $script:connectionTestContext = [pscustomobject]@{
                AuthType = 'Delegated'; Scopes = @('ConfigurationMonitoring.Read.All')
                Environment = 'Global'; TenantId = 'test-tenant'
            }
            Mock Get-MgContext { $script:connectionTestContext }
            Mock Connect-MgGraph {
                param($Scopes)
                $script:connectionTestContext = [pscustomobject]@{ AuthType = 'Delegated'; Scopes = $Scopes }
            }
        }

        It 'Reuses a sufficient delegated read-only context without reconnecting' {
            Ensure-GraphConnection -ReadOnly
            Should -Invoke Connect-MgGraph -Times 0 -Exactly
        }

        It 'Accepts read/write permission as satisfying the corresponding read permission' {
            $script:connectionTestContext.Scopes = @('ConfigurationMonitoring.ReadWrite.All','Application.ReadWrite.All')
            Ensure-GraphConnection -ReadOnly
            Ensure-GraphConnection -Scopes @('Application.Read.All')
            Should -Invoke Connect-MgGraph -Times 0 -Exactly
        }

        It 'Rejects an insufficient existing context without silently replacing the tenant or account' {
            { Ensure-GraphConnection } | Should -Throw '*missing required scope*ConfigurationMonitoring.ReadWrite.All*'
            Should -Invoke Connect-MgGraph -Times 0 -Exactly
            $script:connectionTestContext.TenantId | Should -Be 'test-tenant'
        }

        It 'Requests only the read permission for a new read-only connection' {
            $script:connectionTestContext = $null
            Ensure-GraphConnection -ReadOnly
            Should -Invoke Connect-MgGraph -Times 1 -Exactly -ParameterFilter {
                $Scopes.Count -eq 1 -and $Scopes[0] -eq 'ConfigurationMonitoring.Read.All' -and $NoWelcome
            }
        }

        It 'Honors explicitly requested setup scopes when ReadOnly is present' {
            $script:connectionTestContext = $null
            Ensure-GraphConnection -ReadOnly -Scopes @('Application.ReadWrite.All','AppRoleAssignment.ReadWrite.All')
            Should -Invoke Connect-MgGraph -Times 1 -Exactly -ParameterFilter {
                $Scopes -contains 'Application.ReadWrite.All' -and $Scopes -contains 'AppRoleAssignment.ReadWrite.All'
            }
        }

        It 'Does not replace an app-only or caller-supplied-token connection: <AuthType>' -ForEach @(
            @{ AuthType = 'AppOnly' }, @{ AuthType = 'UserProvidedAccessToken' }
        ) {
            $script:connectionTestContext.AuthType = $AuthType
            $script:connectionTestContext.Scopes = @()
            Ensure-GraphConnection
            Should -Invoke Connect-MgGraph -Times 0 -Exactly
        }

        It 'Preserves an explicit monitoring write scope even if ReadOnly is specified' {
            $script:connectionTestContext = $null
            Ensure-GraphConnection -ReadOnly -Scopes @('ConfigurationMonitoring.ReadWrite.All')
            Should -Invoke Connect-MgGraph -Times 1 -Exactly -ParameterFilter {
                $Scopes.Count -eq 1 -and $Scopes[0] -eq 'ConfigurationMonitoring.ReadWrite.All'
            }
        }

        It 'Throws if connection did not establish a context' {
            $script:connectionTestContext = $null
            Mock Connect-MgGraph {}
            { Ensure-GraphConnection -ReadOnly } | Should -Throw '*did not establish a Graph context*'
        }
    }
}
