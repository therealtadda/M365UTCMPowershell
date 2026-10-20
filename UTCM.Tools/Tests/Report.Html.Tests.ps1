# Structure, security, CSP and empty-state tests for the HTML report documents.
Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

BeforeAll {
    function script:Get-Sha256Csp([string]$text) {
        $lf = $text.Replace("`r`n", "`n").Replace("`r", "`n")
        $sha = [System.Security.Cryptography.SHA256]::Create()
        'sha256-' + [Convert]::ToBase64String($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($lf)))
    }
    $script:hostile = '"><img src=x onerror=alert(1)></script><script>alert(2)</script>'
}

Describe "Encoding and URL helpers" {
    It "ConvertTo-UTCMSafeUrl only allows absolute https URLs" {
        InModuleScope UTCM.Tools {
            ConvertTo-UTCMSafeUrl 'https://graph.microsoft.com/v1.0/x' | Should -Be 'https://graph.microsoft.com/v1.0/x'
            ConvertTo-UTCMSafeUrl 'javascript:alert(1)' | Should -BeNullOrEmpty
            ConvertTo-UTCMSafeUrl 'http://example.com' | Should -BeNullOrEmpty
            ConvertTo-UTCMSafeUrl 'data:text/html,<script>' | Should -BeNullOrEmpty
            ConvertTo-UTCMSafeUrl '/relative/path' | Should -BeNullOrEmpty
            ConvertTo-UTCMSafeUrl $null | Should -BeNullOrEmpty
        }
    }
    It "ConvertTo-UTCMJsonIsland cannot terminate or confuse the script element" {
        InModuleScope UTCM.Tools {
            $json = ConvertTo-UTCMJsonIsland -InputObject @{ v = "</script><!-- & $([char]0x2028)$([char]0x2029)" }
            $json | Should -Not -Match '<'
            $json | Should -Not -Match '>'
            $json | Should -Not -Match '&'
            $json | Should -Not -Match "[\u2028\u2029]"
            ($json | ConvertFrom-Json).v | Should -Be "</script><!-- & $([char]0x2028)$([char]0x2029)"
        }
    }
    It "Get-UTCMCspHash matches an independent SHA-256 and ignores CRLF vs LF" {
        InModuleScope UTCM.Tools {
            Get-UTCMCspHash '' | Should -Be 'sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU='
            (Get-UTCMCspHash "a`r`nb") | Should -Be (Get-UTCMCspHash "a`nb")
        }
    }
}

Describe "Drift report document" {
    BeforeAll {
        Mock -ModuleName UTCM.Tools Write-Log {}
        Mock -ModuleName UTCM.Tools Get-UTCMSnapshot {
            [pscustomobject]@{ id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; displayName = $using:hostile; createdDateTime = '2026-02-08T10:00:00Z'; status = 'succeeded'; resourceLocation = 'javascript:alert(1)' }
        }
        $diff = @(
            [pscustomobject]@{ id = 'c1'; displayName = 'Zeta'; type = 'microsoft.entra.conditionalaccesspolicy'; SideIndicator = '<='; normalizedData = '{"State":"enabled","Same":"x"}' },
            [pscustomobject]@{ id = 'c1'; displayName = 'Zeta'; type = 'microsoft.entra.conditionalaccesspolicy'; SideIndicator = '=>'; normalizedData = '{"State":"disabled","Same":"x"}' },
            [pscustomobject]@{ id = 'h1'; displayName = $script:hostile; type = 'microsoft.exchange.transportrule'; SideIndicator = '=>'; normalizedData = ('{"Note":"' + ($script:hostile -replace '"', '\"') + '"}') }
        )
        $current = @([pscustomobject]@{ id = 'x1'; displayName = $script:hostile; type = 'microsoft.teams.t'; data = [pscustomobject]@{ a = '</script>' } })
        $res = New-UTCMDriftReport -Diff $diff -SnapshotId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -OutputPath $TestDrive -CurrentItems $current
        $script:html = Get-Content -LiteralPath $res.HtmlPath -Raw
    }

    It "Never emits the hostile markup unencoded" {
        $script:html | Should -Not -Match ([regex]::Escape('<img src=x onerror'))
        $script:html | Should -Not -Match ([regex]::Escape('<script>alert(2)'))
        $script:html | Should -Match ([regex]::Escape('&lt;img src=x onerror=alert(1)&gt;'))
    }
    It "Contains only the two expected scripts plus JSON data islands" {
        $types = [regex]::Matches($script:html, '<script(?<a>[^>]*)>') | ForEach-Object { $_.Groups['a'].Value.Trim() }
        @($types | Where-Object { $_ -eq '' }).Count | Should -Be 1
        @($types | Where-Object { $_ -ne '' -and $_ -notmatch '^type="application/json"' }).Count | Should -Be 0
    }
    It "Does not link a non-https resourceLocation" {
        $script:html | Should -Not -Match 'javascript:'
        $script:html | Should -Not -Match 'Download baseline JSON'
    }
    It "Has no inline style or event-handler attributes and no external resources" {
        $markup = [regex]::Replace($script:html, '(?s)<(script|style)\b.*?</\1>', '')
        $names = foreach ($tag in [regex]::Matches($markup, '<[a-zA-Z][^>]*>')) {
            foreach ($a in [regex]::Matches($tag.Value, '\s([a-zA-Z_:][-a-zA-Z0-9_:.]*)(?:\s*=\s*(?:"[^"]*"|''[^'']*''|[^\s>]+))?')) { $a.Groups[1].Value.ToLowerInvariant() }
        }
        @($names | Where-Object { $_ -eq 'style' }).Count | Should -Be 0
        @($names | Where-Object { $_ -like 'on*' }).Count | Should -Be 0
        @($names | Where-Object { $_ -eq 'src' }).Count | Should -Be 0
        @([regex]::Matches($markup, 'href="([^"#][^"]*)"')).Count | Should -Be 0
    }
    It "Pins the script and style by SHA-256 in the CSP, matching the actual element text" {
        $csp = [regex]::Match($script:html, 'http-equiv="Content-Security-Policy" content="([^"]+)"').Groups[1].Value
        $js  = [regex]::Match($script:html, '(?s)<script>(.*?)</script>').Groups[1].Value
        $css = [regex]::Match($script:html, '(?s)<style>(.*?)</style>').Groups[1].Value
        $csp | Should -Match "default-src 'none'"
        $csp | Should -Match ([regex]::Escape("script-src '$(Get-Sha256Csp $js)'"))
        $csp | Should -Match ([regex]::Escape("style-src '$(Get-Sha256Csp $css)'"))
    }
    It "Is LF-normalized (required for the CSP hash to match in browsers)" {
        $script:html | Should -Not -Match "`r"
    }
    It "Shows the property comparison, counts and legacy ids" {
        $script:html | Should -Match 'id="drift-summary"'
        $script:html | Should -Match 'id="drifttable"'
        $script:html | Should -Match 'id="current-state"'
        $script:html | Should -Match 'id="currentTable"'
        $script:html | Should -Match 'data-st="changed"'
        $script:html | Should -Match 'data-status="Changed"'
        $script:html | Should -Match 'data-status="Added"'
    }
    It "Embeds CSV-parity rows for the client download" {
        $json = [regex]::Match($script:html, '(?s)<script type="application/json" id="utcm-drift-data">(.*?)</script>').Groups[1].Value
        $rows = ($json | ConvertFrom-Json).rows
        @($rows).Count | Should -Be 3
        $rows[0].PSObject.Properties.Name | Should -Be @('Id', 'DisplayName', 'Type', 'DriftType', 'NormalizedData')
    }
}

