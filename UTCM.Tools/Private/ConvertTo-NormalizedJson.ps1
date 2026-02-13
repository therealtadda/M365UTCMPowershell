function ConvertTo-NormalizedJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$InputObject)

    # Normalize complex objects to compressed JSON for consistent comparisons.
    # NOTE: Property order may still impact equality; this is generally acceptable for UTCM data.
    return ($InputObject | ConvertTo-Json -Depth 50 -Compress)
}