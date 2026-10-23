function Resolve-UTCMGraphUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Uri
    )

    $context = Get-MgContext -ErrorAction Stop
    $environmentName = if ($context) { $context.Environment } else { 'Global' }
    $environment = Get-MgEnvironment -Name $environmentName -ErrorAction Stop
    $endpoint = [uri]$environment.GraphEndpoint
    if (-not $endpoint.IsAbsoluteUri -or $endpoint.Scheme -ne 'https') {
        throw 'The Graph environment must define an absolute HTTPS Graph endpoint.'
    }

    $target = $null
    if ($Uri -match '[\x00-\x20\\]' -or $Uri.StartsWith('//')) {
        throw 'Graph request URLs must not contain whitespace, control characters, backslashes, or a network-path authority.'
    }
    if ($Uri.StartsWith('/')) {
        $target = [uri]::new($endpoint, $Uri)
    } elseif (-not [uri]::TryCreate($Uri, [UriKind]::Absolute, [ref]$target)) {
        throw 'Graph request URLs must be absolute HTTPS URLs or root-relative Graph paths.'
    }

    if ($target.Scheme -ne 'https' -or
        $target.Host -ne $endpoint.Host -or $target.Port -ne $endpoint.Port -or
        $target.UserInfo -or $target.Fragment) {
        throw "Graph request and snapshot download URLs must use the connected HTTPS Graph endpoint ($($endpoint.Authority)), without credentials or fragments. External hosts are not supported."
    }
    return $target.AbsoluteUri
}
