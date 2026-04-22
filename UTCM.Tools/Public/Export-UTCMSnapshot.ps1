function Export-UTCMSnapshot {
    <#
    .SYNOPSIS
        Download and export a completed UTCM snapshot to disk in JSON, CSV, and/or HTML format.

    .DESCRIPTION
        Accepts either a configurationSnapshotJob object (as returned by New-UTCMSnapshot) or a job Id (GUID).
        If the job isn't completed yet, this function polls until a terminal status is reached.
        It then downloads from job.resourceLocation and writes the requested formats.

        Output formats (all enabled by default — use -Format to choose a subset):
            JSON — configurationItems array (or full payload with -Raw)
            CSV  — flat table with Id, DisplayName, Type, Workload, Data columns
            HTML — self-contained sortable dashboard of all configuration items

        Path behaviour:
            Path is always treated as a DIRECTORY (created if missing).
            Files are named Snapshot-{jobId}.{ext}.

        Legacy switches:
            -SplitByResourceType creates one JSON file per resource instance under
            <Path>\{workload}\{resourceType}\{name|id}.json (only JSON, ignores -Format).

    .PARAMETER Snapshot
        A configurationSnapshotJob object or a job Id (GUID/string).

    .PARAMETER Path
        Destination directory. Created if it does not exist.

    .PARAMETER Format
        Which formats to write. Default: JSON, CSV, HTML. E.g. -Format JSON,CSV

    .PARAMETER PollingIntervalSeconds
        Delay between status polls if the job is not yet complete. (5..300, default 10)

    .PARAMETER Raw
        Write the FULL JSON payload rather than just 'configurationItems'.

    .PARAMETER SplitByResourceType
        Write one JSON file per resource instance (ignores -Format).

    .PARAMETER NameFieldOrder
        Field precedence for per-file names when splitting. Default: displayName, name, id.

    .PARAMETER Overwrite
        Overwrite existing files.

    .PARAMETER WriteErrorFileOnFailure
        Write an error JSON file when a job has failed.

    .PARAMETER ErrorPath
        Path for the error JSON file.

    .OUTPUTS
        String[] — the file path(s) written.
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory)] $Snapshot,
        [Parameter(Mandatory)][string] $Path,
        [ValidateSet('JSON','CSV','HTML')]
        [string[]] $Format = @('JSON','CSV','HTML'),
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

    # Prepare destination directory (Path is always a directory now)
    _EnsureDirectory $Path

    # Download to a temp file first (resourceLocation is a Graph API URL that requires auth)
    $tmp = [System.IO.Path]::GetTempFileName()
    $outPaths = @()

    try {
        if ($PSCmdlet.ShouldProcess($job.resourceLocation, "Download UTCM snapshot")) {
            Invoke-MgGraphRequest -Method GET -Uri $job.resourceLocation -OutputFilePath $tmp -ErrorAction Stop
        }

        # Try to interpret as JSON; if not JSON (e.g., ZIP), write raw file and return.
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
            $rawPath = Join-Path -Path $Path -ChildPath ("Snapshot-{0}.bin" -f $job.id)
            Copy-Item -LiteralPath $tmp -Destination $rawPath -Force
            _WriteLog ("Exported raw UTCM snapshot to '{0}' (job {1}, status {2})" -f $rawPath, $job.id, $job.status) 'Green'
            return $rawPath
        }

        # Extract items. The UTCM snapshot payload uses 'resources' (with 'resourceType' /
        # 'properties' fields); older/alternate payloads may expose 'configurationItems'
        # (with 'type' / 'data' fields). Support both and normalize downstream.
        $items = $null
        if ($json.PSObject.Properties.Name -contains 'configurationItems') {
            $items = $json.configurationItems
        } elseif ($json.PSObject.Properties.Name -contains 'resources') {
            $items = $json.resources
        } elseif ($json -is [System.Collections.IEnumerable]) {
            $items = $json
        } else {
            $items = @($json)
        }

        # Local helpers that understand both field shapes
        function _GetItemId($item) {
            if ($item.PSObject.Properties.Name -contains 'id' -and $item.id) { return [string]$item.id }
            if ($item.PSObject.Properties.Name -contains 'resourceInstanceIdentifier' -and $item.resourceInstanceIdentifier) { return [string]$item.resourceInstanceIdentifier }
            # Prefer a stable Id from properties when available
            if ($item.PSObject.Properties.Name -contains 'properties' -and $item.properties) {
                foreach ($p in 'Id','Identity','Guid','ObjectId') {
                    if ($item.properties.PSObject.Properties.Name -contains $p -and $item.properties.$p) {
                        return [string]$item.properties.$p
                    }
                }
            }
            return ''
        }
        function _GetItemType($item) {
            if ($item.PSObject.Properties.Name -contains 'resourceType' -and $item.resourceType) { return [string]$item.resourceType }
            if ($item.PSObject.Properties.Name -contains 'type' -and $item.type) { return [string]$item.type }
            return ''
        }
        function _GetItemDataObject($item) {
            if ($item.PSObject.Properties.Name -contains 'properties') { return $item.properties }
            if ($item.PSObject.Properties.Name -contains 'data') { return $item.data }
            return $null
        }

        # --- SplitByResourceType (JSON only, existing behaviour) ---
        if ($SplitByResourceType) {
            foreach ($item in $items) {
                $rt = $null
                if ($item.PSObject.Properties.Name -contains 'resourceType') { $rt = [string]$item.resourceType }
                elseif ($item.PSObject.Properties.Name -contains 'type')     { $rt = [string]$item.type }

                $workload = $null
                if ($item.PSObject.Properties.Name -contains 'workload')     { $workload = [string]$item.workload }
                if (-not $workload) { $workload = _WorkloadFromResourceType $rt }

                $safeWorkload = _Sanitize($workload)  ?? 'unknown'
                $safeRt       = _Sanitize($rt)        ?? 'unknown'

                $base = $null
                foreach ($f in $NameFieldOrder) {
                    if ($item.PSObject.Properties.Name -contains $f) {
                        $val  = [string]($item.($f))
                        $cand = _Sanitize($val)
                        if ($cand) { $base = $cand; break }
                    }
                }
                if (-not $base -and $item.PSObject.Properties.Name -contains 'id') { $base = _Sanitize([string]$item.id) }
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

        # --- Multi-format export -----------------------------------------------
        $baseName = "Snapshot-{0}" -f $job.id

        # JSON
        if ('JSON' -in $Format) {
            $jsonPath = Join-Path -Path $Path -ChildPath ("$baseName.json")
            if ($Raw) {
                $json | ConvertTo-Json -Depth 99 | Out-File -LiteralPath $jsonPath -Encoding UTF8
            } else {
                $items | ConvertTo-Json -Depth 99 | Out-File -LiteralPath $jsonPath -Encoding UTF8
            }
            _WriteLog ("JSON  -> $jsonPath") 'Green'
            $outPaths += $jsonPath
        }

        # CSV
        if ('CSV' -in $Format) {
            $csvPath = Join-Path -Path $Path -ChildPath ("$baseName.csv")
            $items | ForEach-Object {
                $typeVal = _GetItemType $_
                $wl      = if ($_.PSObject.Properties.Name -contains 'workload' -and $_.workload) { [string]$_.workload }
                           else { _WorkloadFromResourceType $typeVal }
                $dataObj = _GetItemDataObject $_
                $dataStr = if ($null -ne $dataObj) {
                               try { $dataObj | ConvertTo-Json -Depth 99 -Compress } catch { [string]$dataObj }
                           } else { '' }
                [pscustomobject]@{
                    Id          = _GetItemId $_
                    DisplayName = $_.displayName
                    Type        = $typeVal
                    Workload    = $wl
                    Data        = $dataStr
                }
            } | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
            _WriteLog ("CSV   -> $csvPath") 'Green'
            $outPaths += $csvPath
        }

        # HTML
        if ('HTML' -in $Format) {
            $htmlPath = Join-Path -Path $Path -ChildPath ("$baseName.html")

            # Safe HTML encoder
            $encodeFn = if (Get-Command -Name HtmlEncode -ErrorAction SilentlyContinue) {
                { param($v) HtmlEncode $v }
            } else {
                { param($v) if ($null -eq $v) { '' } else { [System.Net.WebUtility]::HtmlEncode([string]$v) } }
            }

            $snapshotName = ''
            $createdStr   = ''
            try {
                if ($job.PSObject.Properties.Name -contains 'displayName') { $snapshotName = $job.displayName }
                if ($job.PSObject.Properties.Name -contains 'createdDateTime') { $createdStr = (Get-Date $job.createdDateTime).ToString('yyyy-MM-dd HH:mm:ss') }
            } catch {}

            # Group items by workload for summary
            $groups = @{}
            foreach ($item in $items) {
                $typeVal = _GetItemType $item
                if (-not $typeVal) { $typeVal = 'unknown' }
                $wl      = if ($item.PSObject.Properties.Name -contains 'workload' -and $item.workload) { [string]$item.workload }
                           else { _WorkloadFromResourceType $typeVal }
                if (-not $groups.ContainsKey($wl)) { $groups[$wl] = 0 }
                $groups[$wl]++
            }
            $summarySpans = ($groups.GetEnumerator() | Sort-Object Name | ForEach-Object {
                "<span style='background:#e0e0e0;padding:4px 8px;border-radius:4px;display:inline-block;margin:2px 4px'>" +
                (& $encodeFn $_.Name) + ": $($_.Value)</span>"
            }) -join ''

            $rowHtml = foreach ($item in $items) {
                $typeVal = _GetItemType $item
                $wl      = if ($item.PSObject.Properties.Name -contains 'workload' -and $item.workload) { [string]$item.workload }
                           else { _WorkloadFromResourceType $typeVal }
                $dataObj = _GetItemDataObject $item
                $dataJson = ''
                if ($null -ne $dataObj) {
                    try { $dataJson = $dataObj | ConvertTo-Json -Depth 99 } catch { $dataJson = [string]$dataObj }
                }
                $rowIdx = [guid]::NewGuid().ToString('N').Substring(0,8)
                $idVal  = _GetItemId $item
                "<tr>
                    <td>$(& $encodeFn $idVal)</td>
                    <td>$(& $encodeFn $item.displayName)</td>
                    <td>$(& $encodeFn $typeVal)</td>
                    <td>$(& $encodeFn $wl)</td>
                    <td><button class='toggleBtn' onclick=""toggleDetail('d$rowIdx')"">Show</button>
                        <div id='d$rowIdx' class='detail' style='display:none'><pre>$(& $encodeFn $dataJson)</pre></div></td>
                </tr>"
            }

            $html = @"
<html>
<head>
<meta charset="utf-8">
<title>UTCM Snapshot Export</title>
<style>
body { font-family: Arial, Helvetica, sans-serif; margin: 20px; }
h2 { margin-bottom: 6px; }
small { color: #666; }
table { border-collapse: collapse; width: 100%; margin-top: 10px; }
th, td { padding: 8px; border: 1px solid #ccc; text-align: left; vertical-align: top; }
th { background: #333; color: #fff; cursor: pointer; }
tr:nth-child(even) { background: #f9f9f9; }
tr:hover { background: #eef; }
.summary { margin-top: 10px; font-size: 13px; }
.toggleBtn { font-size: 11px; padding: 2px 8px; cursor: pointer; }
.detail pre { background: #f4f4f4; padding: 8px; border-radius: 4px; white-space: pre-wrap; word-break: break-word; max-height: 400px; overflow: auto; font-size: 12px; margin-top: 4px; }
</style>
<script>
function sortTable(n) {
  var table = document.getElementById("snapTable");
  var switching = true, dir = "asc";
  while (switching) {
    switching = false;
    var rows = table.rows;
    for (var i = 1; i < (rows.length - 1); i++) {
      var x = rows[i].getElementsByTagName("TD")[n];
      var y = rows[i + 1].getElementsByTagName("TD")[n];
      if ((dir == "asc"  && x.textContent.toLowerCase() > y.textContent.toLowerCase()) ||
          (dir == "desc" && x.textContent.toLowerCase() < y.textContent.toLowerCase())) {
        rows[i].parentNode.insertBefore(rows[i + 1], rows[i]);
        switching = true; break;
      }
    }
    if (!switching && dir == "asc") { dir = "desc"; switching = true; }
  }
}
function toggleDetail(id) {
  var el = document.getElementById(id);
  var btn = el.parentElement.querySelector('.toggleBtn');
  if (el.style.display === 'none') { el.style.display = 'block'; btn.textContent = 'Hide'; }
  else { el.style.display = 'none'; btn.textContent = 'Show'; }
}
function expandAll() {
  document.querySelectorAll('.detail').forEach(function(el){ el.style.display='block'; el.parentElement.querySelector('.toggleBtn').textContent='Hide'; });
}
function collapseAll() {
  document.querySelectorAll('.detail').forEach(function(el){ el.style.display='none'; el.parentElement.querySelector('.toggleBtn').textContent='Show'; });
}
</script>
</head>
<body>
  <h2>UTCM Snapshot Export</h2>
  <small>
    Snapshot: $(& $encodeFn $snapshotName) ($(& $encodeFn $job.id))
    &nbsp;|&nbsp; Created: $(& $encodeFn $createdStr)
    &nbsp;|&nbsp; Status: $(& $encodeFn $job.status)
    &nbsp;|&nbsp; Items: $($items.Count)
    &nbsp;|&nbsp; Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  </small>
  <div class="summary">$summarySpans</div>
  <p style="margin-top:8px"><button onclick="expandAll()">Expand All</button> <button onclick="collapseAll()">Collapse All</button></p>
  <table id="snapTable">
    <thead>
      <tr>
        <th onclick="sortTable(0)">ID</th>
        <th onclick="sortTable(1)">Display Name</th>
        <th onclick="sortTable(2)">Type</th>
        <th onclick="sortTable(3)">Workload</th>
        <th>Settings</th>
      </tr>
    </thead>
    <tbody>
      $($rowHtml -join "`n")
    </tbody>
  </table>
</body>
</html>
"@
            $html | Out-File -LiteralPath $htmlPath -Encoding UTF8
            _WriteLog ("HTML  -> $htmlPath") 'Green'
            $outPaths += $htmlPath
        }

        _WriteLog ("Exported snapshot {0} ({1} format(s)) to '{2}'" -f $job.id, $outPaths.Count, $Path) 'Green'
        return $outPaths
    }
    catch {
        if ($WriteErrorFileOnFailure) {
            _WriteErrorJson -job $job -errPath $ErrorPath
        }
        throw
    }
    finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}