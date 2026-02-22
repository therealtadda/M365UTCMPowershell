# UTCM.Tools

**UTCM.Tools** is a PowerShell 7+ module for working with Microsoft Graph’s  
**Unified Tenant Configuration Management (UTCM)** public preview APIs.

It enables:

- Creating and retrieving **snapshots** of Microsoft 365 tenant configuration  
- Comparing snapshots to **current** configuration or to other snapshots  
- Detailed, sortable **HTML drift reports** and **CSV** exports  
- Exporting snapshots to **JSON**  
- Automation-friendly behavior with **bind-time validation**, **retry logic**, and **Pester tests**  

> ⚠️ **UTCM APIs are in public preview.** Configuration apply/restore is **not yet available**.  
> This module focuses solely on **read**, **compare**, and **report** workflows.

---

## Required Graph Permissions

To use the module correctly, you must authenticate with Microsoft Graph permissions that allow reading and managing UTCM snapshots.

### Minimum Required Permissions

| Purpose                                         | Permission                                | Why It's Required                                                                 |
|-------------------------------------------------|--------------------------------------------|------------------------------------------------------------------------------------|
| Snapshot creation, retrieval, drift comparison  | `ConfigurationMonitoring.ReadWrite.All`  | Required to create snapshot jobs, list snapshots, retrieve configuration items, and perform drift comparisons. |

### Connect Example

```powershell
Connect-MgGraph -Scopes "ConfigurationMonitoring.ReadWrite.All"
```

---

## Features

### Snapshot Lifecycle
- Create new UTCM snapshots
- List available snapshots
- Retrieve detailed snapshot content
- Export snapshot configuration items to JSON

### Drift Detection
- Compare baseline → current state
- Compare baseline → another snapshot
- Normalize objects for stable and meaningful drift analysis

### Reporting
- Generate self-contained **HTML drift dashboards**
- Export **CSV** for Excel and Power BI
- Color-coded and sortable report output

### Engineering Quality
- Strict mode enabled
- Folder‑organized public/private functions
- Retry wrapper for Graph calls (429/503 aware)
- Bind-time validation (GUIDs, numeric ranges)
- Pester 5 test suite with module-scoped mocks
- Non-interactive mode for CI/CD (`-NoPrompt`)

---

## Requirements

- PowerShell **7+**
- Microsoft Graph PowerShell SDK:
  ```powershell
  Install-Module Microsoft.Graph -Scope CurrentUser
  ```
- Required Graph scope:
  - `ConfigurationMonitoring.ReadWrite.All`

---

## Installation

### Per‑User Installation (Recommended)

```powershell
$mod = Join-Path $HOME "Documents/PowerShell/Modules/UTCM.Tools"
New-Item -ItemType Directory -Path $mod -Force | Out-Null

# Copy the module contents into $mod (Public/, Private/, UTCM.Tools.psd1, UTCM.Tools.psm1, Tests/)
Import-Module (Join-Path $mod 'UTCM.Tools.psd1') -Force
```

### Machine‑Wide Installation (Admin)

Place the module folder in:

```
C:\Program Files\PowerShell\Modules\UTCM.Tools\
```

### Verify Installation

```powershell
Import-Module UTCM.Tools -Force
Get-Command -Module UTCM.Tools
```

---

## Module Structure

```
UTCM.Tools
│
├── UTCM.Tools.psd1            # Module manifest
├── UTCM.Tools.psm1            # Root module (strict mode + loader + retry guard)
│
├── Public                     # Exported cmdlets
│   ├── Enable-UTCM.ps1
│   ├── Grant-UTCMWorkloadAccess.ps1
│   ├── Initialize-UTCM.ps1
│   ├── Test-UTCMSetup.ps1
│   ├── Get-UTCMAvailableSnapshot.ps1
│   ├── New-UTCMSnapshot.ps1
│   ├── Get-UTCMSnapshot.ps1
│   ├── Compare-UTCMConfiguration.ps1
│   ├── Export-UTCMSnapshot.ps1
│   ├── New-UTCMDriftReport.ps1
│   └── Get-UTCMTenantDriftReport.ps1
│
├── Private                    # Internal helpers (not exported)
│   ├── Ensure-GraphConnection.ps1
│   ├── Invoke-GraphRequestWithRetry.ps1
│   ├── Get-UTCMCurrentStateSnapshot.ps1
│   ├── ConvertTo-NormalizedJson.ps1
│   ├── Resolve-OutputPath.ps1
│   ├── Validate-Guid.ps1
│   ├── HtmlEncode.ps1
│   └── Write-Log.ps1
│
└── Tests                      # Pester 5 test suite
    ├── Get-UTCMAvailableSnapshot.Tests.ps1
    ├── New-UTCMSnapshot.Tests.ps1
    ├── Get-UTCMSnapshot.Tests.ps1
    ├── Compare-UTCMConfiguration.Tests.ps1
    ├── Export-UTCMSnapshot.Tests.ps1
    ├── New-UTCMDriftReport.Tests.ps1
    └── Get-UTCMTenantDriftReport.Tests.ps1
```

