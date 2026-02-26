#requires -Version 7.0
<#
===============================================================================
    UTCM.Tools.psm1  (PowerShell 7+)
    Root module for the UTCM.Tools PowerShell module.

    Responsibilities:
      • Enable strict mode for safer execution
      • Define module-wide constants shared by functions
      • JSON-backed resource presets + allow-list validation
      • Reliably dot-source all Private\*.ps1 helpers (required)
      • Reliably dot-source all Public\*.ps1 functions (required)
      • Export ONLY the intended public functions
      • Validate public functions using a safe Retry Guard (no autoload)
      • Register dynamic arg completer for New-UTCMSnapshot -Preset

    Notes:
      • Keep Export-ModuleMember's function list in sync with Public\ files.
      • The loader throws clear errors if folders/files are missing.
      • Retry guard uses Function: drive to avoid command discovery/autoload.
      • For import troubleshooting, set: $VerbosePreference='Continue' then Import-Module -Force

      Preset JSON files:
        <ModuleRoot>\Presets\resource-presets.json
        <ModuleRoot>\Presets\supported-resource-types.json
      Optional overrides:
        %ProgramData%\UTCM.Tools\resource-presets.json
        %AppData%\UTCM.Tools\resource-presets.json
===============================================================================
#>

Set-StrictMode -Version Latest

# ---------------------------
# Module-wide constants (UTCM Graph preview/beta)
# ---------------------------

# Base for all UTCM endpoints (beta)
$script:GraphBase = '/beta/admin/configurationManagement'

# Snapshot jobs collection (used to GET/POLL jobs and list them)
$script:SnapshotJobsUri = "$script:GraphBase/configurationSnapshotJobs"

# Action endpoint to START a snapshot job (required for UTCM snapshot creation)
$script:CreateSnapshotActionUri = "$script:GraphBase/configurationSnapshots/createSnapshot"

# ---------------------------
# JSON Preset & Allow-list support (module-local helpers)
# ---------------------------

function Get-UTCMPresetSearchPaths {
    <#
      Returns the search order for resource preset JSON files.
      Order: Module-shipped -> Machine override -> User override
    #>
    [CmdletBinding()]
    param()

    $moduleRoot = Split-Path -Path $PSCommandPath -Parent
    @(
        (Join-Path $moduleRoot 'Presets\resource-presets.json'),
        (Join-Path $env:ProgramData 'UTCM.Tools\resource-presets.json'),
        (Join-Path $env:AppData     'UTCM.Tools\resource-presets.json')
    )
}

function Get-UTCMAllowListPath {
    <#
      Returns the module-shipped allow-list path used by Test-UTCMResourceTypes.
    #>
    [CmdletBinding()]
    param()
    $moduleRoot = Split-Path -Path $PSCommandPath -Parent
    (Join-Path $moduleRoot 'Presets\supported-resource-types.json')
}

# Built-in tiny fallback if JSON preset files are missing (keeps module functional)
$script:BuiltInResourcePresets = [ordered]@{
    ExchangeCore = @(
        'microsoft.exchange.sharedmailbox',
        'microsoft.exchange.transportrule'
    )
    TenantCore = @(
        'microsoft.entra.securitydefaults',
        'microsoft.entra.namedlocationpolicy',
        'microsoft.entra.authorizationpolicy',
        'microsoft.entra.tenantdetails',
        'microsoft.entra.conditionalaccesspolicy',
        'microsoft.exchange.sharedmailbox',
        'microsoft.exchange.transportrule',
        'microsoft.teams.meetingpolicy',
        'microsoft.teams.messagingpolicy',
        'microsoft.teams.appsetuppolicy',
        'microsoft.intune.devicecategory',
        'microsoft.intune.policysets',
        'microsoft.securityandcompliance.labelpolicy',
        'microsoft.securityandcompliance.dlpcompliancepolicy',
        'microsoft.securityandcompliance.protectionalert'
    )
}

