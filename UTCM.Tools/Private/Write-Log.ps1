function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Cyan','Yellow','Green','Red','Gray','Magenta','White')]
        [string]$Color = 'White'
    )
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Write-Host "[$ts] $Message" -ForegroundColor $Color
}