function New-UTCMDriftReport {
    <#
    .SYNOPSIS
        Generates a paginated HTML drift report and CSV from a configuration diff.

    .DESCRIPTION
        Produces a self-contained HTML report with two sections:
          Page 1 — Drift Summary: color-coded table of added/missing/changed items with
                   expandable settings detail per row.
          Page 2 — Full Current State: complete table of all current configuration items
                   with expandable settings (only rendered when -CurrentItems is provided).

        Also writes a CSV with Id, DisplayName, Type, DriftType, NormalizedData columns.

    .PARAMETER Diff
        The diff array from Compare-UTCMConfiguration.

    .PARAMETER SnapshotId
        GUID of the baseline snapshot (used in the report header and file name).

    .PARAMETER OutputPath
        Directory for the output files.

    .PARAMETER CurrentItems
        Full configurationItems array from the current-state snapshot. When provided,
        a "Full Current State" section is appended to the HTML report.

    .PARAMETER Open
        Open the HTML report in the default browser after generation.

    .OUTPUTS
        PSCustomObject with HtmlPath, CsvPath, Added, Missing, Changed, Opened.

    .EXAMPLE
        $diff = Compare-UTCMConfiguration -BaselineSnapshotId $id1 -CompareSnapshotId $id2
        New-UTCMDriftReport -Diff $diff -SnapshotId $id1 -OutputPath .\Reports

    .EXAMPLE
        # With full current state on page 2
        New-UTCMDriftReport -Diff $diff -SnapshotId $id -OutputPath .\Reports -CurrentItems $items -Open
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Diff,
        [Parameter(Mandatory)][string] $SnapshotId,
        [Parameter(Mandatory)][string] $OutputPath,

        # Full configuration items from the current-state snapshot (displayed on page 2)
        $CurrentItems,

        # Open the generated HTML report in the default browser
        [switch] $Open
    )

    # --- Local helpers -------------------------------------------------------
    function _WriteLog([string]$msg, [string]$color='Gray') {
        if (Get-Command -Name Write-Log -ErrorAction SilentlyContinue) {
            Write-Log -Message $msg -Color $color
        } else {
            Write-Host ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) -ForegroundColor $color
        }
    }

    # Safe HTML encoder (fallback if HtmlEncode helper isn't available)
    function _HtmlEncode([object]$value) {
        $s = [string]$value
        if ([string]::IsNullOrEmpty($s)) { return '' }
        $s = $s -replace '&','&amp;'
        $s = $s -replace '<','&lt;'
        $s = $s -replace '>','&gt;'
        $s = $s -replace '"','&quot;'
        $s = $s -replace "'",'&#39;'
        return $s
    }

    # Choose encoder: prefer module's HtmlEncode if present
    $HtmlEncodeFn = if (Get-Command -Name HtmlEncode -ErrorAction SilentlyContinue) { (Get-Command HtmlEncode).Name } else { '_HtmlEncode' }

    # Normalized drift labels/colors
    function _DriftLabel([string]$sideIndicator) {
        if ($sideIndicator -eq '=>') { return 'Added in Current' }
        if ($sideIndicator -eq '<=') { return 'Missing in Current' }
        return 'Changed'
    }
    function _DriftColor([string]$label) {
        switch ($label) {
            'Added in Current'   { 'lightgreen' }
            'Missing in Current' { 'lightcoral' }
            default              { 'khaki' }
        }
    }
    # -------------------------------------------------------------------------

    # Resolve output directory using module helper if available
    $outDir = if (Get-Command -Name Resolve-OutputPath -ErrorAction SilentlyContinue) {
        Resolve-OutputPath -Path $OutputPath
    } else {
        if (-not (Test-Path -LiteralPath $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
        $OutputPath
    }

    $htmlPath = Join-Path -Path $outDir -ChildPath ("UTCM-Drift-Report-{0}.html" -f $SnapshotId)
    $csvPath  = Join-Path -Path $outDir -ChildPath ("UTCM-Drift-Report-{0}.csv"  -f $SnapshotId)

    # Fetch baseline snapshot metadata (uses updated module that supports $select internally)
    $baseline = $null
    try {
        $baseline = Get-UTCMSnapshot -SnapshotId $SnapshotId -IncludeDetails
    } catch {
        _WriteLog ("Warning: Could not fetch snapshot metadata for header (ID: $SnapshotId). Proceeding without details. Error: $($_.Exception.Message)") 'Yellow'
    }

    $baselineName = if ($baseline) { $baseline.displayName } else { $null }
    $baselineCreated = if ($baseline) { $baseline.createdDateTime } else { $null }
    $resourceLocation = if ($baseline) { $baseline.resourceLocation } else { $null }

    # Build rows and summary
    $added = 0; $missing = 0; $changed = 0
    $rowHtml = foreach ($d in $Diff) {
        # Derive a type safely (accept either 'type' or 'resourceType' on diff objects)
        $typeVal = if ($d.PSObject.Properties.Name -contains 'type') { $d.type }
                   elseif ($d.PSObject.Properties.Name -contains 'resourceType') { $d.resourceType }
                   else { $null }

        $label = _DriftLabel $d.SideIndicator
        switch ($label) {
            'Added in Current'   { $added++ }
            'Missing in Current' { $missing++ }
            default              { $changed++ }
        }
        $color = _DriftColor $label

        # Include normalizedData as expandable detail
        $dataJson = ''
        if ($d.PSObject.Properties.Name -contains 'normalizedData' -and $d.normalizedData) {
            $dataJson = [string]$d.normalizedData
        }
        $rowIdx = [guid]::NewGuid().ToString('N').Substring(0,8)

        "<tr style='background:$color'>
            <td>$(& $HtmlEncodeFn $d.id)</td>
            <td>$(& $HtmlEncodeFn $d.displayName)</td>
            <td>$(& $HtmlEncodeFn $typeVal)</td>
            <td>$(& $HtmlEncodeFn $label)</td>
            <td><button class='toggleBtn' onclick=""toggleDetail('dd$rowIdx')"">Show</button>
                <div id='dd$rowIdx' class='detail' style='display:none'><pre>$(& $HtmlEncodeFn $dataJson)</pre></div></td>
        </tr>"
    }

    $reportTitle = "UTCM Drift Report"
    $generatedOn = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $baselineNameEncoded = & $HtmlEncodeFn $baselineName
    $baselineIdEncoded   = & $HtmlEncodeFn $SnapshotId
    $baselineCreatedStr  = if ($baselineCreated) { (Get-Date $baselineCreated).ToString('yyyy-MM-dd HH:mm:ss') } else { 'n/a' }
    $downloadLinkHtml    = if ($resourceLocation) {
        '<span>&nbsp; | &nbsp;</span><a href="' + (& $HtmlEncodeFn $resourceLocation) + '" target="_blank" rel="noopener">Download baseline JSON</a>'
    } else { '' }

    $summaryHtml = @"
<div class="legend" role="group" aria-label="Legend and Summary">
  <span style="background:lightgreen;padding:4px 8px;border-radius:4px;display:inline-block;margin-right:8px">Added in Current: $added</span>
  <span style="background:lightcoral;padding:4px 8px;border-radius:4px;display:inline-block;margin-right:8px">Missing in Current: $missing</span>
  <span style="background:khaki;padding:4px 8px;border-radius:4px;display:inline-block;margin-right:8px">Changed: $changed</span>
</div>
"@

    # --- Page 2: Full Current State (if CurrentItems provided) ---
    $currentStateSection = ''
    if ($CurrentItems -and $CurrentItems.Count -gt 0) {
        $csRows = foreach ($item in $CurrentItems) {
            $typeVal = if ($item.PSObject.Properties.Name -contains 'type') { $item.type }
                       elseif ($item.PSObject.Properties.Name -contains 'resourceType') { $item.resourceType }
                       else { '' }
            $wl      = if ($item.PSObject.Properties.Name -contains 'workload') { $item.workload }
                       else { if ($typeVal -match '^microsoft\.([a-z0-9]+)') { $Matches[1] } else { 'unknown' } }
            $dataJson = ''
            if ($item.PSObject.Properties.Name -contains 'data') {
                try { $dataJson = $item.data | ConvertTo-Json -Depth 20 } catch { $dataJson = [string]$item.data }
            }
            $csIdx = [guid]::NewGuid().ToString('N').Substring(0,8)
            "<tr>
                <td>$(& $HtmlEncodeFn $item.id)</td>
                <td>$(& $HtmlEncodeFn $item.displayName)</td>
                <td>$(& $HtmlEncodeFn $typeVal)</td>
                <td>$(& $HtmlEncodeFn $wl)</td>
                <td><button class='toggleBtn' onclick=""toggleDetail('cs$csIdx')"">Show</button>
                    <div id='cs$csIdx' class='detail' style='display:none'><pre>$(& $HtmlEncodeFn $dataJson)</pre></div></td>
            </tr>"
        }

        $currentStateSection = @"

  <div class="page-break"></div>
  <h2 id="current-state">Full Current State ($($CurrentItems.Count) items)</h2>
  <p style="font-size:13px;color:#666">Complete configuration snapshot at time of comparison.</p>
  <p><button onclick="expandAllIn('currentTable')">Expand All</button> <button onclick="collapseAllIn('currentTable')">Collapse All</button></p>
  <table id="currentTable">
    <thead>
      <tr>
        <th onclick="sortTableById('currentTable',0)">ID</th>
        <th onclick="sortTableById('currentTable',1)">Display Name</th>
        <th onclick="sortTableById('currentTable',2)">Type</th>
        <th onclick="sortTableById('currentTable',3)">Workload</th>
        <th>Settings</th>
      </tr>
    </thead>
    <tbody>
      $($csRows -join "`n")
    </tbody>
  </table>
"@
    }

    $html = @"
<html>
<head>
<meta charset="utf-8">
<title>$reportTitle</title>
<style>
body { font-family: Arial, Helvetica, sans-serif; margin: 20px; }
h2 { margin-bottom: 6px; }
small { color: #666; }
table { border-collapse: collapse; width: 100%; margin-top: 10px; }
th, td { padding: 8px; border: 1px solid #ccc; vertical-align: top; }
th { background: #333; color: #fff; cursor: pointer; }
tr:hover { filter: brightness(0.97); }
.legend { margin-top: 10px; font-size: 12px; }
.legend span { margin-right: 8px; }
.page-break { page-break-before: always; margin-top: 40px; border-top: 2px solid #ccc; padding-top: 20px; }
.nav { margin: 12px 0; font-size: 13px; }
.nav a { margin-right: 16px; }
.toggleBtn { font-size: 11px; padding: 2px 8px; cursor: pointer; }
.detail pre { background: #f4f4f4; padding: 8px; border-radius: 4px; white-space: pre-wrap; word-break: break-word; max-height: 400px; overflow: auto; font-size: 12px; margin-top: 4px; }
@media print { .page-break { page-break-before: always; } }
</style>
<script>
function sortTableById(tableId, n) {
  var table = document.getElementById(tableId);
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
function expandAllIn(tableId) {
  document.getElementById(tableId).querySelectorAll('.detail').forEach(function(el){ el.style.display='block'; el.parentElement.querySelector('.toggleBtn').textContent='Hide'; });
}
function collapseAllIn(tableId) {
  document.getElementById(tableId).querySelectorAll('.detail').forEach(function(el){ el.style.display='none'; el.parentElement.querySelector('.toggleBtn').textContent='Show'; });
}
</script>
</head>
<body>
  <div class="nav">
    <a href="#drift-summary"><strong>Drift Summary</strong></a>
    $(if ($CurrentItems -and $CurrentItems.Count -gt 0) { '<a href="#current-state"><strong>Full Current State</strong></a>' })
  </div>

  <h2 id="drift-summary">$reportTitle</h2>
  <small>
    Baseline Snapshot: $baselineNameEncoded ($baselineIdEncoded)
    &nbsp; | &nbsp; Created: $baselineCreatedStr
    &nbsp; | &nbsp; Generated: $generatedOn
    $downloadLinkHtml
  </small>

  $summaryHtml

  <p><button onclick="expandAllIn('drifttable')">Expand All</button> <button onclick="collapseAllIn('drifttable')">Collapse All</button></p>
  <table id="drifttable" aria-label="UTCM Drift Report Table">
    <thead>
      <tr>
        <th onclick="sortTableById('drifttable',0)">ID</th>
        <th onclick="sortTableById('drifttable',1)">Display Name</th>
        <th onclick="sortTableById('drifttable',2)">Type</th>
        <th onclick="sortTableById('drifttable',3)">Drift Type</th>
        <th>Settings</th>
      </tr>
    </thead>
    <tbody>
      $($rowHtml -join "`n")
    </tbody>
  </table>

  $currentStateSection
</body>
</html>
"@

    # Write outputs
    $html | Out-File -LiteralPath $htmlPath -Encoding UTF8

    $Diff |
        Select-Object `
            @{n='Id';e={$_.id}},
            @{n='DisplayName';e={$_.displayName}},
            @{n='Type';e={
                if ($_.PSObject.Properties.Name -contains 'type') { $_.type }
                elseif ($_.PSObject.Properties.Name -contains 'resourceType') { $_.resourceType }
                else { $null }
            }},
            @{n='DriftType';e={ _DriftLabel $_.SideIndicator }},
            @{n='NormalizedData';e={$_.normalizedData}} |
        Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

    _WriteLog ("Dashboard written to: $htmlPath") 'Green'
    _WriteLog ("CSV written to: $csvPath") 'Green'

    # NEW: Open the HTML report if requested (cross-platform)
    if ($Open) {
        try {
            if ($IsWindows) {
                Start-Process -FilePath $htmlPath | Out-Null
            } elseif ($IsMacOS) {
                Start-Process -FilePath 'open' -ArgumentList @($htmlPath) | Out-Null
            } elseif ($IsLinux) {
                if (Get-Command -Name xdg-open -ErrorAction SilentlyContinue) {
                    Start-Process -FilePath 'xdg-open' -ArgumentList @($htmlPath) | Out-Null
                } else {
                    # Last resort: try Start-Process directly (may work in some DEs)
                    Start-Process -FilePath $htmlPath | Out-Null
                }
            } else {
                _WriteLog "Unknown platform; please open the report manually: $htmlPath" 'Yellow'
            }
        } catch {
            _WriteLog ("Failed to open the report automatically: $($_.Exception.Message)`nPath: $htmlPath") 'Yellow'
        }
    }

    [pscustomobject]@{
        HtmlPath = $htmlPath
        CsvPath  = $csvPath
        Added    = $added
        Missing  = $missing
        Changed  = $changed
        Opened   = [bool]$Open
    }
}