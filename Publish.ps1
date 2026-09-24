<#
.SYNOPSIS
    Validate, stage, and publish the UTCM.Tools module to the PowerShell Gallery.

.DESCRIPTION
    Runs the full pre-publish pipeline:
      1. Validates the module manifest with Test-ModuleManifest.
      2. Optionally runs Pester tests and PSScriptAnalyzer.
      3. Stages a clean copy of the module under $env:TEMP (excluding Tests/ and dev junk).
      4. Imports the staged copy to sanity-check loading and exported function count.
      5. Publishes to the PowerShell Gallery (or any configured repository).

    Use -WhatIf for a dry run, -SkipTests to skip Pester, -SkipAnalyzer to skip PSScriptAnalyzer.
    Provide -NuGetApiKey or set the PSGALLERY_API_KEY environment variable.

.PARAMETER ApiKey
    Gallery API key. Falls back to $env:PSGALLERY_API_KEY if omitted.

.PARAMETER Repository
    Target PowerShellGet repository name. Default: PSGallery.

.PARAMETER SkipTests
    Skip Pester test execution.

.PARAMETER SkipAnalyzer
    Skip PSScriptAnalyzer.

.PARAMETER AllowPrerelease
    Permit publishing a module whose version contains a prerelease tag.

.PARAMETER Force
    Pass -Force to Publish-Module (re-push same version — rarely valid on PSGallery).

.EXAMPLE
    .\Publish.ps1 -WhatIf

.EXAMPLE
    .\Publish.ps1 -ApiKey $env:PSGALLERY_API_KEY

.EXAMPLE
    .\Publish.ps1 -SkipTests -SkipAnalyzer -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]   $ApiKey         = $env:PSGALLERY_API_KEY,
    [string]   $Repository     = 'PSGallery',
    [switch]   $SkipTests,
    [switch]   $SkipAnalyzer,
    [switch]   $AllowPrerelease,
    [switch]   $Force
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$msg) {
    Write-Host ""
    Write-Host ("==> {0}" -f $msg) -ForegroundColor Cyan
}

$repoRoot  = $PSScriptRoot
$moduleDir = Join-Path $repoRoot 'UTCM.Tools'
$manifest  = Join-Path $moduleDir 'UTCM.Tools.psd1'

if (-not (Test-Path $manifest)) {
    throw "Manifest not found: $manifest"
}

# --- 1. Validate manifest ----------------------------------------------------
Write-Step "Validating manifest: $manifest"
$info = Test-ModuleManifest -Path $manifest
Write-Host ("Module: {0}  Version: {1}  Author: {2}" -f $info.Name, $info.Version, $info.Author) -ForegroundColor Gray

if (-not $info.PrivateData.PSData.LicenseUri) { throw "LicenseUri is required in PSData for the Gallery." }
if (-not $info.PrivateData.PSData.ProjectUri) { throw "ProjectUri is required in PSData for the Gallery." }

# --- 2. Optional: Pester -----------------------------------------------------
if (-not $SkipTests) {
    $testsDir = Join-Path $moduleDir 'Tests'
    if (Test-Path $testsDir) {
        Write-Step "Running Pester tests"
        if (-not (Get-Module -ListAvailable Pester | Where-Object { $_.Version -ge [version]'5.0.0' })) {
            Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force -SkipPublisherCheck
        }
        Import-Module Pester -MinimumVersion 5.0.0 -Force
        $result = Invoke-Pester -Path $testsDir -CI -PassThru
        if ($result.FailedCount -gt 0) {
            throw ("Pester reported {0} failed test(s); aborting publish." -f $result.FailedCount)
        }
    } else {
        Write-Host "No Tests/ folder found; skipping Pester." -ForegroundColor Yellow
    }
} else {
    Write-Host "-SkipTests specified; skipping Pester." -ForegroundColor Yellow
}

