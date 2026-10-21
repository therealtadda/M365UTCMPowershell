function Ensure-GraphConnection {
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()][string[]]$Scopes = @('ConfigurationMonitoring.ReadWrite.All'),
        [switch]$ReadOnly
    )

    if ($ReadOnly -and -not $PSBoundParameters.ContainsKey('Scopes')) {
        $Scopes = @('ConfigurationMonitoring.Read.All')
    }

    try {
        if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
            throw 'Microsoft.Graph.Authentication module is not installed. Install-Module Microsoft.Graph -Scope CurrentUser'
        }
        $context = Get-MgContext -ErrorAction Stop
        if (-not $context) {
            Connect-MgGraph -Scopes $Scopes -NoWelcome -ErrorAction Stop | Out-Null
            $context = Get-MgContext -ErrorAction Stop
            if (-not $context) { throw 'Connect-MgGraph did not establish a Graph context.' }
        }

        if ($context.AuthType -in @('AppOnly','UserProvidedAccessToken')) {
            Write-Verbose "Retaining the existing $($context.AuthType) Graph context; Microsoft Graph enforces its token permissions."
            return
        }
        if ($context.AuthType -ne 'Delegated') {
            throw "Unsupported Graph authentication context '$($context.AuthType)'. Reconnect explicitly with Connect-MgGraph."
        }

        $impliedScopes = @{
            'ConfigurationMonitoring.Read.All' = @('ConfigurationMonitoring.ReadWrite.All')
            'Application.Read.All' = @('Application.ReadWrite.All','Directory.Read.All','Directory.ReadWrite.All')
            'Application.ReadWrite.All' = @('Directory.ReadWrite.All')
            'Directory.Read.All' = @('Directory.ReadWrite.All')
        }
        $missing = @($Scopes | Where-Object {
            $required = $_
            $alternatives = @($required)
            if ($impliedScopes.ContainsKey($required)) { $alternatives += $impliedScopes[$required] }
            -not @($context.Scopes | Where-Object { $_ -in $alternatives }).Count
        })
        if ($missing.Count -gt 0) {
            throw (("The existing delegated Graph session is missing required scope(s): {0}. " +
                   "Reconnect explicitly with Connect-MgGraph -Scopes '{1}', preserving your intended tenant and environment. " +
                   "UTCM.Tools has not replaced the existing connection.") -f ($missing -join ', '), ($Scopes -join "','"))
        }
    } catch {
        throw "Failed to ensure Graph connection. $($_.Exception.Message)"
    }
}