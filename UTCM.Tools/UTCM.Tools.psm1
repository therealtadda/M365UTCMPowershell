#requires -Version 7.0
<#
===============================================================================
    UTCM.Tools.psm1  (PowerShell 7+)
    Root module for the UTCM.Tools PowerShell module.

    Responsibilities:
      • Enable strict mode for safer execution
      • Define module-wide constants shared by functions
      • Reliably dot-source all Private\*.ps1 helpers (required)
      • Reliably dot-source all Public\*.ps1 functions (required)
      • Export ONLY the intended public functions
      • Validate public functions using a safe Retry Guard (no autoload)

    Notes:
      • Keep Export-ModuleMember's function list in sync with Public\ files.
      • The loader throws clear errors if folders/files are missing.
      • Retry guard uses Function: drive to avoid command discovery/autoload.
      • For import troubleshooting, set: $VerbosePreference='Continue' then Import-Module -Force
===============================================================================
#>

Set-StrictMode -Version Latest

# ---------------------------
# Module-wide constants (UTCM Graph preview/beta)
# ---------------------------
$script:GraphBase       = '/beta/configuration'
$script:SnapshotJobsUri = "$script:GraphBase/snapshotJobs"

# ---------------------------
# Helper: return .ps1 files from a folder (relative to $PSScriptRoot)
#           NOTE: This function ONLY RETURNS FILES. It does NOT dot-source them.
#           We dot-source at MODULE SCRIPT SCOPE (below), to keep definitions.
# ---------------------------
function _Get-ScriptsFromFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FolderName,
        [switch]$Required
    )

    $dir = Join-Path -Path $PSScriptRoot -ChildPath $FolderName
    Write-Verbose "Loading scripts from: $dir (Required=$($Required.IsPresent))"

    if (-not (Test-Path -LiteralPath $dir)) {
        if ($Required) {
            throw "Required folder not found: $dir"
        } else {
            Write-Verbose "Folder not found (optional): $dir — skipping."
            return @()
        }
    }

    $files = Get-ChildItem -LiteralPath $dir -Filter *.ps1 -File -ErrorAction Stop | Sort-Object Name
    if (-not $files -and $Required) {
        throw "No scripts (*.ps1) found in required folder: $dir"
    }

    return $files
}

# ---------------------------
# Collect scripts
# ---------------------------
$privateFiles = _Get-ScriptsFromFolder -FolderName 'Private' -Required
$publicFiles  = _Get-ScriptsFromFolder -FolderName 'Public'  -Required

# ---------------------------
# DOT-SOURCE FILES AT MODULE SCRIPT SCOPE (critical for persistence)
# ---------------------------

# Private helpers (may or may not declare functions)
foreach ($file in $privateFiles) {
    Write-Verbose "Dot-sourcing: $($file.FullName)"
    $before = (Get-ChildItem Function:\).Name
    . $file.FullName      # dot-source at module script scope
    $after  = (Get-ChildItem Function:\).Name
    $added  = Compare-Object $before $after -PassThru | Where-Object { $_ -like '*UTCM*' }
    if ($added) {
        Write-Verbose "Functions added by $($file.Name): $($added -join ', ')"
    } else {
        Write-Verbose "No UTCM functions detected from $($file.Name)"
    }
}

# Public cmdlets (should declare functions)
foreach ($file in $publicFiles) {
    Write-Verbose "Dot-sourcing: $($file.FullName)"
    $before = (Get-ChildItem Function:\).Name
    . $file.FullName      # dot-source at module script scope
    $after  = (Get-ChildItem Function:\).Name
    $added  = Compare-Object $before $after -PassThru | Where-Object { $_ -like '*UTCM*' }
    if ($added) {
        Write-Verbose "Functions added by $($file.Name): $($added -join ', ')"
    } else {
        Write-Verbose "No UTCM functions detected from $($file.Name)"
    }
}

# ---------------------------
# Export ONLY intended public functions
# ---------------------------
$publicFunctions = @(
    'Enable-UTCM.ps1',
    'Grant-UTCMWorkloadAccess.ps1',
    'Initialize-UTCM.ps1',
    'Test-UTCMSetup.ps1'
    'Get-UTCMAvailableSnapshot',
    'New-UTCMSnapshot',
    'Get-UTCMSnapshot',
    'Compare-UTCMConfiguration',
    'Export-UTCMSnapshot',
    'New-UTCMDriftReport',
    'Get-UTCMTenantDriftReport'
)

# ---------------------------
# Retry Guard (safe): validate functions after load with brief retries
# Uses Function: drive to avoid command discovery or module autoload during import.
# Tune via env vars; defaults are 3 tries and 80 ms delay
# ---------------------------
$maxTries = [Environment]::GetEnvironmentVariable('UTCM_RETRY_TRIES')    ?? '3'
$delayMs  = [Environment]::GetEnvironmentVariable('UTCM_RETRY_DELAY_MS') ?? '80'

try { $maxTries = [int]$maxTries } catch { $maxTries = 3 }
try { $delayMs  = [int]$delayMs  } catch { $delayMs  = 80 }
if ($maxTries -lt 1) { $maxTries = 1 }
if ($delayMs  -lt 1) { $delayMs  = 1 }

Write-Verbose "Validation retries: maxTries=$maxTries, delayMs=$delayMs"

$export  = @()
$missing = @()

foreach ($fn in $publicFunctions) {
    $ok = $false
    for ($i = 1; $i -le $maxTries; $i++) {
        if (Test-Path "Function:\$fn") {
            $ok = $true
            break
        }
        if ($i -lt $maxTries) {
            Start-Sleep -Milliseconds $delayMs
        }
    }

    if ($ok) {
        $export += $fn
    } else {
        $missing += $fn
    }
}

if ($missing.Count -gt 0) {
    $msg = @()
    $msg += "One or more public functions were not found after loading Public\*.ps1 and $maxTries validation attempts:"
    $msg += "  - " + ($missing -join "`n  - ")
    $msg += "Check for file/function name mismatches, scope issues (functions wrapped in invoked blocks),"
    $msg += "or missing files in the Public folder."
    throw ($msg -join "`n")
}

# Final export
Write-Verbose ("Export list: " + ($export -join ', '))
Export-ModuleMember -Function $export