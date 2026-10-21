# Unsupported snapshot resource types and AllSupported coverage

Last reviewed: **2026-10-21 (UTC)**.

This document describes the module's opt-in `AllSupported` snapshot preset and the
resource identifiers excluded from it. The observations apply to the Microsoft Graph
**v1.0 Global-cloud snapshot action**:

```http
POST https://graph.microsoft.com/v1.0/admin/configurationManagement/configurationSnapshots/createSnapshot
```

They are not a Microsoft-published universal deny-list, a statement about every tenant
or cloud, or a list of unsupported monitor/baseline resource types.

## What AllSupported includes

The [shipped presets](UTCM.Tools/Presets/resource-presets.json) include `AllSupported`,
containing **244 unique resource types**. The
[warn-only allow-list](UTCM.Tools/Presets/supported-resource-types.json) contains the
same identifiers. Existing presets and the `TenantCore` default are unchanged.

| Workload namespace | Source catalogue | Excluded | AllSupported |
|---|---:|---:|---:|
| Microsoft Entra | 39 | 3 | 36 |
| Exchange Online | 76 | 10 | 66 |
| Intune | 70 | 3 | 67 |
| Security and Compliance (Defender/Purview) | 28 | 4 | 24 |
| Teams | 58 | 7 | 51 |
| **Total** | **271** | **27** | **244** |

