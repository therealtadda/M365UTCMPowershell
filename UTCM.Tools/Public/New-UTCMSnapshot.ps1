function New-UTCMSnapshot {
    [CmdletBinding()]
    param([ValidateRange(5,300)][int]$PollingIntervalSeconds = 10)

    Ensure-GraphConnection

    $body = @{
        displayName = "UTCM Snapshot $(Get-Date -Format 'yyyyMMdd-HHmm')"
        description = "Baseline snapshot"
    }

    $job = Invoke-GraphRequestWithRetry -Method 'POST' -Uri $script:SnapshotJobsUri -Body $body

    do {
        Start-Sleep -Seconds $PollingIntervalSeconds
        $status = Invoke-GraphRequestWithRetry -Method 'GET' -Uri "$($script:SnapshotJobsUri)/$($job.id)"
        Write-Log -Message "Snapshot status: $($status.status)" -Color Gray
    } until ($status.status -ne 'inProgress')

    if ($status.status -ne 'completed') {
        throw "Snapshot job failed with status '$($status.status)'."
    }

    return $job.id
}