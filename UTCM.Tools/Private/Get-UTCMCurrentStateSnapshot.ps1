function Get-UTCMCurrentStateSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Resources,

        [int]$PollingIntervalSeconds = 10
    )

    # Build request body — the createSnapshot action REQUIRES a resources array
    $body = @{
        displayName = "UTCM Temp Current State"
        description = "Temporary snapshot for comparison"
        resources   = $Resources
    }

    # Use the correct action endpoint (not the jobs collection)
    $job = Invoke-GraphRequestWithRetry -Method 'POST' -Uri $script:CreateSnapshotActionUri -Body $body

    # Poll until terminal status (notStarted|running -> succeeded|failed|partiallySuccessful)
    do {
        Start-Sleep -Seconds $PollingIntervalSeconds
        $status = Invoke-GraphRequestWithRetry -Method 'GET' -Uri "$($script:SnapshotJobsUri)/$($job.id)"
        Write-Log -Message "Current-state snapshot status: $($status.status)" -Color Gray
    } while ($status.status -in @('notStarted','running'))

    if ($status.status -notin @('succeeded','partiallySuccessful')) {
        $errors = $null
        if ($status.PSObject.Properties.Name -contains 'errorDetails') {
            $errors = $status.errorDetails -join '; '
        }
        throw ("Current-state snapshot job failed with status '{0}'. {1}" -f $status.status, ($errors ?? ''))
    }

    # Download snapshot items from resourceLocation (not $expand — unsupported on this entity)
    if (-not $status.resourceLocation -or [string]::IsNullOrWhiteSpace($status.resourceLocation)) {
        throw "Current-state snapshot job '$($status.id)' does not expose resourceLocation; cannot retrieve items."
    }

    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        Invoke-WebRequest -Uri $status.resourceLocation -OutFile $tmp -UseBasicParsing -ErrorAction Stop
        $raw  = Get-Content -LiteralPath $tmp -Raw
        $json = $raw | ConvertFrom-Json -ErrorAction Stop

        $items = $null
        if ($json.PSObject.Properties.Name -contains 'configurationItems') {
            $items = $json.configurationItems
        } elseif ($json -is [System.Collections.IEnumerable]) {
            $items = $json
        } else {
            throw "Downloaded artifact does not contain 'configurationItems' and is not an array."
        }

        Add-Member -InputObject $status -NotePropertyName configurationItems -NotePropertyValue $items -Force
    }
    finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }

    return $status
}