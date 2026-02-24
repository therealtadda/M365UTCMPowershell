function Grant-UTCMWorkloadAccess {
<#
.SYNOPSIS
Grants the UTCM service principal the rights needed to READ tenant configuration across selected workloads.

.DESCRIPTION
Assigns minimum Graph/EXO app roles and (where needed) directory role memberships so UTCM monitors/snapshots can assess configuration:

- Entra: Graph app roles `Policy.Read.All` + `Directory.Read.All` (Conditional Access & directory reads).  # [2](https://learn.microsoft.com/en-us/graph/api/conditionalaccesspolicy-get?view=graph-rest-1.0)
- Exchange: EXO application permission **Exchange.ManageAsApp** (app-only EXO access).                   # [3](https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2?view=exchange-ps)[4](https://learn.microsoft.com/en-us/services-hub/unified/health/getting-started-office365exchange/app-auth)
- Intune: Graph app role `DeviceManagementConfiguration.Read.All` (device config & compliance).          # [5](https://learn.microsoft.com/en-us/graph/api/intune-deviceconfigv2-devicemanagementconfigurationpolicy-list?view=graph-rest-beta)
- SecurityAndCompliance (Purview and Defender): EXO application permission Exchange.ManageAsApp + Graph App Roles `informationProtectionConfig.Read.All` + `Directory.Read.All`         # [6](https://learn.microsoft.com/en-us/graph/utcm-securityandcompliance-resources)
- Teams: Graph app role `TeamSettings.Read.All`                            # [8](https://learn.microsoft.com/en-us/graph/api/teamsappsettings-get?view=graph-rest-1.0)[7](https://graphpermissions.merill.net/permission/TeamSettings.Read.All)

.PARAMETER Workloads
One or more of: Entra, Exchange, Intune, SecurityAndCompliance, Teams. Defaults to all.

.EXAMPLE
Grant-UTCMWorkloadAccess -Workloads Entra,Exchange,Intune -Verbose
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    param(
        [ValidateSet('Entra','Exchange','Intune','SecurityAndCompliance','Teams')]
        [string[]]$Workloads = @('Entra','Exchange','Intune','SecurityAndCompliance','Teams')
    )

    # Ensure Graph connection for app-role assignments and directory role membership
    Ensure-GraphConnection -Scopes @('Application.ReadWrite.All','AppRoleAssignment.ReadWrite.All','Directory.ReadWrite.All')  # [1](https://learn.microsoft.com/en-us/graph/utcm-authentication-setup)

    $utcmAppId = '03b07b79-c5bc-4b5e-9bfa-13acf4a99998'  # [1](https://learn.microsoft.com/en-us/graph/utcm-authentication-setup)
    try {
        $utcm = Get-MgServicePrincipal -Filter "appId eq '$utcmAppId'" -All -ErrorAction Stop
        if (-not $utcm) { $utcm = Enable-UTCM }
    } catch {
        Write-Log -Color Red -Message "Unable to resolve UTCM SP: $($_.Exception.Message)"
        throw
    }

    # Resource AppIds
    $graphAppId = '00000003-0000-0000-c000-000000000000'  # Microsoft Graph
    $exoAppId   = '00000002-0000-0ff1-ce00-000000000000'  # Office 365 Exchange Online

    # Local helpers ----------------------------------------------

    function _Grant-AppRole {
        param([string]$PrincipalObjectId, [string]$ResourceAppId, [string]$RoleValue)

        try {
            $resourceSp = Get-MgServicePrincipal -Filter "appId eq '$ResourceAppId'" -All -ErrorAction Stop
            $role       = $resourceSp.AppRoles | Where-Object { $_.Value -eq $RoleValue -and $_.AllowedMemberTypes -contains 'Application' -and $_.IsEnabled }
            if (-not $role) { throw "Role '$RoleValue' not found on resource AppId $ResourceAppId." }

            $exists = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $PrincipalObjectId -All |
                      Where-Object { $_.ResourceId -eq $resourceSp.Id -and $_.AppRoleId -eq $role.Id }

            if ($exists) {
                Write-Log -Color Gray -Message "App role '$RoleValue' already assigned on resource '$($resourceSp.DisplayName)'."
                return
            }

            if ($PSCmdlet.ShouldProcess("SP:$PrincipalObjectId", "Grant role '$RoleValue' on '$($resourceSp.DisplayName)'")) {
                $body = @{ PrincipalId = $PrincipalObjectId; ResourceId = $resourceSp.Id; AppRoleId = $role.Id }
                New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $PrincipalObjectId -BodyParameter $body -ErrorAction Stop | Out-Null
                Write-Log -Color Green -Message "Granted '$RoleValue' on '$($resourceSp.DisplayName)'."
            }
        } catch {
            Write-Log -Color Red -Message "Granting app role '$RoleValue' failed: $($_.Exception.Message)"
            throw
        }
    }

    function _Ensure-DirectoryRoleMember {
        param([string]$PrincipalObjectId, [string]$RoleDisplayName)

        try {
            $role = Get-MgDirectoryRole -Filter "displayName eq '$RoleDisplayName'" -ErrorAction SilentlyContinue
            if (-not $role) {
                $template = Get-MgDirectoryRoleTemplate -All | Where-Object { $_.DisplayName -eq $RoleDisplayName }
                if (-not $template) { throw "Directory role template '$RoleDisplayName' not found." }
                $role = Enable-MgDirectoryRole -BodyParameter @{ roleTemplateId = $template.Id } -ErrorAction Stop
                Write-Log -Color Cyan -Message "Activated directory role '$RoleDisplayName'."
            }

            $members = Get-MgDirectoryRoleMember -DirectoryRoleId $role.Id -All
            if ($members.Id -contains $PrincipalObjectId) {
                Write-Log -Color Gray -Message "SP already a member of '$RoleDisplayName'."
            } else {
                if ($PSCmdlet.ShouldProcess("SP:$PrincipalObjectId", "Add to directory role '$RoleDisplayName'")) {
                    $odataId = "https://graph.microsoft.com/v1.0/directoryObjects/$PrincipalObjectId"
                    New-MgDirectoryRoleMemberByRef -DirectoryRoleId $role.Id -BodyParameter @{ '@odata.id' = $odataId } -ErrorAction Stop | Out-Null
                    Write-Log -Color Green -Message "Added SP to '$RoleDisplayName'."
                }
            }
        } catch {
            Write-Log -Color Red -Message "Ensuring directory role '$RoleDisplayName' failed: $($_.Exception.Message)"
            throw
        }
    }

    # Workload → grants mapping -----------------------------------

    $map = @{
        'Entra' = @(
            @{ ResourceAppId = $graphAppId; RoleValue = 'Policy.Read.All'    },  # CA policies read    [2](https://learn.microsoft.com/en-us/graph/api/conditionalaccesspolicy-get?view=graph-rest-1.0)
            @{ ResourceAppId = $graphAppId; RoleValue = 'Directory.Read.All' }   # directory read
        )
        'Exchange' = @(
            @{ ResourceAppId = $exoAppId;   RoleValue = 'Exchange.ManageAsApp' } # EXO app-only        [3](https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2?view=exchange-ps)[4](https://learn.microsoft.com/en-us/services-hub/unified/health/getting-started-office365exchange/app-auth)
        )
        'Intune' = @(
            @{ ResourceAppId = $graphAppId; RoleValue = 'DeviceManagementConfiguration.Read.All' },     # Intune read        [5](https://learn.microsoft.com/en-us/graph/api/intune-deviceconfigv2-devicemanagementconfigurationpolicy-list?view=graph-rest-beta)
            @{ ResourceAppId = $graphAppId; RoleValue = 'DeviceManagementRBAC.Read.All'}
        )
        'SecurityAndCompliance' = @(
            @{ ResourceAppId = $exoAppId;   RoleValue = 'Exchange.ManageAsApp' }, # S&C guidance         [6](https://learn.microsoft.com/en-us/graph/utcm-securityandcompliance-resources)
            @{ ResourceAppId = $graphAppId; RoleValue = 'InformationProtectionConfig.Read.All'}, # Should be adequate for Purview; will validate and dig deeper and cite references
            @{ ResourceAppId = $graphAppId; RoleValue = 'Directory.Read.All'} # Should be all that Defender really needs, need to find citation on this
        )
        'Teams' = @(
            @{ ResourceAppId = $graphAppId; RoleValue = 'Organization.Read.All' }                      # Teams settings     [7](https://graphpermissions.merill.net/permission/TeamSettings.Read.All)[8](https://learn.microsoft.com/en-us/graph/api/teamsappsettings-get?view=graph-rest-1.0)
        )
    }

    try {
        foreach ($wl in $Workloads) {
            Write-Log -Color Cyan -Message "Granting UTCM access for workload: $wl"
            foreach ($grant in $map[$wl]) {
                _Grant-AppRole -PrincipalObjectId $utcm.Id -ResourceAppId $grant.ResourceAppId -RoleValue $grant.RoleValue
            }

            if ($wl -eq 'SecurityAndCompliance') {
                _Ensure-DirectoryRoleMember -PrincipalObjectId $utcm.Id -RoleDisplayName 'Security Reader'  # least-priv read  [6](https://learn.microsoft.com/en-us/graph/utcm-securityandcompliance-resources)
            }
        }

        Write-Log -Color Green -Message ("UTCM workload access granted for: " + ($Workloads -join ', '))
    } catch {
        Write-Log -Color Red -Message "Grant-UTCMWorkloadAccess failed: $($_.Exception.Message)"
        throw
    }
}