function Compare-UTCMConfiguration {
    <#
    .SYNOPSIS
        Compares two UTCM snapshots or a baseline snapshot against the current tenant state.

    .DESCRIPTION
        Downloads configuration items from both snapshots, normalizes them via
        ConvertTo-NormalizedJson, and runs Compare-Object to produce a diff.

        Two parameter sets:
          ByTwoSnapshots   — compare BaselineSnapshotId vs CompareSnapshotId.
          AgainstCurrent   — use the baseline's original requested resources, including empty types, create a temp current-state
                             snapshot, and compare.
        Incomplete snapshots are rejected by default. A known-partial baseline is rejected
        before a current-state job is created. The explicit partial override is for investigation,
        not reliable unattended drift conclusions.

    .PARAMETER BaselineSnapshotId
        GUID of the baseline snapshot (mandatory in both parameter sets).

    .PARAMETER CompareSnapshotId
        GUID of the second snapshot to compare against (ByTwoSnapshots set only).

    .PARAMETER PollingIntervalSeconds
        Seconds between polls when creating a current-state snapshot. Default: 10.

    .PARAMETER AllowPartialComparison
        Explicitly allow partiallySuccessful snapshots, with prominent warnings.
        Missing data and an empty diff cannot establish reliable drift or absence of drift.

    .OUTPUTS
        Array of diff objects with id, displayName, type, normalizedData, and SideIndicator.
        '=>' = added/changed in current. '<=' = missing/changed from baseline.

    .EXAMPLE
        Compare-UTCMConfiguration -BaselineSnapshotId $baseId -CompareSnapshotId $compId

    .EXAMPLE
        # Compare baseline to live tenant
        Compare-UTCMConfiguration -BaselineSnapshotId $baseId
    #>
    [CmdletBinding(DefaultParameterSetName='AgainstCurrent')]
    param(
        # Baseline is mandatory for both parameter sets
        [Parameter(Mandatory, ParameterSetName='ByTwoSnapshots')]
        [Parameter(Mandatory, ParameterSetName='AgainstCurrent')]
        [ValidateScript({
            if (-not (Validate-Guid $_)) { throw "BaselineSnapshotId '$_' is not a valid GUID." }
            $true
        })]
        [string]$BaselineSnapshotId,

        # Only required when comparing two static snapshots
        [Parameter(Mandatory, ParameterSetName='ByTwoSnapshots')]
        [ValidateScript({
            if (-not (Validate-Guid $_)) { throw "CompareSnapshotId '$_' is not a valid GUID." }
            $true
        })]
        [string]$CompareSnapshotId,

        # Only used for AgainstCurrent
        [Parameter(ParameterSetName='AgainstCurrent')]
        [ValidateRange(5,300)]
        [int]$PollingIntervalSeconds = 10,

        [switch]$AllowPartialComparison
    )

    if ($PSCmdlet.ParameterSetName -eq 'AgainstCurrent') {
        Ensure-GraphConnection
    } else {
        Ensure-GraphConnection -ReadOnly
    }

    $baseline = Get-UTCMSnapshot -SnapshotId $BaselineSnapshotId -IncludeDetails
    Assert-UTCMComparableSnapshot -Snapshot $baseline -Role 'Baseline' -AllowPartialComparison:$AllowPartialComparison

    if ($PSCmdlet.ParameterSetName -eq 'AgainstCurrent') {
        $baselineResources = @(Get-UTCMComparisonResource -Snapshot $baseline)
    } else {
        $compare = Get-UTCMSnapshot -SnapshotId $CompareSnapshotId -IncludeDetails
        Assert-UTCMComparableSnapshot -Snapshot $compare -Role 'Comparison' -AllowPartialComparison:$AllowPartialComparison
    }

    $baselineDetail = Get-UTCMSnapshot -SnapshotId $BaselineSnapshotId -IncludeItems
    Assert-UTCMComparableSnapshot -Snapshot $baselineDetail -Role 'Baseline' -AllowPartialComparison:$AllowPartialComparison

    # Fetch comparison snapshot (either current-state temp or another fixed snapshot)
    if ($PSCmdlet.ParameterSetName -eq 'AgainstCurrent') {
        $compare = Get-UTCMCurrentStateSnapshot -Resources $baselineResources -PollingIntervalSeconds $PollingIntervalSeconds `
            -AllowPartialComparison:$AllowPartialComparison
        Assert-UTCMComparableSnapshot -Snapshot $compare -Role 'Comparison' -AllowPartialComparison:$AllowPartialComparison
        $compareDetail = $compare
    } else {
        $compareDetail = Get-UTCMSnapshot -SnapshotId $CompareSnapshotId -IncludeItems
        Assert-UTCMComparableSnapshot -Snapshot $compareDetail -Role 'Comparison' -AllowPartialComparison:$AllowPartialComparison
    }

    foreach ($snapshot in @($baselineDetail, $compareDetail)) {
        $diagnostic = Get-UTCMSnapshotDiagnostic -Snapshot $snapshot
        if ($diagnostic.status -eq 'partiallySuccessful') {
            Write-Warning (("INCOMPLETE COMPARISON: -AllowPartialComparison includes snapshot '{0}' with status " +
                "'partiallySuccessful'. Missing/added rows may reflect extraction failures; an empty diff does not " +
                "prove absence of drift. Do not use these results as unattended drift conclusions. {1}") -f
                $diagnostic.id, $diagnostic.errorSummary)
        }
    }

    # Normalize to stable comparison set (avoid slow JSON roundtrips on entire object)
    $baselineItems = @($baselineDetail.configurationItems | Where-Object { $null -ne $_ } | ForEach-Object {
        [pscustomobject]@{
            id             = $_.id
            displayName    = $_.displayName
            type           = $_.type
            normalizedData = ConvertTo-NormalizedJson -InputObject $_.data
        }
    })

    $compareItems = @($compareDetail.configurationItems | Where-Object { $null -ne $_ } | ForEach-Object {
        [pscustomobject]@{
            id             = $_.id
            displayName    = $_.displayName
            type           = $_.type
            normalizedData = ConvertTo-NormalizedJson -InputObject $_.data
        }
    })

    # Compare by stable keys + normalized payload
    $diff = Compare-Object -ReferenceObject $baselineItems -DifferenceObject $compareItems `
                           -Property id, displayName, type, normalizedData -PassThru

    return $diff
}