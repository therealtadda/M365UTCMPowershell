function Export-UTCMSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)][string]$Path
    )

    $dir = Split-Path -Path $Path -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }

    $Snapshot.configurationItems | ConvertTo-Json -Depth 50 | Out-File -LiteralPath $Path -Encoding UTF8
    return $Path
}