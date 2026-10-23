function ConvertTo-UTCMHtmlText {
    # Null-safe HTML encoding for text and attribute values.
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()] $Value)
    $encoded = [System.Net.WebUtility]::HtmlEncode([string]$Value)
    # Character references survive document LF normalization and HTML attribute parsing.
    return $encoded.Replace("`r", '&#13;').Replace("`n", '&#10;').Replace("`t", '&#9;')
}

function ConvertTo-UTCMSafeUrl {
    # Returns the absolute https URL, or $null for anything else (javascript:, data:, http:, relative ...).
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string] $Url)

    if ([string]::IsNullOrWhiteSpace($Url)) { return $null }
    $u = $null
    if ([uri]::TryCreate($Url.Trim(), [System.UriKind]::Absolute, [ref]$u) -and $u.Scheme -eq 'https') {
        return $u.AbsoluteUri
    }
    return $null
}

function ConvertTo-UTCMJsonIsland {
    # Serializes data for a <script type="application/json"> block; neutralizes characters that could
    # end the script element or confuse parsers.
    [CmdletBinding()]
    param([AllowNull()] $InputObject)

    $json = ConvertTo-Json -InputObject $InputObject -Depth 20 -Compress
    return $json.Replace('<', '\u003c').Replace('>', '\u003e').Replace('&', '\u0026').
        Replace([string][char]0x2028, '\u2028').Replace([string][char]0x2029, '\u2029')
}

function ConvertTo-UTCMLfText {
    # Browsers normalize CRLF and CR to LF before hashing inline content, so hash and write LF only.
    [CmdletBinding()]
    param([AllowNull()][string] $Text)
    if ($null -eq $Text) { return '' }
    return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Get-UTCMCspHash {
    # CSP source expression ('sha256-<base64>') for the given inline element text.
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-UTCMLfText $Text))
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return 'sha256-' + [Convert]::ToBase64String($sha.ComputeHash($bytes)) }
    finally { $sha.Dispose() }
}

function Format-UTCMReportDocument {
    # Wraps a report body in the shared document shell: doctype, language, viewport, CSP (script and
    # style pinned by hash), shared CSS and script. Output is LF-normalized.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Title,
        [Parameter(Mandatory)][string] $Body,
        [Parameter(Mandatory)][string] $ReportType
    )

    $css = "`n" + (ConvertTo-UTCMLfText (Get-UTCMReportCss)) + "`n"
    $js  = "`n" + (ConvertTo-UTCMLfText (Get-UTCMReportScript)) + "`n"
    $csp = "default-src 'none'; script-src '{0}'; style-src '{1}'; base-uri 'none'; form-action 'none'" -f (Get-UTCMCspHash $js), (Get-UTCMCspHash $css)
    $t = ConvertTo-UTCMHtmlText $Title
    $rt = ConvertTo-UTCMHtmlText $ReportType

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta http-equiv="Content-Security-Policy" content="$csp">
<title>$t</title>
<style>$css</style>
</head>
<body data-report="$rt">
<a class="skip" href="#main">Skip to report</a>
<div id="live" class="sr-only" role="status" aria-live="polite"></div>
$Body
<script>$js</script>
</body>
</html>
"@
    return (ConvertTo-UTCMLfText $html)
}

function Format-UTCMStatusBadge {
    # Status with icon + text + border style, so it never relies on color alone.
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('Added','Missing','Changed')][string] $Status)

    switch ($Status) {
        'Added'   { return '<span class="badge st-added"><span aria-hidden="true">&#43;</span> Added in Current</span>' }
        'Missing' { return '<span class="badge st-missing"><span aria-hidden="true">&minus;</span> Missing in Current</span>' }
        'Changed' { return '<span class="badge st-changed"><span aria-hidden="true">&ne;</span> Changed</span>' }
    }
}

function Get-UTCMDriftTypeLabel {
    # Label used in the drift CSV (and the embedded CSV download) for a Compare-Object side indicator.
    [CmdletBinding()]
    param([AllowNull()][string] $SideIndicator)

    if ($SideIndicator -eq '=>') { return 'Added in Current' }
    if ($SideIndicator -eq '<=') { return 'Missing in Current' }
    return 'Changed'
}

function Format-UTCMCopyable {
    # Value wrapper; the client script adds the Copy button (keeps large reports small).
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string] $Text, [string] $Tag = 'span', [switch] $IsId)

    $e = ConvertTo-UTCMHtmlText $Text
    $cls = if ($IsId) { 'cp cp-id' } else { 'cp' }
    return "<span class=`"$cls`"><$Tag class=`"v`">$e</$Tag></span>"
}

