function Get-UTCMDrift {
    <#
    .SYNOPSIS
        Retrieves configuration drifts from the UTCM API.

    .DESCRIPTION
        Queries GET /beta/admin/configurationManagement/configurationDrifts for
        server-side property-level drift data. Returns granular information about
        which properties drifted, their current vs. desired values, and the drift status.

        This is far more detailed than client-side snapshot comparison — the API provides
        per-property currentValue/desiredValue pairs and active/fixed status tracking.

    .PARAMETER MonitorId
        Filter drifts to a specific monitor by its GUID.

    .PARAMETER Status
        Filter by drift status: active, fixed.

    .PARAMETER ResourceType
        Filter by resource type (e.g., microsoft.exchange.accepteddomain).

    .PARAMETER Top
        Limit to the N most recent drifts (client-side).

    .PARAMETER IncludeDetails
        Include driftedProperties and resourceInstanceIdentifier (returned only on $select).

    .PARAMETER AsJson
        Return results as a JSON string instead of objects.

    .OUTPUTS
        PSObject collection representing configurationDrift objects.

    .EXAMPLE
        Get-UTCMDrift

    .EXAMPLE
        Get-UTCMDrift -Status active -IncludeDetails

    .EXAMPLE
        Get-UTCMDrift -MonitorId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -AsJson

    .EXAMPLE
        Get-UTCMDrift -ResourceType 'microsoft.exchange.accepteddomain' -IncludeDetails
    #>
    [CmdletBinding()]
    param(
        [ValidateScript({
            if (-not (Validate-Guid $_)) { throw "MonitorId '$_' is not a valid GUID." }
            $true
        })]
        [string] $MonitorId,

        [ValidateSet('active','fixed')]
        [string] $Status,

        [string] $ResourceType,

        [int] $Top = 0,

        [switch] $IncludeDetails,

        [switch] $AsJson
    )

    if (Get-Command -Name Ensure-GraphConnection -ErrorAction SilentlyContinue) {
        Ensure-GraphConnection -ReadOnly
    }

    # Build $select
    $selectList = @('id','monitorId','tenantId','resourceType','baselineResourceDisplayName','firstReportedDateTime','status')
    if ($IncludeDetails) {
        $selectList += @('driftedProperties','resourceInstanceIdentifier')
    }

    # Build $filter
    $filters = @()
    if ($MonitorId) {
        $filters += "monitorId eq '$MonitorId'"
    }
    if ($Status) {
        $filters += "status eq '$Status'"
    }
    if ($ResourceType) {
        $filters += "resourceType eq '$ResourceType'"
    }

    # Assemble querystring
    $qs = @()
    $qs += "`$select=" + [System.Uri]::EscapeDataString(($selectList -join ','))
    if ($filters.Count -gt 0) {
        $qs += "`$filter=" + [System.Uri]::EscapeDataString(($filters -join ' and '))
    }

    $uri = $script:ConfigurationDriftsUri + '?' + ($qs -join '&')

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

    # Sort by firstReportedDateTime descending
    $sorted = $all | Sort-Object firstReportedDateTime -Descending

    if ($Top -gt 0) {
        $sorted = $sorted | Select-Object -First $Top
    }

    if ($AsJson) {
        return ($sorted | ConvertTo-Json -Depth 20)
    }

    if ($IncludeDetails) {
        return $sorted
    }

    return ($sorted | Select-Object id, monitorId, resourceType, baselineResourceDisplayName, firstReportedDateTime, status)
}
