
function Validate-Guid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Value
    )

    $out = [Guid]::Empty
    return [Guid]::TryParse($Value, [ref]$out)
}