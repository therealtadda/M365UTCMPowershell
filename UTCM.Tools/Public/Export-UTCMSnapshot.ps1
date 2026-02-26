function Export-UTCMSnapshot {
    <#
    .SYNOPSIS
        Download and export a completed UTCM snapshot to disk; optionally split by resource type.

    .DESCRIPTION
        Accepts either a configurationSnapshotJob object (as returned by New-UTCMSnapshot) or a job Id (GUID).
        If the job isn't completed yet, this function polls the documented endpoint until a terminal status is reached.
        It then downloads from job.resourceLocation. For JSON payloads:
            - Default: writes ONLY the 'configurationItems' array (back-compat).
            - -Raw:     writes the entire JSON file.
            - -SplitByResourceType: creates one JSON file per resource instance under <Path>\{workload}\{resourceType}\{name|id}.json.
              (When splitting, Path should be a directory; it will be created if missing.)

        Endpoints:
          GET /beta/admin/configurationManagement/configurationSnapshotJobs/{id}

        Terminal statuses:
          succeeded, failed, optionally partiallySuccessful.

        Preview limits:
          Snapshots retained 7 days; max 12 visible jobs; ~20,000 resources/tenant/month.

    .PARAMETER Snapshot
        A configurationSnapshotJob object or a job Id (GUID/string).

    .PARAMETER Path
        Destination path.
        - If -SplitByResourceType is NOT specified: Path is a FILE path; the parent directory is created if missing.
        - If -SplitByResourceType is specified:     Path is treated as a DIRECTORY; it (and subfolders) will be created.

    .PARAMETER PollingIntervalSeconds
        Delay between status polls if the job is not yet complete. (5..300, default 10)

    .PARAMETER Raw
        When specified, write the FULL JSON payload returned by resourceLocation rather than just 'configurationItems'.
        (Ignored if splitting, where items are always derived from 'configurationItems' if present; otherwise entire payload if array.)

    .PARAMETER SplitByResourceType
        Write one file per resource instance organized under <Path>\{workload}\{resourceType}\{name-or-id}.json.

    .PARAMETER NameFieldOrder
        Field precedence to build per-file names when splitting. Default: displayName, name, id.

    .PARAMETER Overwrite
        Overwrite the destination file if it exists (non-splitting mode) or overwrite existing files when splitting.

    .PARAMETER WriteErrorFileOnFailure
        When a job is failed, write an error JSON file with job metadata + errorDetails.

    .PARAMETER ErrorPath
        File or directory path to write the error JSON to (used with -WriteErrorFileOnFailure).
        If a directory is provided, the error file name is 'snapshot-<jobId>-error.json'.

    .OUTPUTS
        String or String[] (the final file path(s))
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory)] $Snapshot,
        [Parameter(Mandatory)][string] $Path,
        [ValidateRange(5,300)][int] $PollingIntervalSeconds = 10,
        [switch] $Raw,
        [switch] $SplitByResourceType,
        [string[]] $NameFieldOrder = @('displayName','name','id'),
        [switch] $Overwrite,
        [switch] $WriteErrorFileOnFailure,
        [string] $ErrorPath
    )

    # --- Local helpers -------------------------------------------------------
    function _WriteLog([string]$msg, [string]$color='Gray') {
        if (Get-Command -Name Write-Log -ErrorAction SilentlyContinue) {
            Write-Log -Message $msg -Color $color
        } else {
            Write-Host ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) -ForegroundColor $color
        }
    }

    function _Sanitize([string]$name) {
        if ([string]::IsNullOrWhiteSpace($name)) { return $null }
        $invalidChars = [IO.Path]::GetInvalidFileNameChars() -join ''
        $charClass    = '[{0}]' -f [regex]::Escape($invalidChars)
        $safe = ($name -replace $charClass, '_').Trim()
        if ($safe.Length -gt 150) { $safe = $safe.Substring(0,150) }
        return $safe
    }

    function _WorkloadFromResourceType([string]$resourceType) {
        if ([string]::IsNullOrWhiteSpace($resourceType)) { return 'unknown' }
        if ($resourceType -match '^microsoft\.([a-z0-9]+)') { return $Matches[1] }
        return 'unknown'
    }

    function _EnsureDirectory([string]$dir) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        } elseif (-not (Get-Item -LiteralPath $dir).PSIsContainer) {
            throw "Path '$dir' exists and is not a directory."
        }
    }

    function _WriteErrorJson($job, [string]$errPath) {
        try {
            $payload = [pscustomobject]@{
                jobId         = $job.id
                status        = $job.status
                errorDetails  = $job.errorDetails
                createdDate   = $job.createdDateTime
                completedDate = $job.completedDateTime
            }

            $target = $errPath
            if ([string]::IsNullOrWhiteSpace($target)) {
                $target = Join-Path -Path (Split-Path -Parent $Path) -ChildPath ("snapshot-{0}-error.json" -f $job.id)
            } elseif ((Test-Path -LiteralPath $target) -and (Get-Item -LiteralPath $target).PSIsContainer) {
                $target = Join-Path -Path $target -ChildPath ("snapshot-{0}-error.json" -f $job.id)
            } else {
                $parent = Split-Path -Path $target -Parent
                if ($parent) { _EnsureDirectory $parent }
            }

            $payload | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $target -Encoding UTF8
            _WriteLog ("Wrote job failure details to '$target'") 'Yellow'
        } catch {
            _WriteLog ("Failed to write failure details: $($_.Exception.Message)") 'Red'
        }
    }
    # -------------------------------------------------------------------------

    # Ensure Graph connection if your module provides the helper
    if (Get-Command -Name Ensure-GraphConnection -ErrorAction SilentlyContinue) {
        Ensure-GraphConnection
    }

    # Resolve the job object from input
    $job = $null
    if ($Snapshot -is [string]) {
        $jobId = $Snapshot
        $job   = Invoke-GraphRequestWithRetry -Method 'GET' -Uri "$($script:SnapshotJobsUri)/$jobId"
    } else {
        $job = $Snapshot
    }

    # If the job isn't terminal yet, poll until it completes
    while ($job.status -in @('notStarted','running')) {
        Start-Sleep -Seconds $PollingIntervalSeconds
        $job = Invoke-GraphRequestWithRetry -Method 'GET' -Uri "$($script:SnapshotJobsUri)/$($job.id)"
        _WriteLog ("Export poll: job $($job.id) status = $($job.status)") 'Gray'
    }

    # If job failed, optionally write error-details file, then throw
    if ($job.status -eq 'failed') {
        if ($WriteErrorFileOnFailure) {
            _WriteErrorJson -job $job -errPath $ErrorPath
        }
        $errors  = ($job.PSObject.Properties.Name -contains 'errorDetails') ? ($job.errorDetails -join '; ') : $null
        $errText = if ($errors) { $errors } else { 'n/a' }
        throw ("Snapshot job '{0}' failed. Errors: {1}" -f $job.id, $errText)
    }

    # Validate exportable statuses
    if ($job.status -notin @('succeeded','partiallySuccessful')) {
        $errors  = ($job.PSObject.Properties.Name -contains 'errorDetails') ? ($job.errorDetails -join '; ') : $null
        $errText = if ($errors) { $errors } else { '' }
        if ($WriteErrorFileOnFailure) {
            _WriteErrorJson -job $job -errPath $ErrorPath
        }
        throw ("Snapshot job '{0}' is not exportable. Status: '{1}'. {2}" -f $job.id, $job.status, $errText)
    }

    # Ensure resourceLocation exists
    if ([string]::IsNullOrWhiteSpace($job.resourceLocation)) {
        if ($WriteErrorFileOnFailure) {
            _WriteErrorJson -job $job -errPath $ErrorPath
        }
        throw "Snapshot job '$($job.id)' has no resourceLocation. Unable to export."
    }

    # Prepare destinations
    if ($SplitByResourceType) {
        _EnsureDirectory $Path   # Path is a directory in splitting mode
    } else {
        $parentDir = Split-Path -Path $Path -Parent
        if ($parentDir) { _EnsureDirectory $parentDir }
        if ((Test-Path -LiteralPath $Path) -and -not $Overwrite) {
            throw "Destination '$Path' already exists. Use -Overwrite to replace it."
        }
    }

    # Download to a temp file first (resourceLocation may be a SAS URL; no Graph token typically required)
    $tmp = [System.IO.Path]::GetTempFileName()
    $outPaths = @()

    try {
        if ($PSCmdlet.ShouldProcess($job.resourceLocation, "Download UTCM snapshot")) {
            Invoke-WebRequest -Uri $job.resourceLocation -OutFile $tmp -UseBasicParsing -ErrorAction Stop
        }

        # Try to interpret as JSON; if not JSON (e.g., ZIP), either write raw (non-splitting) or throw (splitting).
        $content = Get-Content -LiteralPath $tmp -Raw -ErrorAction Stop
        $json    = $null
        $isJson  = $false
        try {
            $json   = $content | ConvertFrom-Json -ErrorAction Stop
            $isJson = $true
        } catch {
            $isJson = $false
        }

        if (-not $isJson) {
            if ($SplitByResourceType) {
                throw "Downloaded snapshot appears to be non-JSON (e.g., ZIP). Splitting by resource type is not supported for this payload."
            }
            Copy-Item -LiteralPath $tmp -Destination $Path -Force
            _WriteLog ("Exported raw UTCM snapshot to '{0}' (job {1}, status {2})" -f $Path, $job.id, $job.status) 'Green'
            return $Path
        }

        # --- JSON payload handling ---
        if ($SplitByResourceType) {
            # Determine the items to split:
            # Prefer 'configurationItems' if present; else if the root is an array, split that; else error.
            $items = $null
            if ($json.PSObject.Properties.Name -contains 'configurationItems') {
                $items = $json.configurationItems
            } elseif ($json -is [System.Collections.IEnumerable]) {
                $items = $json
            } else {
                throw "JSON payload does not contain 'configurationItems' and is not an array—cannot split."
            }

            foreach ($item in $items) {
                # Get resourceType and workload
                $rt = $null
                if ($item.PSObject.Properties.Name -contains 'resourceType') { $rt = [string]$item.resourceType }
                elseif ($item.PSObject.Properties.Name -contains 'type')     { $rt = [string]$item.type }

                $workload = $null
                if ($item.PSObject.Properties.Name -contains 'workload')     { $workload = [string]$item.workload }
                if (-not $workload) { $workload = _WorkloadFromResourceType $rt }

                $safeWorkload = _Sanitize($workload)  ?? 'unknown'
                $safeRt       = _Sanitize($rt)        ?? 'unknown'

                # Choose a friendly file name based on NameFieldOrder
                $base = $null
                foreach ($f in $NameFieldOrder) {
                    if ($item.PSObject.Properties.Name -contains $f) {
                        $val  = [string]($item.($f))            # <-- FIXED dynamic access
                        $cand = _Sanitize($val)
                        if ($cand) { $base = $cand; break }
                    }
                }
                if (-not $base) { $base = _Sanitize([string]$item.id) }
                if (-not $base) { $base = [guid]::NewGuid().Guid }

                $subDir = Join-Path -Path $Path -ChildPath (Join-Path $safeWorkload $safeRt)
                _EnsureDirectory $subDir

                $filePath = Join-Path -Path $subDir -ChildPath ($base + '.json')
                if ((Test-Path -LiteralPath $filePath) -and -not $Overwrite) {
                    $filePath = Join-Path -Path $subDir -ChildPath ($base + '-' + ([guid]::NewGuid().ToString('N').Substring(0,6)) + '.json')
                }

                $item | ConvertTo-Json -Depth 99 | Out-File -LiteralPath $filePath -Encoding UTF8
                $outPaths += $filePath
            }

            _WriteLog ("Exported {0} items under '{1}' (job {2}, status {3})" -f $outPaths.Count, $Path, $job.id, $job.status) 'Green'
            return $outPaths
        }
        else {
            # Non-splitting JSON path
            if ($Raw) {
                $json | ConvertTo-Json -Depth 99 | Out-File -LiteralPath $Path -Encoding UTF8
            } else {
                if ($json.PSObject.Properties.Name -contains 'configurationItems') {
                    $json.configurationItems | ConvertTo-Json -Depth 99 | Out-File -LiteralPath $Path -Encoding UTF8
                } else {
                    $json | ConvertTo-Json -Depth 99 | Out-File -LiteralPath $Path -Encoding UTF8
                }
            }

            _WriteLog ("Exported UTCM snapshot to '{0}' (job {1}, status {2})" -f $Path, $job.id, $job.status) 'Green'
            return $Path
        }
    }
    catch {
        if ($WriteErrorFileOnFailure) {
            _WriteErrorJson -job $job -errPath $ErrorPath
        }
        throw
    }
    finally {
        # Cleanup temp
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}