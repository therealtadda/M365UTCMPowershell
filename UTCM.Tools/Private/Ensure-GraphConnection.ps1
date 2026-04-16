function Ensure-GraphConnection {
    [CmdletBinding()]
    param(
        [string[]]$Scopes = @('ConfigurationMonitoring.ReadWrite.All'),
        [switch]$ReadOnly
    )

    # If ReadOnly is specified and caller hasn't overridden Scopes, use the least-privilege scope
    if ($ReadOnly -and ($Scopes.Count -eq 1) -and ($Scopes[0] -eq 'ConfigurationMonitoring.ReadWrite.All')) {
        $Scopes = @('ConfigurationMonitoring.Read.All')
    }

    try {
        if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
            throw 'Microsoft.Graph.Authentication module is not installed. Install-Module Microsoft.Graph -Scope CurrentUser'
        }
        # If not connected (or token expired), Connect:
        if (-not (Get-MgContext)) {
            Connect-MgGraph -Scopes $Scopes | Out-Null
        }
    } catch {
        throw "Failed to ensure Graph connection. $($_.Exception.Message)"
    }
}