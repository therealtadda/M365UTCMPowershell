function Initialize-UTCM {
<#
.SYNOPSIS
One-shot convenience to set up UTCM SP and grant workload access (uses Ensure-GraphConnection internally).

.DESCRIPTION
Runs Enable-UTCM then Grant-UTCMWorkloadAccess with your chosen workload set.
Prompts before privileged setup. -WhatIf previews the selected workloads without connecting or making grants.

.EXAMPLE
Initialize-UTCM -Workloads Entra,Exchange,Intune,SecurityAndCompliance,Teams
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [ValidateSet('Entra','Exchange','Intune','SecurityAndCompliance','Teams')]
        [string[]]$Workloads = @('Entra','Exchange','Intune','SecurityAndCompliance','Teams')
    )

    if (-not $PSCmdlet.ShouldProcess("UTCM setup for workloads: $($Workloads -join ', ')", 'Create the official service principal and grant workload permissions')) {
        return
    }

    try {
        $scopes = @('Application.ReadWrite.All','AppRoleAssignment.ReadWrite.All')
        if ('Teams' -in $Workloads) { $scopes += 'RoleManagement.ReadWrite.Directory' }
        Ensure-GraphConnection -Scopes $scopes
        Write-Log -Color Cyan -Message "Initializing UTCM setup..."
        $null = Enable-UTCM -Confirm:$false
        Grant-UTCMWorkloadAccess -Workloads $Workloads -Confirm:$false
        Write-Log -Color Green -Message "UTCM initialization complete."
    } catch {
        Write-Log -Color Red -Message "Initialize-UTCM failed: $($_.Exception.Message)"
        throw
    }
}