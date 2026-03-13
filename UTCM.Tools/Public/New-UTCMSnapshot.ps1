function New-UTCMSnapshot {
    [CmdletBinding(DefaultParameterSetName = 'Preset', SupportsShouldProcess = $true)]
    param(
        # How often to poll the job status
        [ValidateRange(5,300)]
        [int] $PollingIntervalSeconds = 10,

        # Supply explicit UTCM resource identifiers (overrides -Preset)
        [Parameter(ParameterSetName = 'Explicit')]
        [string[]] $Resources,

        # Or pick a JSON-backed preset (see Presets\resource-presets.json)
        [Parameter(ParameterSetName = 'Preset')]
        [string] $Preset = 'TenantCore',

        # Friendly metadata
        [string] $DisplayName = $("UTCM Snapshot " + (Get-Date -Format 'yyyyMMdd HHmm')),
        [string] $Description = "Baseline snapshot"
    )

    # Ensure we have a valid Graph token (module helper, if present)
    if (Get-Command -Name Ensure-GraphConnection -ErrorAction SilentlyContinue) {
        Ensure-GraphConnection
    }

    # Resolve resources via JSON presets or explicit list, then warn (non-blocking) on unknown types
    $effectiveResources = Resolve-UTCMResources -Resources $Resources -Preset $Preset
    Test-UTCMResourceTypes -Resources $effectiveResources | Out-Null

    # UTCM API allows only letters, digits, and spaces in displayName
    $DisplayName = ($DisplayName -replace '[^a-zA-Z0-9 ]', ' ') -replace '\s+', ' '
    $DisplayName = $DisplayName.Trim()

    # Build the request body – UTCM action REQUIRES 'resources'
    $body = @{
        displayName = $DisplayName
        description = $Description
        resources   = $effectiveResources
    }

    if (Get-Command -Name Write-Log -ErrorAction SilentlyContinue) {
        Write-Log -Message ("Starting UTCM snapshot: {0} (resources={1})" -f $DisplayName, ($effectiveResources -join ', ')) -Color Cyan
    }

    if (-not $PSCmdlet.ShouldProcess($DisplayName, "Create UTCM snapshot")) {
        return
    }

    # --- Start the snapshot job (UTCM action endpoint) ---
    # Correct endpoint: POST /beta/admin/configurationManagement/configurationSnapshots/createSnapshot
    $job = Invoke-GraphRequestWithRetry -Method 'POST' -Uri $script:CreateSnapshotActionUri -Body $body

    # --- Poll until terminal status (notStarted|running -> succeeded|failed|partiallySuccessful) ---
    do {
        Start-Sleep -Seconds $PollingIntervalSeconds

        # Job read endpoint: GET /beta/admin/configurationManagement/configurationSnapshotJobs/{id}
        $status = Invoke-GraphRequestWithRetry -Method 'GET' -Uri "$($script:SnapshotJobsUri)/$($job.id)"

        if (Get-Command -Name Write-Log -ErrorAction SilentlyContinue) {
            Write-Log -Message "Snapshot status: $($status.status)" -Color Gray
        }
    }
    while ($status.status -in @('notStarted','running'))

    # --- Terminal evaluation ---
    if ($status.status -notin @('succeeded','partiallySuccessful')) {
        # Extract error details — Invoke-MgGraphRequest returns a hashtable,
        # so try both hashtable key access and PSObject property access.
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

        # Dump the full job status so we can diagnose server-side failures
        $statusDump = try { $status | ConvertTo-Json -Depth 5 -Compress } catch { $status.ToString() }
        Write-Warning "Full snapshot job response: $statusDump"

        throw ("Snapshot job failed with status '{0}'. {1}" -f $status.status, ($errorInfo -join ' | '))
    }

    if (Get-Command -Name Write-Log -ErrorAction SilentlyContinue) {
        Write-Log -Message ("Snapshot completed with status '{0}'. ResourceLocation={1}" -f $status.status, $status.resourceLocation) -Color Green
    }

    # Return the final job (contains id, status, and resourceLocation)
    return $status
}