# --- 3. Optional: PSScriptAnalyzer ------------------------------------------
if (-not $SkipAnalyzer) {
    Write-Step "Running PSScriptAnalyzer"
    if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
        Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
    }
    Import-Module PSScriptAnalyzer -Force
    $diags = Invoke-ScriptAnalyzer -Path $moduleDir -Recurse -Severity @('Error','Warning') -ExcludeRule @('PSAvoidUsingWriteHost')
    if ($diags) {
        $diags | Format-Table Severity, RuleName, ScriptName, Line, Message -AutoSize | Out-Host
        $errors = @($diags | Where-Object Severity -eq 'Error')
        if ($errors.Count -gt 0) {
            throw ("PSScriptAnalyzer reported {0} error(s); aborting publish." -f $errors.Count)
        }
        Write-Host "PSScriptAnalyzer reported warnings only; continuing." -ForegroundColor Yellow
    } else {
        Write-Host "PSScriptAnalyzer: clean." -ForegroundColor Green
    }
} else {
    Write-Host "-SkipAnalyzer specified; skipping PSScriptAnalyzer." -ForegroundColor Yellow
}

# --- 4. Stage a clean copy ---------------------------------------------------
Write-Step "Staging clean module copy"
$stageRoot   = Join-Path $env:TEMP ("utcm-publish-{0}" -f ([guid]::NewGuid().ToString('N').Substring(0,8)))
$stageModule = Join-Path $stageRoot 'UTCM.Tools'
New-Item -ItemType Directory -Path $stageModule -Force -WhatIf:$false | Out-Null

$excludeDirs  = @('Tests', '.git', '.github', '.vscode')
$excludeFiles = @('*.Tests.ps1', '*.bak', '*.tmp', '*.log')

Get-ChildItem -LiteralPath $moduleDir -Force | Where-Object {
    $_.Name -notin $excludeDirs
} | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $stageModule -Recurse -Force -Exclude $excludeFiles -WhatIf:$false
}

# Remove any Tests/ folder that slipped in via nested copy
Get-ChildItem -LiteralPath $stageModule -Recurse -Directory -Force |
    Where-Object { $_.Name -eq 'Tests' } |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -WhatIf:$false

Write-Host ("Staged to: {0}" -f $stageModule) -ForegroundColor Gray

# Re-validate manifest from the staged copy
$stagedManifest = Join-Path $stageModule 'UTCM.Tools.psd1'
$stagedInfo = Test-ModuleManifest -Path $stagedManifest

# Quick import smoke test in a clean runspace to avoid contaminating current session
Write-Step "Smoke-testing staged module load"
$importScript = @"
Remove-Module UTCM.Tools -ErrorAction SilentlyContinue
Import-Module '$stagedManifest' -Force -ErrorAction Stop
(Get-Command -Module UTCM.Tools).Count
"@
$count = pwsh -NoProfile -Command $importScript
if (-not $count -or [int]$count -lt 1) {
    throw "Staged module failed to import or exported 0 commands."
}
Write-Host ("Staged module exports {0} commands." -f $count) -ForegroundColor Green

# --- 5. Publish --------------------------------------------------------------
Write-Step ("Publishing to {0}" -f $Repository)

if (-not $ApiKey) {
    throw "No API key provided. Pass -ApiKey or set `$env:PSGALLERY_API_KEY."
}

$publishParams = @{
    Path        = $stageModule
    NuGetApiKey = $ApiKey
    Repository  = $Repository
    Verbose     = $true
}
if ($Force)           { $publishParams.Force = $true }
if ($AllowPrerelease) { $publishParams.AllowPrerelease = $true }

if ($PSCmdlet.ShouldProcess(("{0} {1}" -f $stagedInfo.Name, $stagedInfo.Version), "Publish-Module to $Repository")) {
    Publish-Module @publishParams
    Write-Host ""
    Write-Host ("Published {0} {1} to {2}." -f $stagedInfo.Name, $stagedInfo.Version, $Repository) -ForegroundColor Green
    Write-Host "Verify with: Find-Module UTCM.Tools" -ForegroundColor Gray
} else {
    Write-Host "Dry run: Publish-Module skipped. Staged artifact: $stageModule" -ForegroundColor Yellow
}