The source was the [TCM schema store](https://json.schemastore.org/utcm-monitor.json)
linked from the Microsoft Learn workload references below. Its monitor schema contained
271 canonical identifiers when reviewed. A v1.0 snapshot request explicitly rejected
the 27 identifiers listed below as unsupported. After excluding exactly those
identifiers, the service accepted a request containing the remaining 244.

**Acceptance is not extraction success.** The accepted request completed with
`partiallySuccessful`, so the observation does not prove that every included type was
successfully extracted. A requested type absent from an export can also have no
instances; absence alone is not evidence that a type is unsupported. No specific
partial-extraction cause is inferred here.

`AllSupported` is a **reviewed static catalogue**, not a wildcard or a live discovery
operation. Microsoft can change its catalogue, endpoint capabilities, and availability.
Selecting the preset neither enables workloads nor assigns any permissions.

## Resource types explicitly rejected by the snapshot service

All 27 identifiers below were named in service-side unsupported-resource validation.
The workload links provide Microsoft's schema and permission context; they do **not**
independently confirm these snapshot-specific exclusions.

### Microsoft Entra (3)

Microsoft Learn: [Supported Microsoft Entra resources for TCM](https://learn.microsoft.com/en-us/graph/utcm-entra-resources).

- `microsoft.entra.attributeset`
- `microsoft.entra.groupsnamingpolicy`
- `microsoft.entra.groupssettings`

### Exchange Online (10)

Microsoft Learn: [Supported Microsoft Exchange resources for TCM](https://learn.microsoft.com/en-us/graph/utcm-exchange-resources).

- `microsoft.exchange.addressbookpolicy`
- `microsoft.exchange.addresslist`
- `microsoft.exchange.applicationaccesspolicy`
- `microsoft.exchange.clientaccessrule`
- `microsoft.exchange.eopprotectionpolicyrule`
- `microsoft.exchange.externalinoutlook`
- `microsoft.exchange.globaladdresslist`
- `microsoft.exchange.managementroleentry`
- `microsoft.exchange.offlineaddressbook`
- `microsoft.exchange.sweeprule`

### Intune (3)

Microsoft Learn: [Supported Microsoft Intune resources for TCM](https://learn.microsoft.com/en-us/graph/utcm-intune-resources).

- `microsoft.intune.accountprotectionlocaladministratorpasswordsolutionpolicy`
- `microsoft.intune.asrrulespolicywindows10`
- `microsoft.intune.devicecleanuprule`

### Security and Compliance (4)

Microsoft Learn: [Supported Microsoft Security and Compliance resources for TCM](https://learn.microsoft.com/en-us/graph/utcm-securityandcompliance-resources).

- `microsoft.securityandcompliance.auditconfigurationpolicy`
- `microsoft.securityandcompliance.autosensitivitylabelrule`
- `microsoft.securityandcompliance.dlpcompliancerule`
- `microsoft.securityandcompliance.sensitivitylabel`

### Teams (7)

Microsoft Learn: [Supported Microsoft Teams resources for TCM](https://learn.microsoft.com/en-us/graph/utcm-teams-resources).

- `microsoft.teams.channel`
- `microsoft.teams.channeltab`
- `microsoft.teams.onlinevoicemailusersettings`
- `microsoft.teams.orgwideappsettings`
- `microsoft.teams.team`
- `microsoft.teams.usercallingsettings`
- `microsoft.teams.userpolicyassignment`

## Usage and operational limits

Inspecting a preset is local and does not authenticate or contact Graph:

```powershell
Get-UTCMPreset -Name AllSupported
$resources = @(Get-UTCMPreset -Name AllSupported -Raw)
$resources.Count # 244 for the shipped catalogue, before any configured overrides
```

Creating a snapshot is a separate, explicitly authorized operation:

```powershell
New-UTCMSnapshot -Preset AllSupported -DisplayName "All Supported Baseline"
```

- The [createSnapshot API reference](https://learn.microsoft.com/en-us/graph/api/configurationbaseline-createsnapshot?view=graph-rest-1.0)
  requires `ConfigurationMonitoring.ReadWrite.All`. Successful job creation starts
  asynchronous extraction; it does not establish that extraction has succeeded.
- The [Tenant Governance configuration management overview](https://learn.microsoft.com/en-us/entra/id-governance/tenant-governance/configuration-management)
  states that the TCM service principal needs read access to the requested resources
  for both snapshots and monitors. Review each workload's resource permissions and the
  [TCM authentication setup guidance](https://learn.microsoft.com/en-us/graph/utcm-authentication-setup).
  The module's setup defaults are not a guarantee of access to every catalogue type.
- Broad snapshots can consume substantial extraction quota. Counts in the table are
  **resource types**, not the number of resource instances that will be extracted.
  Snapshot artifacts expire after seven days; download them before expiry, as described
  in the Tenant Governance overview.
- For `partiallySuccessful` jobs, inspect the existing job rather than automatically
  creating a replacement:

  ```powershell
  Get-UTCMSnapshot -SnapshotId <GUID> -IncludeDetails
  ```

  The [snapshot job reference](https://learn.microsoft.com/en-us/graph/api/resources/configurationsnapshotjob?view=graph-rest-1.0)
  documents the partial status and that `errorDetails` requires explicit selection.
- Machine/user preset overrides retain their existing precedence and warning behavior.
  Inspect the effective `AllSupported` list before creating a snapshot; an override
  can replace the shipped list. See [preset configuration](README.md#get-utcmpreset).

The [TCM API overview](https://learn.microsoft.com/en-us/graph/unified-tenant-configuration-management-concept-overview)
establishes the supported workload scope and snapshot/monitor capabilities. Together
with the references above, it supports the catalogue's purpose and operational
requirements, but it does not publish or verify the exact 27 observed exclusions.

## Maintaining the catalogue

1. Review the Microsoft Learn workload references and their linked schema for changes.
   A type's presence in the monitor schema alone is not proof of snapshot support.
2. Reassess exclusions using current documentation and an explicitly authorized
   snapshot validation. Do not remove a type solely because an export has no instances
   or because a job is partially successful.
3. Update `AllSupported` and the warn-only allow-list together. Keep their membership
   identical, preserve the existing presets unless separately reviewed, and update
   this document's review date, counts, and evidence limits.
4. Run the offline preset and snapshot tests. Verify exact membership, duplicate-free
   counts, every exclusion, override behavior, and the unchanged default.
5. Keep tenant identifiers, account details, request identifiers, and configuration
   exports out of source control. This document records only public resource type
   identifiers and non-identifying service observations.