---

## Quick Start

```powershell
# Connect to Graph
Connect-MgGraph -Scopes "ConfigurationMonitoring.ReadWrite.All"

# Create a new snapshot
$baseline = New-UTCMSnapshot

# Compare to current tenant state and build HTML + CSV reports
Get-UTCMTenantDriftReport `
  -SnapshotId $baseline `
  -CompareToCurrent `
  -Dashboard `
  -ExportJson `
  -OutputPath .\Reports `
  -NoPrompt
```

---

## Example Outputs

### Snapshot list

```
id                                   displayName               createdDateTime             status
--                                   -----------               --------------------------- --------
aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee Baseline 2026-02-12       2026-02-12T14:47:10Z        completed
11111111-2222-3333-4444-555555555555 Pre-Change Audit          2026-02-05T09:22:15Z        completed
```

---

### Snapshot object (abbreviated)

```
id           : aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
status       : completed
configurationItems :
  [
    {
      "id": "/identity/conditionalAccess/policies/abc123",
      "displayName": "Require MFA for Admins",
      "type": "conditionalAccessPolicy",
      "data": { "state": "enabled", "conditions": {...} }
    },
    {
      "id": "/exchange/transportRules/xyz456",
      "displayName": "Block Executables",
      "type": "exchangeTransportRule",
      "data": {...}
    }
  ]
```

---

### Drift Comparison Output

```
id     displayName              type                    normalizedData            SideIndicator
--     -----------              ----                    --------------            -------------
1      Require MFA for Admins   conditionalAccessPolicy  {...disabled...}          =>
2      Block Executables        exchangeTransportRule    {...ruleDisabled...}      <=
3      Teams Meeting Policy     teamsPolicy              {...lobby:false...}       =>
```

**Legend**  
- `=>` Added/changed in **current** state  
- `<=` Removed/changed from the **baseline**  

---

### JSON Export Example

```json
[
  {
    "id": "/identity/conditionalAccess/policies/abc123",
    "displayName": "Require MFA for Admins",
    "type": "conditionalAccessPolicy",
    "data": { "state": "enabled" }
  }
]
```

---

### HTML Drift Dashboard (illustration)

```
+--------------------------------------------------------------+
|                     UTCM Drift Report                        |
| Baseline: aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee               |
+------------------+-----------------------+--------------------+
| ID               | Display Name          | Drift Type         |
+------------------+-----------------------+--------------------+
| /identity/...123 | Require MFA Admins    | Added in Current   |
| /exchange/...456 | Block Executables     | Missing in Current |
| /teams/...789    | Teams Meeting Policy  | Changed            |
+--------------------------------------------------------------+
```

---

## Command Reference

