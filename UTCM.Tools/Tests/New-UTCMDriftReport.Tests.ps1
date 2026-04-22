# Updated tests for New-UTCMDriftReport
Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe "New-UTCMDriftReport" {
    BeforeAll {
        Mock -ModuleName UTCM.Tools Write-Log {}
        Mock -ModuleName UTCM.Tools Ensure-GraphConnection {}
        Mock -ModuleName UTCM.Tools Get-UTCMSnapshot {
            [pscustomobject]@{
                id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
                displayName = 'Test Snapshot'
                createdDateTime = '2026-02-08T10:00:00Z'
                status = 'succeeded'
                resourceLocation = 'https://graph.microsoft.com/beta/test'
            }
        }

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