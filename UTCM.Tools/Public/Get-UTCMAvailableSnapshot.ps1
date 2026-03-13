function Get-UTCMAvailableSnapshot {
    [CmdletBinding()]
    param(
        # Original switch kept for compatibility
        [switch] $AsJson,

        # New: filter to specific status(es); auto-validated
        [ValidateSet('notStarted','running','succeeded','failed','partiallySuccessful')]
        [string[]] $Status,

        # New: convenience — equivalent to -Status succeeded,partiallySuccessful (unless -Status is explicitly provided)
        [switch] $OnlyCompleted,

        # New: time window filters (UTC ISO 8601 in server-side OData $filter)
        [datetime] $Since,
        [datetime] $Until,

        # New: return at most N newest items (client-side)
        [int] $Top = 0,

        # New: include extra fields (resourceLocation, errorDetails) in server-side $select
        [switch] $IncludeDetails,

        # New: custom $select (comma-separated field names); overrides -IncludeDetails if provided
        [string[]] $Select,

        # New: keep only jobs that expose a downloadable resourceLocation (client-side filter).
        # If needed, this automatically adds resourceLocation to $select.
        [switch] $DownloadableOnly
    )

    # Ensure a Graph token is available
    if (Get-Command -Name Ensure-GraphConnection -ErrorAction SilentlyContinue) {
        Ensure-GraphConnection
    }

    # -------------------------------
    # Build $select
    # -------------------------------
    $selectList = @()
    if ($Select -and $Select.Count -gt 0) {
        $selectList = $Select
    } else {
        if ($IncludeDetails -or $DownloadableOnly) {
            $selectList = @('id','displayName','createdDateTime','status','resourceLocation','errorDetails')
        } else {
            $selectList = @('id','displayName','createdDateTime','status')
        }
    }

    # -------------------------------
    # Build $filter (OData) for server-side filtering
    # -------------------------------
    $filters = @()

    if ($Since) {
        # ISO 8601 "o" (round-trip) format
        $filters += "createdDateTime ge " + $Since.ToString("o")
    }
    if ($Until) {
        $filters += "createdDateTime le " + $Until.ToString("o")
    }

    # -OnlyCompleted implies succeeded/partiallySuccessful if -Status not explicitly provided
    if ($OnlyCompleted -and -not $Status) {
        $Status = @('succeeded','partiallySuccessful')
    }
    if ($Status) {
        if ($Status.Count -eq 1) {
            $filters += "status eq '$($Status[0])'"
        } else {
            $filters += '(' + (($Status | ForEach-Object { "status eq '$_'" }) -join ' or ') + ')'
        }
    }

    # Assemble querystring
    $qs = @()
    if ($selectList.Count -gt 0) {
        $qs += "`$select=" + [System.Uri]::EscapeDataString(($selectList -join ','))
    }
    if ($filters.Count -gt 0) {
        $qs += "`$filter=" + [System.Uri]::EscapeDataString(($filters -join ' and '))
    }

    $uri = $script:SnapshotJobsUri
    if ($qs.Count -gt 0) {
        $uri = $uri + '?' + ($qs -join '&')
    }

    # -------------------------------
    # Page through all results
    # -------------------------------
    $all = @()
    do {
        $page = Invoke-GraphRequestWithRetry -Method 'GET' -Uri $uri
        if ($page.value) { $all += $page.value }
        $uri = $null
        if ($page -is [System.Collections.IDictionary]) {
            if ($page.ContainsKey('@odata.nextLink')) { $uri = $page['@odata.nextLink'] }
        } elseif ($page.PSObject.Properties.Match('@odata.nextLink').Count) {
            $uri = $page.'@odata.nextLink'
        }
    } while ($uri)

    # -------------------------------
    # Client-side shaping
    # -------------------------------

    # Sort newest first
    $sorted = $all | Sort-Object createdDateTime -Descending

    # Keep only jobs that have a download URL if requested
    if ($DownloadableOnly) {
        # Ensure resourceLocation exists in projection; if not, we still filter client-side defensively
        $sorted = $sorted | Where-Object { $_.resourceLocation -and -not [string]::IsNullOrWhiteSpace($_.resourceLocation) }
    }

    # Apply Top if provided
    if ($Top -gt 0) {
        $sorted = $sorted | Select-Object -First $Top
    }

    # Output formatting
    if ($AsJson) {
        return ($sorted | ConvertTo-Json -Depth 10)
    }

    # If the caller provided a custom -Select, return the objects as-is to honor the projection
    if ($Select) {
        return $sorted
    }

    # Otherwise, present a friendly view
    if ($IncludeDetails -or $DownloadableOnly) {
        return ($sorted | Select-Object id, displayName, createdDateTime, status, resourceLocation, errorDetails)
    } else {
        return ($sorted | Select-Object id, displayName, createdDateTime, status)
    }
}