### `Enable-UTCM`
Ensure the Microsoft‑owned **UTCM service principal** exists in your tenant (idempotent). Uses AppId `03b07b79-c5bc-4b5e-9bfa-13acf4a99998`. [1](https://learn.microsoft.com/en-us/graph/utcm-authentication-setup)

**Usage**
```powershell
Enable-UTCM
```

### `Grant-UTCMWorkloadAccess`
Grants the **UTCM service principal** read‑level access across selected workloads. Supported values: `Entra`, `Exchange`, `Intune`, `SecurityAndCompliance`, `Teams`.
#### What it assigns ####

**Entra** → `Policy.Read.All`, `Directory.Read.All` (Graph app roles). [learn.microsoft.com]
**Exchange** → `Exchange.ManageAsApp` (EXO app permission). ([\[learn.microsoft.com\]](https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2?view=exchange-ps)), [learn.microsoft.com]
**Intune** → `DeviceManagementConfiguration.Read.All` (Graph app role). [learn.microsoft.com]
**Security & Compliance** → `Exchange.ManageAsApp` + adds Security Reader directory role to the SP. [learn.microsoft.com]
**Teams** → `TeamSettings.Read.All` (Graph app role, where app‑only supported). [learn.microsoft.com], [graphpermi...merill.net]

**Usage**
  **All workloads**
  ```powershell
  Grant-UTCMWorkloadAccess -Workloads Entra,Exchange,Intune,SecurityAndCompliance,Teams
  ```
  **Subset**
  ```powershell
  Grant-UTCMWorkloadAccess -Workloads Entra,Exchange
  ```

### `Initialize-UTCM`
One‑shot wrapper that runs `Enable‑UTCM` and `Grant‑UTCMWorkloadAccess`.

**Usage**
```powershell
Initialize-UTCM -Workloads Entra,Exchange,Intune,SecurityAndCompliance,Teams
```

### `Test-UTCMSetup`
Report and validate the **UTCM service principal** configuration: shows app‑role assignments (resource → role value) and directory roles (e.g., **Security Reader** for S&C). Helpful for CI and post‑bootstrap verification. (Reads Microsoft Graph directory and SP metadata.)

**Usage**
```powershell
# After Initialize-UTCM or Enable-UTCM/Grant-UTCMWorkloadAccess
$check = Test-UTCMSetup
$check | Format-List

# Example output:
# UtcmsSpDisplayName : Unified Tenant Configuration Management
# ObjectId           : 00000000-1111-2222-3333-444444444444
# AppRoleAssignments : { Microsoft Graph :: Policy.Read.All,
#                        Microsoft Graph :: Directory.Read.All,
#                        Office 365 Exchange Online :: Exchange.ManageAsApp,
#                        Microsoft Graph :: DeviceManagementConfiguration.Read.All,
#                        Microsoft Graph :: TeamSettings.Read.All }
# DirectoryRoles     : Security Reader
```

**CI-friendly guard**
```powershell
$report = Test-UTCMSetup
if (-not $report) { throw "UTCM SP not found." }

if (-not ($report.AppRoleAssignments -match 'Policy.Read.All')) { throw "Missing Entra read role." }
if (-not ($report.AppRoleAssignments -match 'Exchange.ManageAsApp')) { throw "Missing EXO app-only permission." }
if (-not ($report.AppRoleAssignments -match 'DeviceManagementConfiguration.Read.All')) { Write-Warning "Intune read role not found." }
if (-not ($report.DirectoryRoles -match 'Security Reader')) { Write-Warning "Security Reader not found (S&C read may be limited)." }
```

### `Get-UTCMAvailableSnapshot`
List all available UTCM snapshots.

**Usage**
```powershell
Get-UTCMAvailableSnapshot
Get-UTCMAvailableSnapshot -AsJson
```

---

### `New-UTCMSnapshot`
Create a new snapshot.

```powershell
New-UTCMSnapshot
New-UTCMSnapshot -PollingIntervalSeconds 5
```

---

### `Get-UTCMSnapshot`

```powershell
Get-UTCMSnapshot -SnapshotId <GUID>
```

---

### `Compare-UTCMConfiguration`

```powershell
# Compare two snapshots
Compare-UTCMConfiguration -BaselineSnapshotId <GUID> -CompareSnapshotId <GUID>

# Compare baseline to current tenant state
Compare-UTCMConfiguration -BaselineSnapshotId <GUID> -PollingIntervalSeconds 10
```

---

### `Export-UTCMSnapshot`

```powershell
$snap = Get-UTCMSnapshot -SnapshotId <GUID>
Export-UTCMSnapshot -Snapshot $snap -Path .\Snapshot.json
```

---

### `New-UTCMDriftReport`

```powershell
New-UTCMDriftReport -Diff $diff -SnapshotId <GUID> -OutputPath .\Reports
```

Outputs HTML + CSV.

---

### `Get-UTCMTenantDriftReport`

```powershell
Get-UTCMTenantDriftReport -CompareToCurrent -Dashboard

# Automated
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

```powershell
$env:UTCM_RETRY_TRIES = '5'
$env:UTCM_RETRY_DELAY_MS = '120'
Import-Module UTCM.Tools -Force
```

---

## Error Handling

- Handles 429/503  
- Respects Retry-After  
- Safe bind-time validation  
- Snapshot job lifecycle enforcement  

---

## Testing with Pester

```powershell
Install-Module Pester -Scope CurrentUser
Import-Module .\UTCM.Tools.psd1 -Force
Invoke-Pester -Path .\Tests -CI
```

---

## Troubleshooting

### Missing Functions
- Ensure matching function names in `Public\*.ps1`
- Ensure proper extension: `.ps1`
- Ensure correct folder names: `Public`, `Private`

### Authentication
```powershell
Disconnect-MgGraph
Connect-MgGraph -Scopes "ConfigurationMonitoring.ReadWrite.All"
```

### CI/CD
Use `-NoPrompt`.

---

## Contributing

1. Fork  
2. Create a `feat/*` or `fix/*` branch  
3. Add tests  
4. PR  

---

## License

This project is licensed under the **BSD 3‑Clause License**.

Include a full `LICENSE` file in the repository root.
