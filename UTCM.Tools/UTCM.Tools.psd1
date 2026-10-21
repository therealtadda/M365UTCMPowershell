@{
    # Core identity
    RootModule        = 'UTCM.Tools.psm1'
    ModuleVersion     = '1.4.1'
    GUID              = 'c8b6d337-2a88-4f7b-b7c0-3e5d21df310a'
    Author            = 'Tadd Axon'
    CompanyName       = 'tadda.org'
    Copyright         = '(c) 2026 Tadd Axon. All rights reserved.'
    Description       = 'Unified Tenant Configuration Management (UTCM) tooling for Microsoft 365: create and retrieve configuration snapshots, compare snapshots to current tenant state, manage server-side monitors, and export/report results as JSON, CSV, and HTML via the Microsoft Graph UTCM APIs.'

    # Runtime requirements
    PowerShellVersion    = '7.0'
    CompatiblePSEditions = @('Core')
    RequiredModules      = @(
        @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.0.0' }
    )

    # Exports (explicit — no wildcards, per Gallery best practice)
    FunctionsToExport = @(
        'Enable-UTCM',
        'Grant-UTCMWorkloadAccess',
        'Initialize-UTCM',
        'Test-UTCMSetup',
        'Get-UTCMAvailableSnapshot',
        'New-UTCMSnapshot',
        'Get-UTCMSnapshot',
        'Remove-UTCMSnapshot',
        'Compare-UTCMConfiguration',
        'Export-UTCMSnapshot',
        'New-UTCMDriftReport',
        'Get-UTCMTenantDriftReport',
        'Get-UTCMPreset',
        'Get-UTCMDrift',
        'New-UTCMMonitor',
        'Get-UTCMMonitor',
        'Update-UTCMMonitor',
        'Remove-UTCMMonitor',
        'Get-UTCMMonitoringResult',
        'ConvertTo-UTCMMonitorResource'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    # Files shipped with the module (helps packaging tools and some installers)
    FileList = @(
        'UTCM.Tools.psd1',
        'UTCM.Tools.psm1',
        'Presets/resource-presets.json',
        'Presets/supported-resource-types.json'
    )

    # Gallery metadata
    PrivateData = @{
        PSData = @{
            Tags       = @(
                'UTCM','Microsoft365','M365','Graph','GraphAPI',
                'Drift','Snapshot','TenantConfig','ConfigurationMonitoring',
                'Entra','Exchange','Intune','Teams','SecurityAndCompliance',
                'Windows','Linux','MacOS','PSEdition_Core'
            )
            LicenseUri = 'https://github.com/therealtadda/M365UTCMPowershell/blob/main/LICENSE'
            ProjectUri = 'https://github.com/therealtadda/M365UTCMPowershell'
            # IconUri  = 'https://raw.githubusercontent.com/therealtadda/M365UTCMPowershell/main/icon.png'

            # Modern NuGet license metadata used by Publish-PSResource (PSResourceGet).
            # Avoids the "<licenseUrl> will be deprecated" NuGet warning.
            License    = 'BSD-3-Clause'

            ReleaseNotes = @'
1.4.1
- CSV text cells are spreadsheet-safe by default in snapshot/drift exports and HTML downloads; JSON and displayed values remain unchanged.
- Report metadata preserves CR/LF/tab characters through HTML parsing so browser CSV/JSON downloads retain the original values.
- Graph requests validate HTTPS URLs against the connected environment, including pagination and snapshot downloads. External download hosts are rejected.
- Snapshot downloads consistently use Graph authentication and retry handling; exhausted retries now throw without a final unnecessary sleep.
- Privileged setup supports an offline -WhatIf preview and high-impact confirmation. Setup requests only the required scopes, adding role management for Teams.
- Existing delegated sessions are checked for required scopes without silently changing tenant/account; read-only workflows request read-only permissions.
- Directory-role assignment errors are reported unless concurrent membership is verified; resource-type OData literals are escaped.
- Machine-wide presets require trusted Windows ownership and ACLs, reject reparse points, and warn when replacing a shipped/built-in preset.
- Publishing stages only intended module content; generated test output is no longer tracked.

1.4.0
- Redesigned HTML reports (New-UTCMDriftReport and Export-UTCMSnapshot -Format HTML) on a shared, self-contained foundation:
  summary cards, workload/type distribution, search (including property values), status/workload/type filters, sorting, paging,
  column chooser, CSV/JSON downloads, copy buttons, shareable filter state in the URL hash, light/dark themes, responsive and print layouts.
- Drift report: property-level Baseline / Current comparison for changed resources (full JSON remains as "Raw JSON"); a "Show only changed properties" toggle; the Full current state section is searchable and paged.
- Snapshot report: items grouped by workload (collapsible) or a flat paged view; explicit empty state for snapshots with no items.
- Accessibility: semantic tables, labelled controls, keyboard support, visible focus, status shown by icon, text and border style (not color alone), forced-colors support.
- Security: every report ships a Content-Security-Policy that pins its own script and style by SHA-256 and blocks all network access; output is HTML-encoded in text and attribute contexts; only https links are emitted; no inline event handlers or style attributes.
- CSV and JSON outputs are unchanged. Browser support: current Edge, Chrome and Firefox; Safari is best-effort.

1.3.1
- Drift report: a modified resource is now reported once as "Changed" (baseline and current shown pretty-printed) instead of as one "Missing" plus one "Added" row. The Added/Missing/Changed counts returned by New-UTCMDriftReport reflect this. CSV output is unchanged.
- New-UTCMDriftReport accepts an empty -Diff, and Get-UTCMTenantDriftReport -Dashboard now writes a "No drift detected" report instead of warning when the comparison finds no differences.
- HTML reports: sorting by a column can now end in ascending order; statuses show an icon and text in addition to color; added doctype, lang and viewport.
- HtmlEncode no longer throws on null or empty input.
- Test output now goes to TestDrive; Tests/artifacts is no longer tracked.

1.3.0
- Updated UTCM REST operations to Microsoft Graph v1.0 endpoints.
- Added Update-UTCMMonitor and Remove-UTCMMonitor.
- Added support for active and inactive monitor status filtering.
- Updated UTCM documentation to distinguish GA configuration capabilities from module-supported workflows.

1.2.0
- Added server-side drift monitoring: New-UTCMMonitor, Get-UTCMMonitor, Get-UTCMMonitoringResult, Get-UTCMDrift.
- Get-UTCMSnapshot -IncludeItems normalizes both `configurationItems` and `resources`/`properties` payloads to a consistent id/displayName/type/data shape; original artifact exposed as `rawConfiguration`.
- Export-UTCMSnapshot CSV/HTML now include full per-resource configuration JSON (matches JSON export fidelity).
- New-UTCMDriftReport: full-fidelity expandable per-row details; CSV `NormalizedData` carries full normalized payload.
- Added `ConfigurationMonitoring.Read.All` least-privilege scope for read-only cmdlets.
- Hardened idempotency when assigning Entra directory roles (handles "already exists" 400).
- Test-UTCMSetup resilient to Microsoft.Graph SDK object-shape differences.
'@

            RequireLicenseAcceptance = $false
        }
    }

    # Help (optional — populate when a help site exists)
    # HelpInfoURI = 'https://github.com/therealtadda/M365UTCMPowershell/blob/main/README.md'
}