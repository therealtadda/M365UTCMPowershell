function Remove-UTCMMonitor {
    <#
    .SYNOPSIS
        Deletes a UTCM configuration monitor.

    .DESCRIPTION
        Sends DELETE /v1.0/admin/configurationManagement/configurationMonitors/{id}.

    .PARAMETER MonitorId
        GUID of the monitor to delete.

    .EXAMPLE
        Remove-UTCMMonitor -MonitorId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'

    .EXAMPLE
        Get-UTCMMonitor | Where-Object status -eq inactive |
            Remove-UTCMMonitor -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('id')]
        [ValidateScript({
            if (-not (Validate-Guid $_)) { throw "MonitorId '$_' is not a valid GUID." }
            $true
        })]
        [string] $MonitorId
    )

    process {
        Ensure-GraphConnection
        if (-not $PSCmdlet.ShouldProcess($MonitorId, "Delete UTCM configuration monitor")) {
            return
        }

        $uri = "$($script:ConfigurationMonitorsUri)/$MonitorId"
        Invoke-GraphRequestWithRetry -Method 'DELETE' -Uri $uri | Out-Null
    }
}
