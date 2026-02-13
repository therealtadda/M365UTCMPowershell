function Compare-UTCMConfiguration {
    [CmdletBinding(DefaultParameterSetName='ByTwoSnapshots')]
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
        [int]$PollingIntervalSeconds = 10
    )

    Ensure-GraphConnection

    # Fetch baseline snapshot
    $baseline = Get-UTCMSnapshot -SnapshotId $BaselineSnapshotId

    # Fetch comparison snapshot (either current-state temp or another fixed snapshot)
    if ($PSCmdlet.ParameterSetName -eq 'AgainstCurrent') {
        $compare = Get-UTCMCurrentStateSnapshot -PollingIntervalSeconds $PollingIntervalSeconds
    } else {
        $compare = Get-UTCMSnapshot -SnapshotId $CompareSnapshotId
    }

    # Normalize to stable comparison set (avoid slow JSON roundtrips on entire object)
    $baselineItems = $baseline.configurationItems | ForEach-Object {
        [pscustomobject]@{
            id             = $_.id
            displayName    = $_.displayName
            type           = $_.type
            normalizedData = ConvertTo-NormalizedJson -InputObject $_.data
        }
    }

    $compareItems = $compare.configurationItems | ForEach-Object {
        [pscustomobject]@{
            id             = $_.id
            displayName    = $_.displayName
            type           = $_.type
            normalizedData = ConvertTo-NormalizedJson -InputObject $_.data
        }
    }

    # Compare by stable keys + normalized payload
    $diff = Compare-Object -ReferenceObject $baselineItems -DifferenceObject $compareItems `
                           -Property id, displayName, type, normalizedData -PassThru

    return $diff
}