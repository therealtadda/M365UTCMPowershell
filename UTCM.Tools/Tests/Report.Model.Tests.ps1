# Unit tests for the report model helpers (Private\Report.Model.ps1) and HtmlEncode.
Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe "HtmlEncode" {
    It "Is null and empty safe" {
        InModuleScope UTCM.Tools {
            HtmlEncode $null | Should -Be ''
            HtmlEncode ''    | Should -Be ''
        }
    }
    It "Encodes markup and quotes" {
        InModuleScope UTCM.Tools {
            HtmlEncode '<a href="x">&''</a>' | Should -Be '&lt;a href=&quot;x&quot;&gt;&amp;&#39;&lt;/a&gt;'
        }
    }
}

Describe "Get-UTCMWorkloadFromType" {
    It "Derives the workload or 'unknown'" {
        InModuleScope UTCM.Tools {
            Get-UTCMWorkloadFromType 'microsoft.exchange.sharedmailbox' | Should -Be 'exchange'
            Get-UTCMWorkloadFromType 'caPolicy' | Should -Be 'unknown'
            Get-UTCMWorkloadFromType $null      | Should -Be 'unknown'
            Get-UTCMWorkloadFromType ''         | Should -Be 'unknown'
        }
    }
}

Describe "Format-UTCMJsonPretty" {
    It "Pretty-prints valid JSON and passes invalid text through" {
        InModuleScope UTCM.Tools {
            (Format-UTCMJsonPretty '{"a":1}') | Should -Match '(?s)\{\s+"a": 1\s+\}'
            Format-UTCMJsonPretty 'not json' | Should -Be 'not json'
            Format-UTCMJsonPretty ''         | Should -Be ''
            Format-UTCMJsonPretty 'null'     | Should -Be 'null'
        }
    }
}

Describe "ConvertTo-UTCMDriftRecord" {
    It "Pairs a baseline row and a current row with the same id into one Changed record" {
        InModuleScope UTCM.Tools {
            $diff = @(
                [pscustomobject]@{ id='1'; displayName='A'; type='t'; SideIndicator='=>'; normalizedData='{"x":2}' },
                [pscustomobject]@{ id='1'; displayName='A'; type='t'; SideIndicator='<='; normalizedData='{"x":1}' }
            )
            $r = @(ConvertTo-UTCMDriftRecord -Diff $diff)
            $r.Count | Should -Be 1
            $r[0].Status | Should -Be 'Changed'
            $r[0].BaselineData | Should -Be '{"x":1}'
            $r[0].CurrentData  | Should -Be '{"x":2}'
            $r[0].RowIndexes.Count | Should -Be 2
        }
    }

    It "Classifies unpaired rows as Added or Missing" {
        InModuleScope UTCM.Tools {
            $diff = @(
                [pscustomobject]@{ id='1'; displayName='A'; type='t'; SideIndicator='=>'; normalizedData='{}' },
                [pscustomobject]@{ id='2'; displayName='B'; type='t'; SideIndicator='<='; normalizedData='{}' }
            )
            $r = @(ConvertTo-UTCMDriftRecord -Diff $diff)
            @($r | Where-Object Status -eq 'Added').Count   | Should -Be 1
            @($r | Where-Object Status -eq 'Missing').Count | Should -Be 1
            @($r | Where-Object Status -eq 'Changed').Count | Should -Be 0
        }
    }

    It "Does not pair rows whose key is ambiguous on one side" {
        InModuleScope UTCM.Tools {
            $diff = @(
                [pscustomobject]@{ id='1'; displayName='A'; type='t'; SideIndicator='=>'; normalizedData='{"x":2}' },
                [pscustomobject]@{ id='1'; displayName='A'; type='t'; SideIndicator='=>'; normalizedData='{"x":3}' },
                [pscustomobject]@{ id='1'; displayName='A'; type='t'; SideIndicator='<='; normalizedData='{"x":1}' }
            )
            $r = @(ConvertTo-UTCMDriftRecord -Diff $diff)
            $r.Count | Should -Be 3
            @($r | Where-Object Status -eq 'Changed').Count | Should -Be 0
        }
    }

    It "Falls back to type+displayName when id is empty, and tolerates null type" {
        InModuleScope UTCM.Tools {
            $diff = @(
                [pscustomobject]@{ id=''; displayName='A'; SideIndicator='=>'; normalizedData='{"x":2}' },
                [pscustomobject]@{ id=''; displayName='A'; SideIndicator='<='; normalizedData='{"x":1}' }
            )
            $r = @(ConvertTo-UTCMDriftRecord -Diff $diff)
            $r.Count | Should -Be 1
            $r[0].Status | Should -Be 'Changed'
            $r[0].Workload | Should -Be 'unknown'
        }
    }

    It "Returns an empty array for null or empty input" {
        InModuleScope UTCM.Tools {
            @(ConvertTo-UTCMDriftRecord -Diff $null).Count | Should -Be 0
            @(ConvertTo-UTCMDriftRecord -Diff @()).Count   | Should -Be 0
        }
    }
}
