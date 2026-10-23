function Get-UTCMObjectField {
    # Returns the first non-null value among the candidate names, for hashtables and objects alike.
    [CmdletBinding()]
    param([AllowNull()] $Object, [Parameter(Mandatory)][string[]] $Name)

    if ($null -eq $Object) { return $null }
    foreach ($n in $Name) {
        if ($Object -is [System.Collections.IDictionary]) {
            if ($Object.Contains($n) -and $null -ne $Object[$n]) { return $Object[$n] }
        } else {
            $p = $Object.PSObject.Properties[$n]
            if ($p -and $null -ne $p.Value) { return $p.Value }
        }
    }
    return $null
}

function Get-UTCMWorkloadFromType {
    # Derives the workload (e.g. 'exchange') from a resource type such as 'microsoft.exchange.sharedmailbox'.
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string] $Type)

    if (-not [string]::IsNullOrWhiteSpace($Type) -and $Type -match '^microsoft\.([a-z0-9]+)') {
        return $Matches[1]
    }
    return 'unknown'
}

function Format-UTCMJsonPretty {
    # Pretty-prints a JSON string; returns the input unchanged when it is not valid JSON.
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string] $Json)

    if ([string]::IsNullOrWhiteSpace($Json)) { return '' }
    try {
        $obj = $Json | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $obj) { return 'null' }
        return ($obj | ConvertTo-Json -Depth 50)
    } catch {
        return $Json
    }
}

function ConvertTo-UTCMUtcDisplay {
    # Formats a date value as 'yyyy-MM-dd HH:mm:ss UTC'; 'n/a' when empty, the raw text when unparseable.
    [CmdletBinding()]
    param([AllowNull()] $Value)

    if ($null -eq $Value -or ([string]$Value).Trim() -eq '') { return 'n/a' }
    $dto = [datetimeoffset]::MinValue
    if ($Value -is [datetimeoffset]) { $dto = $Value }
    elseif ($Value -is [datetime]) { $dto = [datetimeoffset]$Value }
    elseif (-not [datetimeoffset]::TryParse([string]$Value, [cultureinfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$dto)) {
        return [string]$Value
    }
    return $dto.UtcDateTime.ToString('yyyy-MM-dd HH:mm:ss', [cultureinfo]::InvariantCulture) + ' UTC'
}

function ConvertTo-UTCMReportItem {
    # Normalizes a snapshot/current-state item (either 'data' or 'properties'; either 'type' or
    # 'resourceType') to { Id, DisplayName, Type, Workload, Data }.
    [CmdletBinding()]
    param([AllowNull()] $Item)

    $id = $null; $data = $null; $type = $null; $workload = $null; $display = $null
    if ($Item -is [System.Collections.IDictionary]) {
        $id = $Item['id'] ?? $Item['resourceInstanceIdentifier']
        $data = $Item['data'] ?? $Item['properties']
        $type = $Item['type'] ?? $Item['resourceType']
        $workload = $Item['workload']; $display = $Item['displayName']
    } elseif ($null -ne $Item) {
        $p = $Item.PSObject.Properties
        foreach ($n in 'id','resourceInstanceIdentifier') { $m = $p[$n]; if ($m -and $null -ne $m.Value) { $id = $m.Value; break } }
        foreach ($n in 'data','properties') { $m = $p[$n]; if ($m -and $null -ne $m.Value) { $data = $m.Value; break } }
        foreach ($n in 'type','resourceType') { $m = $p[$n]; if ($m -and $null -ne $m.Value) { $type = $m.Value; break } }
        $m = $p['workload']; if ($m) { $workload = $m.Value }
        $m = $p['displayName']; if ($m) { $display = $m.Value }
    }
    if ($null -eq $id -and $null -ne $data) {
        foreach ($n in 'Id','Identity','Guid','ObjectId') {
            $v = Get-UTCMObjectField $data @($n)
            if ($v) { $id = $v; break }
        }
    }
    $type = [string]$type
    $workload = [string]$workload
    if (-not $workload) { $workload = Get-UTCMWorkloadFromType $type }

    [pscustomobject]@{
        Id          = [string]$id
        DisplayName = [string]$display
        Type        = $type
        Workload    = $workload
        Data        = $data
    }
}

function ConvertTo-UTCMScalarText {
    [CmdletBinding()]
    param([AllowNull()] $Value)

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [datetime]) { return $Value.ToString('yyyy-MM-ddTHH:mm:ss.FFFFFFFK', [cultureinfo]::InvariantCulture) }
    if ($Value -is [datetimeoffset]) { return $Value.ToString('yyyy-MM-ddTHH:mm:ss.FFFFFFFK', [cultureinfo]::InvariantCulture) }
    if ($Value -is [System.IFormattable]) { return $Value.ToString($null, [cultureinfo]::InvariantCulture) }
    return [string]$Value
}

