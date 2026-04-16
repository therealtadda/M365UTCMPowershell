function Get-UTCMTenantDriftReport {
    <#
    .SYNOPSIS
        End-to-end drift detection pipeline: select baseline, compare to current, generate report.

    .DESCRIPTION
        Orchestrates the full drift workflow:
          1. Select or create a baseline snapshot (interactive menu or -SnapshotId / -CreateSnapshot).
          2. Optionally create a current-state snapshot and compare (-CompareToCurrent).
             Resources for the comparison snapshot default to the same types as the baseline;
             override with -ComparePreset or -CompareResources. In interactive mode a preset
             menu is shown.
          3. Optionally export the baseline to JSON (-ExportJson).
          4. Optionally generate a paginated HTML drift dashboard + CSV (-Dashboard).
             The HTML includes a drift summary on page 1 and the full current configuration
             state on page 2.

    .PARAMETER CreateSnapshot
        Create a fresh baseline snapshot before comparing.

    .PARAMETER SnapshotId
        GUID of an existing baseline snapshot. If omitted, an interactive menu is shown.

    .PARAMETER CompareToCurrent
        Create a current-state snapshot and compare it to the baseline.

    .PARAMETER ComparePreset
        Named preset for the current-state snapshot resources (e.g. ExchangeCore, TenantCore).

    .PARAMETER CompareResources
        Explicit resource identifiers for the current-state snapshot.

    .PARAMETER ExportJson
        Export the baseline snapshot to JSON in the output directory.

    .PARAMETER Dashboard
        Generate the HTML drift report and CSV.

    .PARAMETER ListSnapshots
        List available snapshots and exit.

    .PARAMETER NoPrompt
        Non-interactive mode (CI-friendly). Requires -SnapshotId or -CreateSnapshot.

    .PARAMETER OutputPath
        Output directory. Default: current directory.

    .PARAMETER PollingIntervalSeconds
        Seconds between polls during snapshot creation. Default: 10.

    .PARAMETER GraphScopes
        Graph scopes for the connection. Default: ConfigurationMonitoring.ReadWrite.All.

    .OUTPUTS
        The diff array (or $null if no comparison was performed).

    .EXAMPLE
        # Interactive: select baseline, choose preset, generate dashboard
        Get-UTCMTenantDriftReport -CompareToCurrent -Dashboard

    .EXAMPLE
        # CI pipeline
        Get-UTCMTenantDriftReport -SnapshotId $id -CompareToCurrent -Dashboard -ExportJson -OutputPath .\Reports -NoPrompt

    .EXAMPLE
        # Compare using a specific preset
        Get-UTCMTenantDriftReport -SnapshotId $id -CompareToCurrent -ComparePreset ExchangeCore -Dashboard
    #>
    [CmdletBinding()]
    param(
        [switch] $CreateSnapshot,

        # Optional SnapshotId: validate only when supplied (allow null for interactive selection)
        [ValidateScript({
            if ($_ -and -not (Validate-Guid $_)) { throw "SnapshotId '$_' is not a valid GUID." }
            $true
        })]
        [string] $SnapshotId,

        [switch] $CompareToCurrent,
        [switch] $ExportJson,
        [switch] $Dashboard,
        [switch] $ListSnapshots,
        [switch] $NoPrompt,

        [ValidateNotNullOrEmpty()]
        [string] $OutputPath = ".\",

        [ValidateRange(5,300)]
        [int] $PollingIntervalSeconds = 10,

        [string[]] $GraphScopes = @('ConfigurationMonitoring.ReadWrite.All'),

        # Resources for the "current" comparison snapshot.
        # -CompareResources: explicit resource identifiers (overrides preset & baseline).
        # -ComparePreset: named preset from resource-presets.json.
        # If neither is specified, defaults to the same resource types as the baseline.
        [string] $ComparePreset,
        [string[]] $CompareResources
    )

    # Ensure Graph session (scope list is passed through for consistency with your module)
    if (Get-Command -Name Ensure-GraphConnection -ErrorAction SilentlyContinue) {
        Ensure-GraphConnection -Scopes $GraphScopes
    }

    # Quick list mode: leverage the improved listing cmdlet
    if ($ListSnapshots) {
        # Show newest, completed, downloadable jobs for practical use
        return Get-UTCMAvailableSnapshot -OnlyCompleted -DownloadableOnly
    }

    # If no SnapshotId and no CreateSnapshot => optionally prompt to select one (unless -NoPrompt)
    if (-not $SnapshotId -and -not $CreateSnapshot) {
        $snapshots = Get-UTCMAvailableSnapshot -OnlyCompleted -DownloadableOnly
        if (-not $snapshots -or $snapshots.Count -eq 0) {
            throw "No snapshots exist. Use -CreateSnapshot to generate a new baseline."
        }

        if ($NoPrompt) {
            throw "No SnapshotId provided and -NoPrompt is set. Provide -SnapshotId or use -CreateSnapshot."
        }

        Write-Host "`nAvailable Snapshots (Completed & Downloadable):`n" -ForegroundColor Cyan
        $i = 1
        foreach ($s in $snapshots) {
            # default projection has id, displayName, createdDateTime, status
            Write-Host ("[{0}]  {1}  ({2})  Created: {3}  Status: {4}" -f $i, $s.displayName, $s.id, $s.createdDateTime, $s.status)
            $i++
        }

        $selection = Read-Host "`nSelect a snapshot number to use as baseline"
        if (-not ($selection -as [int]) -or $selection -lt 1 -or $selection -gt $snapshots.Count) {
            throw "Invalid snapshot selection."
        }

        $SnapshotId = $snapshots[$selection - 1].id
    }

    # Create a fresh snapshot (uses module defaults, e.g., 'TenantCore' preset).
    if ($CreateSnapshot) {
        # New-UTCMSnapshot returns the final job object (status + resourceLocation).
        $job = New-UTCMSnapshot -PollingIntervalSeconds $PollingIntervalSeconds
        if ($job.status -notin @('succeeded','partiallySuccessful')) {
            $errors = $null
            if ($job.PSObject.Properties.Name -contains 'errorDetails') {
                $errors = $job.errorDetails -join '; '
            }
            throw ("Snapshot creation did not complete successfully. Status: {0}. {1}" -f $job.status, ($errors ?? ''))
        }
        $SnapshotId = $job.id
    }

    # Fetch baseline snapshot metadata (concise by default)
    $baseline = Get-UTCMSnapshot -SnapshotId $SnapshotId

    # Export baseline if requested (downloads from resourceLocation under the hood)
    if ($ExportJson) {
        if (-not (Get-Command -Name Resolve-OutputPath -ErrorAction SilentlyContinue)) {
            throw "Resolve-OutputPath utility is not available. Ensure your Private helpers are loaded."
        }
        $resolvedPath = Resolve-OutputPath -Path $OutputPath
        Export-UTCMSnapshot -Snapshot $baseline -Path $resolvedPath -Format JSON -Overwrite | Out-Null
    }

    # Optionally compare against the current state
    $diff = $null
    if ($CompareToCurrent) {
        if (-not (Get-Command -Name Get-UTCMCurrentStateSnapshot -ErrorAction SilentlyContinue)) {
            throw "Get-UTCMCurrentStateSnapshot is not available in this module."
        }
        if (-not (Get-Command -Name Compare-UTCMConfiguration -ErrorAction SilentlyContinue)) {
            throw "Compare-UTCMConfiguration is not available in this module."
        }

        # ── Resolve resources for the current-state snapshot ──────────────
        $compResources = $null

        if ($CompareResources -and $CompareResources.Count -gt 0) {
            # Explicit resource list wins
            $compResources = $CompareResources
        }
        elseif ($ComparePreset) {
            # Named preset
            $compResources = Resolve-UTCMResources -Preset $ComparePreset
        }

        if (-not $compResources) {
            # Derive from baseline snapshot items
            $baselineDetail = Get-UTCMSnapshot -SnapshotId $SnapshotId -IncludeItems
            $baselineResources = @($baselineDetail.configurationItems |
                ForEach-Object { $_.type } | Select-Object -Unique)

            if (-not $NoPrompt) {
                # Interactive: offer presets or same-as-baseline
                $presets     = Get-UTCMResourcePresets
                $presetNames = @($presets.Keys | Sort-Object)

                Write-Host "`nCompare resources:" -ForegroundColor Cyan
                Write-Host "[Enter]  Same as baseline ($($baselineResources.Count) resource types)"
                $i = 1
                foreach ($pn in $presetNames) {
                    Write-Host ("[{0}]  {1} ({2} resources)" -f $i, $pn, $presets[$pn].Count)
                    $i++
                }

                $choice = Read-Host "`nPress Enter for same as baseline, or select a preset number"

                if ($choice) {
                    $idx = $choice -as [int]
                    if ($idx -ge 1 -and $idx -le $presetNames.Count) {
                        $selectedPreset = $presetNames[$idx - 1]
                        $compResources  = @($presets[$selectedPreset])
                        Write-Host ("Using preset '{0}' for comparison." -f $selectedPreset) -ForegroundColor Green
                    } else {
                        Write-Warning "Invalid selection — using same resources as baseline."
                    }
                }
            }

            if (-not $compResources) {
                $compResources = $baselineResources
            }
        }

        if (-not $compResources -or $compResources.Count -eq 0) {
            throw "Could not determine resources for current-state comparison."
        }

        Write-Host ("Creating current-state snapshot with {0} resource type(s)..." -f $compResources.Count) -ForegroundColor Cyan
        $current = Get-UTCMCurrentStateSnapshot -Resources $compResources -PollingIntervalSeconds $PollingIntervalSeconds

        $diff = Compare-UTCMConfiguration -BaselineSnapshotId $SnapshotId -CompareSnapshotId $current.id

        # Fetch current items for full-state page in the drift report
        $currentItems = $null
        try {
            $currentSnap = Get-UTCMSnapshot -SnapshotId $current.id -IncludeItems
            if ($currentSnap.PSObject.Properties.Name -contains 'configurationItems') {
                $currentItems = $currentSnap.configurationItems
            }
        } catch {
            Write-Warning "Could not fetch current snapshot items for full-state report: $($_.Exception.Message)"
        }
    }

    # Optional dashboard (render only if we have a diff)
    if ($Dashboard -and -not $diff) {
        Write-Warning "No drift comparison was performed — nothing to render. Use -CompareToCurrent to generate a diff."
    }
    if ($Dashboard -and $diff) {
        if (-not (Get-Command -Name Resolve-OutputPath -ErrorAction SilentlyContinue)) {
            throw "Resolve-OutputPath utility is not available. Ensure your Private helpers are loaded."
        }
        $resolved = Resolve-OutputPath -Path $OutputPath

        if (-not (Get-Command -Name New-UTCMDriftReport -ErrorAction SilentlyContinue)) {
            throw "New-UTCMDriftReport is not available in this module."
        }

        $reportParams = @{
            Diff       = $diff
            SnapshotId = $SnapshotId
            OutputPath = $resolved
        }
        if ($currentItems) {
            $reportParams['CurrentItems'] = $currentItems
        }

        New-UTCMDriftReport @reportParams | Out-Null
    }

    return $diff
}