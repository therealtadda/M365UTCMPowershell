# Tests for New-UTCMDriftReport (contract + behaviour). Output goes to $TestDrive only.
Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe "New-UTCMDriftReport contract" {
    BeforeAll {
        Mock -ModuleName UTCM.Tools Write-Log {}
        Mock -ModuleName UTCM.Tools Ensure-GraphConnection {}
        Mock -ModuleName UTCM.Tools Get-UTCMSnapshot {
            [pscustomobject]@{
                id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
                displayName = 'Test Snapshot'
                createdDateTime = '2026-02-08T10:00:00Z'
                status = 'succeeded'
                resourceLocation = 'https://graph.microsoft.com/v1.0/test'
            }
        }

        $script:sid = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        $script:diff = @(
            [pscustomobject]@{ id='1'; displayName='A'; type='caPolicy'; SideIndicator='=>'; normalizedData='{}' },
            [pscustomobject]@{ id='2'; displayName='B'; type='caPolicy'; SideIndicator='<='; normalizedData='{}' }
        )
    }

    It "Creates HTML and CSV outputs with the documented file names" {
        $res = New-UTCMDriftReport -Diff $script:diff -SnapshotId $script:sid -OutputPath $TestDrive
        Test-Path $res.HtmlPath | Should -BeTrue
        Test-Path $res.CsvPath  | Should -BeTrue
        (Split-Path $res.HtmlPath -Leaf) | Should -Be "UTCM-Drift-Report-$($script:sid).html"
        (Split-Path $res.CsvPath  -Leaf) | Should -Be "UTCM-Drift-Report-$($script:sid).csv"
    }

    It "Returns the documented output properties" {
        $res = New-UTCMDriftReport -Diff $script:diff -SnapshotId $script:sid -OutputPath $TestDrive
        $res.PSObject.Properties.Name | Should -Be @('HtmlPath','CsvPath','Added','Missing','Changed','Opened')
        $res.Opened | Should -BeFalse
    }

    It "Writes the CSV with the documented columns and one row per diff row" {
        $res = New-UTCMDriftReport -Diff $script:diff -SnapshotId $script:sid -OutputPath $TestDrive
        $csv = (Get-Content -LiteralPath $res.CsvPath -Raw) -replace "`r`n", "`n"
        $expected = @(
            '"Id","DisplayName","Type","DriftType","NormalizedData"'
            '"1","A","caPolicy","Added in Current","{}"'
            '"2","B","caPolicy","Missing in Current","{}"'
            ''
        ) -join "`n"
        $csv | Should -Be $expected
    }

    It "Keeps the legacy anchors and element ids" {
        $res = New-UTCMDriftReport -Diff $script:diff -SnapshotId $script:sid -OutputPath $TestDrive
        $html = Get-Content -LiteralPath $res.HtmlPath -Raw
        $html | Should -Match 'id="drift-summary"'
        $html | Should -Match 'id="drifttable"'
    }

    It "Counts a modified resource as one Changed (not Added + Missing) and keeps both CSV rows" {
        $pair = @(
            [pscustomobject]@{ id='9'; displayName='P'; type='microsoft.exchange.x'; SideIndicator='=>'; normalizedData='{"v":2}' },
            [pscustomobject]@{ id='9'; displayName='P'; type='microsoft.exchange.x'; SideIndicator='<='; normalizedData='{"v":1}' }
        )
        $res = New-UTCMDriftReport -Diff $pair -SnapshotId $script:sid -OutputPath $TestDrive
        $res.Added   | Should -Be 0
        $res.Missing | Should -Be 0
        $res.Changed | Should -Be 1
        @(Import-Csv -LiteralPath $res.CsvPath).Count | Should -Be 2
        $html = Get-Content -LiteralPath $res.HtmlPath -Raw
        $html | Should -Match 'Baseline'
        $html | Should -Match '&ne;'
    }

    It "Accepts an empty -Diff, writes a header-only CSV and a no-drift message" {
        $res = New-UTCMDriftReport -Diff @() -SnapshotId $script:sid -OutputPath $TestDrive
        $res.Added | Should -Be 0
        (Get-Content -LiteralPath $res.CsvPath -Raw).Trim() | Should -Be '"Id","DisplayName","Type","DriftType","NormalizedData"'
        (Get-Content -LiteralPath $res.HtmlPath -Raw) | Should -Match 'No drift detected'
    }

    It "Does not throw when a diff row has no type" {
        $notype = @([pscustomobject]@{ id='5'; displayName='N'; SideIndicator='=>'; normalizedData='{}' })
        { New-UTCMDriftReport -Diff $notype -SnapshotId $script:sid -OutputPath $TestDrive } | Should -Not -Throw
    }

    It "Emits a doctype, lang, viewport, CSP and a client script" {
        $res = New-UTCMDriftReport -Diff $script:diff -SnapshotId $script:sid -OutputPath $TestDrive
        $html = Get-Content -LiteralPath $res.HtmlPath -Raw
        $html | Should -Match '^<!DOCTYPE html>'
        $html | Should -Match '<html lang="en">'
        $html | Should -Match 'name="viewport"'
        $html | Should -Match 'Content-Security-Policy'
        $html | Should -Match 'data-sort='
    }
}