function Format-UTCMPropertyTable {
    # Property table. Mode 'diff': Change | Property | Baseline | Current. Mode 'single': Property | Value.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Rows,
        [Parameter(Mandatory)][ValidateSet('diff','single')][string] $Mode,
        [AllowNull()][string] $Label = 'Properties',
        [ValidateSet('Baseline','Current')][string] $Side = 'Current',
        [int] $Max = 500
    )

    $all = @($Rows)
    $shown = if ($all.Count -gt $Max) { $all[0..($Max - 1)] } else { $all }
    $sb = New-Object System.Text.StringBuilder
    $lbl = ConvertTo-UTCMHtmlText $Label
    [void]$sb.Append("<div class=`"tablewrap`" role=`"region`" aria-label=`"$lbl`" tabindex=`"0`"><table class=`"props`"><thead><tr>")
    if ($Mode -eq 'diff') {
        [void]$sb.Append('<th scope="col">Change</th><th scope="col">Property</th><th scope="col">Baseline</th><th scope="col">Current</th>')
    } else {
        [void]$sb.Append('<th scope="col">Property</th><th scope="col">Value</th>')
    }
    [void]$sb.Append('</tr></thead><tbody>')

    foreach ($r in $shown) {
        $path = [System.Net.WebUtility]::HtmlEncode($r.Path)
        if ($Mode -eq 'diff') {
            $st = switch ($r.Status) {
                'changed'   { '&ne; Changed' }
                'added'     { '&#43; Added' }
                'removed'   { '&minus; Removed' }
                default     { '&#61; Same' }
            }
            $b = if ($r.Status -eq 'added')   { '<span class="absent">(not set)</span>' } else { Format-UTCMCopyable $r.Baseline }
            $c = if ($r.Status -eq 'removed') { '<span class="absent">(not set)</span>' } else { Format-UTCMCopyable $r.Current }
            [void]$sb.Append("<tr class=`"prop`" data-st=`"$($r.Status)`"><td><span class=`"pst`">$st</span></td><th scope=`"row`" class=`"path`">$path</th><td>$b</td><td>$c</td></tr>")
        } else {
            $val = if ($Side -eq 'Baseline') { $r.Baseline } else { $r.Current }
            [void]$sb.Append("<tr class=`"prop`" data-st=`"single`"><th scope=`"row`" class=`"path`">$path</th><td>$(Format-UTCMCopyable $val)</td></tr>")
        }
    }
    [void]$sb.Append('</tbody></table></div>')
    if ($all.Count -gt $Max) {
        [void]$sb.Append("<p class=`"note`">Showing the first $Max of $($all.Count) properties. See Raw JSON for the full configuration.</p>")
    }
    return $sb.ToString()
}

function Format-UTCMDriftItem {
    # One <tbody class="item"> for a drift record (Added, Missing or Changed).
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Record)

    $enc = [System.Net.WebUtility]
    $rec = $Record
    $status = $rec.Status
    $name = if ($rec.DisplayName) { $rec.DisplayName } else { '(unnamed)' }
    $nameAttr = ConvertTo-UTCMHtmlText $rec.DisplayName

    $rows = $null; $changes = 0; $changesText = ''
    $printHtml = ''; $tableHtml = ''; $note = ''; $rawHtml = ''

    if ($status -eq 'Changed') {
        $rows = Get-UTCMPropertyDiff -BaselineJson $rec.BaselineData -CurrentJson $rec.CurrentData
        if ($null -ne $rows) {
            $diffRows = @($rows | Where-Object { $_.Status -ne 'unchanged' })
            $changes = $diffRows.Count
            $changesText = if ($changes -eq 0) { 'Ordering or formatting only' } elseif ($changes -eq 1) { '1 property change' } else { "$changes property changes" }
            $tableHtml = Format-UTCMPropertyTable -Rows $rows -Mode diff -Label ("Property comparison for " + $name)
            if ($diffRows.Count -gt 0) {
                $top = $diffRows | Select-Object -First 5
                $li = foreach ($d in $top) {
                    $o = if ($null -ne $d.Baseline) { $enc::HtmlEncode($d.Baseline) } else { '(not set)' }
                    $n = if ($null -ne $d.Current)  { $enc::HtmlEncode($d.Current) }  else { '(not set)' }
                    "<li><code>$($enc::HtmlEncode($d.Path))</code>: $o &rarr; $n</li>"
                }
                $more = if ($diffRows.Count -gt 5) { "<li>+$($diffRows.Count - 5) more</li>" } else { '' }
                $printHtml = "<ul class=`"chg-print`">$($li -join '')$more</ul>"
            }
        } else {
            $changesText = 'Details unavailable'
        }
        if ($rec.BaselineDisplayName -and $rec.BaselineDisplayName -ne $rec.DisplayName) {
            $note = "<p class=`"note`">Renamed from <strong>$($enc::HtmlEncode($rec.BaselineDisplayName))</strong>.</p>"
        }
        $rawHtml = "<details class=`"rawwrap`"><summary>Raw JSON</summary><p class=`"note`">Baseline</p><pre class=`"raw`">$($enc::HtmlEncode((Format-UTCMJsonPretty $rec.BaselineData)))</pre>" +
                   "<p class=`"note`">Current</p><pre class=`"raw`">$($enc::HtmlEncode((Format-UTCMJsonPretty $rec.CurrentData)))</pre></details>"
    } else {
        $json = if ($status -eq 'Added') { $rec.CurrentData } else { $rec.BaselineData }
        $rows = if ($status -eq 'Added') { Get-UTCMPropertyDiff -BaselineJson $null -CurrentJson $json } else { Get-UTCMPropertyDiff -BaselineJson $json -CurrentJson $null }
        if ($null -ne $rows) {
            $changes = @($rows).Count
            $changesText = if ($changes -eq 1) { '1 property' } else { "$changes properties" }
            $side = if ($status -eq 'Added') { 'Current' } else { 'Baseline' }
            $tableHtml = Format-UTCMPropertyTable -Rows $rows -Mode single -Side $side -Label ("Properties of " + $name)
        } else {
            $changesText = 'Details unavailable'
        }
        $rawHtml = "<details class=`"rawwrap`"><summary>Raw JSON</summary><pre class=`"raw`">$($enc::HtmlEncode((Format-UTCMJsonPretty $json)))</pre></details>"
    }

    $rowIdx = ($rec.RowIndexes -join ',')
    $idCell = if ($rec.Id) { "<span class=`"idl`" data-col=`"id`">$(Format-UTCMCopyable $rec.Id -Tag 'code' -IsId)</span>" } else { '' }
    $badge = Format-UTCMStatusBadge -Status $status

    return @"
<tbody class="item" data-status="$status" data-workload="$(ConvertTo-UTCMHtmlText $rec.Workload)" data-type="$(ConvertTo-UTCMHtmlText $rec.Type)" data-name="$nameAttr" data-id="$(ConvertTo-UTCMHtmlText $rec.Id)" data-changes="$changes" data-rows="$rowIdx">
<tr class="main"><td data-label="Status">$badge</td><td data-label="Resource"><span class="nm">$($enc::HtmlEncode($name))</span>$idCell</td><td data-col="type" data-label="Type">$($enc::HtmlEncode($rec.Type))</td><td data-col="workload" data-label="Workload">$($enc::HtmlEncode($rec.Workload))</td><td data-col="changes" data-label="Changes">$changesText</td></tr>
<tr class="detail"><td colspan="5">$printHtml<details><summary>Show property details</summary>$note$tableHtml$rawHtml</details></td></tr>
</tbody>
"@
}

function Format-UTCMInventoryItem {
    # One <tbody class="item"> for a snapshot / current-state configuration item.
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Item)

    $enc = [System.Net.WebUtility]
    $name = if ($Item.DisplayName) { $Item.DisplayName } else { '(unnamed)' }
    $json = ''
    if ($null -ne $Item.Data) {
        try { $json = $Item.Data | ConvertTo-Json -Depth 99 } catch { $json = [string]$Item.Data }
    }
    $preview = $enc::HtmlEncode((Get-UTCMItemPreview -Data $Item.Data))
    $idCell = if ($Item.Id) { "<span class=`"idl`" data-col=`"id`">$(Format-UTCMCopyable $Item.Id -Tag 'code' -IsId)</span>" } else { '' }
    $wl = ConvertTo-UTCMHtmlText $Item.Workload

    return @"
<tbody class="item" data-workload="$wl" data-type="$(ConvertTo-UTCMHtmlText $Item.Type)" data-name="$(ConvertTo-UTCMHtmlText $Item.DisplayName)" data-id="$(ConvertTo-UTCMHtmlText $Item.Id)">
<tr class="main"><td data-label="Resource"><span class="nm">$($enc::HtmlEncode($name))</span>$idCell</td><td data-col="type" data-label="Type">$($enc::HtmlEncode($Item.Type))</td><td data-col="workload" data-label="Workload">$wl</td><td data-col="preview" data-label="Preview">$preview</td></tr>
<tr class="detail"><td colspan="4"><details><summary>Configuration JSON</summary><pre class="raw">$($enc::HtmlEncode($json))</pre></details></td></tr>
</tbody>
"@
}

function Format-UTCMSummaryCard {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Cards)

    $li = foreach ($c in $Cards) {
        $cls = if ($c['Class']) { " $($c['Class'])" } else { '' }
        $icon = if ($c['Icon']) { "<span aria-hidden=`"true`">$($c['Icon'])</span> " } else { '' }
        "<li class=`"card$cls`"><span class=`"n`">$($c['Value'])</span><span class=`"l`">$icon$([System.Net.WebUtility]::HtmlEncode([string]$c['Label']))</span></li>"
    }
    return "<ul class=`"cards`" aria-label=`"Summary`">$($li -join '')</ul>"
}

function Format-UTCMDistribution {
    # Horizontal distribution drawn with SVG (width is an attribute, so no inline style is needed and the
    # strict CSP holds in every engine), with the number always shown as text.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Title, [AllowNull()] $Rows, [int] $Top = 12)

    $all = @($Rows)
    if ($all.Count -eq 0) { return '' }
    $max = [double](($all | Measure-Object -Property Count -Maximum).Maximum)
    $shown = @($all | Select-Object -First $Top)
    $inv = [cultureinfo]::InvariantCulture
    $li = foreach ($r in $shown) {
        $n = [System.Net.WebUtility]::HtmlEncode([string]$r.Name)
        $pct = if ($max -gt 0) { [math]::Round(100.0 * $r.Count / $max, 1).ToString($inv) } else { '0' }
        "<li><span class=`"dn`">$n</span><svg class=`"bar`" viewBox=`"0 0 100 10`" preserveAspectRatio=`"none`" role=`"img`" aria-label=`"$n`: $($r.Count)`"><rect class=`"bar-bg`" width=`"100`" height=`"10`"/><rect class=`"bar-fg`" width=`"$pct`" height=`"10`"/></svg><span class=`"dc`">$($r.Count)</span></li>"
    }
    $more = if ($all.Count -gt $Top) { "<p class=`"note`">Showing the top $Top of $($all.Count).</p>" } else { '' }
    return "<section aria-label=`"$([System.Net.WebUtility]::HtmlEncode($Title))`"><h2>$([System.Net.WebUtility]::HtmlEncode($Title))</h2><ul class=`"dist`">$($li -join '')</ul>$more</section>"
}

function Format-UTCMToolbar {
    # Search, filters, sort, column chooser, downloads and actions. Everything is hidden without JS.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ScopeId,
        [AllowNull()] $Statuses,
        [AllowNull()] $Workloads,
        [AllowNull()] $Types,
        [Parameter(Mandatory)] $SortOptions,
        [Parameter(Mandatory)] $Columns,
        [switch] $ChangedToggle,
        [switch] $GroupToggle,
        [switch] $GroupButtons
    )

    $enc = [System.Net.WebUtility]
    $sid = $enc::HtmlEncode($ScopeId)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("<div class=`"toolbar needs-js`" role=`"search`" aria-label=`"Search and filter`">")
    [void]$sb.Append("<div class=`"fld search`"><label for=`"q-$sid`">Search</label><input id=`"q-$sid`" type=`"search`" data-f=`"q`" maxlength=`"200`" placeholder=`"Name, ID, type or property`" autocomplete=`"off`"></div>")

    if ($Statuses) {
        [void]$sb.Append('<div class="chips" role="group" aria-label="Filter by status">')
        foreach ($s in $Statuses) {
            [void]$sb.Append("<button type=`"button`" class=`"chip`" data-status=`"$($enc::HtmlEncode($s.Value))`" aria-pressed=`"false`">$($s.Icon) $($enc::HtmlEncode($s.Label)) ($($s.Count))</button>")
        }
        [void]$sb.Append('</div>')
    }
    foreach ($pair in @(@('workload', 'Workload', $Workloads, 'All workloads'), @('type', 'Resource type', $Types, 'All types'))) {
        if ($pair[2] -and @($pair[2]).Count -gt 0) {
            [void]$sb.Append("<div class=`"fld`"><label for=`"$($pair[0])-$sid`">$($pair[1])</label><select id=`"$($pair[0])-$sid`" data-f=`"$($pair[0])`"><option value=`"`">$($pair[3])</option>")
            foreach ($o in $pair[2]) { $ov = ConvertTo-UTCMHtmlText $o; [void]$sb.Append("<option value=`"$ov`">$ov</option>") }
            [void]$sb.Append('</select></div>')
        }
    }
    [void]$sb.Append("<div class=`"fld`"><label for=`"sort-$sid`">Sort by</label><select id=`"sort-$sid`" data-f=`"sort`">")
    foreach ($o in $SortOptions) { [void]$sb.Append("<option value=`"$($enc::HtmlEncode($o.Value))`">$($enc::HtmlEncode($o.Label))</option>") }
    [void]$sb.Append('</select></div>')
    if ($ChangedToggle) { [void]$sb.Append("<label class=`"fld chk`"><input type=`"checkbox`" data-f=`"changed`" checked> Show only changed properties</label>") }
    if ($GroupToggle)   { [void]$sb.Append("<label class=`"fld chk`"><input type=`"checkbox`" data-f=`"group`" checked> Group by workload</label>") }

    [void]$sb.Append('<details class="menu"><summary>Columns</summary><div class="menu-body">')
    foreach ($c in $Columns) { [void]$sb.Append("<label><input type=`"checkbox`" data-col-toggle=`"$($enc::HtmlEncode($c.Name))`" checked> $($enc::HtmlEncode($c.Label))</label>") }
    [void]$sb.Append('</div></details>')

    [void]$sb.Append('<details class="menu"><summary>Download</summary><div class="menu-body">' +
        '<button type="button" data-dl="csv-filtered">CSV (filtered)</button><button type="button" data-dl="csv-all">CSV (all)</button>' +
        '<button type="button" data-dl="json-filtered">JSON (filtered)</button><button type="button" data-dl="json-all">JSON (all)</button></div></details>')
    [void]$sb.Append('<button type="button" data-act="expand">Expand visible</button><button type="button" data-act="collapse">Collapse visible</button>')
    if ($GroupButtons) { [void]$sb.Append('<button type="button" data-act="groups-open">Open all groups</button><button type="button" data-act="groups-close">Close all groups</button>') }
    [void]$sb.Append('<button type="button" data-act="copylink">Copy link</button><button type="button" data-act="clear">Clear filters</button></div>')
    return $sb.ToString()
}

function Format-UTCMTableHead {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Columns)

    $th = foreach ($c in $Columns) {
        $col = if ($c['DataCol']) { " data-col=`"$($c['DataCol'])`"" } else { '' }
        $inner = if ($c['SortKey']) { "<button type=`"button`" class=`"sortbtn`" data-sort=`"$($c['SortKey'])`">$($c['Label'])</button>" } else { "<span class=`"thl`">$($c['Label'])</span>" }
        $aria = if ($c['SortKey']) { ' aria-sort="none"' } else { '' }
        "<th scope=`"col`"$col$aria>$inner</th>"
    }
    return "<thead><tr>$($th -join '')</tr></thead>"
}

function Format-UTCMSnapshotDiagnosticNotice {
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] $Diagnostic)

    $incomplete = @($Diagnostic | Where-Object { $null -ne $_ -and $_.status -ne 'succeeded' })
    if ($incomplete.Count -eq 0) { return '' }
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('<aside class="empty card k-missing" role="alert"><h2>Incomplete extraction - conclusions are provisional</h2><p>Missing or added rows may reflect extraction failures. An empty comparison cannot establish absence of drift. Do not use these results as unattended drift conclusions.</p><ul>')
    foreach ($entry in $incomplete) {
        $id = ConvertTo-UTCMHtmlText $entry.id
        $status = ConvertTo-UTCMHtmlText $entry.status
        $summary = ConvertTo-UTCMHtmlText $entry.errorSummary
        [void]$sb.Append("<li>Snapshot <code>$id</code>: <strong>$status</strong>. $summary</li>")
    }
    [void]$sb.Append('</ul></aside>')
    $sb.ToString()
}

function Format-UTCMDriftReportHtml {
    # Builds the complete drift report document.
    [CmdletBinding()]
    param(
        [AllowNull()] $Records,
        [AllowNull()] $Diff,
        [Parameter(Mandatory)][string] $SnapshotId,
        [AllowNull()][string] $BaselineName,
        [AllowNull()] $BaselineCreated,
        [AllowNull()][string] $ResourceLocation,
        [AllowNull()] $CurrentItems,
        [AllowNull()] $SnapshotDiagnostics,
        [Parameter(Mandatory)][string] $GeneratedUtc
    )

    $enc = [System.Net.WebUtility]
    $recs = @($Records | Where-Object { $null -ne $_ })
    $added   = @($recs | Where-Object Status -eq 'Added').Count
    $missing = @($recs | Where-Object Status -eq 'Missing').Count
    $changed = @($recs | Where-Object Status -eq 'Changed').Count
    $items = @($CurrentItems | Where-Object { $null -ne $_ } | ForEach-Object { ConvertTo-UTCMReportItem $_ })
    $incomplete = @($SnapshotDiagnostics | Where-Object { $null -ne $_ -and $_.status -ne 'succeeded' }).Count -gt 0
    $title = if ($incomplete) { 'UTCM Drift Report - Incomplete Comparison' } else { 'UTCM Drift Report' }
    $currentStateNote = if ($incomplete) {
        'Configuration returned by the current snapshot; extraction may be incomplete. See the warnings above.'
    } else {
        'Complete configuration captured at the time of comparison.'
    }

    $link = ''
    $safe = ConvertTo-UTCMSafeUrl $ResourceLocation
    if ($safe) { $link = " &middot; <a href=`"$($enc::HtmlEncode($safe))`" target=`"_blank`" rel=`"noopener noreferrer`">Download baseline JSON</a>" }
    $nav = '<a href="#drift-summary" data-nav>Drift summary</a>'
    if ($items.Count -gt 0) { $nav += " <a href=`"#current-state`" data-nav>Full current state ($($items.Count))</a>" }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append(@"
<div class="wrap">
<header>
<h1 id="drift-summary">$title</h1>
<p class="meta">Baseline snapshot: <strong>$($enc::HtmlEncode($BaselineName))</strong> (<code>$($enc::HtmlEncode($SnapshotId))</code>) &middot; Baseline created: $($enc::HtmlEncode((ConvertTo-UTCMUtcDisplay $BaselineCreated))) &middot; Generated: $($enc::HtmlEncode($GeneratedUtc))$link</p>
<p class="note">This report contains tenant configuration data. Handle it as confidential.</p>
<nav class="topnav" aria-label="Report sections">$nav</nav>
</header>
<main id="main">
$(Format-UTCMSnapshotDiagnosticNotice -Diagnostic $SnapshotDiagnostics)
$(Format-UTCMSummaryCard -Cards @(
    @{ Label = 'Resources with drift'; Value = $recs.Count; Class = ''; Icon = '' },
    @{ Label = 'Changed'; Value = $changed; Class = 'k-changed'; Icon = '&ne;' },
    @{ Label = 'Missing in current'; Value = $missing; Class = 'k-missing'; Icon = '&minus;' },
    @{ Label = 'Added in current'; Value = $added; Class = 'k-added'; Icon = '&#43;' }
))
"@)

    if ($recs.Count -eq 0) {
        if ($incomplete) {
            [void]$sb.Append('<p class="empty" role="status"><strong>No differences observed in the extracted data.</strong> This incomplete comparison cannot establish absence of drift.</p>')
        } else {
            [void]$sb.Append('<p class="empty ok" role="status"><strong>No drift detected.</strong> The current configuration matches the baseline.</p>')
        }
    } else {
        [void]$sb.Append((Format-UTCMDistribution -Title 'Drift by workload' -Rows (Get-UTCMCountBy -Items $recs -Property Workload)))
        [void]$sb.Append((Format-UTCMDistribution -Title 'Drift by resource type' -Rows (Get-UTCMCountBy -Items $recs -Property Type) -Top 10))

        $islandRows = foreach ($d in @($Diff | Where-Object { $null -ne $_ })) {
            [ordered]@{
                Id = [string](Get-UTCMObjectField $d @('id')); DisplayName = [string](Get-UTCMObjectField $d @('displayName'))
                Type = [string](Get-UTCMObjectField $d @('type','resourceType')); DriftType = (Get-UTCMDriftTypeLabel ([string](Get-UTCMObjectField $d @('SideIndicator'))))
                NormalizedData = [string](Get-UTCMObjectField $d @('normalizedData'))
            }
        }
        $statuses = @(
            @{ Value = 'Changed'; Label = 'Changed'; Icon = '&ne;'; Count = $changed },
            @{ Value = 'Missing'; Label = 'Missing in current'; Icon = '&minus;'; Count = $missing },
            @{ Value = 'Added';   Label = 'Added in current';   Icon = '&#43;'; Count = $added }
        )
        $toolbar = Format-UTCMToolbar -ScopeId 'drift' -Statuses $statuses `
            -Workloads @($recs | ForEach-Object Workload | Sort-Object -Unique) -Types @($recs | ForEach-Object Type | Sort-Object -Unique) `
            -SortOptions @(@{ Value = 'status'; Label = 'Status' }, @{ Value = 'name'; Label = 'Resource name' }, @{ Value = 'type'; Label = 'Type' }, @{ Value = 'workload'; Label = 'Workload' }, @{ Value = 'changes'; Label = 'Number of changes' }) `
            -Columns @(@{ Name = 'id'; Label = 'Resource ID' }, @{ Name = 'type'; Label = 'Type' }, @{ Name = 'workload'; Label = 'Workload' }, @{ Name = 'changes'; Label = 'Changes' }) `
            -ChangedToggle
        $head = Format-UTCMTableHead -Columns @(
            @{ Label = 'Status'; SortKey = 'status' }, @{ Label = 'Resource'; SortKey = 'name' },
            @{ Label = 'Type'; SortKey = 'type'; DataCol = 'type' }, @{ Label = 'Workload'; SortKey = 'workload'; DataCol = 'workload' },
            @{ Label = 'Changes'; SortKey = 'changes'; DataCol = 'changes' })
        $body = New-Object System.Text.StringBuilder
        foreach ($r in $recs) { [void]$body.Append((Format-UTCMDriftItem -Record $r)) }

        [void]$sb.Append(@"
<section class="scope changed-only" data-scope="drift" data-dlname="UTCM-Drift-Report-$($enc::HtmlEncode($SnapshotId))" data-download="island" data-island="utcm-drift-data" data-sort="status" aria-labelledby="drift-h">
<h2 id="drift-h">Drift details</h2>
$toolbar
<p class="count" data-count></p>
<p class="empty" data-empty hidden>No resources match the current search and filters.</p>
<div data-list data-flat><table id="drifttable" class="rtable" aria-label="UTCM drift report"><caption class="sr-only">Resources that differ from the baseline</caption>$head$($body.ToString())</table><div data-pager></div></div>
<script type="application/json" id="utcm-drift-data">{"rows":$(ConvertTo-UTCMJsonIsland -InputObject @($islandRows))}</script>
</section>
"@)
    }

    if ($items.Count -gt 0) {
        $toolbar = Format-UTCMToolbar -ScopeId 'current' -Workloads @($items | ForEach-Object Workload | Sort-Object -Unique) -Types @($items | ForEach-Object Type | Sort-Object -Unique) `
            -SortOptions @(@{ Value = 'name'; Label = 'Resource name' }, @{ Value = 'type'; Label = 'Type' }, @{ Value = 'workload'; Label = 'Workload' }) `
            -Columns @(@{ Name = 'id'; Label = 'Resource ID' }, @{ Name = 'type'; Label = 'Type' }, @{ Name = 'workload'; Label = 'Workload' }, @{ Name = 'preview'; Label = 'Preview' })
        $head = Format-UTCMTableHead -Columns @(
            @{ Label = 'Resource'; SortKey = 'name' }, @{ Label = 'Type'; SortKey = 'type'; DataCol = 'type' },
            @{ Label = 'Workload'; SortKey = 'workload'; DataCol = 'workload' }, @{ Label = 'Preview'; DataCol = 'preview' })
        $body = New-Object System.Text.StringBuilder
        foreach ($it in (Get-UTCMSortedReportItem $items)) { [void]$body.Append((Format-UTCMInventoryItem -Item $it)) }
        [void]$sb.Append(@"
<section class="scope" id="current-state" data-scope="current" data-dlname="UTCM-Current-State-$($enc::HtmlEncode($SnapshotId))" data-download="dom" data-sort="name" data-presorted="1" aria-labelledby="current-h">
<h2 id="current-h">Full current state ($($items.Count) items)</h2>
<p class="note">$currentStateNote</p>
$toolbar
<p class="count" data-count></p>
<p class="empty" data-empty hidden>No resources match the current search and filters.</p>
<div data-list data-flat><table id="currentTable" class="rtable" aria-label="Current configuration state"><caption class="sr-only">All current configuration items</caption>$head$($body.ToString())</table><div data-pager></div></div>
</section>
"@)
    }

    [void]$sb.Append('</main></div>')
    return (Format-UTCMReportDocument -Title $title -Body $sb.ToString() -ReportType 'drift')
}

function Format-UTCMSnapshotReportHtml {
    # Builds the complete snapshot export document.
    [CmdletBinding()]
    param(
        [AllowNull()] $Items,
        [AllowNull()][string] $SnapshotName,
        [Parameter(Mandatory)][string] $SnapshotId,
        [AllowNull()] $Created,
        [AllowNull()][string] $Status,
        [AllowNull()] $SnapshotDiagnostic,
        [Parameter(Mandatory)][string] $GeneratedUtc
    )

    $enc = [System.Net.WebUtility]
    $list = @($Items | Where-Object { $null -ne $_ } | ForEach-Object { ConvertTo-UTCMReportItem $_ })
    $byWorkload = @(Get-UTCMCountBy -Items $list -Property Workload)
    $types = @($list | ForEach-Object Type | Sort-Object -Unique)
    if ($Status -eq 'partiallySuccessful' -and $null -eq $SnapshotDiagnostic) {
        $SnapshotDiagnostic = Get-UTCMSnapshotDiagnostic -Snapshot @{ id = $SnapshotId; status = $Status }
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append(@"
<div class="wrap">
<header>
<h1 id="snapshot-top">UTCM Snapshot Export</h1>
<p class="meta">Snapshot: <strong>$($enc::HtmlEncode($SnapshotName))</strong> (<code>$($enc::HtmlEncode($SnapshotId))</code>) &middot; Created: $($enc::HtmlEncode((ConvertTo-UTCMUtcDisplay $Created))) &middot; Status: $($enc::HtmlEncode($Status)) &middot; Items: $($list.Count) &middot; Generated: $($enc::HtmlEncode($GeneratedUtc))</p>
<p class="note">This report contains tenant configuration data. Handle it as confidential.</p>
</header>
<main id="main">
$(Format-UTCMSnapshotDiagnosticNotice -Diagnostic $SnapshotDiagnostic)
$(Format-UTCMSummaryCard -Cards @(
    @{ Label = 'Items'; Value = $list.Count; Class = '' },
    @{ Label = 'Workloads'; Value = $byWorkload.Count; Class = '' },
    @{ Label = 'Resource types'; Value = $types.Count; Class = '' }
))
"@)

    if ($list.Count -eq 0) {
        [void]$sb.Append('<p class="empty" role="status"><strong>This snapshot contains no items.</strong> A partially successful job can return no data for some resource types; check the job error details.</p>')
    } else {
        [void]$sb.Append((Format-UTCMDistribution -Title 'Items by workload' -Rows $byWorkload))
        $toolbar = Format-UTCMToolbar -ScopeId 'snap' -Workloads @($byWorkload | ForEach-Object Name) -Types $types `
            -SortOptions @(@{ Value = 'name'; Label = 'Resource name' }, @{ Value = 'type'; Label = 'Type' }, @{ Value = 'workload'; Label = 'Workload' }) `
            -Columns @(@{ Name = 'id'; Label = 'Resource ID' }, @{ Name = 'type'; Label = 'Type' }, @{ Name = 'workload'; Label = 'Workload' }, @{ Name = 'preview'; Label = 'Preview' }) `
            -GroupToggle -GroupButtons
        $head = Format-UTCMTableHead -Columns @(
            @{ Label = 'Resource'; SortKey = 'name' }, @{ Label = 'Type'; SortKey = 'type'; DataCol = 'type' },
            @{ Label = 'Workload'; SortKey = 'workload'; DataCol = 'workload' }, @{ Label = 'Preview'; DataCol = 'preview' })

        [void]$sb.Append(@"
<section class="scope" data-scope="snapshot" data-dlname="Snapshot-$($enc::HtmlEncode($SnapshotId))" data-download="dom" data-groupable="1" data-sort="name" data-presorted="1" aria-labelledby="snap-h">
<h2 id="snap-h">Resources</h2>
$toolbar
<p class="count" data-count></p>
<p class="empty" data-empty hidden>No resources match the current search and filters.</p>
<div data-grouped-wrap>
"@)
        $openAll = ($list.Count -le 500) -or ($byWorkload.Count -eq 1)
        $groups = $list | Group-Object -Property Workload
        foreach ($g in ($groups | Sort-Object Name)) {
            $wl = ConvertTo-UTCMHtmlText $g.Name
            $rows = New-Object System.Text.StringBuilder
            foreach ($it in (Get-UTCMSortedReportItem $g.Group)) { [void]$rows.Append((Format-UTCMInventoryItem -Item $it)) }
            $open = if ($openAll) { ' open' } else { '' }
            [void]$sb.Append("<details class=`"wl-group`" data-wl=`"$wl`"$open><summary>$wl <span class=`"gc`">($($g.Count))</span></summary><div data-list data-group=`"$wl`"><table class=`"rtable`"><caption class=`"sr-only`">$wl resources</caption>$head$($rows.ToString())</table><div data-pager></div></div></details>")
        }
        [void]$sb.Append("</div><div data-flat-wrap hidden><div data-list data-flat><table id=`"snapTable`" class=`"rtable`"><caption class=`"sr-only`">All resources</caption>$head</table><div data-pager></div></div></div></section>")
    }

    [void]$sb.Append('</main></div>')
    return (Format-UTCMReportDocument -Title 'UTCM Snapshot Export' -Body $sb.ToString() -ReportType 'snapshot')
}
