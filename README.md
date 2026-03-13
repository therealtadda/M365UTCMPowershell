# UTCM.Tools

**UTCM.Tools** is a PowerShell 7+ module for working with Microsoft Graph's
**Unified Tenant Configuration Management (UTCM)** public preview APIs.

It enables:

- Creating and retrieving **snapshots** of Microsoft 365 tenant configuration
- Comparing snapshots to **current** configuration or to other snapshots
- Detailed, sortable **HTML drift reports** and **CSV** exports
- Exporting snapshots to **JSON**
- Automation-friendly behavior with **bind-time validation**, **retry logic**, and **Pester tests**

> :warning: **UTCM APIs are in public preview.** Configuration apply/restore is **not yet available**.
> This module focuses solely on **read**, **compare**, and **report** workflows.

---

## Permissions

### Graph Connection (interactive user)

```powershell
Connect-MgGraph -Scopes "ConfigurationMonitoring.ReadWrite.All"
```

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

Expected: 12 exported functions.

---

## Module Structure

```
UTCM.Tools/
+-- UTCM.Tools.psd1            # Module manifest
+-- UTCM.Tools.psm1            # Root module (strict mode + loader)
|
+-- Public/                    # Exported functions (12)
|   +-- Enable-UTCM.ps1
|   +-- Grant-UTCMWorkloadAccess.ps1
|   +-- Initialize-UTCM.ps1
|   +-- Test-UTCMSetup.ps1
|   +-- Get-UTCMAvailableSnapshot.ps1
|   +-- New-UTCMSnapshot.ps1
|   +-- Get-UTCMSnapshot.ps1
|   +-- Get-UTCMPreset.ps1
|   +-- Compare-UTCMConfiguration.ps1
|   +-- Export-UTCMSnapshot.ps1
|   +-- New-UTCMDriftReport.ps1
|   +-- Get-UTCMTenantDriftReport.ps1
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
    +-- Get-UTCMSnapshot.Tests.ps1
    +-- Get-UTCMTenantDriftReport.Tests.ps1
    +-- New-UTCMDriftReport.Tests.ps1
    +-- New-UTCMSnapshot.Tests.ps1
```

---

## Quick Start

```powershell
# 1. Bootstrap UTCM (one-time)
Import-Module UTCM.Tools -Force
Connect-MgGraph -Scopes "ConfigurationMonitoring.ReadWrite.All","Application.ReadWrite.All","AppRoleAssignment.ReadWrite.All","Directory.ReadWrite.All"
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

Lists all available UTCM snapshot jobs.

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

Exports snapshot configuration items to JSON.

```powershell
Export-UTCMSnapshot -Snapshot $snap -Path .\Snapshot.json
```

---

### `New-UTCMDriftReport`

Generates HTML dashboard and CSV from a diff result.

```powershell
$diff = Compare-UTCMConfiguration -BaselineSnapshotId <GUID>
New-UTCMDriftReport -Diff $diff -SnapshotId <GUID> -OutputPath .\Reports
```

---

### `Get-UTCMTenantDriftReport`

End-to-end drift pipeline: snapshot -> compare -> report.

```powershell
Get-UTCMTenantDriftReport -CompareToCurrent -Dashboard

# Automated / CI
Get-UTCMTenantDriftReport `
  -SnapshotId <GUID> `
  -CompareToCurrent `
  -ExportJson `
  -Dashboard `
  -OutputPath .\Reports `
  -NoPrompt
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
