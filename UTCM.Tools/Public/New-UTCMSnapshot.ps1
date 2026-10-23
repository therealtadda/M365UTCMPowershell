function New-UTCMSnapshot {
    <#
    .SYNOPSIS
        Creates a new UTCM configuration snapshot.

    .DESCRIPTION
        Submits a createSnapshot request to the UTCM API and polls until the job reaches
        a terminal status (succeeded, failed, or partiallySuccessful).
        Resources can be specified explicitly or via a JSON-backed preset.
        Terminal metadata explicitly includes resources, resourceLocation and errorDetails.
        Partial completion emits a warning but remains available for retrieval and export.

        DisplayName is auto-sanitized to meet the API constraint (letters, numbers, and spaces only).

        Snapshot artifacts are retained for seven days. A tenant can have up to 12
        visible snapshot jobs and may extract up to 20,000 resources per month.

    .PARAMETER PollingIntervalSeconds
        Seconds between status polls while the job runs. Default: 10.

    .PARAMETER Resources
        Explicit UTCM resource identifiers. Overrides -Preset.

    .PARAMETER Preset
        Named preset from Presets/resource-presets.json. Default: TenantCore.
        AllSupported explicitly selects every type in the reviewed snapshot catalogue,
        excluding known service-rejected types. Workload permissions are still required;
        selecting this preset does not grant permissions or guarantee complete extraction.

    .PARAMETER DisplayName
        Friendly snapshot name (alphanumeric + spaces only; special characters stripped).

    .PARAMETER Description
        Snapshot description. Default: "Baseline snapshot".

    .OUTPUTS
        The completed snapshot job object, including id, status, resources, resourceLocation and errorDetails.

    .EXAMPLE
        New-UTCMSnapshot

    .EXAMPLE
        New-UTCMSnapshot -Preset ExchangeCore -DisplayName "Exchange Baseline"

    .EXAMPLE
        New-UTCMSnapshot -Preset AllSupported -DisplayName "All Supported Baseline"

    .EXAMPLE
        New-UTCMSnapshot -Resources 'microsoft.exchange.sharedmailbox','microsoft.exchange.transportrule'
    #>
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
    # Correct endpoint: POST /v1.0/admin/configurationManagement/configurationSnapshots/createSnapshot
    $job = Invoke-GraphRequestWithRetry -Method 'POST' -Uri $script:CreateSnapshotActionUri -Body $body

    # --- Poll until terminal status (notStarted|running -> succeeded|failed|partiallySuccessful) ---
    do {
        Start-Sleep -Seconds $PollingIntervalSeconds

        $status = Get-UTCMSnapshot -SnapshotId $job.id -IncludeDetails

        if (Get-Command -Name Write-Log -ErrorAction SilentlyContinue) {
            Write-Log -Message "Snapshot status: $($status.status)" -Color Gray
        }
    }
    while ($status.status -in @('notStarted','running'))

    # --- Terminal evaluation ---
    $diagnostic = Get-UTCMSnapshotDiagnostic -Snapshot $status
    if ($diagnostic.status -notin @('succeeded','partiallySuccessful')) {
        throw ("Snapshot job '{0}' failed with status '{1}'. {2}" -f
            $diagnostic.id, $diagnostic.status, $diagnostic.errorSummary)
    }
    if ($diagnostic.status -eq 'partiallySuccessful') {
        Write-Warning (("Snapshot job '{0}' completed partiallySuccessful; extraction is incomplete. {1} " +
            "Keep the job metadata or export the snapshot to retain diagnostics. Do not treat missing data as drift.") -f
            $diagnostic.id, $diagnostic.errorSummary)
    }

    if (Get-Command -Name Write-Log -ErrorAction SilentlyContinue) {
        $color = if ($diagnostic.status -eq 'succeeded') { 'Green' } else { 'Yellow' }
        Write-Log -Message ("Snapshot job '{0}' completed with status '{1}'." -f $status.id, $status.status) -Color $color
    }

    return $status
}