function New-UTCMDriftReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Diff,
        [Parameter(Mandatory)][string] $SnapshotId,
        [Parameter(Mandatory)][string] $OutputPath,

        # NEW: open the generated HTML report in the default browser
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

        "<tr style='background:$color'>
            <td>$(& $HtmlEncodeFn $d.id)</td>
            <td>$(& $HtmlEncodeFn $d.displayName)</td>
            <td>$(& $HtmlEncodeFn $typeVal)</td>
            <td>$(& $HtmlEncodeFn $label)</td>
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
th, td { padding: 8px; border: 1px solid #ccc; }
th { background: #333; color: #fff; cursor: pointer; }
tr:hover { filter: brightness(0.97); }
.legend { margin-top: 10px; font-size: 12px; }
.legend span { margin-right: 8px; }
</style>
<script>
function sortTable(n) {
  var table = document.getElementById("drifttable");
  var switching = true;
  var dir = "asc";
  while (switching) {
    switching = false;
    var rows = table.rows;
    for (var i = 1; i < (rows.length - 1); i++) {
      var shouldSwitch = false;
      var x = rows[i].getElementsByTagName("TD")[n];
      var y = rows[i + 1].getElementsByTagName("TD")[n];
      if ((dir == "asc"  && x.textContent.toLowerCase() > y.textContent.toLowerCase()) ||
          (dir == "desc" && x.textContent.toLowerCase() < y.textContent.toLowerCase())) {
        shouldSwitch = true; break;
      }
    }
    if (shouldSwitch) {
      rows[i].parentNode.insertBefore(rows[i + 1], rows[i]);
      switching = true;
    } else {
      if (dir == "asc") { dir = "desc"; switching = true; }
    }
  }
}
</script>
</head>
<body>
  <h2 id="title" aria-label="UTCM Drift Report">$reportTitle</h2>
  <small>
    Baseline Snapshot: $baselineNameEncoded ($baselineIdEncoded)
    &nbsp; | &nbsp; Created: $baselineCreatedStr
    &nbsp; | &nbsp; Generated: $generatedOn
    $downloadLinkHtml
  </small>

  $summaryHtml

  <table id="drifttable" aria-label="UTCM Drift Report Table">
    <thead>
      <tr>
        <th onclick="sortTable(0)">ID</th>
        <th onclick="sortTable(1)">Display Name</th>
        <th onclick="sortTable(2)">Type</th>
        <th onclick="sortTable(3)">Drift Type</th>
      </tr>
    </thead>
    <tbody>
      $($rowHtml -join "`n")
    </tbody>
  </table>
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