Describe "Snapshot report document" {
    It "Renders an explicit empty state for zero items" {
        InModuleScope UTCM.Tools {
            $html = Format-UTCMSnapshotReportHtml -Items @() -SnapshotName 'S' -SnapshotId 'bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee' -Created $null -Status 'partiallySuccessful' -GeneratedUtc 'now'
            $html | Should -Match 'This snapshot contains no items'
            $html | Should -Not -Match 'data-scope='
            $html | Should -Match 'partiallySuccessful'
        }
    }
    It "Groups by workload, keeps the legacy table id and encodes hostile values" {
        InModuleScope UTCM.Tools {
            $h = '"><img src=x onerror=alert(1)>'
            $items = @(
                [pscustomobject]@{ id = '1'; displayName = $h; type = 'microsoft.exchange.a'; data = [pscustomobject]@{ k = '</script>' } },
                [pscustomobject]@{ id = '2'; displayName = ''; type = 'microsoft.teams.b'; data = $null },
                [pscustomobject]@{ id = '3'; displayName = 'No type' }
            )
            $html = Format-UTCMSnapshotReportHtml -Items $items -SnapshotName $h -SnapshotId 'bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee' -Created '2026-02-08T10:00:00Z' -Status 'succeeded' -GeneratedUtc 'now'
            $html | Should -Not -Match ([regex]::Escape('<img src=x onerror'))
            $html | Should -Match 'id="snapTable"'
            @([regex]::Matches($html, 'class="wl-group"')).Count | Should -Be 3
            $html | Should -Match '\(unnamed\)'
            $html | Should -Match 'data-workload="unknown"'
        }
    }
}

Describe "Client script" {
    It "Is syntactically valid JavaScript (node --check)" -Skip:(-not (Get-Command node -ErrorAction SilentlyContinue)) {
        $js = InModuleScope UTCM.Tools { Get-UTCMReportScript }
        $tmp = Join-Path $TestDrive 'report.js'
        [System.IO.File]::WriteAllText($tmp, $js)
        $out = & node --check $tmp 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($out | Out-String)
    }
    It "Uses no inline styles, eval or network APIs" {
        $js = InModuleScope UTCM.Tools { Get-UTCMReportScript }
        $js | Should -Not -Match '\.style\.'
        $js | Should -Not -Match '\beval\s*\('
        $js | Should -Not -Match '\bfetch\s*\('
        $js | Should -Not -Match 'XMLHttpRequest'
        $js | Should -Not -Match 'innerHTML'
    }
}

Describe "Report generation performance" -Tag 'Performance' {
    It "Generates a 2,000 item snapshot document within budget" -Skip:(-not $env:UTCM_PERF) {
        InModuleScope UTCM.Tools {
            $items = 1..2000 | ForEach-Object { [pscustomobject]@{ id = "id-$_"; displayName = "Item $_"; type = "microsoft.entra.r$($_ % 7)"; data = [pscustomobject]@{ Name = "n$_"; Level = $_ } } }
            $t = (Measure-Command { $null = Format-UTCMSnapshotReportHtml -Items $items -SnapshotName 'p' -SnapshotId 'bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee' -Created $null -Status 'ok' -GeneratedUtc 'now' }).TotalSeconds
            $t | Should -BeLessThan 10
        }
    }
}