function ConvertTo-UTCMFlatProperty {
    # Flattens an object graph into an ordered path -> text map (a.b[0].c). Depth and size are capped.
    [CmdletBinding()]
    param(
        [AllowNull()] $Value,
        [string] $Prefix = '',
        [Parameter(Mandatory)][System.Collections.Specialized.OrderedDictionary] $Into,
        [int] $Depth = 0,
        [int] $MaxEntries = 20000
    )

    if ($Into.Count -ge $MaxEntries) { return }
    $label = if ($Prefix) { $Prefix } else { '(value)' }

    if ($null -eq $Value -or $Value -is [string] -or $Value.GetType().IsPrimitive -or
        $Value -is [decimal] -or $Value -is [datetime] -or $Value -is [datetimeoffset] -or $Value -is [guid] -or $Depth -ge 30) {
        $Into[$label] = ConvertTo-UTCMScalarText $Value
        return
    }

    if ($Value -is [System.Collections.IDictionary]) {
        if ($Value.Count -eq 0) { $Into[$label] = '{}'; return }
        foreach ($k in $Value.Keys) {
            $p = if ($Prefix) { "$Prefix.$k" } else { [string]$k }
            ConvertTo-UTCMFlatProperty -Value $Value[$k] -Prefix $p -Into $Into -Depth ($Depth + 1) -MaxEntries $MaxEntries
        }
        return
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        $i = 0
        foreach ($el in $Value) {
            ConvertTo-UTCMFlatProperty -Value $el -Prefix "$Prefix[$i]" -Into $Into -Depth ($Depth + 1) -MaxEntries $MaxEntries
            $i++
        }
        if ($i -eq 0) { $Into[$label] = '[]' }
        return
    }

    $props = @($Value.PSObject.Properties | Where-Object { $_.MemberType -in 'NoteProperty','Property' })
    if ($props.Count -eq 0) { $Into[$label] = '{}'; return }
    foreach ($prop in $props) {
        $p = if ($Prefix) { "$Prefix.$($prop.Name)" } else { $prop.Name }
        ConvertTo-UTCMFlatProperty -Value $prop.Value -Prefix $p -Into $Into -Depth ($Depth + 1) -MaxEntries $MaxEntries
    }
}

