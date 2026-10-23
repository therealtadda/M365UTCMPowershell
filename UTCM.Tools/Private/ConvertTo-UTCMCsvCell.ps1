function ConvertTo-UTCMCsvCell {
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()]$Value
    )

    $text = [string]$Value
    if ($text -match '^[ \t\r\n]*[=+\-@]|^[\t\r\n]') {
        return "'" + $text
    }
    return $Value
}
