# Unit tests for the report property model: flatten, property diff, item normalization, preview, counts.
Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe "ConvertTo-UTCMFlatProperty / Get-UTCMPropertyDiff" {
    It "Flattens nested objects and arrays to dotted paths" {
        InModuleScope UTCM.Tools {
            $into = [ordered]@{}
            ConvertTo-UTCMFlatProperty -Value ('{"a":{"b":1},"l":[10,20],"e":[],"o":{}}' | ConvertFrom-Json) -Into $into
            $into['a.b'] | Should -Be '1'
            $into['l[0]'] | Should -Be '10'
            $into['l[1]'] | Should -Be '20'
            $into['e'] | Should -Be '[]'
            $into['o'] | Should -Be '{}'
        }
    }

    It "Reports changed, added, removed and unchanged properties (differences first)" {
        InModuleScope UTCM.Tools {
            $rows = Get-UTCMPropertyDiff -BaselineJson '{"s":"on","k":1,"gone":"x","same":"y"}' -CurrentJson '{"s":"off","k":1,"new":"z","same":"y"}'
            $byPath = @{}; foreach ($r in $rows) { $byPath[$r.Path] = $r }
            $byPath['s'].Status    | Should -Be 'changed'
            $byPath['gone'].Status | Should -Be 'removed'
            $byPath['new'].Status  | Should -Be 'added'
            $byPath['same'].Status | Should -Be 'unchanged'
            $byPath['k'].Status    | Should -Be 'unchanged'
            ($rows | Select-Object -Last 2 | ForEach-Object Status | Sort-Object -Unique) | Should -Be 'unchanged'
        }
    }

    It "Returns an empty array (not `$null) when nothing differs structurally" {
        InModuleScope UTCM.Tools {
            $rows = Get-UTCMPropertyDiff -BaselineJson '{"a":1}' -CurrentJson '{"a":1}'
            $null -ne $rows | Should -BeTrue
            @($rows | Where-Object Status -ne 'unchanged').Count | Should -Be 0
        }
    }

    It "Returns `$null when either side is not JSON" {
        InModuleScope UTCM.Tools {
            Get-UTCMPropertyDiff -BaselineJson 'not json' -CurrentJson '{}' | Should -BeNullOrEmpty
        }
    }

    It "Treats a missing side as all-added / all-removed without a bogus root row" {
        InModuleScope UTCM.Tools {
            $added = Get-UTCMPropertyDiff -BaselineJson $null -CurrentJson '{"a":1,"b":2}'
            @($added).Count | Should -Be 2
            @($added | Where-Object Status -ne 'added').Count | Should -Be 0
            $removed = Get-UTCMPropertyDiff -BaselineJson '{"a":1}' -CurrentJson $null
            @($removed).Count | Should -Be 1
            $removed[0].Status | Should -Be 'removed'
        }
    }

    It "Detects value-only changes that only differ by case" {
        InModuleScope UTCM.Tools {
            $rows = Get-UTCMPropertyDiff -BaselineJson '{"a":"Enabled"}' -CurrentJson '{"a":"enabled"}'
            $rows[0].Status | Should -Be 'changed'
        }
    }
}

Describe "Get-UTCMSortedReportItem" {
    It "Orders by lowercased name then id using ordinal comparison" {
        InModuleScope UTCM.Tools {
            $items = @(
                [pscustomobject]@{ DisplayName = 'b'; Id = '2' }, [pscustomobject]@{ DisplayName = 'B'; Id = '1' },
                [pscustomobject]@{ DisplayName = 'a'; Id = '9' }, [pscustomobject]@{ DisplayName = 'Item 10'; Id = '1' },
                [pscustomobject]@{ DisplayName = 'Item 2'; Id = '1' }, [pscustomobject]@{ DisplayName = ''; Id = 'z' },
                [pscustomobject]@{ DisplayName = 'ab'; Id = '1' }, [pscustomobject]@{ DisplayName = 'a'; Id = '10' })
            $sorted = Get-UTCMSortedReportItem $items
            (($sorted | ForEach-Object { "$($_.DisplayName)|$($_.Id)" }) -join ',') | Should -Be '|z,a|10,a|9,ab|1,B|1,b|2,Item 10|1,Item 2|1'
        }
    }
    It "Handles empty and single inputs" {
        InModuleScope UTCM.Tools {
            @(Get-UTCMSortedReportItem $null).Count | Should -Be 0
            @(Get-UTCMSortedReportItem @([pscustomobject]@{ DisplayName = 'x'; Id = '1' })).Count | Should -Be 1
        }
    }
}

Describe "ConvertTo-UTCMReportItem" {
    It "Normalizes hashtable and object items, 'data'/'properties' and 'type'/'resourceType'" {
        InModuleScope UTCM.Tools {
            $a = ConvertTo-UTCMReportItem @{ id = '1'; displayName = 'A'; type = 'microsoft.teams.x'; data = @{ k = 'v' } }
            $a.Id | Should -Be '1'; $a.Workload | Should -Be 'teams'; $a.Data.k | Should -Be 'v'
            $b = ConvertTo-UTCMReportItem ([pscustomobject]@{ resourceType = 'microsoft.exchange.y'; properties = [pscustomobject]@{ Identity = 'contoso' }; displayName = 'B' })
            $b.Id | Should -Be 'contoso'; $b.Type | Should -Be 'microsoft.exchange.y'; $b.Workload | Should -Be 'exchange'
        }
    }
    It "Tolerates null and missing fields" {
        InModuleScope UTCM.Tools {
            $c = ConvertTo-UTCMReportItem $null
            $c.Id | Should -Be ''; $c.Workload | Should -Be 'unknown'
        }
    }
}

Describe "Get-UTCMItemPreview / ConvertTo-UTCMUtcDisplay / Get-UTCMCountBy" {
    It "Previews the first scalar properties and truncates long values" {
        InModuleScope UTCM.Tools {
            $p = Get-UTCMItemPreview -Data ([pscustomobject]@{ A = 'x'; Nested = [pscustomobject]@{ z = 1 }; B = 2; C = ('y' * 100); D = 4 })
            $p | Should -Match '^A=x; B=2; C=y{40}\.\.\.$'
            Get-UTCMItemPreview -Data $null | Should -Be ''
        }
    }
    It "Formats dates as UTC and degrades gracefully" {
        InModuleScope UTCM.Tools {
            ConvertTo-UTCMUtcDisplay '2026-02-08T10:00:00Z' | Should -Be '2026-02-08 10:00:00 UTC'
            ConvertTo-UTCMUtcDisplay $null | Should -Be 'n/a'
            ConvertTo-UTCMUtcDisplay 'garbage' | Should -Be 'garbage'
        }
    }
    It "Counts by property, sorted by count then name" {
        InModuleScope UTCM.Tools {
            $rows = Get-UTCMCountBy -Property Workload -Items @(
                [pscustomobject]@{ Workload = 'b' }, [pscustomobject]@{ Workload = 'a' }, [pscustomobject]@{ Workload = 'b' }, [pscustomobject]@{ Workload = '' })
            $rows[0].Name | Should -Be 'b'; $rows[0].Count | Should -Be 2
            ($rows | ForEach-Object Name) | Should -Contain 'unknown'
        }
    }
}
