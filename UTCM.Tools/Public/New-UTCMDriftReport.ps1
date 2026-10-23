function New-UTCMDriftReport {
    <#
    .SYNOPSIS
        Generates a self-contained HTML drift report and a CSV from a configuration diff.

    .DESCRIPTION
        Produces a single HTML file (no external resources) with:
          - Summary cards (resources with drift, Changed, Missing, Added) and workload / type distribution.
          - A searchable, filterable, sortable, paged table of drifted resources. A resource that changed
            is reported once as "Changed" with a property-level baseline vs current comparison; the full
            JSON stays available as a secondary "Raw JSON" detail.
          - A "Full current state" section when -CurrentItems is provided.
          - Column chooser, CSV/JSON downloads, copy buttons, shareable filter state (URL hash), print layout.

        A modified resource appears in Compare-UTCMConfiguration output as two rows (one per side); the
        report pairs them. The companion CSV still lists one row per diff row
        (Id, DisplayName, Type, DriftType, NormalizedData). An empty -Diff produces a "No drift detected"
        report and a header-only CSV. Formula-like CSV text cells are prefixed with an apostrophe
        for spreadsheet safety; JSON and HTML values are not modified.
        Available snapshot metadata is retained in a companion diagnostics JSON file.
        Partial metadata produces a prominent incomplete-comparison warning instead of a
        clean no-drift conclusion.

    .PARAMETER Diff
        The diff array from Compare-UTCMConfiguration (may be empty).

    .PARAMETER SnapshotId
        GUID of the baseline snapshot (used in the report header and file name).

    .PARAMETER OutputPath
        Directory for the output files.

    .PARAMETER CurrentItems
        Full configurationItems array from the current-state snapshot. When provided,
        a "Full current state" section is added to the HTML report.

    .PARAMETER Open
        Open the HTML report in the default browser after generation.

    .PARAMETER SnapshotDiagnostics
        Baseline and comparison job metadata, including status, resources and errorDetails.
        Get-UTCMTenantDriftReport supplies both automatically. For manually generated partial
        reports, supply both jobs so the warning and diagnostics cover both sides.

    .OUTPUTS
        PSCustomObject with HtmlPath, CsvPath, Added, Missing, Changed, Opened.

    .EXAMPLE
        $diff = Compare-UTCMConfiguration -BaselineSnapshotId $id1 -CompareSnapshotId $id2
        New-UTCMDriftReport -Diff $diff -SnapshotId $id1 -OutputPath .\Reports

    .EXAMPLE
        # With the full current state included
        New-UTCMDriftReport -Diff $diff -SnapshotId $id -OutputPath .\Reports -CurrentItems $items -Open
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()] $Diff,
        [Parameter(Mandatory)][string] $SnapshotId,
        [Parameter(Mandatory)][string] $OutputPath,

        # Full configuration items from the current-state snapshot
        $CurrentItems,

        [object[]] $SnapshotDiagnostics,

        # Open the generated HTML report in the default browser
        [switch] $Open
    )

    function _WriteLog([string]$msg, [string]$color='Gray') {
        if (Get-Command -Name Write-Log -ErrorAction SilentlyContinue) {
            Write-Log -Message $msg -Color $color
        } else {
            Write-Host ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) -ForegroundColor $color
        }
    }

    # Resolve output directory using module helper if available
    $outDir = if (Get-Command -Name Resolve-OutputPath -ErrorAction SilentlyContinue) {
        Resolve-OutputPath -Path $OutputPath
    } else {
        if (-not (Test-Path -LiteralPath $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
        $OutputPath
    }

    $htmlPath = Join-Path -Path $outDir -ChildPath ("UTCM-Drift-Report-{0}.html" -f $SnapshotId)
    $csvPath  = Join-Path -Path $outDir -ChildPath ("UTCM-Drift-Report-{0}.csv"  -f $SnapshotId)

    # Baseline snapshot metadata for the header (best effort)
    $baseline = $null
    try {
        $baseline = Get-UTCMSnapshot -SnapshotId $SnapshotId -IncludeDetails
    } catch {
        _WriteLog ("Warning: Could not fetch snapshot metadata for header (ID: $SnapshotId). Proceeding without details. Error: $($_.Exception.Message)") 'Yellow'
    }
    $baselineName     = [string](Get-UTCMObjectField $baseline @('displayName'))
    $baselineCreated  = Get-UTCMObjectField $baseline @('createdDateTime')
    $resourceLocation = [string](Get-UTCMObjectField $baseline @('resourceLocation'))
    $diagnostics = @($SnapshotDiagnostics | Where-Object { $null -ne $_ } |
        ForEach-Object { Get-UTCMSnapshotDiagnostic -Snapshot $_ })
    if ($baseline) {
        $baselineDiagnostic = Get-UTCMSnapshotDiagnostic -Snapshot $baseline
        if ($SnapshotId -notin @($diagnostics | ForEach-Object id)) {
            $diagnostics = @($baselineDiagnostic) + $diagnostics
        } elseif ($baselineDiagnostic.status -ne 'succeeded') {
            $diagnostics = @($baselineDiagnostic) + @($diagnostics | Where-Object id -ne $SnapshotId)
        }
    }
    $diagnosticsPath = Join-Path -Path $outDir -ChildPath ("UTCM-Drift-Report-{0}.diagnostics.json" -f $SnapshotId)
    Export-UTCMSnapshotDiagnostic -Diagnostic $diagnostics -Path $diagnosticsPath -Overwrite | Out-Null
    $incomplete = @($diagnostics | Where-Object { $_.status -ne 'succeeded' })
    if ($incomplete.Count -gt 0) {
        Write-Warning "INCOMPLETE COMPARISON: report differences are provisional, not reliable unattended drift conclusions. Diagnostics: $diagnosticsPath"
    }

    # One record per resource; a '<=' + '=>' pair becomes Changed
    $diffRows = @($Diff | Where-Object { $null -ne $_ })
    $records  = @(ConvertTo-UTCMDriftRecord -Diff $diffRows)
    $added    = @($records | Where-Object Status -eq 'Added').Count
    $missing  = @($records | Where-Object Status -eq 'Missing').Count
    $changed  = @($records | Where-Object Status -eq 'Changed').Count

    $html = Format-UTCMDriftReportHtml -Records $records -Diff $diffRows -SnapshotId $SnapshotId `
        -BaselineName $baselineName -BaselineCreated $baselineCreated -ResourceLocation $resourceLocation `
        -SnapshotDiagnostics $diagnostics `
        -CurrentItems $CurrentItems -GeneratedUtc ((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss') + ' UTC')

    $fullHtmlPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($htmlPath)
    [System.IO.File]::WriteAllText($fullHtmlPath, $html, (New-Object System.Text.UTF8Encoding($false)))

    if ($diffRows.Count -eq 0) {
        # Export-Csv emits nothing for empty input; keep the documented header row
        '"Id","DisplayName","Type","DriftType","NormalizedData"' | Out-File -LiteralPath $csvPath -Encoding UTF8
    } else {
        $diffRows |
            Select-Object `
                @{n='Id';e={ConvertTo-UTCMCsvCell $_.id}},
                @{n='DisplayName';e={ConvertTo-UTCMCsvCell $_.displayName}},
                @{n='Type';e={
                    if ($_.PSObject.Properties.Name -contains 'type') { ConvertTo-UTCMCsvCell $_.type }
                    elseif ($_.PSObject.Properties.Name -contains 'resourceType') { ConvertTo-UTCMCsvCell $_.resourceType }
                    else { $null }
                }},
                @{n='DriftType';e={ ConvertTo-UTCMCsvCell (Get-UTCMDriftTypeLabel $_.SideIndicator) }},
                @{n='NormalizedData';e={ConvertTo-UTCMCsvCell $_.normalizedData}} |
            Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
    }

    _WriteLog ("Dashboard written to: $htmlPath") 'Green'
    _WriteLog ("CSV written to: $csvPath") 'Green'

    # Open the HTML report if requested (cross-platform)
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
