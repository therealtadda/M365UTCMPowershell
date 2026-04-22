# UTCM.Tools

**UTCM.Tools** is a PowerShell 7+ module for working with Microsoft Graph's
**Unified Tenant Configuration Management (UTCM)** public preview APIs.

It enables:

- Creating and retrieving **snapshots** of Microsoft 365 tenant configuration
- Comparing snapshots to **current** configuration or to other snapshots
- **Server-side drift monitoring** with automated periodic detection via configuration monitors
- **Property-level drift details** showing current vs. desired values from the API
- Detailed, sortable **HTML drift reports** and **CSV** exports
- Exporting snapshots to **JSON**, **CSV**, and **HTML**
- **Snapshot lifecycle management** including creation, listing, and deletion
- Automation-friendly behavior with **bind-time validation**, **retry logic**, and **Pester tests**

> :warning: **UTCM APIs are in public preview.** Configuration apply/restore is **not yet available**.
> This module focuses solely on **read**, **compare**, and **report** workflows.

---

## Permissions

### Graph Connection (interactive user)

```powershell
# Full access (create snapshots, monitors, delete jobs)
Connect-MgGraph -Scopes "ConfigurationMonitoring.ReadWrite.All"

# Read-only access (list snapshots, view drifts, read monitors)
Connect-MgGraph -Scopes "ConfigurationMonitoring.Read.All"
```

> **New in v1.2.0:** `ConfigurationMonitoring.Read.All` is now supported as a least-privilege
> scope for read-only operations (listing snapshots, viewing drifts, reading monitors).
> Read-only cmdlets like `Get-UTCMDrift`, `Get-UTCMMonitor`, and `Get-UTCMMonitoringResult`
> automatically use this scope when calling `Ensure-GraphConnection`.

> **For setup / `Initialize-UTCM`:** you also need `Application.ReadWrite.All`,
> `AppRoleAssignment.ReadWrite.All`, `Directory.ReadWrite.All`, and
> `RoleManagement.ReadWrite.Directory` (the last one is required to assign the
> `Global Reader` directory role for Teams).

### UTCM Service Principal Permissions

The UTCM service principal (`03b07b79-c5bc-4b5e-9bfa-13acf4a99998`) requires
workload-specific permissions. Use `Grant-UTCMWorkloadAccess` to assign them.

#### Graph App Roles

| Workload | Graph App Roles |
|---|---|
| **Entra** | `Policy.Read.All`, `Directory.Read.All` |
| **Exchange** | `Exchange.ManageAsApp` (on Office 365 Exchange Online resource) |
| **Intune** | `DeviceManagementConfiguration.Read.All`, `DeviceManagementRBAC.Read.All`, `DeviceManagementManagedDevices.Read.All`, `DeviceManagementApps.Read.All`, `DeviceManagementServiceConfig.Read.All`, `Group.Read.All` |
| **Security & Compliance** | `Exchange.ManageAsApp`, `InformationProtectionConfig.Read.All`, `Directory.Read.All` |
| **Teams** | `Organization.Read.All`, `TeamSettings.Read.All` |

#### Exchange Online RBAC Roles (scoped to the SP via `-App`)

| Workload | EXO Management Roles |
|---|---|
| **Exchange** | `View-Only Configuration`, `View-Only Recipients` |
| **Security & Compliance** | `View-Only Configuration`, `Security Reader` (EXO role, NOT the Entra directory role) |

> These are assigned via `New-ManagementRoleAssignment -App` and are scoped exclusively
> to the UTCM service principal -- no tenant-wide Entra directory roles are used for
> Exchange or S&C workloads.

#### Entra Directory Roles

