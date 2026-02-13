<# =====================================================================
    UTCM.Tools.psm1  (PowerShell 7+)
    Root module for the UTCM.Tools PowerShell module.

    Responsibilities:
      • Enable strict mode for safer execution
      • Define module-wide constants shared by functions
      • Reliably dot-source all Private\*.ps1 helpers (required)
      • Reliably dot-source all Public\*.ps1 functions (required)
      • Export ONLY the intended public functions
      • Validate public functions using Option B (Retry Guard)

    Notes:
      • Keep Export-ModuleMember's function list in sync with Public\ files.
      • The loader throws clear errors if folders/files are missing.
      • Tested with PowerShell 7+ and Pester 5+.
===================================================================== #>

Set-StrictMode -Version Latest

# ---------------------------
# Module-wide constants (UTCM Graph preview/beta)
# ---------------------------
$script:GraphBase       = "/beta/configuration"
$script:SnapshotJobsUri = "$script:GraphBase/snapshotJobs"

# ---------------------------
# Helper: Load .ps1 files from a folder (relative to $PSScriptRoot)
# ---------------------------
function _Load-ScriptsFromFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FolderName,
        [switch]$Required
    )

    $dir = Join-Path -Path $PSScriptRoot -ChildPath $FolderName

    if (-not (Test-Path -LiteralPath $dir)) {
        if ($Required) {
            throw "Required folder not found: $dir"
        } else {
            return
        }
    }

    # Load only *.ps1 files; stop immediately on access/path errors
    $files = Get-ChildItem -LiteralPath $dir -Filter *.ps1 -File -ErrorAction Stop
    if (-not $files -and $Required) {
        throw "No scripts (*.ps1) found in required folder: $dir"
    }

    foreach ($file in $files) {
        . $file.FullName
    }
}

# ---------------------------
# Load Private helpers first (required)
# ---------------------------
_Load-ScriptsFromFolder -FolderName 'Private' -Required

# ---------------------------
# Load Public cmdlets next (required)
# ---------------------------
_Load-ScriptsFromFolder -FolderName 'Public' -Required

# ---------------------------
# Export ONLY intended public functions
# ---------------------------
# Keep this list in sync with the public API surface of the module.
$publicFunctions = @(
    'Get-UTCMAvailableSnapshot',
    'New-UTCMSnapshot',
    'Get-UTCMSnapshot',
    'Compare-UTCMConfiguration',
    'Export-UTCMSnapshot',
    'New-UTCMDriftReport',
    'Get-UTCMTenantDriftReport'
)

# ---------------------------
# Option B: Retry Guard (validate functions after load, with brief retries)
# ---------------------------
# Tune via environment variables; defaults are 3 tries and 80 ms delay
# (PowerShell 7+ null-coalescing operator ?? is used here)
$maxTries = [Environment]::GetEnvironmentVariable('UTCM_RETRY_TRIES')    ?? '3'
$delayMs  = [Environment]::GetEnvironmentVariable('UTCM_RETRY_DELAY_MS') ?? '80'

# Convert to int and enforce sane minimums
try { $maxTries = [int]$maxTries } catch { $maxTries = 3 }
try { $delayMs  = [int]$delayMs  } catch { $delayMs  = 80 }
if ($maxTries -lt 1) { $maxTries = 1 }
if ($delayMs  -lt 1) { $delayMs  = 1 }

$export  = @()
$missing = @()

foreach ($fn in $publicFunctions) {
    $ok = $false
    for ($i = 1; $i -le $maxTries; $i++) {
        if (Get-Command -Name $fn -ErrorAction SilentlyContinue) {
            $ok = $true
            break
        }
        Start-Sleep -Milliseconds $delayMs
    }

    if ($ok) {
        $export += $fn
    } else {
        # Collect missing names and fail once, below
        $missing += $fn
    }
}

if ($missing.Count -gt 0) {
    $msg = @()
    $msg += "One or more public functions were not found after loading Public\*.ps1 and $maxTries validation attempts:"
    $msg += "  - " + ($missing -join "`n  - ")
    $msg += "Check for file/function name mismatches, syntax errors, or missing files in the Public folder."
    throw ($msg -join "`n")
}

Export-ModuleMember -Function $export