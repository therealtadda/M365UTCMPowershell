# Updated tests for Export-UTCMSnapshot
Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe "Export-UTCMSnapshot" {
    BeforeAll {
        $testDir = Join-Path $PSScriptRoot 'artifacts'
        if (-not (Test-Path $testDir)) { New-Item -ItemType Directory -Path $testDir | Out-Null }
        Set-Variable -Name testPath -Value $testDir -Scope Script

        Mock -ModuleName UTCM.Tools Ensure-GraphConnection {}

        # Mock the Graph download (Invoke-MgGraphRequest writes to file)
        Mock -ModuleName UTCM.Tools Invoke-MgGraphRequest {
            param($Method, $Uri, $OutputFilePath)
            $payload = @{
                configurationItems = @(
                    @{ id='1'; displayName='TestItem'; type='caPolicy'; data=@{x='y'} }
                )
            }
            $payload | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $OutputFilePath -Encoding UTF8
        }

        # Snapshot object with all required properties
        $snapshot = [pscustomobject]@{
            id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
            status = 'succeeded'
            resourceLocation = 'https://graph.microsoft.com/beta/admin/configurationManagement/test'
            configurationItems = @(@{id='1'; data=@{x='y'}})
        }
        Set-Variable -Name snap -Value $snapshot -Scope Script
    }

    It "Writes JSON file to specified path" {
        $paths = Export-UTCMSnapshot -Snapshot $script:snap -Path $script:testPath -Format JSON -Overwrite
        $paths | Should -Not -BeNullOrEmpty
        $jsonFile = $paths | Where-Object { $_ -like '*.json' }
        $jsonFile | Should -Not -BeNullOrEmpty
        Test-Path $jsonFile | Should -BeTrue
        (Get-Content $jsonFile -Raw) | Should -Match '"id"'
    }
}