Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe 'Reviewed snapshot resource presets' {
    BeforeAll {
        $script:presetPath = Join-Path (Get-Module UTCM.Tools).ModuleBase 'Presets\resource-presets.json'
        $script:allowPath = Join-Path (Get-Module UTCM.Tools).ModuleBase 'Presets\supported-resource-types.json'
        $script:allResources = @(Get-UTCMPreset -Name AllSupported -Raw -SearchPaths @($script:presetPath))
        $script:excluded = @(
            'microsoft.entra.attributeset'
            'microsoft.entra.groupsnamingpolicy'
            'microsoft.entra.groupssettings'
            'microsoft.exchange.addressbookpolicy'
            'microsoft.exchange.addresslist'
            'microsoft.exchange.applicationaccesspolicy'
            'microsoft.exchange.clientaccessrule'
            'microsoft.exchange.eopprotectionpolicyrule'
            'microsoft.exchange.externalinoutlook'
            'microsoft.exchange.globaladdresslist'
            'microsoft.exchange.managementroleentry'
            'microsoft.exchange.offlineaddressbook'
            'microsoft.exchange.sweeprule'
            'microsoft.intune.accountprotectionlocaladministratorpasswordsolutionpolicy'
            'microsoft.intune.asrrulespolicywindows10'
            'microsoft.intune.devicecleanuprule'
            'microsoft.securityandcompliance.auditconfigurationpolicy'
            'microsoft.securityandcompliance.autosensitivitylabelrule'
            'microsoft.securityandcompliance.dlpcompliancerule'
            'microsoft.securityandcompliance.sensitivitylabel'
            'microsoft.teams.channel'
            'microsoft.teams.channeltab'
            'microsoft.teams.onlinevoicemailusersettings'
            'microsoft.teams.orgwideappsettings'
            'microsoft.teams.team'
            'microsoft.teams.usercallingsettings'
            'microsoft.teams.userpolicyassignment'
        )
    }

    BeforeEach {
        Mock -ModuleName UTCM.Tools Ensure-GraphConnection { throw 'Preset inspection must not authenticate.' }
        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry { throw 'Preset inspection must not call Graph.' }
        Mock -ModuleName UTCM.Tools Get-UTCMPresetSearchPaths {
            Join-Path (Get-Module UTCM.Tools).ModuleBase 'Presets\resource-presets.json'
        }
    }

    It 'Lists the new preset alongside all existing presets' {
        $names = @(Get-UTCMPreset)
        $names.Count | Should -Be 10
        $names | Should -Contain 'AllSupported'
        $names | Should -Contain 'TenantCore'
        $names | Should -Contain 'TeamsCore+Voice'
    }

    It 'Returns the named wrapper and raw resources using ordered-dictionary lookup' {
        $preset = Get-UTCMPreset -Name AllSupported
        $preset.Name | Should -Be 'AllSupported'
        $preset.Resources.Count | Should -Be 244
        @(Get-UTCMPreset -Name allsupported -Raw).Count | Should -Be 244
        @(Get-UTCMPreset -Name TenantCore -Raw).Count | Should -Be 15
    }

    It 'Contains exactly 244 unique canonical identifiers' {
        $script:allResources.Count | Should -Be 244
        @($script:allResources | Select-Object -Unique).Count | Should -Be 244
        foreach ($resource in $script:allResources) {
            $resource | Should -Match '^microsoft\.(entra|exchange|intune|securityandcompliance|teams)\.[a-z0-9]+$'
        }
    }

    It 'Has the reviewed per-workload coverage' {
        $expected = @{ entra = 36; exchange = 66; intune = 67; securityandcompliance = 24; teams = 51 }
        foreach ($workload in $expected.Keys) {
            @($script:allResources | Where-Object { $_.Split('.')[1] -eq $workload }).Count |
                Should -Be $expected[$workload]
        }
    }

    It 'Keeps the comprehensive preset and warn-only allow-list identical' {
        $allowed = (Get-Content -LiteralPath $script:allowPath -Raw | ConvertFrom-Json).resourceTypes
        $allowed.Count | Should -Be 244
        @(Compare-Object $script:allResources $allowed).Count | Should -Be 0
        InModuleScope UTCM.Tools -Parameters @{ Resources = $script:allResources } {
            Test-UTCMResourceTypes -Resources $Resources -WarningAction Stop | Should -BeTrue
        }
    }

    It 'Excludes every explicitly rejected type' {
        $script:excluded.Count | Should -Be 27
        foreach ($resource in $script:excluded) {
            $script:allResources | Should -Not -Contain $resource
        }
    }

    It 'Documents exactly the 27 exclusions and links the document from README' {
        $root = Split-Path (Get-Module UTCM.Tools).ModuleBase -Parent
        $document = Get-Content -LiteralPath (Join-Path $root 'UNSUPPORTED-RESOURCE-TYPES.md') -Raw
        $documented = @([regex]::Matches($document, '`(microsoft\.[a-z0-9.]+)`') |
            ForEach-Object { $_.Groups[1].Value })
        $documented.Count | Should -Be 27
        @(Compare-Object $script:excluded $documented).Count | Should -Be 0
        $readme = Get-Content -LiteralPath (Join-Path $root 'README.md') -Raw
        $readme | Should -Match '\]\(UNSUPPORTED-RESOURCE-TYPES\.md\)'
        $document | Should -Match 'https://learn\.microsoft\.com/en-us/graph/api/configurationbaseline-createsnapshot'
    }

    It 'Retains existing preset coverage without validation warnings' {
        $counts = @{
            ExchangeCore = 2; EntraCore = 5; TeamsCore = 3; IntuneCore = 2; SecCompCore = 3
            TenantCore = 15; 'TeamsCore+Voice' = 13; 'IntuneCore+Roles' = 4; SecurityCore = 6
        }
        foreach ($name in $counts.Keys) {
            $resources = @(Get-UTCMPreset -Name $name -Raw)
            $resources.Count | Should -Be $counts[$name]
            InModuleScope UTCM.Tools -Parameters @{ Resources = $resources } {
                Test-UTCMResourceTypes -Resources $Resources -WarningAction Stop | Should -BeTrue
            }
        }
    }

    It 'Reports unknown preset names clearly instead of a dictionary method error' {
        { Get-UTCMPreset -Name DoesNotExist } | Should -Throw "*Preset 'DoesNotExist' not found*AllSupported*"
    }

    It 'Does not silently substitute the tiny fallback for a missing AllSupported preset' {
        $missing = Join-Path $TestDrive 'missing-presets.json'
        { Get-UTCMPreset -Name AllSupported -Raw -SearchPaths @($missing) } |
            Should -Throw "*Preset 'AllSupported' not found*"
    }

    It 'Retains explicit-resource precedence over a named preset' {
        InModuleScope UTCM.Tools {
            $resources = @(Resolve-UTCMResources -Resources @('microsoft.entra.securitydefaults') -Preset AllSupported)
            $resources.Count | Should -Be 1
            $resources[0] | Should -Be 'microsoft.entra.securitydefaults'
        }
    }

    It 'Retains warning-only validation for unknown explicit resource types' {
        InModuleScope UTCM.Tools {
            $valid = Test-UTCMResourceTypes -Resources @('microsoft.example.unknown') -WarningVariable warnings -WarningAction SilentlyContinue
            $valid | Should -BeFalse
            ($warnings -join ' ') | Should -Match 'microsoft.example.unknown'
        }
    }

    It 'Allows a user-selected override of AllSupported with a visible warning' {
        $override = Join-Path $TestDrive 'user-presets.json'
        '{"presets":{"AllSupported":["microsoft.entra.securitydefaults"]}}' |
            Set-Content -LiteralPath $override
        $resources = @(Get-UTCMPreset -Name AllSupported -Raw -SearchPaths @($script:presetPath, $override) -WarningVariable warnings -WarningAction SilentlyContinue)
        $resources.Count | Should -Be 1
        $resources[0] | Should -Be 'microsoft.entra.securitydefaults'
        ($warnings -join ' ') | Should -Match "AllSupported.*overridden"
    }

    It 'Offers AllSupported through the existing snapshot argument completer' {
        $inputScript = 'New-UTCMSnapshot -Preset All'
        $completion = TabExpansion2 -inputScript $inputScript -cursorColumn $inputScript.Length
        $completion.CompletionMatches.CompletionText | Should -Contain 'AllSupported'
    }
}

