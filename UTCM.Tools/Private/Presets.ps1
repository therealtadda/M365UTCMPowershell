# Private\Presets.ps1
# ---------------------------------------------------------------------------
# PRIVATE helpers for JSON-backed resource presets used by New-UTCMSnapshot
#   - Get-UTCMPresetSearchPaths     (where to read JSON presets from)
#   - Get-UTCMResourcePresets       (load + merge presets)
#   - Resolve-UTCMResources         (resolve explicit list OR a preset)
# Optional (warn-only validator, useful during preview):
#   - Get-UTCMAllowListPath
#   - Test-UTCMResourceTypes
# ---------------------------------------------------------------------------

# Returns the search order for the JSON preset file(s):
#   Module-shipped -> Machine override -> User override
function Get-UTCMPresetSearchPaths {
    [CmdletBinding()]
    param()

    # This script is in <ModuleRoot>\Private, so module root is the parent folder
    $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
    @(
        (Join-Path $moduleRoot 'Presets\resource-presets.json'),
        (Join-Path $env:ProgramData 'UTCM.Tools\resource-presets.json'),
        (Join-Path $env:AppData     'UTCM.Tools\resource-presets.json')
    )
}

# OPTIONAL: return the allow-list file for warn-only validation
function Get-UTCMAllowListPath {
    [CmdletBinding()]
    param()
    $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
    (Join-Path $moduleRoot 'Presets\supported-resource-types.json')
}

# Built-in tiny fallback if JSON is missing (keeps module functional)
# Feel free to adjust the default preset names/contents.
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

# Load and merge resource presets from JSON (module, machine, user) with built-in defaults.
# OUTPUT: OrderedDictionary Name -> string[] resource identifiers
function Get-UTCMResourcePresets {
    [CmdletBinding()]
    param(
        [string[]] $SearchPaths = (Get-UTCMPresetSearchPaths)
    )

    # Keep insertion order; OrderedDictionary exposes .Contains(key), not .ContainsKey()
    $presets = [ordered]@{} + $script:BuiltInResourcePresets

    foreach ($path in $SearchPaths) {
        if (Test-Path $path) {
            try {
                $json = Get-Content -Path $path -Raw | ConvertFrom-Json -Depth 16
                if ($null -ne $json -and $null -ne $json.presets) {
                    $p = $json.presets

                    # If it's already a dictionary, use .Keys; otherwise iterate PSCustomObject properties.
                    if ($p -is [System.Collections.IDictionary]) {
                        foreach ($key in $p.Keys) {
                            $presets[$key] = @(
                                $p[$key] | ForEach-Object { [string]$_ } | Select-Object -Unique
                            )
                        }
                    } else {
                        foreach ($prop in $p.PSObject.Properties) {
                            $presets[$prop.Name] = @(
                                $prop.Value | ForEach-Object { [string]$_ } | Select-Object -Unique
                            )
                        }
                    }
                }
            } catch {
                Write-Warning "Failed to load UTCM presets from '$path': $($_.Exception.Message)"
            }
        }
    }

    return $presets
}

# Resolve effective resources from an explicit list or a named preset (backed by JSON).
# OUTPUT: string[] resource identifiers (non-empty)
function Resolve-UTCMResources {
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

    # OrderedDictionary has .Contains(key)
    if (-not $presets.Contains($Preset)) {
        $known = ($presets.Keys | Sort-Object) -join ', '
        throw "Unknown preset '$Preset'. Known presets: $known"
    }

    $resolved = @($presets[$Preset] | ForEach-Object { [string]$_ })
    if (-not $resolved -or $resolved.Count -eq 0) {
        throw "Preset '$Preset' resolved to an empty resource list."
    }

    return $resolved
}

# OPTIONAL (warn-only): validate resource identifiers against a local allow-list JSON
function Test-UTCMResourceTypes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]] $Resources,
        [string] $AllowListPath = (Get-UTCMAllowListPath)
    )

    if (Test-Path $AllowListPath) {
        try {
            $allow   = Get-Content -Path $AllowListPath -Raw | ConvertFrom-Json -Depth 8
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