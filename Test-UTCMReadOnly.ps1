#requires -Version 7.0
<#
.SYNOPSIS
    Smoke-tests UTCM read operations using an existing Microsoft Graph connection.

.DESCRIPTION
    Imports the repository's UTCM.Tools module and reads snapshot jobs, monitors,
    recent monitoring results, and drifts. Requires an existing connection to the
    explicitly supplied tenant GUID and checks the tenant and environment before
    every operation. Does not sign in, reconnect, install modules, or mutate tenant
    configuration. Missing scopes and API failures terminate the script.

    Returns a summary containing counts, not resource names or configuration values.
    Empty collections are valid read results, not proof of workload health. The
    module follows pagination before applying client-side result limits.

.PARAMETER TenantId
    The expected directory tenant GUID. Domain names are not resolved.

.PARAMETER SnapshotId
    Optional existing snapshot job GUID. Explicitly opts into downloading its
    configuration artifact through the module's authenticated Graph request path.
    The module removes its temporary download; only the item count is returned.

.OUTPUTS
    PSObject with TenantId, Environment, AuthType, ModuleVersion, CheckedAtUtc,
    and Checks. Each check has Name, Status, and Count. Failures throw.

.EXAMPLE
    .\Test-UTCMReadOnly.ps1 -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'

.EXAMPLE
    .\Test-UTCMReadOnly.ps1 -TenantId $tenantId -SnapshotId $existingSnapshotId
#>
[CmdletBinding()]
[OutputType([pscustomobject])]
param(
    [Parameter(Mandatory)]
    [ValidateScript({
        if ($_ -eq [guid]::Empty) { throw 'TenantId must not be an empty GUID.' }
        $true
    })]
    [guid]$TenantId,

    [ValidateScript({
        if ($_ -eq [guid]::Empty) { throw 'SnapshotId must not be an empty GUID.' }
        $true
    })]
    [guid]$SnapshotId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-UTCMReadOnlyContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][guid]$ExpectedTenantId,
        [string]$ExpectedEnvironment
    )

    $context = Get-MgContext -ErrorAction Stop
    if (-not $context) {
        throw 'No existing Microsoft Graph connection. Connect explicitly to the intended tenant in this PowerShell session before running this script.'
    }

    $connectedTenantId = [guid]::Empty
    if (-not [guid]::TryParse([string]$context.TenantId, [ref]$connectedTenantId)) {
        throw 'The existing Graph context does not expose a valid tenant GUID. Reconnect explicitly before running this script.'
    }
    if ($connectedTenantId -ne $ExpectedTenantId) {
        throw "The connected tenant '$connectedTenantId' does not match the expected tenant '$ExpectedTenantId'. No read was attempted with this context."
    }
    if ([string]::IsNullOrWhiteSpace($context.Environment)) {
        throw 'The existing Graph context does not expose an environment. Reconnect explicitly before running this script.'
    }
    if ($ExpectedEnvironment -and $context.Environment -ne $ExpectedEnvironment) {
        throw 'The Graph environment changed during validation. No read was attempted with the changed context.'
    }
    return $context
}

$module = Import-Module (Join-Path $PSScriptRoot 'UTCM.Tools\UTCM.Tools.psd1') -PassThru -ErrorAction Stop
$initialContext = Get-UTCMReadOnlyContext -ExpectedTenantId $TenantId
$environment = [string]$initialContext.Environment
$readChecks = @(
    @{
        Name = 'Snapshot jobs'
        Command = 'UTCM.Tools\Get-UTCMAvailableSnapshot'
        Parameters = @{ Top = 5 }
    }
    @{
        Name = 'Monitors'
        Command = 'UTCM.Tools\Get-UTCMMonitor'
        Parameters = @{}
    }
    @{
        Name = 'Monitoring results (last 7 days)'
        Command = 'UTCM.Tools\Get-UTCMMonitoringResult'
        Parameters = @{ Since = [datetime]::UtcNow.AddDays(-7); Top = 5 }
    }
    @{
        Name = 'Drifts'
        Command = 'UTCM.Tools\Get-UTCMDrift'
        Parameters = @{ Top = 5 }
    }
)

$results = @(foreach ($check in $readChecks) {
    Get-UTCMReadOnlyContext -ExpectedTenantId $TenantId -ExpectedEnvironment $environment | Out-Null
    $parameters = $check.Parameters
    $items = @(& $check.Command @parameters -ErrorAction Stop)
    [pscustomobject]@{
        Name = $check.Name
        Status = 'Passed'
        Count = $items.Count
    }
})

if ($PSBoundParameters.ContainsKey('SnapshotId')) {
    Get-UTCMReadOnlyContext -ExpectedTenantId $TenantId -ExpectedEnvironment $environment | Out-Null
    $snapshot = UTCM.Tools\Get-UTCMSnapshot -SnapshotId $SnapshotId.ToString() -IncludeItems -ErrorAction Stop
    $itemCount = if ($null -eq $snapshot.configurationItems) { 0 } else { @($snapshot.configurationItems).Count }
    $results += [pscustomobject]@{
        Name = 'Snapshot artifact items'
        Status = 'Passed'
        Count = $itemCount
    }
} else {
    $results += [pscustomobject]@{
        Name = 'Snapshot artifact items'
        Status = 'Skipped'
        Count = $null
    }
}

[pscustomobject]@{
    TenantId = $TenantId.ToString()
    Environment = $environment
    AuthType = [string]$initialContext.AuthType
    ModuleVersion = $module.Version.ToString()
    CheckedAtUtc = [datetimeoffset]::UtcNow
    Checks = $results
}
