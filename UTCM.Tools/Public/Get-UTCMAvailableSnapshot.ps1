function Get-UTCMAvailableSnapshot {
    [CmdletBinding()]
    param(
        [switch]$AsJson
    )
    Ensure-GraphConnection

    $results = @()
    $uri = $script:SnapshotJobsUri

    do {
        $page = Invoke-GraphRequestWithRetry -Method 'GET' -Uri $uri
        if ($page.value) { $results += $page.value }
        $uri = $page.'@odata.nextLink'
    } while ($uri)

    # Return sorted by createdDateTime (desc)
    $sorted = $results | Sort-Object createdDateTime -Descending

    if ($AsJson) { 
        return ($sorted | ConvertTo-Json -Depth 10)
    } else {
        return ($sorted | Select-Object id, displayName, createdDateTime, status)
    }
}