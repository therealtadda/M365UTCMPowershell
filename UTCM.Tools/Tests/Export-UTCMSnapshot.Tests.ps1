# Tests for Export-UTCMSnapshot (contract + behaviour). Output goes to $TestDrive only.
Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe "Export-UTCMSnapshot" {
    BeforeAll {
        Mock -ModuleName UTCM.Tools Write-Log {}
        Mock -ModuleName UTCM.Tools Ensure-GraphConnection {}
        Mock -ModuleName UTCM.Tools Get-MgContext { $null }

        # Mock the Graph download (Invoke-MgGraphRequest writes to file)
        Mock -ModuleName UTCM.Tools Invoke-MgGraphRequest {
            param($Method, $Uri, $OutputFilePath)
            $payload = @{
                configurationItems = @(
                    @{ id='1'; displayName='TestItem'; type='microsoft.exchange.caPolicy'; data=@{x='y'} }
                )
            }
            $payload | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $OutputFilePath -Encoding UTF8
        }

        $script:snap = [pscustomobject]@{
            id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
            displayName = 'Test Snapshot'
            createdDateTime = '2026-02-08T10:00:00Z'
            status = 'succeeded'
            resourceLocation = 'https://graph.microsoft.com/v1.0/admin/configurationManagement/test'
        }
    }

    It "Writes JSON file to specified path" {
        $paths = Export-UTCMSnapshot -Snapshot $script:snap -Path $TestDrive -Format JSON -Overwrite
        $paths | Should -Not -BeNullOrEmpty
        $jsonFile = $paths | Where-Object { $_ -like '*.json' }
        $jsonFile | Should -Not -BeNullOrEmpty
        Test-Path $jsonFile | Should -BeTrue
        (Get-Content $jsonFile -Raw) | Should -Match '"id"'
    }

    It "Writes all three formats with documented names and returns their paths" {
        $paths = @(Export-UTCMSnapshot -Snapshot $script:snap -Path $TestDrive -Overwrite)
        $names = $paths | ForEach-Object { Split-Path $_ -Leaf }
        $names | Should -Contain "Snapshot-$($script:snap.id).json"
        $names | Should -Contain "Snapshot-$($script:snap.id).csv"
        $names | Should -Contain "Snapshot-$($script:snap.id).html"
    }

    It "Writes the CSV with the documented columns" {
        $paths = @(Export-UTCMSnapshot -Snapshot $script:snap -Path $TestDrive -Format CSV -Overwrite)
        $csv = (Get-Content -LiteralPath $paths[0] -Raw) -replace "`r`n", "`n"
        $expected = @(
            '"Id","DisplayName","Type","Workload","Data"'
            '"1","TestItem","microsoft.exchange.caPolicy","exchange","{""x"":""y""}"'
            ''
        ) -join "`n"
        $csv | Should -Be $expected
    }

    It "Keeps the legacy table id in the HTML export" {
        $paths = @(Export-UTCMSnapshot -Snapshot $script:snap -Path $TestDrive -Format HTML -Overwrite)
        (Get-Content -LiteralPath $paths[0] -Raw) | Should -Match 'id="snapTable"'
    }

    It "Writes an explicit empty state when the snapshot has no items" {
        Mock -ModuleName UTCM.Tools Invoke-MgGraphRequest {
            '{"configurationItems":[]}' | Out-File -LiteralPath $OutputFilePath -Encoding UTF8
        }
        $partial = [pscustomobject]@{ id = 'cccccccc-bbbb-cccc-dddd-eeeeeeeeeeee'; displayName = 'Partial'; status = 'partiallySuccessful'; resourceLocation = 'https://graph.microsoft.com/v1.0/x'; resources = @('microsoft.entra.securitydefaults'); errorDetails = @('Synthetic extraction failure') }
        $paths = @(Export-UTCMSnapshot -Snapshot $partial -Path $TestDrive -Format HTML -Overwrite)
        $html = Get-Content -LiteralPath $paths[0] -Raw
        $html | Should -Match 'This snapshot contains no items'
        $html | Should -Match 'partiallySuccessful'
    }
}
