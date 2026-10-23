Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe "Comparison completeness and original requested scope" {
    BeforeAll {
        Mock -ModuleName UTCM.Tools Ensure-GraphConnection {}
    }

    BeforeEach {
        $script:safeBaseline = [pscustomobject]@{
            id = '00000000-0000-0000-0000-000000000000'
            status = 'succeeded'
            resources = @('microsoft.entra.securitydefaults', 'microsoft.exchange.transportrule')
            errorDetails = @()
            configurationItems = @(
                [pscustomobject]@{ id = 'existing'; displayName = 'Existing'; type = 'microsoft.entra.securitydefaults'; data = @{ Enabled = $true } }
            )
        }
        $script:safeComparison = [pscustomobject]@{
            id = '11111111-1111-1111-1111-111111111111'
            status = 'succeeded'
            resources = @('microsoft.entra.securitydefaults', 'microsoft.exchange.transportrule')
            errorDetails = @()
            configurationItems = @(
                [pscustomobject]@{ id = 'existing'; displayName = 'Existing'; type = 'microsoft.entra.securitydefaults'; data = @{ Enabled = $true } },
                [pscustomobject]@{ id = 'new-rule'; displayName = 'New rule'; type = 'microsoft.exchange.transportrule'; data = @{ Enabled = $true } }
            )
        }
        Mock -ModuleName UTCM.Tools Get-UTCMSnapshot {
            if ($SnapshotId -eq '00000000-0000-0000-0000-000000000000') { $script:safeBaseline }
            else { $script:safeComparison }
        }
        Mock -ModuleName UTCM.Tools Get-UTCMCurrentStateSnapshot { $script:safeComparison }
    }

    It "Selects current-state mode for a baseline-only call and includes previously empty resource types" {
        $diff = @(Compare-UTCMConfiguration -BaselineSnapshotId $script:safeBaseline.id)
        $diff.Count | Should -Be 1
        $diff[0].id | Should -Be 'new-rule'
        $diff[0].SideIndicator | Should -Be '=>'
        Should -Invoke -ModuleName UTCM.Tools Get-UTCMCurrentStateSnapshot -Times 1 -Exactly -ParameterFilter {
            $Resources.Count -eq 2 -and $Resources -contains 'microsoft.exchange.transportrule'
        }
    }

    It "Keeps 244 requested types when only 138 baseline types returned instances" {
        $catalogue = Get-Content -LiteralPath "$PSScriptRoot\..\Presets\resource-presets.json" -Raw | ConvertFrom-Json
        $script:safeBaseline.resources = @($catalogue.presets.AllSupported)
        $script:safeBaseline.configurationItems = @(foreach ($index in 0..137) {
            [pscustomobject]@{ id="synthetic-$index"; displayName="Synthetic $index"; type=$catalogue.presets.AllSupported[$index]; data=@{Enabled=$true} }
        })
        $script:safeComparison.resources = $script:safeBaseline.resources
        $script:safeComparison.configurationItems = @($script:safeBaseline.configurationItems) +
            @([pscustomobject]@{ id='new-rule'; displayName='New rule'; type=$catalogue.presets.AllSupported[243]; data=@{Enabled=$true} })
        $diff = @(Compare-UTCMConfiguration -BaselineSnapshotId $script:safeBaseline.id)
        $diff.Count | Should -Be 1
        $diff[0].id | Should -Be 'new-rule'
        $diff[0].SideIndicator | Should -Be '=>'
        Should -Invoke -ModuleName UTCM.Tools Get-UTCMCurrentStateSnapshot -Times 1 -Exactly -ParameterFilter {
            $Resources.Count -eq 244 -and @(Compare-Object $Resources $script:safeBaseline.resources).Count -eq 0
        }
    }

    It "Compares an empty successful baseline using its original requested resources" {
        $script:safeBaseline.configurationItems = @()
        $diff = @(Compare-UTCMConfiguration -BaselineSnapshotId $script:safeBaseline.id)
        $diff.Count | Should -Be 2
        @($diff | Where-Object SideIndicator -ne '=>').Count | Should -Be 0
        Should -Invoke -ModuleName UTCM.Tools Get-UTCMCurrentStateSnapshot -Times 1 -Exactly -ParameterFilter { $Resources.Count -eq 2 }
    }

    It "Reports baseline-only rows when the successful comparison snapshot is empty" {
        $script:safeComparison.configurationItems = @()
        $diff = @(Compare-UTCMConfiguration -BaselineSnapshotId $script:safeBaseline.id -CompareSnapshotId $script:safeComparison.id)
        $diff.Count | Should -Be 1
        $diff[0].SideIndicator | Should -Be '<='
    }

    It "Returns no differences when both successful snapshots are empty" {
        $script:safeBaseline.configurationItems = @()
        $script:safeComparison.configurationItems = @()
        @(Compare-UTCMConfiguration -BaselineSnapshotId $script:safeBaseline.id -CompareSnapshotId $script:safeComparison.id).Count | Should -Be 0
    }

    It "Refuses to infer scope from populated records when requested metadata is missing" {
        $script:safeBaseline.PSObject.Properties.Remove('resources')
        { Compare-UTCMConfiguration -BaselineSnapshotId $script:safeBaseline.id -AllowPartialComparison } |
            Should -Throw '*original requested resources*'
        Should -Invoke -ModuleName UTCM.Tools Get-UTCMCurrentStateSnapshot -Times 0 -Exactly
    }

    It "Rejects malformed requested resource metadata before creating a current snapshot" {
        $script:safeBaseline.resources = @('microsoft.entra.securitydefaults', '')
        { Compare-UTCMConfiguration -BaselineSnapshotId $script:safeBaseline.id } |
            Should -Throw '*invalid original requested resource identifier*'
        Should -Invoke -ModuleName UTCM.Tools Get-UTCMCurrentStateSnapshot -Times 0 -Exactly
    }

    It "Rejects a partial baseline before downloads or a new current-state job and retains diagnostic metadata" {
        $script:safeBaseline.status = 'partiallySuccessful'
        $script:safeBaseline.errorDetails = @('Synthetic baseline extraction denied')
        $failure = { Compare-UTCMConfiguration -BaselineSnapshotId $script:safeBaseline.id } |
            Should -Throw '*partiallySuccessful*AllowPartialComparison*Synthetic baseline extraction denied*' -PassThru
        $failure.TargetObject.errorDetails | Should -Contain 'Synthetic baseline extraction denied'
        Should -Invoke -ModuleName UTCM.Tools Get-UTCMSnapshot -Times 0 -Exactly -ParameterFilter { $IncludeItems }
        Should -Invoke -ModuleName UTCM.Tools Get-UTCMCurrentStateSnapshot -Times 0 -Exactly
    }

    It "Rejects a partial baseline for fixed-snapshot comparisons too" {
        $script:safeBaseline.status = 'partiallySuccessful'
        { Compare-UTCMConfiguration -BaselineSnapshotId $script:safeBaseline.id -CompareSnapshotId $script:safeComparison.id } |
            Should -Throw '*Baseline*partiallySuccessful*'
        Should -Invoke -ModuleName UTCM.Tools Get-UTCMSnapshot -Times 0 -Exactly -ParameterFilter { $IncludeItems }
    }

    It "Rejects a partial fixed comparison before either artifact is downloaded" {
        $script:safeComparison.status = 'partiallySuccessful'
        { Compare-UTCMConfiguration -BaselineSnapshotId $script:safeBaseline.id -CompareSnapshotId $script:safeComparison.id } |
            Should -Throw '*Comparison*partiallySuccessful*'
        Should -Invoke -ModuleName UTCM.Tools Get-UTCMSnapshot -Times 0 -Exactly -ParameterFilter { $IncludeItems }
    }

    It "Rejects a partial current-state result instead of returning normal missing differences" {
        $script:safeComparison.status = 'partiallySuccessful'
        $script:safeComparison.configurationItems = @()
        { Compare-UTCMConfiguration -BaselineSnapshotId $script:safeBaseline.id } |
            Should -Throw '*Comparison*partiallySuccessful*'
        Should -Invoke -ModuleName UTCM.Tools Get-UTCMCurrentStateSnapshot -Times 1 -Exactly
    }

    It "Revalidates the loaded <Role> snapshot rather than trusting only earlier metadata" -ForEach @(
        @{ Role = 'Baseline'; Id = '00000000-0000-0000-0000-000000000000' }
        @{ Role = 'Comparison'; Id = '11111111-1111-1111-1111-111111111111' }
    ) {
        $script:loadedPartialSnapshot = [pscustomobject]@{
            id = $Id; status = 'partiallySuccessful'; resources = $script:safeBaseline.resources
            errorDetails = @('Synthetic later partial extraction'); configurationItems = @()
        }
        Mock -ModuleName UTCM.Tools Get-UTCMSnapshot {
            if ($IncludeItems -and $SnapshotId -eq $script:loadedPartialSnapshot.id) { $script:loadedPartialSnapshot }
            elseif ($SnapshotId -eq $script:safeBaseline.id) { $script:safeBaseline }
            else { $script:safeComparison }
        }
        if ($Role -eq 'Baseline') {
            { Compare-UTCMConfiguration -BaselineSnapshotId $script:safeBaseline.id } | Should -Throw '*Synthetic later partial extraction*'
            Should -Invoke -ModuleName UTCM.Tools Get-UTCMCurrentStateSnapshot -Times 0 -Exactly
        } else {
            { Compare-UTCMConfiguration -BaselineSnapshotId $script:safeBaseline.id -CompareSnapshotId $script:safeComparison.id } |
                Should -Throw '*Synthetic later partial extraction*'
        }
    }

    It "Warns about actual loaded partial data even when earlier metadata said succeeded" {
        $script:loadedPartialSnapshot = [pscustomobject]@{
            id = $script:safeComparison.id; status = 'partiallySuccessful'; resources = $script:safeComparison.resources
            errorDetails = @('Synthetic later partial extraction'); configurationItems = @()
        }
        Mock -ModuleName UTCM.Tools Get-UTCMSnapshot {
            if ($IncludeItems -and $SnapshotId -eq $script:loadedPartialSnapshot.id) { $script:loadedPartialSnapshot }
            elseif ($SnapshotId -eq $script:safeBaseline.id) { $script:safeBaseline }
            else { $script:safeComparison }
        }
        $warnings = @()
        Compare-UTCMConfiguration -BaselineSnapshotId $script:safeBaseline.id -CompareSnapshotId $script:safeComparison.id `
            -AllowPartialComparison -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null
        ($warnings -join ' ') | Should -Match 'INCOMPLETE COMPARISON.*Synthetic later partial extraction'
    }

    It "Warns prominently when partial data is explicitly compared, retaining the existing diff shape" {
        $script:safeComparison.status = 'partiallySuccessful'
        $script:safeComparison.errorDetails = @('Synthetic comparison extraction denied')
        $script:safeComparison.configurationItems = @()
        $warnings = @()
        $diff = @(Compare-UTCMConfiguration -BaselineSnapshotId $script:safeBaseline.id -CompareSnapshotId $script:safeComparison.id `
            -AllowPartialComparison -WarningVariable warnings -WarningAction SilentlyContinue)
        $diff.Count | Should -Be 1
        $diff[0].SideIndicator | Should -Be '<='
        $diff[0].PSObject.Properties.Name | Should -Be @('id','displayName','type','normalizedData','SideIndicator')
        ($warnings -join ' ') | Should -Match 'INCOMPLETE COMPARISON'
        ($warnings -join ' ') | Should -Match 'Synthetic comparison extraction denied'
        ($warnings -join ' ') | Should -Match 'empty diff does not prove absence of drift'
    }

    It "Warns even when the explicit partial comparison returns an empty diff" {
        $script:safeComparison.status = 'partiallySuccessful'
        $script:safeComparison.configurationItems = $script:safeBaseline.configurationItems
        $warnings = @()
        @(Compare-UTCMConfiguration -BaselineSnapshotId $script:safeBaseline.id -CompareSnapshotId $script:safeComparison.id `
            -AllowPartialComparison -WarningVariable warnings -WarningAction SilentlyContinue).Count | Should -Be 0
        ($warnings -join ' ') | Should -Match 'INCOMPLETE COMPARISON'
    }

    It "Propagates the override for current-state creation and warns for both partial jobs" {
        $script:safeBaseline.status = 'partiallySuccessful'
        $script:safeComparison.status = 'partiallySuccessful'
        $warnings = @()
        Compare-UTCMConfiguration -BaselineSnapshotId $script:safeBaseline.id -AllowPartialComparison `
            -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null
        @($warnings).Count | Should -Be 2
        Should -Invoke -ModuleName UTCM.Tools Get-UTCMCurrentStateSnapshot -Times 1 -Exactly -ParameterFilter {
            $AllowPartialComparison -and $Resources.Count -eq 2
        }
    }

    It "Does not let the override admit a <Status> snapshot" -ForEach @(
        @{ Status = 'running' }
        @{ Status = 'notStarted' }
        @{ Status = 'failed' }
        @{ Status = 'unknownFutureValue' }
    ) {
        $script:safeBaseline.status = $Status
        { Compare-UTCMConfiguration -BaselineSnapshotId $script:safeBaseline.id -AllowPartialComparison } |
            Should -Throw '*comparison requires succeeded snapshots*'
        Should -Invoke -ModuleName UTCM.Tools Get-UTCMCurrentStateSnapshot -Times 0 -Exactly
    }
}
