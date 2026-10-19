function ConvertTo-UTCMMonitorResource {
    <#
    .SYNOPSIS
        Converts UTCM snapshot items into BaselineResources hashtables for New-UTCMMonitor.

    .DESCRIPTION
        Takes the normalized configurationItems produced by Get-UTCMSnapshot -IncludeItems
        (each having id / displayName / type / data) and emits hashtables in the shape
        expected by New-UTCMMonitor -BaselineResources:
            @{ displayName = '...'; resourceType = '...'; properties = @{ ... } }

        Accepts pipeline input of either:
          - The snapshot object itself (with a .configurationItems collection), or
          - Individual configurationItems.

        Optional filtering lets you narrow a full-tenant snapshot down to just the
        resources/properties you want monitored.

    .PARAMETER InputObject
        Pipeline input. Either a snapshot object returned by Get-UTCMSnapshot -IncludeItems,
        or one or more normalized configurationItems.

    .PARAMETER SnapshotId
        Alternative to piping: a snapshot GUID to fetch and convert in-line.
        Internally calls Get-UTCMSnapshot -IncludeItems.

    .PARAMETER ResourceType
        Optional resource-type allow-list (e.g. 'microsoft.exchange.sharedmailbox').
        Items whose resourceType is not in this list are skipped. Case-insensitive.

    .PARAMETER Identity
        Optional id allow-list. Items whose id is not in this list are skipped.
        Case-insensitive exact match against the normalized item id.

    .PARAMETER IncludeProperty
        Optional property allow-list. When supplied, only these property names are kept
        in the resulting `properties` hashtable. Case-insensitive.

    .PARAMETER ExcludeProperty
        Optional property deny-list. Property names removed from the resulting
        `properties` hashtable. Applied after IncludeProperty. Case-insensitive.

    .PARAMETER DisplayNameTemplate
        Optional template for the per-resource displayName. Tokens:
          {displayName}, {id}, {type}
        Default: uses the item's displayName, falling back to id, then type.

    .OUTPUTS
        Hashtable. One hashtable per emitted resource, ready to pass to
        New-UTCMMonitor -BaselineResources.

    .EXAMPLE
        # Round-trip: snapshot -> monitor baseline
        $resources = Get-UTCMSnapshot -SnapshotId $id -IncludeItems |
                     ConvertTo-UTCMMonitorResource -ResourceType microsoft.exchange.sharedmailbox
        New-UTCMMonitor -DisplayName 'Shared Mailbox Monitor' -BaselineResources $resources

    .EXAMPLE
        # Pull from a snapshot ID and trim properties
        ConvertTo-UTCMMonitorResource -SnapshotId $id `
            -ResourceType microsoft.exchange.accepteddomain `
            -IncludeProperty Identity,DomainType,Ensure |
            ForEach-Object { $_ }
    #>
    [CmdletBinding(DefaultParameterSetName = 'Pipeline')]
    [OutputType([hashtable])]
    param(
        [Parameter(ParameterSetName = 'Pipeline', ValueFromPipeline = $true, Mandatory = $true)]
        [object] $InputObject,

        [Parameter(ParameterSetName = 'BySnapshotId', Mandatory = $true)]
        [ValidateScript({
            if (-not (Validate-Guid $_)) { throw "SnapshotId '$_' is not a valid GUID." }
            $true
        })]
        [string] $SnapshotId,

        [string[]] $ResourceType,

        [string[]] $Identity,

        [string[]] $IncludeProperty,

        [string[]] $ExcludeProperty,

        [string] $DisplayNameTemplate
    )

    begin {
        # Build comparison sets once (case-insensitive)
        $typeSet = $null
        if ($ResourceType) {
            $typeSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($t in $ResourceType) { [void]$typeSet.Add($t) }
        }
        $idSet = $null
        if ($Identity) {
            $idSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($i in $Identity) { [void]$idSet.Add($i) }
        }
        $includeSet = $null
        if ($IncludeProperty) {
            $includeSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($p in $IncludeProperty) { [void]$includeSet.Add($p) }
        }
        $excludeSet = $null
        if ($ExcludeProperty) {
            $excludeSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($p in $ExcludeProperty) { [void]$excludeSet.Add($p) }
        }

        # Local helper: convert PSCustomObject / IDictionary / Hashtable -> hashtable,
        # optionally filtering property names by include/exclude sets.
        $toHashtable = {
            param($obj)

            if ($null -eq $obj) { return @{} }

            $result = @{}

            if ($obj -is [System.Collections.IDictionary]) {
                foreach ($key in $obj.Keys) {
                    $name = [string]$key
                    if ($includeSet -and -not $includeSet.Contains($name)) { continue }
                    if ($excludeSet -and  $excludeSet.Contains($name))     { continue }
                    $result[$name] = $obj[$key]
                }
                return $result
            }

            # PSCustomObject / arbitrary object
            $props = $null
            try { $props = $obj.PSObject.Properties } catch { $props = $null }
            if ($null -eq $props) { return $result }

            foreach ($p in $props) {
                $name = $p.Name
                if ($includeSet -and -not $includeSet.Contains($name)) { continue }
                if ($excludeSet -and  $excludeSet.Contains($name))     { continue }
                $result[$name] = $p.Value
            }
            return $result
        }

        # Local helper: yield baseline-resource hashtable for one item (or $null to skip).
        $convertItem = {
            param($item)

            if ($null -eq $item) { return $null }

            # Read fields defensively (snapshot items may be PSCustomObject or hashtable)
            $itemType = $null
            $itemId   = $null
            $itemName = $null
            $itemData = $null

            if ($item -is [System.Collections.IDictionary]) {
                if ($item.Contains('type'))         { $itemType = [string]$item['type'] }
                elseif ($item.Contains('resourceType')) { $itemType = [string]$item['resourceType'] }
                if ($item.Contains('id'))           { $itemId   = [string]$item['id'] }
                if ($item.Contains('displayName'))  { $itemName = [string]$item['displayName'] }
                if ($item.Contains('data'))         { $itemData = $item['data'] }
                elseif ($item.Contains('properties')) { $itemData = $item['properties'] }
            } else {
                $names = @()
                try { $names = $item.PSObject.Properties.Name } catch { $names = @() }
                if ($names -contains 'type'         -and $item.type)         { $itemType = [string]$item.type }
                elseif ($names -contains 'resourceType' -and $item.resourceType) { $itemType = [string]$item.resourceType }
                if ($names -contains 'id'           -and $item.id)           { $itemId   = [string]$item.id }
                if ($names -contains 'displayName'  -and $item.displayName)  { $itemName = [string]$item.displayName }
                if ($names -contains 'data')         { $itemData = $item.data }
                elseif ($names -contains 'properties') { $itemData = $item.properties }
            }

            if (-not $itemType) { return $null }
            if ($typeSet -and -not $typeSet.Contains($itemType)) { return $null }
            if ($idSet   -and (-not $itemId -or -not $idSet.Contains($itemId))) { return $null }

            $propsHash = & $toHashtable $itemData
            if ($propsHash.Count -eq 0) { return $null }

            # Resolve displayName
            $resourceDisplayName = $null
            if ($DisplayNameTemplate) {
                $resourceDisplayName = $DisplayNameTemplate `
                    -replace '\{displayName\}', ([string]$itemName) `
                    -replace '\{id\}',          ([string]$itemId) `
                    -replace '\{type\}',        ([string]$itemType)
            } else {
                if     ($itemName) { $resourceDisplayName = $itemName }
                elseif ($itemId)   { $resourceDisplayName = $itemId }
                else               { $resourceDisplayName = $itemType }
            }

            return @{
                displayName  = $resourceDisplayName
                resourceType = $itemType
                properties   = $propsHash
            }
        }

        # If invoked with -SnapshotId, fetch items now and process them in begin {}
        if ($PSCmdlet.ParameterSetName -eq 'BySnapshotId') {
            if (-not (Get-Command -Name Get-UTCMSnapshot -ErrorAction SilentlyContinue)) {
                throw "Get-UTCMSnapshot is not available; cannot resolve -SnapshotId."
            }
            $snap = Get-UTCMSnapshot -SnapshotId $SnapshotId -IncludeItems
            $items = $null
            if ($snap -and ($snap.PSObject.Properties.Name -contains 'configurationItems')) {
                $items = $snap.configurationItems
            }
            if (-not $items) {
                Write-Verbose "Snapshot '$SnapshotId' returned no configurationItems."
                return
            }
            foreach ($it in $items) {
                $emit = & $convertItem $it
                if ($null -ne $emit) { $emit }
            }
        }
    }

    process {
        if ($PSCmdlet.ParameterSetName -ne 'Pipeline') { return }
        if ($null -eq $InputObject) { return }

        # If we were handed a snapshot object, unwrap its configurationItems.
        $hasConfigItems = $false
        try {
            $hasConfigItems = ($InputObject.PSObject.Properties.Name -contains 'configurationItems')
        } catch { $hasConfigItems = $false }

        if ($hasConfigItems -and $InputObject.configurationItems) {
            foreach ($it in $InputObject.configurationItems) {
                $emit = & $convertItem $it
                if ($null -ne $emit) { $emit }
            }
            return
        }

        # Otherwise treat as a single item
        $emit = & $convertItem $InputObject
        if ($null -ne $emit) { $emit }
    }
}