function Get-UTCMResourcePresets {
    <#
    .SYNOPSIS
        Load and merge resource presets from JSON (module, machine, user) with built-in defaults.
    .OUTPUTS
        [ordered] hashtable: Name -> [string[]] UTCM resource identifiers
    #>
    [CmdletBinding()]
    param(
        [string[]] $SearchPaths = (Get-UTCMPresetSearchPaths)
    )

    $presets = [ordered]@{} + $script:BuiltInResourcePresets

    foreach ($path in $SearchPaths) {
        if (Test-Path $path) {
            try {
                $json = Get-Content -Path $path -Raw | ConvertFrom-Json -Depth 16
                if ($null -ne $json -and $json.presets) {
                    foreach ($kv in $json.presets.GetEnumerator()) {
                        # Merge/replace; ensure unique values
                        $presets[$kv.Key] = @($kv.Value | ForEach-Object { [string]$_ } | Select-Object -Unique)
                    }
                }
            } catch {
                Write-Warning "Failed to load UTCM presets from '$path': $($_.Exception.Message)"
            }
        }
    }

    return $presets
}

function Test-UTCMResourceTypes {
    <#
    .SYNOPSIS
        Warn if a requested resource identifier is not in the local allow-list.
    .DESCRIPTION
        Non-blocking validation; helps avoid common typos / not-yet-supported types in preview.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]] $Resources,
        [string] $AllowListPath = (Get-UTCMAllowListPath)
    )

    if (Test-Path $AllowListPath) {
        try {
            $allow = Get-Content -Path $AllowListPath -Raw | ConvertFrom-Json -Depth 8
            $allowed = @([string[]]$allow.resourceTypes)
            if ($allowed.Count -gt 0) {
                $invalid = $Resources | Where-Object { $_ -notin $allowed }
                if ($invalid) {
                    Write-Warning ("The following UTCM resource type(s) may not be supported in this preview: {0}" -f ($invalid -join ', '))
                    return $false
                }
            }
        } catch {
            Write-Warning "Failed to parse allow-list '$AllowListPath': $($_.Exception.Message)"
        }
    } else {
        Write-Verbose "Allow-list not found at '$AllowListPath'; skipping validation."
    }

    return $true
}

function Resolve-UTCMResources {
    <#
    .SYNOPSIS
        Resolve effective resources from an explicit list or a named preset (backed by JSON).
    .OUTPUTS
        [string[]] resource identifiers (non-empty)
    #>
    [CmdletBinding()]
    param(
        [string[]] $Resources,
        [string]   $Preset = 'TenantCore',
        [string[]] $PresetSearchPaths = (Get-UTCMPresetSearchPaths)
    )

    if ($Resources -and $Resources.Count -gt 0) {
        return @($Resources | ForEach-Object { [string]$_ })
    }

    $presets = Get-UTCMResourcePresets -SearchPaths $PresetSearchPaths
    if (-not $presets.ContainsKey($Preset)) {
        $known = ($presets.Keys | Sort-Object) -join ', '
        throw "Unknown preset '$Preset'. Known presets: $known"
    }

    $resolved = @($presets[$Preset] | ForEach-Object { [string]$_ })
    if (-not $resolved -or $resolved.Count -eq 0) {
        throw "Preset '$Preset' resolved to an empty resource list."
    }

    return $resolved
}

# ---------------------------
# Helper: return .ps1 files from a folder (relative to $PSScriptRoot)
#           NOTE: This function ONLY RETURNS FILES. It does NOT dot-source them.
#           We dot-source at MODULE SCRIPT SCOPE (below), to keep definitions.
# ---------------------------
function _Get-ScriptsFromFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FolderName,
        [switch]$Required
    )

    $dir = Join-Path -Path $PSScriptRoot -ChildPath $FolderName
    Write-Verbose "Loading scripts from: $dir (Required=$($Required.IsPresent))"

    if (-not (Test-Path -LiteralPath $dir)) {
        if ($Required) {
            throw "Required folder not found: $dir"
        } else {
            Write-Verbose "Folder not found (optional): $dir — skipping."
            return @()
        }
    }

    $files = Get-ChildItem -LiteralPath $dir -Filter *.ps1 -File -ErrorAction Stop | Sort-Object Name
    if (-not $files -and $Required) {
        throw "No scripts (*.ps1) found in required folder: $dir"
    }

    return $files
}

# ---------------------------
# Collect scripts
# ---------------------------
$privateFiles = _Get-ScriptsFromFolder -FolderName 'Private' -Required
$publicFiles  = _Get-ScriptsFromFolder -FolderName 'Public'  -Required

# ---------------------------
# DOT-SOURCE FILES AT MODULE SCRIPT SCOPE (critical for persistence)
# ---------------------------

