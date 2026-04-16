function Remove-UTCMSnapshot {
    <#
    .SYNOPSIS
        Deletes a UTCM snapshot job by ID.

    .DESCRIPTION
        Sends DELETE /beta/admin/configurationManagement/configurationSnapshotJobs/{id}
        to permanently remove a snapshot job and its associated artifact.

    .PARAMETER SnapshotId
        The GUID of the snapshot job to delete.

    .EXAMPLE
        Remove-UTCMSnapshot -SnapshotId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'

    .EXAMPLE
        # Delete all failed snapshots
        Get-UTCMAvailableSnapshot -Status failed | ForEach-Object { Remove-UTCMSnapshot -SnapshotId $_.id }
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('id')]
        [ValidateScript({
            if (-not (Validate-Guid $_)) { throw "SnapshotId '$_' is not a valid GUID." }
            $true
        })]
        [string] $SnapshotId
    )

    process {
        if (Get-Command -Name Ensure-GraphConnection -ErrorAction SilentlyContinue) {
            Ensure-GraphConnection
        }

        if (-not $PSCmdlet.ShouldProcess($SnapshotId, "Delete UTCM snapshot job")) {
            return
        }

        $uri = "$($script:SnapshotJobsUri)/${SnapshotId}"
        Invoke-GraphRequestWithRetry -Method 'DELETE' -Uri $uri | Out-Null

        if (Get-Command -Name Write-Log -ErrorAction SilentlyContinue) {
            Write-Log -Message "Deleted snapshot job: $SnapshotId" -Color Green
        }
    }
}
