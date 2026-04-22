function Enable-UTCM {
<#
.SYNOPSIS
Ensures the official Unified Tenant Configuration Management (UTCM) service principal exists.

.DESCRIPTION
Creates the Microsoft-owned UTCM service principal (AppId 03b07b79-c5bc-4b5e-9bfa-13acf4a99998) if missing.
Per Microsoft’s preview setup, creating the SP and assigning app roles requires Graph scopes:
Application.ReadWrite.All, AppRoleAssignment.ReadWrite.All, and Directory.ReadWrite.All.  # [1](https://learn.microsoft.com/en-us/graph/utcm-authentication-setup)
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Low')]
    param()

    # Ensure Graph connection with the setup scopes required by Microsoft’s UTCM preview
    Ensure-GraphConnection -Scopes @('Application.ReadWrite.All','AppRoleAssignment.ReadWrite.All','Directory.ReadWrite.All')  # [1](https://learn.microsoft.com/en-us/graph/utcm-authentication-setup)

    $utcmAppId = '03b07b79-c5bc-4b5e-9bfa-13acf4a99998'  # Official UTCM AppId  # [1](https://learn.microsoft.com/en-us/graph/utcm-authentication-setup)

    try {
        if ($PSCmdlet.ShouldProcess("ServicePrincipal(appId=$utcmAppId)", "Ensure exists")) {
            $sp = Get-MgServicePrincipal -Filter "appId eq '$utcmAppId'" -All -ErrorAction Stop
            if (-not $sp) {
                Write-Log -Color Cyan -Message "Creating UTCM service principal..."
                $sp = New-MgServicePrincipal -AppId $utcmAppId -ErrorAction Stop
                Write-Log -Color Green -Message "UTCM service principal created. ObjectId: $($sp.Id)"
            } else {
                Write-Log -Color Gray -Message "UTCM service principal already exists. ObjectId: $($sp.Id)"
            }
            return $sp
        }
    } catch {
        Write-Log -Color Red -Message "Enable-UTCM failed: $($_.Exception.Message)"
        throw
    }
}