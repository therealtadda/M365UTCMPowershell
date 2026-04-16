# Updated tests for Get-UTCMSnapshot (bind-time GUID validation)
Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe "Get-UTCMSnapshot (GUID validation at binding)" {
    BeforeAll {
        Mock -ModuleName UTCM.Tools Ensure-GraphConnection {}
        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry {
            [pscustomobject]@{ id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; displayName='Test Snap'; createdDateTime='2026-01-01T00:00:00Z'; status='succeeded'; createdBy='user@contoso.com'; resources=@('microsoft.exchange.sharedmailbox'); tenantId='tenant-1'; configurationItems = @(@{id='x'}) }
        }
    }

    It "Throws early on invalid SnapshotId" {
        { Get-UTCMSnapshot -SnapshotId 'not-a-guid' } | Should -Throw
    }

    It "Returns snapshot object with concise view on valid GUID" {
        $o = Get-UTCMSnapshot -SnapshotId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        $o.id | Should -Be 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        $o.status | Should -Not -BeNullOrEmpty
    }
}