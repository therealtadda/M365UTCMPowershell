function Get-UTCMCurrentStateSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Resources,

        [ValidateRange(5,300)]
        [int]$PollingIntervalSeconds = 10,

        [switch]$AllowPartialComparison
    )

    $job = New-UTCMSnapshot -Resources $Resources -PollingIntervalSeconds $PollingIntervalSeconds `
        -DisplayName 'UTCM Temp Current State' -Description 'Temporary snapshot for comparison'
    Assert-UTCMComparableSnapshot -Snapshot $job -Role 'Current-state' -AllowPartialComparison:$AllowPartialComparison

    $snapshot = Get-UTCMSnapshot -SnapshotId $job.id -IncludeItems
    Assert-UTCMComparableSnapshot -Snapshot $snapshot -Role 'Current-state' -AllowPartialComparison:$AllowPartialComparison
    return $snapshot
}