Describe 'Publish content allowlist' {
    BeforeAll {
        $script:publishFixture = Join-Path $TestDrive 'publish-fixture'
        $script:publishTemp = Join-Path $TestDrive 'publish-temp'
        New-Item -ItemType Directory -Path $script:publishTemp | Out-Null
        $script:publishModule = Join-Path $script:publishFixture 'UTCM.Tools'
        foreach ($folder in @('Public','Private','Presets','Tests','Private\nested')) {
            New-Item -ItemType Directory -Path (Join-Path $script:publishModule $folder) -Force | Out-Null
        }
        $script:publishScript = Join-Path $script:publishFixture 'Publish.ps1'
        Copy-Item -LiteralPath "$PSScriptRoot\..\..\Publish.ps1" -Destination $script:publishScript
        foreach ($file in @(
            'UTCM.Tools.psd1','UTCM.Tools.psm1','Public\Get-Example.ps1','Private\Get-Helper.ps1',
            'Presets\resource-presets.json','Presets\supported-resource-types.json',
            '.env','private-key.pfx','Private\secret.pfx','Private\debug.log','Private\Get-Helper.Tests.ps1',
            'Private\nested\Unexpected.ps1','Presets\local.json','Tests\Example.Tests.ps1'
        )) {
            'fixture' | Set-Content -LiteralPath (Join-Path $script:publishModule $file)
        }
        Mock Test-ModuleManifest {
            [pscustomobject]@{
                Name = 'UTCM.Tools'; Version = '1.4.1'; Author = 'Test'
                PrivateData = @{ PSData = @{ LicenseUri = 'https://example.invalid/license'; ProjectUri = 'https://example.invalid/project' } }
            }
        }
        Mock pwsh { '20' }
        if (-not (Get-Command Publish-PSResource -ErrorAction SilentlyContinue)) {
            function Publish-PSResource {
                [CmdletBinding()]
                param($Path, $ApiKey, $Repository)
                throw "Unmocked publisher: $($PSBoundParameters.Keys -join ', ')"
            }
        }
        Mock Publish-PSResource {}
        Mock Install-Module { throw 'Publishing tests must not install dependencies' }
    }

    It 'Stages only entry points, top-level module scripts, and the two shipped preset files' {
        $originalTemp = $env:TEMP
        try {
            $env:TEMP = $script:publishTemp
            & $script:publishScript -SkipTests -SkipAnalyzer -WhatIf -ApiKey 'not-a-real-api-key'
            $stageDirectories = @(Get-ChildItem -LiteralPath $script:publishTemp -Directory -Filter 'utcm-publish-*')
            $stageDirectories.Count | Should -Be 1
            $stagedModule = Join-Path $stageDirectories[0].FullName 'UTCM.Tools'
            $files = @(Get-ChildItem -LiteralPath $stagedModule -Recurse -File |
                ForEach-Object { [IO.Path]::GetRelativePath($stagedModule, $_.FullName) } | Sort-Object)
            $files | Should -Be @(
                'Presets\resource-presets.json','Presets\supported-resource-types.json',
                'Private\Get-Helper.ps1','Public\Get-Example.ps1','UTCM.Tools.psd1','UTCM.Tools.psm1'
            )
            Should -Invoke Publish-PSResource -Times 0 -Exactly
            Should -Invoke Install-Module -Times 0 -Exactly
        } finally {
            $env:TEMP = $originalTemp
        }
    }
}
