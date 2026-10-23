Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe "Partial snapshot export diagnostics" {
    BeforeAll {
        Mock -ModuleName UTCM.Tools Ensure-GraphConnection {}
        Mock -ModuleName UTCM.Tools Get-MgContext { $null }
        Mock -ModuleName UTCM.Tools Write-Log {}
        Mock -ModuleName UTCM.Tools Start-Sleep {}
    }

    BeforeEach {
        $script:partialExportJob = [pscustomobject]@{
            id = 'cccccccc-bbbb-cccc-dddd-eeeeeeeeeeee'
            displayName = 'Synthetic partial snapshot'
            status = 'partiallySuccessful'
            createdDateTime = [datetime]::UtcNow.ToString('o')
            completedDateTime = [datetime]::UtcNow.ToString('o')
            resourceLocation = 'https://graph.microsoft.com/v1.0/synthetic-snapshot'
            resources = @('microsoft.entra.securitydefaults','microsoft.exchange.transportrule')
            errorDetails = @('Synthetic <resource> & extraction denied', "Synthetic line 1`r`nline 2`tend")
        }
        $script:partialExportPayload = '{"resources":[{"resourceType":"microsoft.entra.securitydefaults","displayName":"Synthetic item","properties":{"Id":"synthetic-one","Enabled":true}}]}'
        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry {
            if ($OutputFilePath) { Set-Content -LiteralPath $OutputFilePath -Value $script:partialExportPayload }
            else { $script:partialExportJob }
        }
    }

    It "Persists original requested scope and full extraction errors beside an unchanged raw JSON export" {
        $warnings = @()
        $paths = @(Export-UTCMSnapshot -Snapshot $script:partialExportJob -Path $TestDrive -Format JSON -Raw `
            -Overwrite -WarningVariable warnings -WarningAction SilentlyContinue)
        $paths.Count | Should -Be 1
        Split-Path $paths[0] -Leaf | Should -Be "Snapshot-$($script:partialExportJob.id).json"
        $raw = Get-Content -LiteralPath $paths[0] -Raw | ConvertFrom-Json
        $raw.resources.Count | Should -Be 1
        $raw.resources[0].properties.Id | Should -Be 'synthetic-one'
        $raw.PSObject.Properties.Name | Should -Be @('resources')
        $diagnosticPath = Join-Path $TestDrive "Snapshot-$($script:partialExportJob.id).diagnostics.json"
        $diagnostic = Get-Content -LiteralPath $diagnosticPath -Raw | ConvertFrom-Json
        $diagnostic.snapshots.Count | Should -Be 1
        $diagnostic.snapshots[0].status | Should -Be 'partiallySuccessful'
        $diagnostic.snapshots[0].resources | Should -Be $script:partialExportJob.resources
        $diagnostic.snapshots[0].errorDetails | Should -Be $script:partialExportJob.errorDetails
        ($warnings -join ' ') | Should -Match 'this export is incomplete'
        ($warnings -join ' ') | Should -Match 'diagnostics.json'
    }

    It "Shows encoded extraction errors in partial HTML while preserving the three-format return contract" {
        $paths = @(Export-UTCMSnapshot -Snapshot $script:partialExportJob -Path $TestDrive -Overwrite -WarningAction SilentlyContinue)
        $paths.Count | Should -Be 3
        $html = Get-Content -LiteralPath ($paths | Where-Object { $_ -like '*.html' }) -Raw
        $html | Should -Match 'role="alert"'
        $html | Should -Match 'Incomplete extraction'
        $html | Should -Match 'Synthetic &lt;resource&gt; &amp; extraction denied'
        $html | Should -Not -Match '<resource>'
        $html | Should -Match 'partiallySuccessful'
    }

    It "Refreshes concise partial metadata through the detailed projection before export" {
        $concise = [pscustomobject]@{ id = $script:partialExportJob.id; status = 'partiallySuccessful' }
        Export-UTCMSnapshot -Snapshot $concise -Path $TestDrive -Format JSON -Overwrite -WarningAction SilentlyContinue | Out-Null
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -Times 1 -Exactly -ParameterFilter {
            -not $OutputFilePath -and [uri]::UnescapeDataString($Uri) -match '\$select=.*resourceLocation.*errorDetails'
        }
    }

    It "Uses detailed metadata when an export poll reaches partial completion" {
        $pending = [pscustomobject]@{ id = $script:partialExportJob.id; status = 'running' }
        Export-UTCMSnapshot -Snapshot $pending -Path $TestDrive -Format JSON -Overwrite -WarningAction SilentlyContinue | Out-Null
        $diagnostic = Get-Content -LiteralPath (Join-Path $TestDrive "Snapshot-$($script:partialExportJob.id).diagnostics.json") -Raw | ConvertFrom-Json
        $diagnostic.snapshots[0].errorDetails | Should -Be $script:partialExportJob.errorDetails
        Should -Invoke -ModuleName UTCM.Tools Start-Sleep -Times 1 -Exactly
    }

    It "Writes no artifact, diagnostic or destination directory when WhatIf declines export" {
        $destination = Join-Path $TestDrive 'whatif'
        @(Export-UTCMSnapshot -Snapshot $script:partialExportJob -Path $destination -Format JSON -WhatIf).Count | Should -Be 0
        Test-Path -LiteralPath $destination | Should -BeFalse
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -Times 0 -Exactly -ParameterFilter { $OutputFilePath }
    }

    It "Does not overwrite an existing diagnostics file without explicit overwrite" {
        $diagnosticPath = Join-Path $TestDrive "Snapshot-$($script:partialExportJob.id).diagnostics.json"
        Set-Content -LiteralPath $diagnosticPath -Value 'synthetic sentinel'
        { Export-UTCMSnapshot -Snapshot $script:partialExportJob -Path $TestDrive -Format JSON } |
            Should -Throw '*Diagnostics file*already exists*Overwrite*'
        (Get-Content -LiteralPath $diagnosticPath -Raw).Trim() | Should -Be 'synthetic sentinel'
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -Times 0 -Exactly -ParameterFilter { $OutputFilePath }
    }

    It "Surfaces diagnostics write failure rather than returning a success-shaped export" {
        $destination = Join-Path $TestDrive 'blocked'
        New-Item -ItemType Directory -Path (Join-Path $destination "Snapshot-$($script:partialExportJob.id).diagnostics.json") -Force | Out-Null
        { Export-UTCMSnapshot -Snapshot $script:partialExportJob -Path $destination -Format JSON -Overwrite } | Should -Throw
        Test-Path -LiteralPath (Join-Path $destination "Snapshot-$($script:partialExportJob.id).json") | Should -BeFalse
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -Times 0 -Exactly -ParameterFilter { $OutputFilePath }
    }

    It "Retains extraction diagnostics even if the artifact download subsequently fails" {
        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -ParameterFilter { $OutputFilePath } {
            throw 'Synthetic artifact download failure'
        }
        $destination = Join-Path $TestDrive 'failed-download'
        { Export-UTCMSnapshot -Snapshot $script:partialExportJob -Path $destination -Format JSON -Overwrite -WarningAction SilentlyContinue } |
            Should -Throw '*Synthetic artifact download failure*'
        $sidecar = Get-Content -LiteralPath (Join-Path $destination "Snapshot-$($script:partialExportJob.id).diagnostics.json") -Raw | ConvertFrom-Json
        $sidecar.snapshots[0].errorDetails | Should -Be $script:partialExportJob.errorDetails
        Test-Path -LiteralPath (Join-Path $destination "Snapshot-$($script:partialExportJob.id).json") | Should -BeFalse
    }

    It "Retains partial diagnostics for split-resource exports without adding them to the returned paths" {
        $paths = @(Export-UTCMSnapshot -Snapshot $script:partialExportJob -Path $TestDrive -SplitByResourceType `
            -Overwrite -WarningAction SilentlyContinue)
        $paths.Count | Should -Be 1
        (Get-Content -LiteralPath $paths[0] -Raw | ConvertFrom-Json).resourceType | Should -Be 'microsoft.entra.securitydefaults'
        Test-Path -LiteralPath (Join-Path $TestDrive "Snapshot-$($script:partialExportJob.id).diagnostics.json") | Should -BeTrue
    }

    It "Does not add a partial diagnostics sidecar to a healthy snapshot export" {
        $script:partialExportJob.status = 'succeeded'
        $script:partialExportJob.errorDetails = @()
        $destination = Join-Path $TestDrive 'healthy'
        $warnings = @()
        $paths = @(Export-UTCMSnapshot -Snapshot $script:partialExportJob -Path $destination -Format JSON `
            -WarningVariable warnings -WarningAction SilentlyContinue)
        $paths.Count | Should -Be 1
        Test-Path -LiteralPath (Join-Path $destination "Snapshot-$($script:partialExportJob.id).diagnostics.json") | Should -BeFalse
        @($warnings).Count | Should -Be 0
    }

    It "Writes valid empty JSON, header-only CSV and empty-state HTML: <Label>" -ForEach @(
        @{ Label = 'resources'; Payload = '{"resources":[]}' }
        @{ Label = 'configurationItems'; Payload = '{"configurationItems":[]}' }
        @{ Label = 'top-level array'; Payload = '[]' }
    ) {
        $script:partialExportJob.status = 'succeeded'
        $script:partialExportPayload = $Payload
        $paths = @(Export-UTCMSnapshot -Snapshot $script:partialExportJob -Path $TestDrive -Overwrite)
        $paths.Count | Should -Be 3
        $json = Get-Content -LiteralPath ($paths | Where-Object { $_ -like '*.json' }) -Raw | ConvertFrom-Json -NoEnumerate
        $json.GetType().FullName | Should -Be 'System.Object[]'
        $json.Count | Should -Be 0
        (Get-Content -LiteralPath ($paths | Where-Object { $_ -like '*.csv' }) -Raw).Trim() | Should -Be '"Id","DisplayName","Type","Workload","Data"'
        (Get-Content -LiteralPath ($paths | Where-Object { $_ -like '*.html' }) -Raw) | Should -Match 'This snapshot contains no items'
    }

    It "Keeps raw top-level array shape even with a single resource" {
        $script:partialExportJob.status = 'succeeded'
        $script:partialExportPayload = '[{"id":"synthetic-one","displayName":"Synthetic item","type":"microsoft.entra.securitydefaults","data":{"Enabled":true}}]'
        $paths = @(Export-UTCMSnapshot -Snapshot $script:partialExportJob -Path $TestDrive -Format JSON -Raw -Overwrite)
        $json = Get-Content -LiteralPath $paths[0] -Raw | ConvertFrom-Json -NoEnumerate
        $json.GetType().FullName | Should -Be 'System.Object[]'
        $json.Count | Should -Be 1
        $json[0].id | Should -Be 'synthetic-one'
    }
}

Describe "Incomplete drift report diagnostics" {
    BeforeAll {
        Mock -ModuleName UTCM.Tools Write-Log {}
    }

    BeforeEach {
        $script:reportBaseline = [pscustomobject]@{
            id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
            displayName = 'Synthetic baseline'
            status = 'succeeded'
            resources = @('microsoft.entra.securitydefaults','microsoft.exchange.transportrule')
            errorDetails = @()
            resourceLocation = 'https://graph.microsoft.com/v1.0/synthetic-baseline'
        }
        $script:reportCurrent = [pscustomobject]@{
            id = '11111111-1111-1111-1111-111111111111'
            status = 'partiallySuccessful'
            resources = @('microsoft.entra.securitydefaults','microsoft.exchange.transportrule')
            errorDetails = @('Synthetic <resource> & extraction denied', "Synthetic line 1`r`nline 2")
        }
        Mock -ModuleName UTCM.Tools Get-UTCMSnapshot { $script:reportBaseline }
    }

    It "Never claims no drift for an empty partial diff and keeps a prominent persistent warning" {
        $warnings = @()
        $current = @([pscustomobject]@{ id='synthetic-one'; displayName='Synthetic item'; type='microsoft.entra.securitydefaults'; data=@{Enabled=$true} })
        $result = New-UTCMDriftReport -Diff @() -SnapshotId $script:reportBaseline.id -OutputPath $TestDrive `
            -SnapshotDiagnostics @($script:reportBaseline, $script:reportCurrent) -CurrentItems $current `
            -WarningVariable warnings -WarningAction SilentlyContinue
        $html = Get-Content -LiteralPath $result.HtmlPath -Raw
        $html | Should -Match '<title>UTCM Drift Report - Incomplete Comparison</title>'
        $html | Should -Match 'role="alert"'
        $html | Should -Match 'Synthetic &lt;resource&gt; &amp; extraction denied'
        $html | Should -Not -Match '<resource>'
        $html | Should -Match 'No differences observed in the extracted data'
        $html | Should -Not -Match 'No drift detected'
        $html | Should -Not -Match 'Complete configuration captured'
        ($warnings -join ' ') | Should -Match 'INCOMPLETE COMPARISON'
        (Get-Content -LiteralPath $result.CsvPath -Raw).Trim() | Should -Be '"Id","DisplayName","Type","DriftType","NormalizedData"'
        $result.PSObject.Properties.Name | Should -Be @('HtmlPath','CsvPath','Added','Missing','Changed','Opened')
    }

    It "Persists both original requested scopes, statuses and full service errors for a nonempty partial diff" {
        $diff = @([pscustomobject]@{ id='synthetic-one'; displayName='Synthetic item'; type='microsoft.entra.securitydefaults'; normalizedData='{}'; SideIndicator='<=' })
        $result = New-UTCMDriftReport -Diff $diff -SnapshotId $script:reportBaseline.id -OutputPath $TestDrive `
            -SnapshotDiagnostics @($script:reportBaseline, $script:reportCurrent) -WarningAction SilentlyContinue
        $sidecar = Get-Content -LiteralPath (Join-Path $TestDrive "UTCM-Drift-Report-$($script:reportBaseline.id).diagnostics.json") -Raw | ConvertFrom-Json
        $sidecar.snapshots.Count | Should -Be 2
        $sidecar.snapshots[0].resources | Should -Be $script:reportBaseline.resources
        $sidecar.snapshots[1].status | Should -Be 'partiallySuccessful'
        $sidecar.snapshots[1].errorDetails | Should -Be $script:reportCurrent.errorDetails
        $result.Missing | Should -Be 1
        (Get-Content -LiteralPath $result.HtmlPath -Raw) | Should -Match 'Incomplete extraction'
        (Import-Csv -LiteralPath $result.CsvPath).PSObject.Properties.Name | Should -Be @('Id','DisplayName','Type','DriftType','NormalizedData')
    }

    It "Detects a partial baseline from header metadata when no explicit diagnostics were supplied" {
        $script:reportBaseline.status = 'partiallySuccessful'
        $script:reportBaseline.errorDetails = @('Synthetic baseline failure')
        $result = New-UTCMDriftReport -Diff @() -SnapshotId $script:reportBaseline.id -OutputPath $TestDrive -WarningAction SilentlyContinue
        $html = Get-Content -LiteralPath $result.HtmlPath -Raw
        $html | Should -Match 'Synthetic baseline failure'
        $html | Should -Not -Match 'No drift detected'
    }

    It "Does not let older supplied metadata hide a newly reported partial baseline" {
        $script:reportCurrent.status = 'succeeded'
        $script:reportCurrent.errorDetails = @()
        Mock -ModuleName UTCM.Tools Get-UTCMSnapshot {
            [pscustomobject]@{
                id='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; status='partiallySuccessful'
                resources=@('microsoft.entra.securitydefaults'); errorDetails=@('Synthetic fresh metadata failure')
            }
        }
        $result = New-UTCMDriftReport -Diff @() -SnapshotId $script:reportBaseline.id -OutputPath $TestDrive `
            -SnapshotDiagnostics @($script:reportBaseline, $script:reportCurrent) -WarningAction SilentlyContinue
        $html = Get-Content -LiteralPath $result.HtmlPath -Raw
        $html | Should -Match 'Synthetic fresh metadata failure'
        $html | Should -Not -Match 'No drift detected'
    }

    It "Keeps healthy no-drift behavior and refreshes diagnostics from an older incomplete report" {
        New-UTCMDriftReport -Diff @() -SnapshotId $script:reportBaseline.id -OutputPath $TestDrive `
            -SnapshotDiagnostics @($script:reportBaseline, $script:reportCurrent) -WarningAction SilentlyContinue | Out-Null
        $script:reportCurrent.status = 'succeeded'
        $script:reportCurrent.errorDetails = @()
        $result = New-UTCMDriftReport -Diff @() -SnapshotId $script:reportBaseline.id -OutputPath $TestDrive `
            -SnapshotDiagnostics @($script:reportBaseline, $script:reportCurrent)
        $html = Get-Content -LiteralPath $result.HtmlPath -Raw
        $html | Should -Match 'No drift detected'
        $html | Should -Not -Match 'role="alert"'
        $sidecar = Get-Content -LiteralPath (Join-Path $TestDrive "UTCM-Drift-Report-$($script:reportBaseline.id).diagnostics.json") -Raw | ConvertFrom-Json
        @($sidecar.snapshots | Where-Object status -ne 'succeeded').Count | Should -Be 0
        @($sidecar.snapshots | Where-Object errorSummary -ne '').Count | Should -Be 0
    }
}
