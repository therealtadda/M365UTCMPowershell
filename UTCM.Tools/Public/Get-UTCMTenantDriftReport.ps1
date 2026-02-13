function Get-UTCMTenantDriftReport {
    [CmdletBinding()]
    param(
        [switch]$CreateSnapshot,

        # Optional SnapshotId: validate only when supplied (allow null for interactive selection)
        [ValidateScript({
            if ($_ -and -not (Validate-Guid $_)) { throw "SnapshotId '$_' is not a valid GUID." }
            $true
        })]
        [string]$SnapshotId,

        [switch]$CompareToCurrent,
        [switch]$ExportJson,
        [switch]$Dashboard,
        [switch]$ListSnapshots,
        [switch]$NoPrompt,

        [ValidateNotNullOrEmpty()]
        [string]$OutputPath = ".\",

        [ValidateRange(5,300)]
        [int]$PollingIntervalSeconds = 10,

        [string[]]$GraphScopes = @('ConfigurationMonitoring.ReadWrite.All')
    )

    # Ensure Graph session
    Ensure-GraphConnection -Scopes $GraphScopes

    if ($ListSnapshots) {
        return Get-UTCMAvailableSnapshot
    }

    # No SnapshotId provided and no CreateSnapshot => interactive selection unless -NoPrompt
    if (-not $SnapshotId -and -not $CreateSnapshot) {
        $snapshots = Get-UTCMAvailableSnapshot
        if (-not $snapshots -or $snapshots.Count -eq 0) {
            throw "No snapshots exist. Use -CreateSnapshot to generate a new baseline."
        }

        if ($NoPrompt) {
            throw "No SnapshotId provided and -NoPrompt is set. Provide -SnapshotId or use -CreateSnapshot."
        }

        Write-Host "`nAvailable Snapshots:`n" -ForegroundColor Cyan
        $i = 1
        foreach ($s in $snapshots) {
            Write-Host ("[{0}]  {1}  ({2})  Created: {3}  Status: {4}" -f $i, $s.displayName, $s.id, $s.createdDateTime, $s.status)
            $i++
        }

        $selection = Read-Host "`nSelect a snapshot number to use as baseline"
        if (-not ($selection -as [int]) -or $selection -lt 1 -or $selection -gt $snapshots.Count) {
            throw "Invalid snapshot selection."
        }

        $SnapshotId = $snapshots[$selection - 1].id
    }

    if ($CreateSnapshot) {
        $SnapshotId = New-UTCMSnapshot -PollingIntervalSeconds $PollingIntervalSeconds
    }

    # Fetch baseline snapshot
    $baseline = Get-UTCMSnapshot -SnapshotId $SnapshotId

    # Export baseline if requested
    if ($ExportJson) {
        $resolvedPath = Resolve-OutputPath -Path $OutputPath
        $jsonPath = Join-Path -Path $resolvedPath -ChildPath ("Snapshot-{0}.json" -f $SnapshotId)
        Export-UTCMSnapshot -Snapshot $baseline -Path $jsonPath | Out-Null
    }

    # Compare against current (optional)
    $diff = $null
    if ($CompareToCurrent) {
        $current = Get-UTCMCurrentStateSnapshot -PollingIntervalSeconds $PollingIntervalSeconds

        # Reuse compare function (this re-fetches by ID; simple and explicit)
        $diff = Compare-UTCMConfiguration -BaselineSnapshotId $SnapshotId -CompareSnapshotId $current.id
    }

    # Dashboard (optional)
    if ($Dashboard -and $diff) {
        $resolved = Resolve-OutputPath -Path $OutputPath
        New-UTCMDriftReport -Diff $diff -SnapshotId $SnapshotId -OutputPath $resolved | Out-Null
    }

    return $diff
}