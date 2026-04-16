@{
    RootModule        = 'UTCM.Tools.psm1'
    ModuleVersion     = '1.2.0'
    GUID              = 'c8b6d337-2a88-4f7b-b7c0-3e5d21df310a'
    Author            = 'Tadd Axon (pragmaticscripts@tadda.ltd)'
    CompanyName       = 'tadda.org'
    Description       = 'Unified Tenant Configuration Management tooling: snapshots, comparison, and drift reporting for Microsoft 365 via Graph.'
    PowerShellVersion = '7.0'
    # Optional: require the Graph module explicitly
    RequiredModules   = @('Microsoft.Graph.Authentication')

    # Public functions to export:
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

    PrivateData = @{
        PSData = @{
            Tags = @('UTCM','Microsoft365','GraphAPI','Drift','Snapshot','TenantConfig')
        }
    }
}