# Updated tests for Export-UTCMSnapshot
Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe "Export-UTCMSnapshot" {
    BeforeAll {
        $testDir = Join-Path $PSScriptRoot 'artifacts'
        if (-not (Test-Path $testDir)) { New-Item -ItemType Directory -Path $testDir | Out-Null }
        Set-Variable -Name testPath -Value (Join-Path $testDir 'snapshot.json') -Scope Script

        $snapshot = @{ configurationItems = @(@{id='1'; data=@{x='y'}}) }
        Set-Variable -Name snap -Value $snapshot -Scope Script
    }

    It "Writes JSON file to specified path" {
        $p = Export-UTCMSnapshot -Snapshot $script:snap -Path $script:testPath
        Test-Path $p | Should -BeTrue
        (Get-Content $p -Raw) | Should -Match '"id":\s*"1"'
    }
}