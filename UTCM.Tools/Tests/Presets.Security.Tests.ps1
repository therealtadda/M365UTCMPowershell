Import-Module "$PSScriptRoot\..\UTCM.Tools.psd1" -Force

Describe 'Machine preset ownership and ACL trust' -Skip:(-not $IsWindows) {
    BeforeAll {
        $script:presetDir = Join-Path $TestDrive 'UTCM.Tools'
        New-Item -ItemType Directory -Path $script:presetDir | Out-Null
        $script:presetFile = Join-Path $script:presetDir 'resource-presets.json'
        '{"presets":{"TenantCore":["microsoft.entra.securitydefaults"]}}' | Set-Content -LiteralPath $script:presetFile
    }

    BeforeEach {
        Mock -ModuleName UTCM.Tools Get-Acl {
            $acl = [System.Security.AccessControl.DirectorySecurity]::new()
            $acl.SetSecurityDescriptorSddlForm('O:BAG:BAD:(A;;FA;;;SY)(A;;FA;;;BA)(A;;FR;;;BU)')
            return $acl
        }
    }

    It 'Accepts administrator-owned paths with only trusted write access' {
        InModuleScope UTCM.Tools -Parameters @{ Path = $script:presetFile } {
            Test-UTCMMachinePresetTrust -Path $Path | Should -BeTrue
        }
    }

    It 'Rejects an untrusted owner even when the file is not writable by other users' {
        Mock -ModuleName UTCM.Tools Get-Acl {
            $acl = [System.Security.AccessControl.DirectorySecurity]::new()
            $acl.SetSecurityDescriptorSddlForm('O:BUG:BAD:(A;;FA;;;SY)(A;;FA;;;BA)(A;;FR;;;BU)')
            return $acl
        }
        InModuleScope UTCM.Tools -Parameters @{ Path = $script:presetFile } {
            { Test-UTCMMachinePresetTrust -Path $Path } | Should -Throw '*must be owned by*'
        }
    }

    It 'Rejects write access for an untrusted principal on the file or containing directory' {
        Mock -ModuleName UTCM.Tools Get-Acl {
            $acl = [System.Security.AccessControl.DirectorySecurity]::new()
            $acl.SetSecurityDescriptorSddlForm('O:BAG:BAD:(A;;FA;;;SY)(A;;FA;;;BA)(A;OICI;FW;;;BU)')
            return $acl
        }
        InModuleScope UTCM.Tools -Parameters @{ Path = $script:presetFile } {
            { Test-UTCMMachinePresetTrust -Path $Path } | Should -Throw '*grants write*'
        }
    }

    It 'Rejects a writable containing directory even when the file ACL itself is trusted' {
        Mock -ModuleName UTCM.Tools Get-Acl {
            param($LiteralPath)
            $acl = [System.Security.AccessControl.DirectorySecurity]::new()
            $sddl = 'O:BAG:BAD:(A;;FA;;;SY)(A;;FA;;;BA)'
            if ($LiteralPath -eq $script:presetDir) { $sddl += '(A;;FW;;;BU)' }
            $acl.SetSecurityDescriptorSddlForm($sddl)
            return $acl
        }
        InModuleScope UTCM.Tools -Parameters @{ Path = $script:presetFile } {
            { Test-UTCMMachinePresetTrust -Path $Path } | Should -Throw '*grants write*'
        }
    }

    It 'Allows sibling creation on an ancestor, as on ProgramData, but rejects child-replacement rights' {
        $script:ancestor = Split-Path $script:presetDir -Parent
        Mock -ModuleName UTCM.Tools Get-Acl {
            param($LiteralPath)
            $acl = [System.Security.AccessControl.DirectorySecurity]::new()
            $sddl = 'O:BAG:BAD:(A;;FA;;;SY)(A;;FA;;;BA)'
            if ($LiteralPath -eq $script:ancestor) { $sddl += '(A;;0x6;;;BU)' }
            $acl.SetSecurityDescriptorSddlForm($sddl)
            return $acl
        }
        InModuleScope UTCM.Tools -Parameters @{ Path = $script:presetFile } {
            Test-UTCMMachinePresetTrust -Path $Path | Should -BeTrue
        }
        Mock -ModuleName UTCM.Tools Get-Acl {
            param($LiteralPath)
            $acl = [System.Security.AccessControl.DirectorySecurity]::new()
            $sddl = 'O:BAG:BAD:(A;;FA;;;SY)(A;;FA;;;BA)'
            if ($LiteralPath -eq $script:ancestor) { $sddl += '(A;;0x40;;;BU)' }
            $acl.SetSecurityDescriptorSddlForm($sddl)
            return $acl
        }
        InModuleScope UTCM.Tools -Parameters @{ Path = $script:presetFile } {
            { Test-UTCMMachinePresetTrust -Path $Path } | Should -Throw '*grants write*'
        }
    }

    It 'Rejects reparse points before trusting the target ACL' {
        Mock -ModuleName UTCM.Tools Get-Item {
            [pscustomobject]@{ FullName = $script:presetFile; PSIsContainer = $false; Attributes = [IO.FileAttributes]::ReparsePoint }
        } -ParameterFilter { $LiteralPath -eq $script:presetFile }
        InModuleScope UTCM.Tools -Parameters @{ Path = $script:presetFile } {
            { Test-UTCMMachinePresetTrust -Path $Path } | Should -Throw '*reparse point*'
        }
    }

    It 'Fails closed when ownership or permissions cannot be read' {
        Mock -ModuleName UTCM.Tools Get-Acl { throw 'Access denied reading ACL' }
        InModuleScope UTCM.Tools -Parameters @{ Path = $script:presetFile } {
            { Test-UTCMMachinePresetTrust -Path $Path } | Should -Throw '*Access denied*'
        }
    }
}

