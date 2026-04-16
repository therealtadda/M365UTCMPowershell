function Get-UTCMMonitoringResult {
    <#
    .SYNOPSIS
        Lists configuration monitoring results (monitor run history).

    .DESCRIPTION
        Queries GET /beta/admin/configurationManagement/configurationMonitoringResults
        to retrieve the history of monitor runs, including drift counts, run status,
        and error details for each execution.

    .PARAMETER MonitorId
        Filter results to a specific monitor by its GUID.

    .PARAMETER RunStatus
        Filter by run status: successful, partiallySuccessful, failed.

    .PARAMETER Since
        Only return results initiated on or after this datetime (UTC).

    .PARAMETER Top
        Limit to the N most recent results (client-side).

    .PARAMETER IncludeDetails
        Include errorDetails in the response (returned only on $select).

    .PARAMETER AsJson
        Return results as a JSON string.

    .OUTPUTS
        PSObject collection representing configurationMonitoringResult objects.

    .EXAMPLE
        Get-UTCMMonitoringResult

    .EXAMPLE
        Get-UTCMMonitoringResult -MonitorId $id -IncludeDetails

    .EXAMPLE
        Get-UTCMMonitoringResult -RunStatus failed -Since (Get-Date).AddDays(-7) -AsJson
    #>
    [CmdletBinding()]
    param(
        [ValidateScript({
            if (-not (Validate-Guid $_)) { throw "MonitorId '$_' is not a valid GUID." }
            $true
        })]
        [string] $MonitorId,

        [ValidateSet('successful','partiallySuccessful','failed')]
        [string] $RunStatus,

        [datetime] $Since,

        [int] $Top = 0,

        [switch] $IncludeDetails,

        [switch] $AsJson
    )

    if (Get-Command -Name Ensure-GraphConnection -ErrorAction SilentlyContinue) {
        Ensure-GraphConnection -ReadOnly
    }

    # Build $select
    $selectList = @('id','monitorId','tenantId','driftsCount','runStatus','runInitiationDateTime','runCompletionDateTime')
    if ($IncludeDetails) {
        $selectList += 'errorDetails'
    }

    # Build $filter
    $filters = @()
    if ($MonitorId) {
        $filters += "monitorId eq '$MonitorId'"
    }
    if ($RunStatus) {
        $filters += "runStatus eq '$RunStatus'"
    }
    if ($Since) {
        $filters += "runInitiationDateTime ge " + $Since.ToString("o")
    }

    # Assemble querystring
    $qs = @()
    $qs += "`$select=" + [System.Uri]::EscapeDataString(($selectList -join ','))
    if ($filters.Count -gt 0) {
        $qs += "`$filter=" + [System.Uri]::EscapeDataString(($filters -join ' and '))
    }

    $uri = $script:MonitoringResultsUri + '?' + ($qs -join '&')

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

    # Sort by runInitiationDateTime descending
    $sorted = $all | Sort-Object runInitiationDateTime -Descending

    if ($Top -gt 0) {
        $sorted = $sorted | Select-Object -First $Top
    }

    if ($AsJson) {
        return ($sorted | ConvertTo-Json -Depth 20)
    }

    if ($IncludeDetails) {
        return $sorted
    }

    return ($sorted | Select-Object id, monitorId, driftsCount, runStatus, runInitiationDateTime, runCompletionDateTime)
}
