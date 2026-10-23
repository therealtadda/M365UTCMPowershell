Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe 'Privileged setup safety and permission requirements' {
    BeforeAll {
        InModuleScope UTCM.Tools {
            $script:setupTestStubs = @()
            foreach ($name in @(
                'Get-MgServicePrincipal','New-MgServicePrincipal',
                'Get-MgServicePrincipalAppRoleAssignment','New-MgServicePrincipalAppRoleAssignment',
                'Get-MgDirectoryRole','Get-MgDirectoryRoleTemplate','New-MgDirectoryRole',
                'Get-MgDirectoryRoleMember','New-MgDirectoryRoleMemberByRef'
            )) {
                if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
                    Set-Item -Path "Function:\script:$name" -Value {
                        [CmdletBinding()]
                        param($Filter, [switch]$All, $AppId, $ServicePrincipalId, $DirectoryRoleId, $BodyParameter)
                        throw "Unmocked SDK command: $($PSBoundParameters.Keys -join ', ')"
                    }
                    $script:setupTestStubs += $name
                }
            }
        }
        Mock -ModuleName UTCM.Tools Write-Log {}
        Mock -ModuleName UTCM.Tools Ensure-GraphConnection {}
        Mock -ModuleName UTCM.Tools Resolve-UTCMGraphUri { param($Uri) "https://graph.microsoft.com$Uri" }
        Mock -ModuleName UTCM.Tools Get-MgServicePrincipal {
            param($Filter)
            if ($Filter -match '03b07b79-c5bc-4b5e-9bfa-13acf4a99998') {
                [pscustomobject]@{ Id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; DisplayName = 'UTCM' }
            } else {
                [pscustomobject]@{
                    Id = 'bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee'
                    DisplayName = 'Microsoft Graph'
                    AppRoles = @(
                        'Policy.Read.All','Directory.Read.All','Organization.Read.All','TeamSettings.Read.All' |
                            ForEach-Object {
                                [pscustomobject]@{
                                    Value = $_; Id = 'cccccccc-bbbb-cccc-dddd-eeeeeeeeeeee'
                                    AllowedMemberTypes = @('Application'); IsEnabled = $true
                                }
                            }
                    )
                }
            }
        }
        Mock -ModuleName UTCM.Tools New-MgServicePrincipal {}
        Mock -ModuleName UTCM.Tools Get-MgServicePrincipalAppRoleAssignment {}
        Mock -ModuleName UTCM.Tools New-MgServicePrincipalAppRoleAssignment {}
        Mock -ModuleName UTCM.Tools Get-MgDirectoryRole {
            [pscustomobject]@{ Id = 'dddddddd-bbbb-cccc-dddd-eeeeeeeeeeee'; DisplayName = 'Global Reader' }
        }
        Mock -ModuleName UTCM.Tools Get-MgDirectoryRoleTemplate {
            [pscustomobject]@{ Id = 'eeeeeeee-bbbb-cccc-dddd-eeeeeeeeeeee'; DisplayName = 'Global Reader' }
        }
        Mock -ModuleName UTCM.Tools New-MgDirectoryRole {
            [pscustomobject]@{ Id = 'dddddddd-bbbb-cccc-dddd-eeeeeeeeeeee'; DisplayName = 'Global Reader' }
        }
        Mock -ModuleName UTCM.Tools Get-MgDirectoryRoleMember {}
        Mock -ModuleName UTCM.Tools New-MgDirectoryRoleMemberByRef {}
    }

    AfterAll {
        InModuleScope UTCM.Tools {
            foreach ($name in $script:setupTestStubs) {
                Remove-Item -Path "Function:\script:$name"
            }
            Remove-Variable -Name setupTestStubs -Scope Script
        }
    }

    It 'Supports high-impact confirmation and WhatIf on <Command>' -ForEach @(
        @{ Command = 'Initialize-UTCM' }, @{ Command = 'Enable-UTCM' }, @{ Command = 'Grant-UTCMWorkloadAccess' }
    ) {
        $commandInfo = Get-Command $Command
        $commandInfo.Parameters.Keys | Should -Contain 'WhatIf'
        ($commandInfo.ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }).ConfirmImpact |
            Should -Be 'High'
        & $Command -WhatIf
        Should -Invoke -ModuleName UTCM.Tools Ensure-GraphConnection -Times 0 -Exactly
        Should -Invoke -ModuleName UTCM.Tools Get-MgServicePrincipal -Times 0 -Exactly
        Should -Invoke -ModuleName UTCM.Tools New-MgServicePrincipal -Times 0 -Exactly
        Should -Invoke -ModuleName UTCM.Tools New-MgDirectoryRole -Times 0 -Exactly
        Should -Invoke -ModuleName UTCM.Tools New-MgDirectoryRoleMemberByRef -Times 0 -Exactly
    }

    It 'Requests only the service-principal creation scope in Enable' {
        Enable-UTCM -Confirm:$false
        Should -Invoke -ModuleName UTCM.Tools Ensure-GraphConnection -Times 1 -Exactly -ParameterFilter {
            $Scopes.Count -eq 1 -and $Scopes[0] -eq 'Application.ReadWrite.All'
        }
    }

    It 'Requests role management only when Teams is selected' {
        Grant-UTCMWorkloadAccess -Workloads Entra -Confirm:$false
        Should -Invoke -ModuleName UTCM.Tools Ensure-GraphConnection -Times 1 -Exactly -ParameterFilter {
            $Scopes.Count -eq 2 -and $Scopes -contains 'Application.ReadWrite.All' -and
            $Scopes -contains 'AppRoleAssignment.ReadWrite.All' -and $Scopes -notcontains 'Directory.ReadWrite.All'
        }
        Should -Invoke -ModuleName UTCM.Tools New-MgDirectoryRoleMemberByRef -Times 0 -Exactly
    }

    It 'Includes the required Teams role-management scope but no Directory.ReadWrite.All' {
        Grant-UTCMWorkloadAccess -Workloads Teams -Confirm:$false
        Should -Invoke -ModuleName UTCM.Tools Ensure-GraphConnection -Times 1 -Exactly -ParameterFilter {
            $Scopes.Count -eq 3 -and $Scopes -contains 'RoleManagement.ReadWrite.Directory' -and
            $Scopes -notcontains 'Directory.ReadWrite.All'
        }
        Should -Invoke -ModuleName UTCM.Tools New-MgDirectoryRoleMemberByRef -Times 1 -Exactly
    }

    It 'Obtains all setup scopes before initialization and suppresses duplicate child confirmations' {
        Mock -ModuleName UTCM.Tools Enable-UTCM {}
        Mock -ModuleName UTCM.Tools Grant-UTCMWorkloadAccess {}
        Initialize-UTCM -Workloads Teams -Confirm:$false
        Should -Invoke -ModuleName UTCM.Tools Ensure-GraphConnection -Times 1 -Exactly -ParameterFilter {
            $Scopes -contains 'RoleManagement.ReadWrite.Directory' -and $Scopes -notcontains 'Directory.ReadWrite.All'
        }
        Should -Invoke -ModuleName UTCM.Tools Enable-UTCM -Times 1 -Exactly -ParameterFilter { -not $Confirm }
        Should -Invoke -ModuleName UTCM.Tools Grant-UTCMWorkloadAccess -Times 1 -Exactly -ParameterFilter { -not $Confirm }
    }

    It 'Does not treat an arbitrary Request_BadRequest as a successful role assignment' {
        Mock -ModuleName UTCM.Tools New-MgDirectoryRoleMemberByRef { throw 'Request_BadRequest: invalid role request' }
        { Grant-UTCMWorkloadAccess -Workloads Teams -Confirm:$false } | Should -Throw '*invalid role request*'
        Should -Invoke -ModuleName UTCM.Tools Get-MgDirectoryRoleMember -Times 2 -Exactly
    }

    It 'Does not trust even an already-exists message without verifying membership' {
        Mock -ModuleName UTCM.Tools New-MgDirectoryRoleMemberByRef { throw 'added object references already exist' }
        { Grant-UTCMWorkloadAccess -Workloads Teams -Confirm:$false } | Should -Throw '*added object references already exist*'
    }

    It 'Accepts a concurrent assignment only after verifying the intended principal is a member' {
        $script:memberChecks = 0
        Mock -ModuleName UTCM.Tools Get-MgDirectoryRoleMember {
            $script:memberChecks++
            if ($script:memberChecks -gt 1) {
                [pscustomobject]@{ Id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' }
            }
        }
        Mock -ModuleName UTCM.Tools New-MgDirectoryRoleMemberByRef { throw 'Request_BadRequest: duplicate' }
        { Grant-UTCMWorkloadAccess -Workloads Teams -Confirm:$false } | Should -Not -Throw
        Should -Invoke -ModuleName UTCM.Tools Get-MgDirectoryRoleMember -Times 2 -Exactly
    }

    It 'Propagates directory-role lookup failures instead of activating another role' {
        Mock -ModuleName UTCM.Tools Get-MgDirectoryRole { throw 'Directory read denied' }
        { Grant-UTCMWorkloadAccess -Workloads Teams -Confirm:$false } | Should -Throw '*Directory read denied*'
        Should -Invoke -ModuleName UTCM.Tools New-MgDirectoryRole -Times 0 -Exactly
    }
}
