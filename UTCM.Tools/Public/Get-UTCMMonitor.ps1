function Get-UTCMMonitor {
    <#
    .SYNOPSIS
        Lists or retrieves UTCM configuration monitors.

    .DESCRIPTION
        Queries GET /beta/admin/configurationManagement/configurationMonitors to list
        all monitors, or retrieves a specific monitor by ID.
        Monitors run periodically to detect drift from a defined baseline.

    .PARAMETER MonitorId
        Retrieve a specific monitor by its GUID. If omitted, lists all monitors.

    .PARAMETER Status
        Filter monitors by status: active.

    .PARAMETER IncludeBaseline
        Include the baseline relationship ($expand=baseline) for detailed resource definitions.

    .PARAMETER AsJson
        Return results as a JSON string.

    .OUTPUTS
        PSObject or PSObject collection representing configurationMonitor objects.

    .EXAMPLE
        Get-UTCMMonitor

    .EXAMPLE
        Get-UTCMMonitor -MonitorId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -IncludeBaseline

    .EXAMPLE
        Get-UTCMMonitor -Status active -AsJson
    #>
    [CmdletBinding()]
    param(
        [ValidateScript({
            if (-not (Validate-Guid $_)) { throw "MonitorId '$_' is not a valid GUID." }
            $true
        })]
        [string] $MonitorId,

        [ValidateSet('active')]
        [string] $Status,

        [switch] $IncludeBaseline,

        [switch] $AsJson
    )

    if (Get-Command -Name Ensure-GraphConnection -ErrorAction SilentlyContinue) {
        Ensure-GraphConnection -ReadOnly
    }

    # Single monitor by ID
    if ($MonitorId) {
        $qs = @()
        $selectList = @('id','displayName','description','tenantId','status','mode',
                        'monitorRunFrequencyInHours','createdDateTime','lastModifiedDateTime',
                        'createdBy','lastModifiedBy','inactivationReason','parameters')
        $qs += "`$select=" + [System.Uri]::EscapeDataString(($selectList -join ','))
        if ($IncludeBaseline) {
            $qs += "`$expand=baseline"
        }

        $uri = "$($script:ConfigurationMonitorsUri)/${MonitorId}?" + ($qs -join '&')
        $result = Invoke-GraphRequestWithRetry -Method 'GET' -Uri $uri

        if ($AsJson) {
            return ($result | ConvertTo-Json -Depth 20)
        }
        return $result
    }

    # List all monitors
    $qs = @()
    $selectList = @('id','displayName','description','status','mode',
                    'monitorRunFrequencyInHours','createdDateTime','lastModifiedDateTime')
    $qs += "`$select=" + [System.Uri]::EscapeDataString(($selectList -join ','))

    $filters = @()
    if ($Status) {
        $filters += "status eq '$Status'"
    }
    if ($filters.Count -gt 0) {
        $qs += "`$filter=" + [System.Uri]::EscapeDataString(($filters -join ' and '))
    }

    $uri = $script:ConfigurationMonitorsUri + '?' + ($qs -join '&')

    # Page through results
    $all = @()
    do {
        $page = Invoke-GraphRequestWithRetry -Method 'GET' -Uri $uri
        if ($page.value) { $all += $page.value }
        $uri = $null
        if ($page -is [System.Collections.IDictionary]) {
            if ($page.ContainsKey('@odata.nextLink')) { $uri = $page['@odata.nextLink'] }
        } elseif ($page.PSObject.Properties.Match('@odata.nextLink').Count) {
            $uri = $page.'@odata.nextLink'
        }
    } while ($uri)

    $sorted = $all | Sort-Object createdDateTime -Descending

    if ($AsJson) {
        return ($sorted | ConvertTo-Json -Depth 20)
    }

    return ($sorted | Select-Object id, displayName, status, mode, monitorRunFrequencyInHours, createdDateTime, lastModifiedDateTime)
}