| Workload | Directory Role | Why |
|---|---|---|
| **Teams** | `Global Reader` | Required by all UTCM Teams resources per [official docs](https://learn.microsoft.com/en-us/graph/utcm-teams-resources) |

> `Global Reader` is the only tenant-wide directory role used. It is required for Teams
> and there is no lesser alternative in the current UTCM API.

#### Required Modules

| Module | Required For |
|---|---|
| `Microsoft.Graph.Authentication` | All operations (Graph API calls) |
| `ExchangeOnlineManagement` | `Grant-UTCMWorkloadAccess -Workloads Exchange` or `SecurityAndCompliance` (EXO RBAC setup) |

---

## Requirements

- PowerShell **7+**
- `Microsoft.Graph.Authentication` module:
  ```powershell
  Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
  ```
- `ExchangeOnlineManagement` (optional, for Exchange/S&C RBAC):
  ```powershell
  Install-Module ExchangeOnlineManagement -Scope CurrentUser
  ```

---

## Installation

### Per-User Installation (Recommended)

```powershell
$mod = Join-Path $HOME "Documents/PowerShell/Modules/UTCM.Tools"
New-Item -ItemType Directory -Path $mod -Force | Out-Null
Copy-Item -Path '.\UTCM.Tools\*' -Destination $mod -Recurse -Force
Import-Module UTCM.Tools -Force
```

### Verify Installation

```powershell
Import-Module UTCM.Tools -Force
Get-Command -Module UTCM.Tools
```

Expected: 17 exported functions.

All 17 functions include full comment-based help:

```powershell
Get-Help New-UTCMSnapshot -Full
Get-Help Get-UTCMTenantDriftReport -Examples
```

---

## Module Structure

```
UTCM.Tools/
+-- UTCM.Tools.psd1            # Module manifest
+-- UTCM.Tools.psm1            # Root module (strict mode + loader)
|
+-- Public/                    # Exported functions (17)
|   +-- Enable-UTCM.ps1
|   +-- Grant-UTCMWorkloadAccess.ps1
|   +-- Initialize-UTCM.ps1
|   +-- Test-UTCMSetup.ps1
|   +-- Get-UTCMAvailableSnapshot.ps1
|   +-- New-UTCMSnapshot.ps1
|   +-- Get-UTCMSnapshot.ps1
|   +-- Remove-UTCMSnapshot.ps1
|   +-- Get-UTCMPreset.ps1
|   +-- Compare-UTCMConfiguration.ps1
|   +-- Export-UTCMSnapshot.ps1
|   +-- New-UTCMDriftReport.ps1
|   +-- Get-UTCMTenantDriftReport.ps1
|   +-- Get-UTCMDrift.ps1
|   +-- New-UTCMMonitor.ps1
|   +-- Get-UTCMMonitor.ps1
|   +-- Get-UTCMMonitoringResult.ps1
|
+-- Private/                   # Internal helpers (not exported)
|   +-- Ensure-GraphConnection.ps1
|   +-- Invoke-GraphRequestWithRetry.ps1
|   +-- Get-UTCMCurrentStateSnapshot.ps1
|   +-- ConvertTo-NormalizedJson.ps1
|   +-- Presets.ps1
|   +-- Resolve-OutputPath.ps1
|   +-- Validate-Guid.ps1
|   +-- HtmlEncode.ps1
|   +-- Write-Log.ps1
|
+-- Presets/                   # JSON-backed resource presets & allow-list
|   +-- resource-presets.json
|   +-- supported-resource-types.json
|
+-- Tests/                     # Pester 5 test suite
    +-- Compare-UTCMConfiguration.Tests.ps1
    +-- Export-UTCMSnapshot.Tests.ps1
    +-- Get-UTCMAvailableSnapshot.Tests.ps1
    +-- Get-UTCMDrift.Tests.ps1
    +-- Get-UTCMMonitor.Tests.ps1
    +-- Get-UTCMMonitoringResult.Tests.ps1
    +-- Get-UTCMSnapshot.Tests.ps1
    +-- Get-UTCMTenantDriftReport.Tests.ps1
    +-- New-UTCMDriftReport.Tests.ps1
    +-- New-UTCMMonitor.Tests.ps1
    +-- New-UTCMSnapshot.Tests.ps1
    +-- Remove-UTCMSnapshot.Tests.ps1
```

---

## Quick Start

```powershell
# 1. Bootstrap UTCM (one-time)
Import-Module UTCM.Tools -Force
Connect-MgGraph -Scopes "ConfigurationMonitoring.ReadWrite.All","Application.ReadWrite.All","AppRoleAssignment.ReadWrite.All","Directory.ReadWrite.All","RoleManagement.ReadWrite.Directory"
Initialize-UTCM -Workloads Entra,Exchange,Intune,SecurityAndCompliance,Teams

# 2. Create a baseline snapshot
$snap = New-UTCMSnapshot -DisplayName "Baseline March 2026"

# 3. Generate drift report against current tenant state
Get-UTCMTenantDriftReport -SnapshotId $snap.id -CompareToCurrent -Dashboard -OutputPath .\Reports -NoPrompt
```

---

## Command Reference

### `Enable-UTCM`

Ensures the Microsoft-owned UTCM service principal exists in your tenant (idempotent).

```powershell
Enable-UTCM
```

---

### `Grant-UTCMWorkloadAccess`

Grants the UTCM service principal minimum read-level access across selected workloads.

**What it assigns per workload:**

| Workload | Graph App Roles | EXO RBAC | Entra Directory Role |
|---|---|---|---|
| Entra | `Policy.Read.All`, `Directory.Read.All` | -- | -- |
| Exchange | `Exchange.ManageAsApp` | `View-Only Configuration`, `View-Only Recipients` | -- |
| Intune | 6 Graph app roles (see Permissions section) | -- | -- |
| SecurityAndCompliance | `Exchange.ManageAsApp`, `InformationProtectionConfig.Read.All`, `Directory.Read.All` | `View-Only Configuration`, `Security Reader` | -- |
| Teams | `Organization.Read.All`, `TeamSettings.Read.All` | -- | `Global Reader` |

```powershell
# All workloads
Grant-UTCMWorkloadAccess

# Subset
Grant-UTCMWorkloadAccess -Workloads Entra,Exchange

# Exchange requires ExchangeOnlineManagement -- will prompt for EXO auth
Grant-UTCMWorkloadAccess -Workloads Exchange
```

> **Note:** Exchange and S&C workloads require `ExchangeOnlineManagement` module.
> The function connects to EXO automatically (WAM first, device-code fallback).

---

### `Initialize-UTCM`

One-shot wrapper: runs `Enable-UTCM` then `Grant-UTCMWorkloadAccess`.

```powershell
Initialize-UTCM -Workloads Entra,Exchange,Intune,SecurityAndCompliance,Teams
```

---

### `Test-UTCMSetup`

Validates the UTCM service principal: shows app-role assignments and directory roles.

```powershell
Test-UTCMSetup
```

---

### `New-UTCMSnapshot`

Creates a new UTCM snapshot. Resources can be specified explicitly or via a named preset.

| Parameter | Default | Description |
|---|---|---|
| `-Preset` | `TenantCore` | Named preset from `Presets/resource-presets.json` |
| `-Resources` | -- | Explicit resource identifiers (overrides `-Preset`) |
| `-DisplayName` | Auto-generated | Friendly name (alphanumeric + spaces only) |
| `-Description` | `"Baseline snapshot"` | Description |
| `-PollingIntervalSeconds` | `10` | Poll interval during job execution |

```powershell
New-UTCMSnapshot
New-UTCMSnapshot -Preset ExchangeCore
New-UTCMSnapshot -Resources 'microsoft.exchange.sharedmailbox','microsoft.exchange.transportrule'
New-UTCMSnapshot -DisplayName "Pre Change Audit 20260313"
```

> **DisplayName constraint:** The UTCM API allows only letters, numbers, and spaces.
> Any special characters are automatically stripped before submission.

Available presets: `ExchangeCore`, `EntraCore`, `TeamsCore`, `IntuneCore`, `SecCompCore`,
`TenantCore`, `TeamsCore+Voice`, `IntuneCore+Roles`, `SecurityCore`.

---

### `Get-UTCMAvailableSnapshot`

Lists all available UTCM snapshot jobs. Now returns enriched metadata including
`createdBy` (who created the snapshot), `resources` (which resource types were included),
and `tenantId`.

```powershell
Get-UTCMAvailableSnapshot
Get-UTCMAvailableSnapshot -DownloadableOnly
Get-UTCMAvailableSnapshot -AsJson
```

---

### `Get-UTCMSnapshot`

Retrieves a snapshot job by ID. Use `-IncludeItems` to download the full configuration payload.

```powershell
Get-UTCMSnapshot -SnapshotId <GUID>
Get-UTCMSnapshot -SnapshotId <GUID> -IncludeDetails    # includes errorDetails, resourceLocation
Get-UTCMSnapshot -SnapshotId <GUID> -IncludeItems       # downloads and attaches configurationItems
Get-UTCMSnapshot -SnapshotId <GUID> -IncludeItems -AsJson
```

> Use `-IncludeDetails` on `partiallySuccessful` snapshots to see per-resource error messages.

**Item normalization:** `-IncludeItems` handles both UTCM payload shapes and returns a
consistent `configurationItems` array where each item has `id`, `displayName`, `type`, and
`data`. The original payload is also attached as `rawConfiguration` for power users.

| Raw payload field | Normalized to |
|---|---|
| `resources[].resourceType` / `type` | `type` |
| `resources[].properties` / `data` | `data` |
| `id` / `resourceInstanceIdentifier` / `properties.Id\|Identity\|Guid\|ObjectId` | `id` |
| `displayName` | `displayName` |

---

### `Get-UTCMPreset`

Lists available resource presets or inspects a specific preset.

```powershell
Get-UTCMPreset                          # list all preset names
Get-UTCMPreset -Name ExchangeCore       # show resources in preset
Get-UTCMPreset -Name TenantCore -Raw    # raw string array
```

---

### `Compare-UTCMConfiguration`

Compares two snapshots or a baseline against current tenant state.

```powershell
# Compare two snapshots
Compare-UTCMConfiguration -BaselineSnapshotId <GUID> -CompareSnapshotId <GUID>

# Compare baseline to current tenant state
Compare-UTCMConfiguration -BaselineSnapshotId <GUID>
```

---

### `Export-UTCMSnapshot`

Downloads and exports a snapshot to JSON, CSV, and/or HTML (all three by default).

`-Path` is always a **directory** (created if missing). Files are named `Snapshot-{jobId}.{ext}`.

| Parameter | Default | Description |
|---|---|---|
| `-Snapshot` | *(mandatory)* | Snapshot job object or GUID |
| `-Path` | *(mandatory)* | Output directory |
| `-Format` | `JSON,CSV,HTML` | Which formats to write |
| `-Raw` | — | Write full JSON payload instead of just `configurationItems` |
| `-SplitByResourceType` | — | One JSON file per resource under `{workload}/{type}/` (ignores `-Format`) |
| `-Overwrite` | — | Overwrite existing files |

```powershell
# All three formats (default)
Export-UTCMSnapshot -Snapshot $snap -Path .\exports

# JSON only
Export-UTCMSnapshot -Snapshot $snap -Path .\exports -Format JSON

# CSV + HTML
Export-UTCMSnapshot -Snapshot $snap -Path .\exports -Format CSV,HTML

# By snapshot ID
Export-UTCMSnapshot -Snapshot 99452b34-8a9f-49fb-bdc2-744cbdea7654 -Path .\exports

# Split into per-resource JSON files
Export-UTCMSnapshot -Snapshot $snap -Path .\exports -SplitByResourceType
```

**Output formats:**
- **JSON** — `configurationItems` array (or full payload with `-Raw`)
- **CSV** — One row per resource with `Id`, `DisplayName`, `Type`, `Workload`, and `Data` (full
  configuration JSON, compact). Matches the JSON export in fidelity.
- **HTML** — Self-contained sortable dashboard with workload summary badges and
  expandable per-item settings showing the full configuration JSON (Expand All / Collapse All)

---

### `New-UTCMDriftReport`

Generates a paginated HTML dashboard and CSV from a diff result.

| Parameter | Default | Description |
|---|---|---|
| `-Diff` | *(mandatory)* | Output from `Compare-UTCMConfiguration` |
| `-SnapshotId` | *(mandatory)* | Baseline snapshot GUID (used in report title) |
| `-OutputPath` | `.\` | Output directory |
| `-CurrentItems` | — | Array of current-state `configurationItems` for full-state page |

**HTML output has two pages:**
1. **Drift Summary** — Added, Removed, and Changed items with expandable normalised-data details per row
2. **Full Current State** — Every item from the current snapshot with expandable settings (shown when `-CurrentItems` is supplied)

Both pages include sortable columns, Expand All / Collapse All buttons, and cross-page navigation links.
The expandable per-row detail contains the full configuration JSON (same fidelity as
`Export-UTCMSnapshot`), and the companion CSV's `NormalizedData` column carries the full
normalized payload for each drifted row.

```powershell
$diff = Compare-UTCMConfiguration -BaselineSnapshotId <GUID>
New-UTCMDriftReport -Diff $diff -SnapshotId <GUID> -OutputPath .\Reports

# Include full current state page
$current = Get-UTCMSnapshot -SnapshotId <CURRENT_GUID> -IncludeItems
New-UTCMDriftReport -Diff $diff -SnapshotId <GUID> -OutputPath .\Reports `
  -CurrentItems $current.configurationItems
```

Returns a `PSCustomObject` with `HtmlPath`, `CsvPath`, `Added`, `Missing`, `Changed`, and `Opened` properties.

---

### `Get-UTCMTenantDriftReport`

End-to-end drift pipeline: select baseline -> compare to current -> generate report.

When `-CompareToCurrent` is used, the function creates a fresh "current state" snapshot
and compares it to the baseline. By default it uses the **same resource types** as the
baseline. You can override this with `-ComparePreset` or `-CompareResources`.

In interactive mode (no `-NoPrompt`), a numbered menu of available presets is shown so
you can pick a different resource scope for the comparison.

| Parameter | Default | Description |
|---|---|---|
| `-SnapshotId` | *(interactive)* | Baseline snapshot GUID (prompted if omitted) |
| `-CompareToCurrent` | — | Create a current-state snapshot and compare |
| `-ComparePreset` | — | Named preset for the comparison snapshot |
| `-CompareResources` | — | Explicit resource identifiers for comparison |
| `-Dashboard` | — | Generate HTML drift report |
| `-ExportJson` | — | Export baseline snapshot to JSON |
| `-OutputPath` | `.\` | Output directory |
| `-NoPrompt` | — | Non-interactive (CI-friendly) |

```powershell
# Interactive: select baseline, choose preset for comparison
Get-UTCMTenantDriftReport -CompareToCurrent -Dashboard

# Same resources as baseline, no prompts
Get-UTCMTenantDriftReport `
  -SnapshotId <GUID> `
  -CompareToCurrent `
  -Dashboard `
  -OutputPath .\Reports `
  -NoPrompt

# Compare using a specific preset
Get-UTCMTenantDriftReport `
  -SnapshotId <GUID> `
  -CompareToCurrent `
  -ComparePreset ExchangeCore `
  -Dashboard

# Full CI pipeline
Get-UTCMTenantDriftReport `
  -SnapshotId <GUID> `
  -CompareToCurrent `
  -ExportJson `
  -Dashboard `
  -OutputPath .\Reports `
  -NoPrompt
```

---

### `Remove-UTCMSnapshot`

Deletes a snapshot job and its associated artifact.

```powershell
Remove-UTCMSnapshot -SnapshotId <GUID>

# Delete all failed snapshots
Get-UTCMAvailableSnapshot -Status failed | ForEach-Object { Remove-UTCMSnapshot -SnapshotId $_.id }
```

> Requires `ConfigurationMonitoring.ReadWrite.All`. Has `ConfirmImpact = 'High'`; use `-Confirm:$false` to suppress.

---

### `Get-UTCMDrift`

Queries the UTCM API for **server-side property-level drift data**. Returns granular information
about which properties drifted from their desired baseline values, including `currentValue` and
`desiredValue` for each property.

| Parameter | Default | Description |
|---|---|---|
| `-MonitorId` | — | Filter drifts to a specific monitor GUID |
| `-Status` | — | `active` or `fixed` |
| `-ResourceType` | — | Filter by resource type (e.g., `microsoft.exchange.accepteddomain`) |
| `-Top` | — | Limit to N most recent drifts |
| `-IncludeDetails` | — | Include `driftedProperties` and `resourceInstanceIdentifier` |
| `-AsJson` | — | Return as JSON string |

```powershell
# List all active drifts
Get-UTCMDrift -Status active

# Get full drift details with property-level changes
Get-UTCMDrift -IncludeDetails

# Drifts for a specific monitor
Get-UTCMDrift -MonitorId <GUID> -IncludeDetails -AsJson

# Filter by resource type
Get-UTCMDrift -ResourceType 'microsoft.exchange.accepteddomain' -IncludeDetails
```

> Uses `ConfigurationMonitoring.Read.All` (least privilege). The `-IncludeDetails` switch
> exposes `driftedProperties` (array of `propertyName`, `currentValue`, `desiredValue`)
> and `resourceInstanceIdentifier` (helps identify exact resource instances).

---

### `New-UTCMMonitor`

Creates a **configuration monitor** that runs automatically every 6 hours to detect drift
from a defined baseline. Monitors are triggered at fixed GMT times: 6 AM, 12 PM, 6 PM, 12 AM.

| Parameter | Default | Description |
|---|---|---|
| `-DisplayName` | *(mandatory)* | Friendly name for the monitor |
| `-Description` | — | Optional description |
| `-BaselineDisplayName` | `"{DisplayName} Baseline"` | Name for the baseline |
| `-BaselineResources` | *(mandatory)* | Array of hashtables with `displayName`, `resourceType`, `properties` |
| `-Parameters` | — | Optional key-value pairs for baseline parameters |

```powershell
$resources = @(
    @{
        displayName  = 'Accepted Domain'
        resourceType = 'microsoft.exchange.accepteddomain'
        properties   = @{
            Identity   = 'contoso.onmicrosoft.com'
            DomainType = 'InternalRelay'
            Ensure     = 'Present'
        }
    },
    @{
        displayName  = 'TestSharedMailbox'
        resourceType = 'microsoft.exchange.sharedmailbox'
        properties   = @{
            DisplayName = 'TestSharedMailbox'
            Alias       = 'testSharedMailbox'
            Ensure      = 'Present'
        }
    }
)
New-UTCMMonitor -DisplayName 'Exchange Monitor' -Description 'Monitor Exchange config' -BaselineResources $resources
```

> The monitor's baseline defines the **desired state** for each property. When the API
> detects a property has a different value, it records a drift. Use `Get-UTCMDrift` to view.

---

### `Get-UTCMMonitor`

Lists or retrieves configuration monitors.

```powershell
# List all monitors
Get-UTCMMonitor

# Get a specific monitor with its baseline
Get-UTCMMonitor -MonitorId <GUID> -IncludeBaseline

# Active monitors as JSON
Get-UTCMMonitor -Status active -AsJson
```

---

### `Get-UTCMMonitoringResult`

Retrieves the history of monitor runs, including drift counts, run status, and errors.

| Parameter | Default | Description |
|---|---|---|
| `-MonitorId` | — | Filter to a specific monitor GUID |
| `-RunStatus` | — | `successful`, `partiallySuccessful`, or `failed` |
| `-Since` | — | Only results after this datetime (UTC) |
| `-Top` | — | Limit to N most recent results |
| `-IncludeDetails` | — | Include `errorDetails` |
| `-AsJson` | — | Return as JSON string |

```powershell
# All recent monitoring results
Get-UTCMMonitoringResult

# Failed runs in the last week with error details
Get-UTCMMonitoringResult -RunStatus failed -Since (Get-Date).AddDays(-7) -IncludeDetails

# Results for a specific monitor
Get-UTCMMonitoringResult -MonitorId <GUID> -Top 10
```

---

## Configuration

Environment variables (optional):

```powershell
$env:UTCM_RETRY_TRIES = '5'
$env:UTCM_RETRY_DELAY_MS = '120'
Import-Module UTCM.Tools -Force
```

---

## Error Handling

- **4xx errors** fail immediately (no retry) with full response body extraction
- **429 / 503** retried with exponential backoff respecting `Retry-After` header
- **Snapshot job failures** dump full job JSON as a warning for diagnosis
- **`partiallySuccessful`** snapshots return successfully -- use `-IncludeDetails` to inspect per-resource `errorDetails`
- Bind-time GUID validation on all snapshot ID parameters
- Safe `@odata.nextLink` pagination (handles missing property without errors)

---

## Troubleshooting

### Snapshot returns `partiallySuccessful`

```powershell
$job = Get-UTCMSnapshot -SnapshotId <GUID> -IncludeDetails
$job.errorDetails | ForEach-Object { "---"; $_ }
```

Common per-resource failures:
- **"Access Denied"** -- missing Graph app role or Entra directory role for that workload
- **"cmdlet not recognized"** -- missing EXO RBAC roles (run `Grant-UTCMWorkloadAccess -Workloads SecurityAndCompliance`)
- **"DeviceManagementManagedDevices.Read.All"** -- run `Grant-UTCMWorkloadAccess -Workloads Intune`

### EXO connection fails with WAM broker error

The module falls back to device-code flow automatically. If both fail, pre-connect:

```powershell
Connect-ExchangeOnline
Grant-UTCMWorkloadAccess -Workloads Exchange
```

### DisplayName validation error

The UTCM API only allows letters, numbers, and spaces in `DisplayName`.
The module auto-sanitizes, but if using older code, avoid hyphens/special characters.

---

## Testing with Pester

```powershell
Install-Module Pester -Scope CurrentUser
Import-Module .\UTCM.Tools\UTCM.Tools.psd1 -Force
Invoke-Pester -Path .\UTCM.Tools\Tests -CI
```

---

## Contributing

1. Fork
2. Create a `feat/*` or `fix/*` branch
3. Add tests
4. PR

---

## License

This project is licensed under the **BSD 3-Clause License**.
