function Get-UTCMPreset {
    <#
    .SYNOPSIS
        Inspect JSON-backed UTCM snapshot presets.

    .DESCRIPTION
        - Lists available preset names (default).
        - Or returns the resources for a specific preset (as PSCustomObject or raw string[]).

    .PARAMETER Name
        Name of a preset (e.g., AllSupported, TenantCore, TeamsCore+Voice). If omitted, all names are listed.

    .PARAMETER Raw
        Return just the string[] of resource identifiers for the preset (no wrapper object).

    .PARAMETER SearchPaths
        Optional override for preset JSON search paths. Uses module defaults otherwise.

    .EXAMPLE
        # List all preset names
        Get-UTCMPreset

    .EXAMPLE
        # Show resources in a given preset
        Get-UTCMPreset -Name TenantCore

    .EXAMPLE
        # Get raw resource array (string[])
        Get-UTCMPreset -Name 'TeamsCore+Voice' -Raw

    .EXAMPLE
        # Inspect the reviewed all-supported snapshot resource list without connecting to Graph
        Get-UTCMPreset -Name AllSupported -Raw
    #>
    [CmdletBinding(DefaultParameterSetName='List')]
    param(
        [Parameter(ParameterSetName='ByName')]
        [string] $Name,

        [Parameter(ParameterSetName='ByName')]
        [switch] $Raw,

        [string[]] $SearchPaths
    )

    # Use the PSM's internal loader (module scope)
    if (-not $SearchPaths) { $SearchPaths = (Get-UTCMPresetSearchPaths) }
    $presets = Get-UTCMResourcePresets -SearchPaths $SearchPaths

    if ($PSCmdlet.ParameterSetName -eq 'List' -and -not $Name) {
        return ($presets.Keys | Sort-Object)
    }

    if (-not $presets.Contains($Name)) {
        $known = ($presets.Keys | Sort-Object) -join ', '
        throw "Preset '$Name' not found. Known presets: $known"
    }

    $resources = $presets[$Name]

    if ($Raw) {
        return $resources
    }

    [pscustomobject]@{
        Name      = $Name
        Resources = $resources
    }
}