function Get-UTCMPropertyDiff {
    # Compares two JSON documents property by property. Returns $null when either side is not JSON.
    # Rows: { Path, Status (changed|added|removed|unchanged), Baseline, Current }; differences first.
    [CmdletBinding()]
    param([AllowNull()][string] $BaselineJson, [AllowNull()][string] $CurrentJson)

    try {
        $b = if ([string]::IsNullOrWhiteSpace($BaselineJson)) { $null } else { $BaselineJson | ConvertFrom-Json -ErrorAction Stop }
        $c = if ([string]::IsNullOrWhiteSpace($CurrentJson))  { $null } else { $CurrentJson  | ConvertFrom-Json -ErrorAction Stop }
    } catch {
        return $null
    }

    $fb = [ordered]@{}; $fc = [ordered]@{}
    if ($null -ne $b) { ConvertTo-UTCMFlatProperty -Value $b -Into $fb }
    if ($null -ne $c) { ConvertTo-UTCMFlatProperty -Value $c -Into $fc }

    $changed = New-Object System.Collections.Generic.List[object]
    $same    = New-Object System.Collections.Generic.List[object]
    foreach ($k in $fb.Keys) {
        if ($fc.Contains($k)) {
            $row = [pscustomobject]@{ Path = $k; Status = $(if ($fb[$k] -ceq $fc[$k]) { 'unchanged' } else { 'changed' }); Baseline = $fb[$k]; Current = $fc[$k] }
            if ($row.Status -eq 'unchanged') { $same.Add($row) } else { $changed.Add($row) }
        } else {
            $changed.Add([pscustomobject]@{ Path = $k; Status = 'removed'; Baseline = $fb[$k]; Current = $null })
        }
    }
    foreach ($k in $fc.Keys) {
        if (-not $fb.Contains($k)) {
            $changed.Add([pscustomobject]@{ Path = $k; Status = 'added'; Baseline = $null; Current = $fc[$k] })
        }
    }
    # The comma keeps an empty result an (empty) array, so callers can tell it from the $null parse failure
    $out = New-Object System.Collections.Generic.List[object]
    $out.AddRange($changed)
    $out.AddRange($same)
    return ,($out.ToArray())
}

function Get-UTCMItemPreview {
    # Short "key=value" preview of the first few top-level scalar properties.
    [CmdletBinding()]
    param([AllowNull()] $Data, [int] $Max = 3, [int] $ValueLength = 40)

    if ($null -eq $Data -or $Data -is [string] -or $Data.GetType().IsPrimitive) { return '' }
    $pairs = New-Object System.Collections.Generic.List[string]
    $isDict = $Data -is [System.Collections.IDictionary]
    $source = if ($isDict) { $Data.GetEnumerator() } else { $Data.PSObject.Properties }
    foreach ($p in $source) {
        if ($isDict) { $name = [string]$p.Key } else {
            if ($p.MemberType -ne 'NoteProperty' -and $p.MemberType -ne 'Property') { continue }
            $name = $p.Name
        }
        $v = $p.Value
        if ($null -eq $v -or $v -is [string] -or $v.GetType().IsPrimitive -or $v -is [datetime]) {
            $t = ConvertTo-UTCMScalarText $v
            if ($t.Length -gt $ValueLength) { $t = $t.Substring(0, $ValueLength) + '...' }
            $pairs.Add("$name=$t")
            if ($pairs.Count -ge $Max) { break }
        }
    }
    return ($pairs -join '; ')
}

function Get-UTCMCountBy {
    # Counts items by a property and returns { Name, Count } sorted by count (desc) then name.
    [CmdletBinding()]
    param([AllowNull()] $Items, [Parameter(Mandatory)][string] $Property)

    $rows = foreach ($g in (@($Items) | Where-Object { $null -ne $_ } | Group-Object -Property $Property)) {
        [pscustomobject]@{ Name = $(if ([string]::IsNullOrEmpty([string]$g.Name)) { 'unknown' } else { [string]$g.Name }); Count = $g.Count }
    }
    return @($rows | Sort-Object @{ Expression = 'Count'; Descending = $true }, Name)
}

