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
        $errorInfo = @()
        try {
            $ed = $null
            if ($status -is [System.Collections.IDictionary] -and $status.ContainsKey('errorDetails')) {
                $ed = $status['errorDetails']
            } elseif ($status.PSObject.Properties.Name -contains 'errorDetails') {
                $ed = $status.errorDetails
            }
            if ($ed -and $ed.Count -gt 0) {
                $errorInfo += "errorDetails: $($ed -join '; ')"
            }
        } catch { <# ignore #> }

        $statusDump = try { $status | ConvertTo-Json -Depth 5 -Compress } catch { $status.ToString() }
        Write-Warning "Full snapshot job response: $statusDump"

        throw ("Current-state snapshot job failed with status '{0}'. {1}" -f $status.status, ($errorInfo -join ' | '))
    }

    # Download snapshot items from resourceLocation (not $expand — unsupported on this entity)
    if (-not $status.resourceLocation -or [string]::IsNullOrWhiteSpace($status.resourceLocation)) {
        throw "Current-state snapshot job '$($status.id)' does not expose resourceLocation; cannot retrieve items."
    }

    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        Invoke-MgGraphRequest -Method GET -Uri $status.resourceLocation -OutputFilePath $tmp -ErrorAction Stop
        $raw  = Get-Content -LiteralPath $tmp -Raw
        $json = $raw | ConvertFrom-Json -ErrorAction Stop

        $items = $null
        if ($json.PSObject.Properties.Name -contains 'configurationItems') {
            $items = $json.configurationItems
        } elseif ($json.PSObject.Properties.Name -contains 'resources') {
            $items = $json.resources
        } elseif ($json -is [System.Collections.IEnumerable]) {
            $items = $json
        } else {
            throw "Downloaded artifact does not contain 'configurationItems'/'resources' and is not an array."
        }

        # Normalize to id/displayName/type/data for downstream compare/report consumers
        $normalizedItems = foreach ($it in $items) {
            $idVal = $null
            if ($it.PSObject.Properties.Name -contains 'id' -and $it.id) { $idVal = [string]$it.id }
            elseif ($it.PSObject.Properties.Name -contains 'resourceInstanceIdentifier' -and $it.resourceInstanceIdentifier) { $idVal = [string]$it.resourceInstanceIdentifier }
            elseif ($it.PSObject.Properties.Name -contains 'properties' -and $it.properties) {
                foreach ($p in 'Id','Identity','Guid','ObjectId') {
                    if ($it.properties.PSObject.Properties.Name -contains $p -and $it.properties.$p) { $idVal = [string]$it.properties.$p; break }
                }
            }

            $typeVal = $null
            if ($it.PSObject.Properties.Name -contains 'resourceType' -and $it.resourceType) { $typeVal = [string]$it.resourceType }
            elseif ($it.PSObject.Properties.Name -contains 'type' -and $it.type) { $typeVal = [string]$it.type }

            $dataVal = $null
            if ($it.PSObject.Properties.Name -contains 'properties') { $dataVal = $it.properties }
            elseif ($it.PSObject.Properties.Name -contains 'data') { $dataVal = $it.data }

            $displayVal = $null
            if ($it.PSObject.Properties.Name -contains 'displayName') { $displayVal = [string]$it.displayName }

            [pscustomobject]@{
                id          = $idVal
                displayName = $displayVal
                type        = $typeVal
                data        = $dataVal
            }
        }

        Add-Member -InputObject $status -NotePropertyName configurationItems -NotePropertyValue $normalizedItems -Force
        Add-Member -InputObject $status -NotePropertyName rawConfiguration -NotePropertyValue $json -Force
    }
    finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }

    return $status
}