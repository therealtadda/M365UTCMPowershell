@{
    RootModule        = 'UTCM.Tools.psm1'
    ModuleVersion     = '1.1.0'
    GUID              = 'c8b6d337-2a88-4f7b-b7c0-3e5d21df310a'
    Author            = 'Your Name'
    CompanyName       = 'Your Org'
    Description       = 'Unified Tenant Configuration Management tooling: snapshots, comparison, and drift reporting for Microsoft 365 via Graph.'
    PowerShellVersion = '7.0'
    # Optional: require the Graph module explicitly
    # RequiredModules   = @('Microsoft.Graph.Authentication')

    # Public functions to export:
    FunctionsToExport = @(
        'Get-UTCMAvailableSnapshot',
        'New-UTCMSnapshot',
        'Get-UTCMSnapshot',
        'Compare-UTCMConfiguration',
        'Export-UTCMSnapshot',
        'New-UTCMDriftReport',
        'Get-UTCMTenantDriftReport'
    )

    PrivateData = @{
        PSData = @{
            Tags = @('UTCM','Microsoft365','GraphAPI','Drift','Snapshot','TenantConfig')
        }
    }
}