function Get-UTCMSortedReportItem {
    # Orders normalized report items by lowercased name, then id, using ordinal (UTF-16) comparison. The client
    # uses the same comparison for its default view, so server-sorted markup needs no re-sort or DOM move.
    [CmdletBinding()]
    param([AllowNull()] $Items)

    $list = [object[]]@($Items | Where-Object { $null -ne $_ })
    if ($list.Count -le 1) { return $list }
    # [Array]::Sort(keys, items) does not permute the items array when called from PowerShell, so sort
    # the keys alone and carry each item's index at the end of its key.
    $keys = New-Object 'string[]' $list.Count
    for ($i = 0; $i -lt $list.Count; $i++) {
        $keys[$i] = ([string]$list[$i].DisplayName).ToLowerInvariant() + [char]0 + [string]$list[$i].Id + [char]0 + $i.ToString([cultureinfo]::InvariantCulture)
    }
    [Array]::Sort($keys, [System.StringComparer]::Ordinal)
    $out = New-Object 'object[]' $list.Count
    for ($i = 0; $i -lt $keys.Count; $i++) {
        $k = $keys[$i]
        $out[$i] = $list[[int]$k.Substring($k.LastIndexOf([char]0) + 1)]
    }
    return $out
}

function ConvertTo-UTCMDriftRecord {
    # Pairs Compare-Object output into one record per resource.
    #   '=>' only          -> Added
    #   '<=' only          -> Missing
    #   one '<=' + one '=>' with the same key -> Changed
    # Key is type+id, falling back to type+displayName when id is empty. Keys that appear more than
    # once on a side are ambiguous and are never paired (reported as plain Added/Missing).
    [CmdletBinding()]
    param([AllowNull()] $Diff)

    $rows = @($Diff | Where-Object { $null -ne $_ })
    if ($rows.Count -eq 0) { return @() }

    $entries = for ($i = 0; $i -lt $rows.Count; $i++) {
        $r = $rows[$i]
        $type = [string](Get-UTCMObjectField $r @('type','resourceType'))
        $id   = [string](Get-UTCMObjectField $r @('id'))
        $name = [string](Get-UTCMObjectField $r @('displayName'))
        $key  = if ($id) { "$type|id:$id" } else { "$type|name:$name" }
        [pscustomobject]@{
            Index = $i; Key = $key; Id = $id; DisplayName = $name; Type = $type
            Side = [string](Get-UTCMObjectField $r @('SideIndicator'))
            Normalized = [string](Get-UTCMObjectField $r @('normalizedData'))
        }
    }

    $records = New-Object System.Collections.Generic.List[object]
    $consumed = New-Object System.Collections.Generic.HashSet[int]

    foreach ($group in ($entries | Group-Object Key)) {
        $base = @($group.Group | Where-Object Side -eq '<=')
        $curr = @($group.Group | Where-Object Side -eq '=>')
        if ($base.Count -eq 1 -and $curr.Count -eq 1) {
            $b = $base[0]; $c = $curr[0]
            [void]$consumed.Add($b.Index); [void]$consumed.Add($c.Index)
            $records.Add([pscustomobject]@{
                Order = [Math]::Min($b.Index, $c.Index); Status = 'Changed'
                Id = $c.Id; DisplayName = $c.DisplayName; BaselineDisplayName = $b.DisplayName
                Type = $c.Type; Workload = (Get-UTCMWorkloadFromType $c.Type)
                BaselineData = $b.Normalized; CurrentData = $c.Normalized
                RowIndexes = @($b.Index, $c.Index)
            })
        }
    }

    foreach ($e in $entries) {
        if ($consumed.Contains($e.Index)) { continue }
        $status = if ($e.Side -eq '=>') { 'Added' } elseif ($e.Side -eq '<=') { 'Missing' } else { 'Changed' }
        $records.Add([pscustomobject]@{
            Order = $e.Index; Status = $status
            Id = $e.Id; DisplayName = $e.DisplayName; BaselineDisplayName = $null
            Type = $e.Type; Workload = (Get-UTCMWorkloadFromType $e.Type)
            BaselineData = $(if ($e.Side -eq '<=') { $e.Normalized } else { $null })
            CurrentData  = $(if ($e.Side -eq '=>') { $e.Normalized } else { $null })
            RowIndexes = @($e.Index)
        })
    }

    return @($records | Sort-Object Order)
}
