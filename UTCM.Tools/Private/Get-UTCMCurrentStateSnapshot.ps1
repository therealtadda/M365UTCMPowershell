function Get-UTCMCurrentStateSnapshot {
    [CmdletBinding()]
    param([int]$PollingIntervalSeconds = 10)

    $body = @{
        displayName = "UTCM Temp Current State"
        description = "Temporary snapshot for comparison"
    }

    $job = Invoke-GraphRequestWithRetry -Method 'POST' -Uri $script:SnapshotJobsUri -Body $body

    do {
        Start-Sleep -Seconds $PollingIntervalSeconds
        $status = Invoke-GraphRequestWithRetry -Method 'GET' -Uri "$($script:SnapshotJobsUri)/$($job.id)"
        Write-Log -Message "Current-state snapshot status: $($status.status)" -Color Gray
    } until ($status.status -ne 'inProgress')

    if ($status.status -ne 'completed') {
        throw "Current-state snapshot job failed with status '$($status.status)'."
    }

    return Invoke-GraphRequestWithRetry -Method 'GET' -Uri "$($script:SnapshotJobsUri)/$($job.id)?`$expand=configurationItems"
}