function Grant-UTCMWorkloadAccess {
<#
.SYNOPSIS
Grants the UTCM service principal the minimum rights needed to READ tenant configuration across selected workloads.

.DESCRIPTION
Assigns Graph app roles plus — for Exchange-backed workloads — Exchange Online RBAC management role
assignments scoped exclusively to the UTCM service principal.  No tenant-wide Entra directory roles are used for Exchange or S&C workloads.
Teams requires the Global Reader Entra directory role (per official UTCM Teams resource docs).

Permission strategy per workload:

- Entra:  Graph app roles Policy.Read.All + Directory.Read.All
          (Conditional Access policies & directory objects)                                              # [2]

- Exchange:  Graph app role Exchange.ManageAsApp (app-only EXO authentication)                          # [3][4]
             + EXO RBAC roles View-Only Configuration & View-Only Recipients                            # [9]
             (reads transport rules, shared mailboxes, org config — scoped to the SP, not tenant-wide)

- Intune:  Graph app roles DeviceManagementConfiguration.Read.All, DeviceManagementRBAC.Read.All,       # [5]
           DeviceManagementManagedDevices.Read.All, DeviceManagementApps.Read.All,
           DeviceManagementServiceConfig.Read.All, Group.Read.All
           (covers device categories, app policies, enrollment, compliance, autopilot, etc.)

- SecurityAndCompliance:  Exchange.ManageAsApp + InformationProtectionConfig.Read.All                   # [6]
                          + Directory.Read.All
                          + EXO RBAC roles View-Only Configuration & Security Reader (EXO role, NOT
                            the Entra directory role)                                                    # [9]

- Teams:  Graph app roles Organization.Read.All + TeamSettings.Read.All                                 # [7][8]
          + Entra directory role Global Reader (required by UTCM for all Teams resources)                # [10]

References:
  [1] https://learn.microsoft.com/en-us/graph/utcm-authentication-setup
  [2] https://learn.microsoft.com/en-us/graph/api/conditionalaccesspolicy-get?view=graph-rest-1.0
  [3] https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2?view=exchange-ps
  [4] https://learn.microsoft.com/en-us/services-hub/unified/health/getting-started-office365exchange/app-auth
  [5] https://learn.microsoft.com/en-us/graph/api/intune-deviceconfigv2-devicemanagementconfigurationpolicy-list?view=graph-rest-beta
  [6] https://learn.microsoft.com/en-us/graph/utcm-securityandcompliance-resources
  [7] https://graphpermissions.merill.net/permission/TeamSettings.Read.All
  [8] https://learn.microsoft.com/en-us/graph/api/teamsappsettings-get?view=graph-rest-1.0
  [9] https://learn.microsoft.com/en-us/graph/utcm-exchange-resources
      https://learn.microsoft.com/en-us/exchange/permissions-exo/application-rbac
  [10] https://learn.microsoft.com/en-us/graph/utcm-teams-resources

.PARAMETER Workloads
One or more of: Entra, Exchange, Intune, SecurityAndCompliance, Teams. Defaults to all.

.EXAMPLE
Grant-UTCMWorkloadAccess -Workloads Entra,Exchange,Intune -Verbose

.EXAMPLE
# Grant only Exchange (includes EXO RBAC setup — requires ExchangeOnlineManagement module)
Grant-UTCMWorkloadAccess -Workloads Exchange
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    param(
        [ValidateSet('Entra','Exchange','Intune','SecurityAndCompliance','Teams')]
        [string[]]$Workloads = @('Entra','Exchange','Intune','SecurityAndCompliance','Teams')
    )

    # Ensure Graph connection for app-role assignments
    Ensure-GraphConnection -Scopes @('Application.ReadWrite.All','AppRoleAssignment.ReadWrite.All','Directory.ReadWrite.All')  # [1]

    $utcmAppId = '03b07b79-c5bc-4b5e-9bfa-13acf4a99998'  # Official UTCM AppId  [1]
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

    # ── Local helpers ──────────────────────────────────────────────

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

    # Ensure the UTCM SP is registered inside Exchange Online and assign EXO RBAC management roles.
    # This uses the ExchangeOnlineManagement module (Connect-ExchangeOnline must be available).
    # Roles are scoped to the SP — NOT tenant-wide Entra directory roles.                        # [9]
    function _Grant-ExoRbacRoles {
        param(
            [string]$AppId,
            [string]$ObjectId,
            [string]$DisplayName,
            [string[]]$ManagementRoles   # e.g. 'View-Only Configuration', 'View-Only Recipients'
        )

        # Verify ExchangeOnlineManagement is available
        if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
            throw ("ExchangeOnlineManagement module is required for Exchange RBAC grants. " +
                   "Install it with: Install-Module ExchangeOnlineManagement -Scope CurrentUser")
        }

        # Connect if not already connected (will prompt interactively)
        Import-Module ExchangeOnlineManagement -ErrorAction Stop
        $exoConn = Get-ConnectionInformation -ErrorAction SilentlyContinue
        if (-not $exoConn) {
            Write-Log -Color Cyan -Message "Connecting to Exchange Online..."
            try {
                Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
            } catch {
                # WAM broker can crash in some PowerShell hosts — fall back to device-code flow
                Write-Log -Color Yellow -Message "WAM broker auth failed ($($_.Exception.Message)). Falling back to device-code flow..."
                Connect-ExchangeOnline -ShowBanner:$false -Device -ErrorAction Stop
            }
        } else {
            Write-Log -Color Gray -Message "Already connected to Exchange Online ($($exoConn[0].Organization))."
        }

        # Register the UTCM SP inside EXO (idempotent — will error if already exists)
        try {
            $exoSp = Get-ServicePrincipal -Identity $AppId -ErrorAction Stop
            Write-Log -Color Gray -Message "EXO service principal already registered: $($exoSp.DisplayName)"
        } catch {
            if ($PSCmdlet.ShouldProcess("AppId:$AppId", "Register service principal in Exchange Online")) {
                Write-Log -Color Cyan -Message "Registering UTCM service principal in Exchange Online..."
                $exoSp = New-ServicePrincipal -AppId $AppId -ObjectId $ObjectId -DisplayName $DisplayName -ErrorAction Stop
                Write-Log -Color Green -Message "Registered EXO service principal: $($exoSp.DisplayName)"
            }
        }

        # Assign each management role (idempotent — skip if already assigned)
        $shortId = $AppId.Substring(0, 8)          # first segment of GUID — keeps name under 64 chars
        foreach ($roleName in $ManagementRoles) {
            $assignmentName = ("UTCM_${roleName}_$shortId" -replace ' ', '_').Substring(0, [Math]::Min(64, ("UTCM_${roleName}_$shortId" -replace ' ', '_').Length))

            $existing = Get-ManagementRoleAssignment -RoleAssignee $ObjectId -ErrorAction SilentlyContinue |
                        Where-Object { $_.Role -eq $roleName }

            if ($existing) {
                Write-Log -Color Gray -Message "EXO role '$roleName' already assigned to UTCM SP."
                continue
            }

            if ($PSCmdlet.ShouldProcess("SP:$ObjectId", "Assign EXO management role '$roleName'")) {
                New-ManagementRoleAssignment -Name $assignmentName -Role $roleName -App $ObjectId -ErrorAction Stop | Out-Null
                Write-Log -Color Green -Message "Assigned EXO management role '$roleName' to UTCM SP."
            }
        }
    }

    # Assign Entra directory roles (only for workloads that require them — currently Teams only)
    function _Ensure-DirectoryRoleMember {
        param([string]$RoleDisplayName, [string]$PrincipalObjectId)

        $role = Get-MgDirectoryRole -Filter "displayName eq '$RoleDisplayName'" -ErrorAction SilentlyContinue
        if (-not $role) {
            # Activate from template if not yet instantiated
            $tmpl = Get-MgDirectoryRoleTemplate -All | Where-Object { $_.DisplayName -eq $RoleDisplayName }
            if (-not $tmpl) { throw "Directory role template '$RoleDisplayName' not found." }
            $role = New-MgDirectoryRole -BodyParameter @{ roleTemplateId = $tmpl.Id } -ErrorAction Stop
        }

        $existing = Get-MgDirectoryRoleMember -DirectoryRoleId $role.Id -All |
                    Where-Object { $_.Id -eq $PrincipalObjectId }
        if ($existing) {
            Write-Log -Color Gray -Message "Directory role '$RoleDisplayName' already assigned to UTCM SP."
            return
        }

        if ($PSCmdlet.ShouldProcess("SP:$PrincipalObjectId", "Assign Entra directory role '$RoleDisplayName'")) {
            $body = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$PrincipalObjectId" }
            try {
                New-MgDirectoryRoleMemberByRef -DirectoryRoleId $role.Id -BodyParameter $body -ErrorAction Stop
                Write-Log -Color Green -Message "Assigned Entra directory role '$RoleDisplayName' to UTCM SP."
            } catch {
                if ($_.Exception.Message -match 'Authorization_RequestDenied|Insufficient privileges') {
                    throw "Cannot assign Entra directory role '$RoleDisplayName': your Graph session lacks the 'RoleManagement.ReadWrite.Directory' scope. " +
                          "Reconnect with: Connect-MgGraph -Scopes 'RoleManagement.ReadWrite.Directory'  then retry."
                }
                throw
            }
        }
    }

    # ── Workload → Graph app-role grants mapping ──────────────────

    $map = @{
        'Entra' = @(
            @{ ResourceAppId = $graphAppId; RoleValue = 'Policy.Read.All'    },  # CA policies read    [2]
            @{ ResourceAppId = $graphAppId; RoleValue = 'Directory.Read.All' }   # directory read
        )
        'Exchange' = @(
            @{ ResourceAppId = $exoAppId;   RoleValue = 'Exchange.ManageAsApp' } # EXO app-only auth   [3][4]
        )
        'Intune' = @(
            @{ ResourceAppId = $graphAppId; RoleValue = 'DeviceManagementConfiguration.Read.All' },     # config policies [5]
            @{ ResourceAppId = $graphAppId; RoleValue = 'DeviceManagementRBAC.Read.All'},                # role assignments
            @{ ResourceAppId = $graphAppId; RoleValue = 'DeviceManagementManagedDevices.Read.All'},      # device categories
            @{ ResourceAppId = $graphAppId; RoleValue = 'DeviceManagementApps.Read.All'},                # app config/protection
            @{ ResourceAppId = $graphAppId; RoleValue = 'DeviceManagementServiceConfig.Read.All'},       # enrollment/autopilot
            @{ ResourceAppId = $graphAppId; RoleValue = 'Group.Read.All'}                                # group assignments
        )
        'SecurityAndCompliance' = @(
            @{ ResourceAppId = $exoAppId;   RoleValue = 'Exchange.ManageAsApp' },                       # S&C EXO auth [6]
            @{ ResourceAppId = $graphAppId; RoleValue = 'InformationProtectionConfig.Read.All'},         # Purview
            @{ ResourceAppId = $graphAppId; RoleValue = 'Directory.Read.All'}                            # Defender
        )
        'Teams' = @(
            @{ ResourceAppId = $graphAppId; RoleValue = 'Organization.Read.All' },                      # org settings
            @{ ResourceAppId = $graphAppId; RoleValue = 'TeamSettings.Read.All' }                       # Teams admin  [7][8]
        )
    }

    # ── Workload → Entra directory role mapping ───────────────────
    # Only Teams requires a directory role — all Teams UTCM resources mandate Global Reader [10]
    $directoryRoleMap = @{
        'Teams' = @('Global Reader')
    }

    # ── Workload → EXO RBAC management role mapping ───────────────
    # These are Exchange Online management roles assigned via -App, NOT Entra directory roles.
    # Per https://learn.microsoft.com/en-us/graph/utcm-exchange-resources:
    #   sharedMailbox  → View-Only Recipients, Mail Recipients
    #   transportRule  → View-Only Configuration, Transport Rules, Security Reader (EXO role)
    # We grant the superset that covers all Exchange + S&C UTCM resource types for read.
    $exoRbacMap = @{
        'Exchange' = @(
            'View-Only Configuration',    # transport rules, org config, connectors, policies
            'View-Only Recipients'        # shared mailboxes, distribution groups, mail contacts
        )
        'SecurityAndCompliance' = @(
            'View-Only Configuration',    # needed by S&C EXO-backed resources
            'Security Reader'             # EXO management role (NOT the Entra directory role)
        )
    }

    try {
        foreach ($wl in $Workloads) {
            Write-Log -Color Cyan -Message "Granting UTCM access for workload: $wl"

            # Grant Graph / EXO app roles
            foreach ($grant in $map[$wl]) {
                _Grant-AppRole -PrincipalObjectId $utcm.Id -ResourceAppId $grant.ResourceAppId -RoleValue $grant.RoleValue
            }

            # Grant EXO RBAC management roles (Exchange and S&C workloads only)
            if ($exoRbacMap.ContainsKey($wl)) {
                Write-Log -Color Cyan -Message "Configuring Exchange Online RBAC roles for workload: $wl"
                _Grant-ExoRbacRoles -AppId $utcmAppId -ObjectId $utcm.Id `
                    -DisplayName 'Unified Tenant Configuration Management' `
                    -ManagementRoles $exoRbacMap[$wl]
            }

            # Grant Entra directory roles (Teams only)
            if ($directoryRoleMap.ContainsKey($wl)) {
                foreach ($roleName in $directoryRoleMap[$wl]) {
                    _Ensure-DirectoryRoleMember -RoleDisplayName $roleName -PrincipalObjectId $utcm.Id
                }
            }
        }

        Write-Log -Color Green -Message ("UTCM workload access granted for: " + ($Workloads -join ', '))
    } catch {
        Write-Log -Color Red -Message "Grant-UTCMWorkloadAccess failed: $($_.Exception.Message)"
        throw
    }
}