# Private helpers (may or may not declare functions)
foreach ($file in $privateFiles) {
    Write-Verbose "Dot-sourcing: $($file.FullName)"
    $before = (Get-ChildItem Function:\).Name
    . $file.FullName
    $after  = (Get-ChildItem Function:\).Name
    $added  = Compare-Object $before $after -PassThru | Where-Object { $_ -like '*UTCM*' }
    if ($added) {
        Write-Verbose "Functions added by $($file.Name): $($added -join ', ')"
    } else {
        Write-Verbose "No UTCM functions detected from $($file.Name)"
    }
}

# Public cmdlets (should declare functions)
foreach ($file in $publicFiles) {
    Write-Verbose "Dot-sourcing: $($file.FullName)"
    $before = (Get-ChildItem Function:\).Name
    . $file.FullName
    $after  = (Get-ChildItem Function:\).Name
    $added  = Compare-Object $before $after -PassThru | Where-Object { $_ -like '*UTCM*' }
    if ($added) {
        Write-Verbose "Functions added by $($file.Name): $($added -join ', ')"
    } else {
        Write-Verbose "No UTCM functions detected from $($file.Name)"
    }
}

# ---------------------------
# Export ONLY intended public functions
# ---------------------------
$publicFunctions = @(
    'Enable-UTCM',
    'Grant-UTCMWorkloadAccess',
    'Initialize-UTCM',
    'Test-UTCMSetup',            # (fixed missing comma)
    'Get-UTCMAvailableSnapshot',
    'New-UTCMSnapshot',
    'Get-UTCMSnapshot',
    'Compare-UTCMConfiguration',
    'Export-UTCMSnapshot',
    'New-UTCMDriftReport',
    'Get-UTCMTenantDriftReport',
    'Get-UTCMPreset'             # new public helper to inspect presets
)

# ---------------------------
# Retry Guard (safe): validate functions after load with brief retries
# Uses Function: drive to avoid command discovery or module autoload during import.
# Tune via env vars; defaults are 3 tries and 80 ms delay
# ---------------------------
$maxTries = [Environment]::GetEnvironmentVariable('UTCM_RETRY_TRIES')    ?? '3'
$delayMs  = [Environment]::GetEnvironmentVariable('UTCM_RETRY_DELAY_MS') ?? '80'

try { $maxTries = [int]$maxTries } catch { $maxTries = 3 }
try { $delayMs  = [int]$delayMs  } catch { $delayMs  = 80 }
if ($maxTries -lt 1) { $maxTries = 1 }
if ($delayMs  -lt 1) { $delayMs  = 1 }

Write-Verbose "Validation retries: maxTries=$maxTries, delayMs=$delayMs"

$export  = @()
$missing = @()

foreach ($fn in $publicFunctions) {
    $ok = $false
    for ($i = 1; $i -le $maxTries; $i++) {
        if (Test-Path "Function:\$fn") {
            $ok = $true
            break
        }
        if ($i -lt $maxTries) {
            Start-Sleep -Milliseconds $delayMs
        }
    }

    if ($ok) {
        $export += $fn
    } else {
        $missing += $fn
    }
}

if ($missing.Count -gt 0) {
    $msg = @()
    $msg += "One or more public functions were not found after loading Public\*.ps1 and $maxTries validation attempts:"
    $msg += "  - " + ($missing -join "`n  - ")
    $msg += "Check for file/function name mismatches, scope issues (functions wrapped in invoked blocks),"
    $msg += "or missing files in the Public folder."
    throw ($msg -join "`n")
}

# Final export
Write-Verbose ("Export list: " + ($export -join ', '))
Export-ModuleMember -Function $export

# ---------------------------
# Dynamic argument completer for: New-UTCMSnapshot -Preset <TAB>
# Uses Get-UTCMPreset so it reflects JSON instantly at import time.
# ---------------------------
if (-not $script:PresetCompleterRegistered) {
    try {
        Register-ArgumentCompleter -CommandName 'New-UTCMSnapshot' -ParameterName 'Preset' -ScriptBlock {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            try {
                $names = Get-UTCMPreset
                $names |
                    Where-Object { $_ -like "$wordToComplete*" } |
                    ForEach-Object {
                        [System.Management.Automation.CompletionResult]::new(
                            $_, $_, 'ParameterValue', "Preset: $_"
                        )
                    }
            } catch {
                @()  # never block tab completion
            }
        } | Out-Null
        $script:PresetCompleterRegistered = $true
        Write-Verbose "Registered argument completer for New-UTCMSnapshot -Preset."
    }
    catch {
        Write-Verbose "Failed to register argument completer: $($_.Exception.Message)"
    }
}