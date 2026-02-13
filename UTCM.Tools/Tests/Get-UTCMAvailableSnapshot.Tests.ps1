# Updated tests for Get-UTCMAvailableSnapshot
Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe "Get-UTCMAvailableSnapshot" {
    BeforeAll {
        # Ensure we don't hit the network or real auth
        Mock -ModuleName UTCM.Tools Ensure-GraphConnection {}

        # Return a single page (no @odata.nextLink) with two snapshots
        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry {
            @{
                value = @(
                    @{ id='2'; displayName='Snap2'; createdDateTime='2026-02-08T10:00:00Z'; status='completed' },
                    @{ id='1'; displayName='Snap1'; createdDateTime='2026-02-07T10:00:00Z'; status='completed' }
                )
            }
        }
    }

    It "Returns snapshots sorted by createdDateTime desc" {
        $r = Get-UTCMAvailableSnapshot
        $r.Count              | Should -Be 2
        $r[0].id              | Should -Be '2'
        $r[1].id              | Should -Be '1'
    }

    It "Can return JSON when -AsJson is used" {
        $json = Get-UTCMAvailableSnapshot -AsJson
        $json | Should -Match '"id":\s*"2"'
    }
}