Describe 'Machine preset loading policy' -Skip:(-not $IsWindows) {
    BeforeAll {
        $script:originalProgramData = $env:ProgramData
        $script:machineRoot = Join-Path $TestDrive 'machine'
        $script:machineDir = Join-Path $script:machineRoot 'UTCM.Tools'
        New-Item -ItemType Directory -Path $script:machineDir -Force | Out-Null
        $script:machineFile = Join-Path $script:machineDir 'resource-presets.json'
        '{"presets":{"TenantCore":["microsoft.entra.securitydefaults"]}}' | Set-Content -LiteralPath $script:machineFile
    }
    BeforeEach { $env:ProgramData = $script:machineRoot }
    AfterEach { $env:ProgramData = $script:originalProgramData }

    It 'Rejects an untrusted machine preset before reading its JSON' {
        Mock -ModuleName UTCM.Tools Test-UTCMMachinePresetTrust { throw 'Untrusted machine preset' }
        Mock -ModuleName UTCM.Tools Get-Content { throw 'Must not read untrusted content' }
        InModuleScope UTCM.Tools -Parameters @{ Path = $script:machineFile } {
            { Get-UTCMResourcePresets -SearchPaths @($Path) } | Should -Throw '*Untrusted machine preset*'
        }
        Should -Invoke -ModuleName UTCM.Tools Get-Content -Times 0 -Exactly
    }

    It 'Retains trusted machine overrides and warns when they replace a built-in preset' {
        Mock -ModuleName UTCM.Tools Test-UTCMMachinePresetTrust { $true }
        InModuleScope UTCM.Tools -Parameters @{ Path = $script:machineFile } {
            $presets = Get-UTCMResourcePresets -SearchPaths @($Path) -WarningVariable warnings -WarningAction SilentlyContinue
            $presets['TenantCore'] | Should -Be @('microsoft.entra.securitydefaults')
            ($warnings -join ' ') | Should -Match "TenantCore.*overridden"
        }
        Should -Invoke -ModuleName UTCM.Tools Test-UTCMMachinePresetTrust -Times 1 -Exactly
    }

    It 'Does not impose machine-wide ownership requirements on a user-selected preset file' {
        $userFile = Join-Path $TestDrive 'user-presets.json'
        '{"presets":{"Custom":["microsoft.entra.securitydefaults"]}}' | Set-Content -LiteralPath $userFile
        Mock -ModuleName UTCM.Tools Test-UTCMMachinePresetTrust { throw 'Machine check must not apply' }
        InModuleScope UTCM.Tools -Parameters @{ Path = $userFile } {
            (Get-UTCMResourcePresets -SearchPaths @($Path))['Custom'] | Should -Be @('microsoft.entra.securitydefaults')
        }
        Should -Invoke -ModuleName UTCM.Tools Test-UTCMMachinePresetTrust -Times 0 -Exactly
    }
}
