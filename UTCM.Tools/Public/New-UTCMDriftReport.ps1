function New-UTCMDriftReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Diff,
        [Parameter(Mandatory)][string]$SnapshotId,
        [Parameter(Mandatory)][string]$OutputPath
    )

    $outDir = Resolve-OutputPath -Path $OutputPath
    $htmlPath = Join-Path -Path $outDir -ChildPath ("UTCM-Drift-Report-{0}.html" -f $SnapshotId)
    $csvPath  = Join-Path -Path $outDir -ChildPath ("UTCM-Drift-Report-{0}.csv"  -f $SnapshotId)

    # Build rows
    $rows = foreach ($d in $Diff) {
        $side = switch ($d.SideIndicator) {
            '=>' { 'Added in Current' }
            '<=' { 'Missing in Current' }
            default { 'Changed' }
        }
        $color = switch ($side) {
            'Added in Current'   { 'lightgreen' }
            'Missing in Current' { 'lightcoral' }
            default              { 'khaki' }
        }

        "<tr style='background:$color'>
            <td>$(HtmlEncode $d.id)</td>
            <td>$(HtmlEncode $d.displayName)</td>
            <td>$(HtmlEncode $d.type)</td>
            <td>$(HtmlEncode $side)</td>
        </tr>"
    }

    $reportTitle = "UTCM Drift Report"
    $generatedOn = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

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
.legend { margin-top: 6px; font-size: 12px; }
.legend span { padding: 4px 8px; margin-right: 8px; border-radius: 4px; display: inline-block; }
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
  <small>Baseline Snapshot ID: $(HtmlEncode $SnapshotId) &nbsp; | &nbsp; Generated: $generatedOn</small>

  <div class="legend" role="group" aria-label="Legend">
    <span style="background:lightgreen">Added in Current</span>
    <span style="background:lightcoral">Missing in Current</span>
    <span style="background:khaki">Changed</span>
  </div>

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
      $($rows -join "`n")
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
            @{n='Type';e={$_.type}},
            @{n='DriftType';e={
                switch ($_.SideIndicator) {
                    '=>' { 'Added in Current' }
                    '<=' { 'Missing in Current' }
                    default { 'Changed' }
                }
            }},
            # Keep normalized data only if present (optional column)
            @{n='NormalizedData';e={$_.normalizedData}} |
        Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

    Write-Log -Message "Dashboard written to: $htmlPath" -Color Green
    Write-Log -Message "CSV written to: $csvPath" -Color Green

    [pscustomobject]@{
        HtmlPath = $htmlPath
        CsvPath  = $csvPath
    }
}