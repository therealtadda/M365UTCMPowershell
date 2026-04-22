@{
    # Core identity
    RootModule        = 'UTCM.Tools.psm1'
    ModuleVersion     = '1.2.0'
    GUID              = 'c8b6d337-2a88-4f7b-b7c0-3e5d21df310a'
    Author            = 'Tadd Axon'
    CompanyName       = 'tadda.org'
    Copyright         = '(c) 2026 Tadd Axon. All rights reserved.'
    Description       = 'Unified Tenant Configuration Management (UTCM) tooling for Microsoft 365: create and retrieve configuration snapshots, compare snapshots to current tenant state, detect drift via server-side monitors, and export/report results as JSON, CSV, and HTML via the Microsoft Graph beta UTCM APIs.'

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
        'Get-UTCMMonitoringResult'
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

            ReleaseNotes = @'
1.2.0
- Added server-side drift monitoring: New-UTCMMonitor, Get-UTCMMonitor, Get-UTCMMonitoringResult, Get-UTCMDrift.
- Get-UTCMSnapshot -IncludeItems normalizes both `configurationItems` and `resources`/`properties` payloads to a consistent id/displayName/type/data shape; original artifact exposed as `rawConfiguration`.
- Export-UTCMSnapshot CSV/HTML now include full per-resource configuration JSON (matches JSON export fidelity).
- New-UTCMDriftReport: full-fidelity expandable per-row details; CSV `NormalizedData` carries full normalized payload.
- Added `ConfigurationMonitoring.Read.All` least-privilege scope for read-only cmdlets.
- Hardened idempotency when assigning Entra directory roles (handles "already exists" 400).
- Test-UTCMSetup resilient to Microsoft.Graph SDK object-shape differences.
'@

            # Prerelease = 'beta1'   # Uncomment for preview builds (e.g. 1.3.0-beta1)
            RequireLicenseAcceptance = $false
        }
    }

    # Help (optional — populate when a help site exists)
    # HelpInfoURI = 'https://github.com/therealtadda/M365UTCMPowershell/blob/main/README.md'
}