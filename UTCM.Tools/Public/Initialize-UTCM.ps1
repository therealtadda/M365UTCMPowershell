function Initialize-UTCM {
<#
.SYNOPSIS
One-shot convenience to set up UTCM SP and grant workload access (uses Ensure-GraphConnection internally).

.DESCRIPTION
Runs Enable-UTCM then Grant-UTCMWorkloadAccess with your chosen workload set.

.EXAMPLE
Initialize-UTCM -Workloads Entra,Exchange,Intune,SecurityAndCompliance,Teams
#>
    [CmdletBinding()]
    param(
        [ValidateSet('Entra','Exchange','Intune','SecurityAndCompliance','Teams')]
        [string[]]$Workloads = @('Entra','Exchange','Intune','SecurityAndCompliance','Teams')
    )

    try {
        Write-Log -Color Cyan -Message "Initializing UTCM setup..."
        $null = Enable-UTCM
        Grant-UTCMWorkloadAccess -Workloads $Workloads
        Write-Log -Color Green -Message "UTCM initialization complete."
    } catch {
        Write-Log -Color Red -Message "Initialize-UTCM failed: $($_.Exception.Message)"
        throw
    }
}