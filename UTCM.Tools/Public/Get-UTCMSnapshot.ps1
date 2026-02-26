function Get-UTCMSnapshot {
    [CmdletBinding()]
    param(
        # Validate at bind time; throw a friendly message if invalid
        [Parameter(Mandatory)]
        [ValidateScript({
            if (-not (Validate-Guid $_)) { throw "SnapshotId '$_' is not a valid GUID." }
            $true
        })]
        [string] $SnapshotId,

        # Include resourceLocation + errorDetails in the server-side projection
        [switch] $IncludeDetails,

        # Download the artifact from resourceLocation and attach configurationItems
        [switch] $IncludeItems,

        # Return JSON instead of an object
        [switch] $AsJson
    )

    # Ensure we have a Graph token (uses the module helper if present)
    if (Get-Command -Name Ensure-GraphConnection -ErrorAction SilentlyContinue) {
        Ensure-GraphConnection
    }

    # 1) Build $select to minimize payload from Graph
    $select = @('id','displayName','description','createdDateTime','completedDateTime','status')
    if ($IncludeDetails -or $IncludeItems) {
        $select += @('resourceLocation','errorDetails')
    }
    $qs = "`$select=" + [System.Uri]::EscapeDataString(($select -join ','))

    # 2) GET the job
    $uri = "$($script:SnapshotJobsUri)/$SnapshotId?$qs"
    $job = Invoke-GraphRequestWithRetry -Method 'GET' -Uri $uri

    # 3) If the caller wants items, download from resourceLocation (for completed jobs)
    if ($IncludeItems) {
        # Validate job status first
        if ($job.status -eq 'failed') {
            $err = ($job.PSObject.Properties.Name -contains 'errorDetails') ? ($job.errorDetails -join '; ') : 'n/a'
            throw ("Snapshot job '{0}' failed. Errors: {1}" -f $job.id, $err)
        }
        if ($job.status -notin @('succeeded','partiallySuccessful')) {
            throw ("Snapshot job '{0}' is not completed yet. Current status: '{1}'." -f $job.id, $job.status)
        }
        if (-not $job.resourceLocation -or [string]::IsNullOrWhiteSpace($job.resourceLocation)) {
            throw "Snapshot job '$($job.id)' does not expose resourceLocation; cannot retrieve items."
        }

        # Download to temp, parse as JSON, attach configurationItems
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            Invoke-WebRequest -Uri $job.resourceLocation -OutFile $tmp -UseBasicParsing -ErrorAction Stop
            $raw  = Get-Content -LiteralPath $tmp -Raw
            $json = $null
            try { $json = $raw | ConvertFrom-Json -ErrorAction Stop } catch { $json = $null }

            if ($null -eq $json) {
                throw "Downloaded artifact is not JSON; cannot extract items."
            }

            $items = $null
            if ($json.PSObject.Properties.Name -contains 'configurationItems') {
                $items = $json.configurationItems
            } elseif ($json -is [System.Collections.IEnumerable]) {
                $items = $json
            } else {
                throw "Artifact JSON does not contain 'configurationItems' and is not an array—cannot extract items."
            }

            # Attach to returned object (add/overwrite configurationItems)
            if ($job.PSObject.Properties.Name -contains 'configurationItems') {
                $job.configurationItems = $items
            } else {
                Add-Member -InputObject $job -NotePropertyName configurationItems -NotePropertyValue $items -Force
            }
        }
        finally {
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        }
    }

    # 4) Output
    if ($AsJson) {
        return ($job | ConvertTo-Json -Depth 99)
    }

    # If caller didn’t ask for details/items, return a concise view (back-compat)
    if (-not $IncludeDetails -and -not $IncludeItems) {
        return $job | Select-Object id, displayName, createdDateTime, status
    }

    # If details requested, pass through the richer object
    return $job
}