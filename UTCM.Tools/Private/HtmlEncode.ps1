function HtmlEncode {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()][AllowEmptyString()]$InputObject)

    if ($null -eq $InputObject) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$InputObject)
}
