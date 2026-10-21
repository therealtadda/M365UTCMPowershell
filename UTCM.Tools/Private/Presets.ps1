# Private\Presets.ps1
# ---------------------------------------------------------------------------
# PRIVATE helpers for JSON-backed resource presets used by New-UTCMSnapshot
#   - Get-UTCMPresetSearchPaths     (where to read JSON presets from)
#   - Get-UTCMResourcePresets       (load + merge presets)
#   - Resolve-UTCMResources         (resolve explicit list OR a preset)
# Optional (warn-only validator for resource type allow-list coverage):
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
    Join-Path $moduleRoot 'Presets\resource-presets.json'
    if ($IsWindows -and $env:ProgramData) {
        Join-Path $env:ProgramData 'UTCM.Tools\resource-presets.json'
    }
    if ($env:AppData) {
        Join-Path $env:AppData 'UTCM.Tools\resource-presets.json'
    }
}

function Test-UTCMMachinePresetTrust {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not $IsWindows) {
        throw 'Machine-wide UTCM presets require Windows ownership and ACL validation.'
    }

    $trusted = @(
        'S-1-5-18'       # SYSTEM
        'S-1-5-32-544'   # Administrators
        'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464' # TrustedInstaller
    )
    $file = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($file.PSIsContainer) { throw "Machine preset '$Path' must be a file." }
    $contentPaths = @($file.FullName, (Split-Path -Path $file.FullName -Parent))
    $current = $file.FullName
    while ($current) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Machine preset '$Path' is not trusted: reparse point '$current' is not allowed."
        }

        $acl = Get-Acl -LiteralPath $current -ErrorAction Stop
        $owner = $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value
        if ($owner -notin $trusted) {
            throw "Machine preset '$Path' is not trusted: '$current' must be owned by Administrators, SYSTEM, or TrustedInstaller."
        }

        $unsafe = [int64][System.Security.AccessControl.FileSystemRights]'Delete, DeleteSubdirectoriesAndFiles, ChangePermissions, TakeOwnership'
        if ($current -in $contentPaths) {
            $unsafe = $unsafe -bor [int64][System.Security.AccessControl.FileSystemRights]::Write
        }
        # Generic rights may be present in an ACL without being mapped to file-system rights.
        $unsafe = $unsafe -bor 0x10000000 -bor 0x40000000
        foreach ($rule in $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
            if ($rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow -or
                ($rule.PropagationFlags -band [System.Security.AccessControl.PropagationFlags]::InheritOnly)) {
                continue
            }
            if ($rule.IdentityReference.Value -notin $trusted -and
                ([int64]$rule.FileSystemRights -band $unsafe)) {
                throw "Machine preset '$Path' is not trusted: '$current' grants write, replacement, or permission-changing access to an untrusted principal."
            }
        }
        $current = Split-Path -Path $current -Parent
    }
    return $true
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
    $modulePreset = [IO.Path]::GetFullPath((Join-Path (Split-Path $PSScriptRoot -Parent) 'Presets\resource-presets.json'))
    $machinePreset = if ($IsWindows -and $env:ProgramData) {
        [IO.Path]::GetFullPath((Join-Path $env:ProgramData 'UTCM.Tools\resource-presets.json'))
    }

    foreach ($path in $SearchPaths) {
        if (Test-Path -LiteralPath $path) {
            $fullPath = [IO.Path]::GetFullPath($path)
            if ($machinePreset -and $fullPath -eq $machinePreset) {
                Test-UTCMMachinePresetTrust -Path $fullPath | Out-Null
            }
            try {
                $json = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -Depth 16 -ErrorAction Stop
                if ($null -ne $json -and $null -ne $json.presets) {
                    $p = $json.presets

                    # If it's already a dictionary, use .Keys; otherwise iterate PSCustomObject properties.
                    if ($p -is [System.Collections.IDictionary]) {
                        foreach ($key in $p.Keys) {
                            if ($fullPath -ne $modulePreset -and $presets.Contains($key)) {
                                Write-Warning "UTCM preset '$key' is overridden by '$path'. Review the effective resource list before creating a snapshot."
                            }
                            $presets[$key] = @(
                                $p[$key] | ForEach-Object { [string]$_ } | Select-Object -Unique
                            )
                        }
                    } else {
                        foreach ($prop in $p.PSObject.Properties) {
                            if ($fullPath -ne $modulePreset -and $presets.Contains($prop.Name)) {
                                Write-Warning "UTCM preset '$($prop.Name)' is overridden by '$path'. Review the effective resource list before creating a snapshot."
                            }
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
                    Write-Warning ("The following UTCM resource type(s) may not be supported by the current allow-list: {0}" -f ($invalid -join ', '))
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