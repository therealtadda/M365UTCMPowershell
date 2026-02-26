function Get-UTCMTenantDriftReport {
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

        [string[]] $GraphScopes = @('ConfigurationMonitoring.ReadWrite.All')
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
        $jsonPath     = Join-Path -Path $resolvedPath -ChildPath ("Snapshot-{0}.json" -f $SnapshotId)
        Export-UTCMSnapshot -Snapshot $baseline -Path $jsonPath -Overwrite | Out-Null
    }

    # Optionally compare against the current state
    $diff = $null
    if ($CompareToCurrent) {
        # This helper is assumed to create a 'current' snapshot and return the job object
        if (-not (Get-Command -Name Get-UTCMCurrentStateSnapshot -ErrorAction SilentlyContinue)) {
            throw "Get-UTCMCurrentStateSnapshot is not available in this module."
        }

        $current = Get-UTCMCurrentStateSnapshot -PollingIntervalSeconds $PollingIntervalSeconds

        if (-not (Get-Command -Name Compare-UTCMConfiguration -ErrorAction SilentlyContinue)) {
            throw "Compare-UTCMConfiguration is not available in this module."
        }

        # Compare by snapshot Ids for clarity (re-fetch or use ids directly, your compare cmdlet handles it)
        $diff = Compare-UTCMConfiguration -BaselineSnapshotId $SnapshotId -CompareSnapshotId $current.id
    }

    # Optional dashboard (render only if we have a diff)
    if ($Dashboard -and $diff) {
        if (-not (Get-Command -Name Resolve-OutputPath -ErrorAction SilentlyContinue)) {
            throw "Resolve-OutputPath utility is not available. Ensure your Private helpers are loaded."
        }
        $resolved = Resolve-OutputPath -Path $OutputPath

        if (-not (Get-Command -Name New-UTCMDriftReport -ErrorAction SilentlyContinue)) {
            throw "New-UTCMDriftReport is not available in this module."
        }

        New-UTCMDriftReport -Diff $diff -SnapshotId $SnapshotId -OutputPath $resolved | Out-Null
    }

    return $diff
}