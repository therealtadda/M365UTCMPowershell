function Get-UTCMSnapshot {
    [CmdletBinding()]
    param(
        # Validate at bind time; throw a friendly message if invalid
        [Parameter(Mandatory)]
        [ValidateScript({
            if (-not (Validate-Guid $_)) { throw "SnapshotId '$_' is not a valid GUID." }
            $true
        })]
        [string]$SnapshotId
    )

    Ensure-GraphConnection

    # No body-level GUID checks needed now
    return Invoke-GraphRequestWithRetry -Method 'GET' -Uri "$($script:SnapshotJobsUri)/$SnapshotId?`$expand=configurationItems"
}