Describe 'AllSupported snapshot requests' {
    BeforeEach {
        Mock -ModuleName UTCM.Tools Ensure-GraphConnection {}
        Mock -ModuleName UTCM.Tools Write-Log {}
        Mock -ModuleName UTCM.Tools Start-Sleep {}
        Mock -ModuleName UTCM.Tools Get-UTCMPresetSearchPaths {
            Join-Path (Get-Module UTCM.Tools).ModuleBase 'Presets\resource-presets.json'
        }
        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -ParameterFilter { $Method -eq 'POST' } {
            @{ id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' }
        }
        Mock -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -ParameterFilter { $Method -eq 'GET' } {
            @{ id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; status = 'succeeded' }
        }
    }

    It 'Sends the complete reviewed list in one explicit AllSupported creation request' {
        $job = New-UTCMSnapshot -Preset AllSupported -DisplayName 'All Supported Baseline'
        $job.status | Should -Be 'succeeded'
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -Times 1 -Exactly -ParameterFilter {
            $allowed = (Get-Content -LiteralPath (Join-Path (Get-Module UTCM.Tools).ModuleBase 'Presets\supported-resource-types.json') -Raw | ConvertFrom-Json).resourceTypes
            $Method -eq 'POST' -and $Uri -match '/v1\.0/admin/configurationManagement/configurationSnapshots/createSnapshot$' -and
                $Body.resources.Count -eq 244 -and @(Compare-Object $Body.resources $allowed).Count -eq 0
        }
    }

    It 'Keeps the exact TenantCore resource list as the default creation request' {
        New-UTCMSnapshot -DisplayName 'Default Baseline' | Out-Null
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -Times 1 -Exactly -ParameterFilter {
            $expected = @(
                'microsoft.entra.securitydefaults', 'microsoft.entra.namedlocationpolicy',
                'microsoft.entra.authorizationpolicy', 'microsoft.entra.tenantdetails',
                'microsoft.entra.conditionalaccesspolicy', 'microsoft.exchange.sharedmailbox',
                'microsoft.exchange.transportrule', 'microsoft.teams.meetingpolicy',
                'microsoft.teams.messagingpolicy', 'microsoft.teams.appsetuppolicy',
                'microsoft.intune.devicecategory', 'microsoft.intune.policysets',
                'microsoft.securityandcompliance.labelpolicy',
                'microsoft.securityandcompliance.dlpcompliancepolicy',
                'microsoft.securityandcompliance.protectionalert'
            )
            $Method -eq 'POST' -and $Body.resources.Count -eq 15 -and
                @(Compare-Object $Body.resources $expected).Count -eq 0
        }
    }

    It 'Does not submit an AllSupported job when ShouldProcess declines creation' {
        New-UTCMSnapshot -Preset AllSupported -DisplayName 'Preview Baseline' -WhatIf
        Should -Invoke -ModuleName UTCM.Tools Invoke-GraphRequestWithRetry -Times 0 -Exactly
    }
}
