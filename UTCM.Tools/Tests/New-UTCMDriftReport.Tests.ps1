# Updated tests for New-UTCMDriftReport
Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe "New-UTCMDriftReport" {
    BeforeAll {
        Mock -ModuleName UTCM.Tools Write-Log {}

        $outDir = Join-Path $PSScriptRoot 'artifacts'
        if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
        Set-Variable -Name dir -Value $outDir -Scope Script

        $diff = @(
            [pscustomobject]@{ id='1'; displayName='A'; type='caPolicy'; SideIndicator='=>'; normalizedData='{}' },
            [pscustomobject]@{ id='2'; displayName='B'; type='caPolicy'; SideIndicator='<='; normalizedData='{}' }
        )
        Set-Variable -Name d -Value $diff -Scope Script
    }

    It "Creates HTML and CSV outputs" {
        $res = New-UTCMDriftReport -Diff $script:d -SnapshotId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -OutputPath $script:dir
        Test-Path $res.HtmlPath | Should -BeTrue
        Test-Path $res.CsvPath  | Should -BeTrue
    }
}