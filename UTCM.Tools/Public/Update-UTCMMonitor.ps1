function Update-UTCMMonitor {
    <#
    .SYNOPSIS
        Updates an existing UTCM configuration monitor.

    .DESCRIPTION
        Sends PATCH /v1.0/admin/configurationManagement/configurationMonitors/{id}
        with the properties supplied by the caller. Updating the baseline replaces
        the full baseline object.

        Updating a baseline deletes previously generated monitoring results and
        detected drifts for the monitor.

    .PARAMETER MonitorId
        GUID of the monitor to update.

    .PARAMETER DisplayName
        New display name.

    .PARAMETER Description
        New description.

    .PARAMETER Baseline
        Full replacement baseline object.

    .PARAMETER Parameters
        Key-value parameter values used by the baseline.

    .PARAMETER Status
        Monitor status: active or inactive.

    .EXAMPLE
        Update-UTCMMonitor -MonitorId $id -DisplayName 'Exchange Monitor'

    .EXAMPLE
        Update-UTCMMonitor -MonitorId $id -Status inactive
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('id')]
        [ValidateScript({
            if (-not (Validate-Guid $_)) { throw "MonitorId '$_' is not a valid GUID." }
            $true
        })]
        [string] $MonitorId,

        [ValidateNotNullOrEmpty()]
        [string] $DisplayName,

        [AllowEmptyString()]
        [string] $Description,

        [hashtable] $Baseline,

        [hashtable] $Parameters,

        [ValidateSet('active','inactive')]
        [string] $Status
    )

    process {
        $body = @{}
        if ($PSBoundParameters.ContainsKey('DisplayName')) { $body['displayName'] = $DisplayName }
        if ($PSBoundParameters.ContainsKey('Description')) { $body['description'] = $Description }
        if ($PSBoundParameters.ContainsKey('Baseline')) {
            $body['baseline'] = $Baseline
            Write-Warning "Updating the monitor baseline deletes previously generated monitoring results and detected drifts for this monitor."
        }
        if ($PSBoundParameters.ContainsKey('Parameters')) { $body['parameters'] = $Parameters }
        if ($PSBoundParameters.ContainsKey('Status')) { $body['status'] = $Status }

        if ($body.Count -eq 0) {
            throw "Specify at least one property to update."
        }

        Ensure-GraphConnection

        if (-not $PSCmdlet.ShouldProcess($MonitorId, "Update UTCM configuration monitor")) {
            return
        }

        $uri = "$($script:ConfigurationMonitorsUri)/$MonitorId"
        Invoke-GraphRequestWithRetry -Method 'PATCH' -Uri $uri -Body $body | Out-Null
        return Get-UTCMMonitor -MonitorId $MonitorId
    }
}
