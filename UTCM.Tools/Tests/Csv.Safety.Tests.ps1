Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe 'Spreadsheet-safe CSV cells' {
    It 'Protects a formula-like or control-prefixed cell: <Label>' -ForEach @(
        @{ Label = 'equals'; Value = '=1+1' }
        @{ Label = 'plus'; Value = '+1+1' }
        @{ Label = 'minus'; Value = '-1+1' }
        @{ Label = 'at'; Value = '@SUM(A1)' }
        @{ Label = 'tab'; Value = "`ttext" }
        @{ Label = 'carriage return'; Value = "`rtext" }
        @{ Label = 'newline'; Value = "`ntext" }
        @{ Label = 'leading spaces'; Value = '  =1+1' }
        @{ Label = 'quoted formula'; Value = '=HYPERLINK("https://example.invalid","Test")' }
        @{ Label = 'numeric negative value'; Value = -1 }
    ) {
        InModuleScope UTCM.Tools -Parameters @{ Value = $Value } {
            ConvertTo-UTCMCsvCell $Value | Should -Be ("'" + $Value)
        }
    }

    It 'Preserves null, empty, normal, quoted, JSON, and already-protected values' {
        InModuleScope UTCM.Tools {
            ConvertTo-UTCMCsvCell $null | Should -BeNullOrEmpty
            ConvertTo-UTCMCsvCell '' | Should -Be ''
            foreach ($value in @('Policy','A-B','a@b','"quoted"','{"name":"=1+1"}',"'=1+1")) {
                ConvertTo-UTCMCsvCell $value | Should -Be $value
            }
        }
    }

    It 'Matches browser CSV protection and quoting against PowerShell test vectors' -Skip:(-not (Get-Command node -ErrorAction SilentlyContinue)) {
        $scriptPath = Join-Path $TestDrive 'report-client.js'
        $casesPath = Join-Path $TestDrive 'csv-cases.json'
        $parameters = @{ ScriptPath = $scriptPath; CasesPath = $casesPath }
        InModuleScope UTCM.Tools -Parameters $parameters {
            Get-UTCMReportScript | Set-Content -LiteralPath $ScriptPath -Encoding utf8
            $cases = foreach ($value in @(
                $null, '', 'ordinary', '"quoted",value', 'a@b', "'=already protected",
                '=1+1', '+1+1', '-1+1', '@SUM(A1)', '  =1+1',
                "`ttext", "`rtext", "`ntext", " `t=1+1",
                '=HYPERLINK("https://example.invalid","Test")', '{"v":"=unchanged"}', -1, 42
            )) {
                [pscustomobject]@{ value = $value; expected = [string](ConvertTo-UTCMCsvCell $value) }
            }
            $cases | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $CasesPath -Encoding utf8
        }
        & node "$PSScriptRoot\Report.Csv.Tests.js" $scriptPath $casesPath
        $LASTEXITCODE | Should -Be 0
    }
}

Describe 'CSV export protection without altering report data' {
    BeforeAll {
        Mock -ModuleName UTCM.Tools Write-Log {}
        Mock -ModuleName UTCM.Tools Ensure-GraphConnection {}
        Mock -ModuleName UTCM.Tools Get-MgContext { $null }
        Mock -ModuleName UTCM.Tools Get-UTCMSnapshot { $null }
        Mock -ModuleName UTCM.Tools Invoke-MgGraphRequest {
            param($OutputFilePath)
            @{
                configurationItems = @(
                    @{
                        id = '=id'
                        displayName = '+name'
                        type = '@type'
                        workload = '-workload'
                        data = @{ value = '=unchanged' }
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputFilePath
        }
    }

    It 'Protects snapshot CSV fields but leaves JSON and HTML values intact' {
        $snapshot = [pscustomobject]@{
            id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
            displayName = 'CSV safety'
            status = 'succeeded'
            resourceLocation = 'https://graph.microsoft.com/v1.0/test'
        }
        $paths = @(Export-UTCMSnapshot -Snapshot $snapshot -Path $TestDrive)
        $row = Import-Csv -LiteralPath ($paths | Where-Object { $_ -like '*.csv' })
        $row.Id | Should -Be "'=id"
        $row.DisplayName | Should -Be "'+name"
        $row.Type | Should -Be "'@type"
        $row.Workload | Should -Be "'-workload"
        ($row.Data | ConvertFrom-Json).value | Should -Be '=unchanged'
        $json = Get-Content -LiteralPath ($paths | Where-Object { $_ -like '*.json' }) -Raw | ConvertFrom-Json
        $json.displayName | Should -Be '+name'
        $html = Get-Content -LiteralPath ($paths | Where-Object { $_ -like '*.html' }) -Raw
        $html | Should -Match 'data-name="\+name"'
        $html | Should -Not -Match 'data-name="&#39;\+name"'
    }

    It 'Protects all drift CSV data fields while keeping the raw download island unchanged' {
        $diff = @([pscustomobject]@{
            id = '=id'; displayName = '@name'; type = '-type'
            SideIndicator = '=>'; normalizedData = '+value'
        })
        $result = New-UTCMDriftReport -Diff $diff -SnapshotId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -OutputPath $TestDrive
        $row = Import-Csv -LiteralPath $result.CsvPath
        $row.Id | Should -Be "'=id"
        $row.DisplayName | Should -Be "'@name"
        $row.Type | Should -Be "'-type"
        $row.NormalizedData | Should -Be "'+value"
        $row.DriftType | Should -Be 'Added in Current'
        $html = Get-Content -LiteralPath $result.HtmlPath -Raw
        $island = [regex]::Match($html, '(?s)id="utcm-drift-data">(.*?)</script>').Groups[1].Value | ConvertFrom-Json
        $island.rows[0].DisplayName | Should -Be '@name'
        $island.rows[0].NormalizedData | Should -Be '+value'
    }
}
