function Test-UTCMSetup {
<#
.SYNOPSIS
Validates the UTCM service principal and summarizes its app-role assignments and directory role memberships.

.DESCRIPTION
- Ensures Graph connection using your module's Ensure-GraphConnection.
- Locates the official UTCM SP (AppId 03b07b79-c5bc-4b5e-9bfa-13acf4a99998).
- Emits a summary object (assignments + directory roles) and logs key steps with Write-Log.

.OUTPUTS
PSCustomObject with properties:
- UtcmsSpDisplayName
- ObjectId
- AppRoleAssignments: array of "ResourceDisplayName :: RoleValue"
- DirectoryRoles: comma-separated list
#>
    [CmdletBinding()]
    param()

    try {
        Ensure-GraphConnection -Scopes @('Directory.Read.All','Application.Read.All')
        $utcmAppId = '03b07b79-c5bc-4b5e-9bfa-13acf4a99998'

        $sp = Get-MgServicePrincipal -Filter "appId eq '$utcmAppId'" -All -ErrorAction Stop
        if (-not $sp) {
            Write-Log -Color Red -Message "UTCM service principal not found. Run Enable-UTCM first."
            return
        }

        Write-Log -Color Cyan -Message "Inspecting UTCM service principal '$($sp.DisplayName)' ($($sp.Id)) ..."

        $assignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -All -ErrorAction Stop
        $appRoles = @()
        foreach ($a in $assignments) {
            $res = Get-MgServicePrincipal -ServicePrincipalId $a.ResourceId -ErrorAction SilentlyContinue
            $resName = if ($res) { $res.DisplayName } else { $a.ResourceId }
            $roleValue = $a.AppRoleId
            if ($res -and $res.AppRoles) {
                $match = $res.AppRoles | Where-Object { $_.Id -eq $a.AppRoleId }
                if ($match) { $roleValue = $match.Value }
            }
            $appRoles += "$resName :: $roleValue"
        }

        $dirRoles = (Get-MgServicePrincipalMemberOf -ServicePrincipalId $sp.Id -All |
                     Where-Object { $_.'@odata.type' -eq '#microsoft.graph.directoryRole' } |
                     ForEach-Object { $_.AdditionalProperties.displayName }) -join ', '

        $summary = [PSCustomObject]@{
            UtcmsSpDisplayName = $sp.DisplayName
            ObjectId           = $sp.Id
            AppRoleAssignments = $appRoles
            DirectoryRoles     = $dirRoles
        }

        Write-Log -Color Green -Message "UTCM setup inspection complete."
        return $summary
    }
    catch {
        Write-Log -Color Red -Message "Test-UTCMSetup failed: $($_.Exception.Message)"
        throw
    }
}