# SPDX-License-Identifier: Unlicense
# Source: http://github.com/mrfootoyou/pstaskframework
# spell:ignore appx,winget,choco
#Requires -Version 7.4

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseCompatibleCommands', '', Justification = 'Chokes on Pester keywords.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Mocked functions may have unused parameters.')]
param()

Set-StrictMode -Version Latest

Describe 'install-helpers.psm1' {
    BeforeAll {
        $script:addedInstallModuleStub = $false
        if (-not (Get-Command Install-Module -ErrorAction Ignore)) {
            function global:Install-Module { param() }
            $script:addedInstallModuleStub = $true
        }

        $modulePath = Join-Path $PSScriptRoot 'install-helpers.psm1'
        Import-Module $modulePath -Force -Scope Local
    }

    BeforeEach {
        $global:LASTEXITCODE = 0
        $Error.Clear()
    }

    AfterAll {
        Remove-Module -Name install-helpers -ErrorAction Ignore

        if ($script:addedInstallModuleStub) {
            Remove-Item Function:\Install-Module -ErrorAction Ignore
        }
    }

    Context 'Get-PackageManager' {
        It 'returns supported package managers for current platform with AllSupported' {
            $result = @(Get-PackageManager -AllSupported | Select-Object -Unique)

            $expected = @(
                if ($IsWindows) { 'winget'; 'choco' }
                if ($IsLinux) { 'apt'; 'dnf'; 'brew', 'brew:linux' }
                if ($IsMacOS) { 'brew', 'brew:macos' }
            )

            $result | Should -Be $expected
        }

        It 'returns only detected package managers when AllSupported is not specified' {
            Mock -CommandName Get-Command -ModuleName install-helpers -MockWith {
                param($Name)
                if ($Name -in @('winget', 'brew')) {
                    [PSCustomObject]@{ Name = $Name }
                }
            }

            $result = @(Get-PackageManager)

            if ($IsWindows) {
                $result | Should -Be @('winget')
                $result | Should -Not -Contain 'brew'
            }
            if ($IsLinux) {
                $result | Should -Contain 'brew'
                $result | Should -Contain 'brew:linux'
            }
            if ($IsMacOS) {
                $result | Should -Contain 'brew'
                $result | Should -Contain 'brew:macos'
            }
        }

        It 'returns expected AllSupported list on Windows' -Skip:(-not $IsWindows) {
            $result = @(Get-PackageManager -AllSupported)

            $result | Should -Be @('winget', 'choco')
        }

        It 'returns expected AllSupported list on Linux' -Skip:(-not $IsLinux) {
            $result = @(Get-PackageManager -AllSupported)

            $result | Should -Be @('apt', 'dnf', 'brew', 'brew:linux')
        }

        It 'returns expected AllSupported list on macOS' -Skip:(-not $IsMacOS) {
            $result = @(Get-PackageManager -AllSupported)

            $result | Should -Be @('brew', 'brew:macos')
        }

        It 'returns no package managers for unsupported platforms' -Skip:($IsWindows -or $IsLinux -or $IsMacOS) {
            $result = @(Get-PackageManager -AllSupported)

            $result | Should -BeEmpty
        }
    }

    Context 'Install-PackageManager' {
        It 'installs explicit package manager and returns its name' {
            Mock -CommandName installWinget -ModuleName install-helpers -MockWith { }

            $result = @(Install-PackageManager -PackageManager 'winget')

            $result | Should -Contain 'winget'
            Should -Invoke -CommandName installWinget -ModuleName install-helpers -Times 1 -Exactly
        }

        It 'tries alternates for any and succeeds when a later manager installs' {
            Mock -CommandName Get-PackageManager -ModuleName install-helpers -ParameterFilter { $AllSupported } -MockWith {
                @('winget', 'choco')
            }

            Mock -CommandName installWinget -ModuleName install-helpers -MockWith {
                throw 'winget failed'
            }

            Mock -CommandName installChocolatey -ModuleName install-helpers -MockWith { }

            $result = @(
                Install-PackageManager -PackageManager 'any' `
                    -ErrorAction SilentlyContinue `
                    -WarningAction SilentlyContinue `
                    -WarningVariable installWarnings
            )
            $warningMessages = @($installWarnings).Message

            $result | Should -Contain 'choco'
            Should -Invoke -CommandName installWinget -ModuleName install-helpers -Times 1 -Exactly
            Should -Invoke -CommandName installChocolatey -ModuleName install-helpers -Times 1 -Exactly
            $warningMessages | Should -Contain 'winget failed'
        }

        It 'writes an error when any cannot install any supported package manager' {
            Mock -CommandName Get-PackageManager -ModuleName install-helpers -ParameterFilter { $AllSupported } -MockWith {
                @('winget', 'choco')
            }

            Mock -CommandName installWinget -ModuleName install-helpers -MockWith {
                throw 'winget failed'
            }

            Mock -CommandName installChocolatey -ModuleName install-helpers -MockWith {
                throw 'choco failed'
            }

            Mock -CommandName Write-Error -ModuleName install-helpers -MockWith { }

            $null = Install-PackageManager -PackageManager 'any' `
                -ErrorAction SilentlyContinue `
                -WarningAction SilentlyContinue `
                -WarningVariable installWarnings
            $warningMessages = @($installWarnings).Message

            Should -Invoke -CommandName Write-Error -ModuleName install-helpers -Times 1
            $warningMessages | Should -Contain 'winget failed'
            $warningMessages | Should -Contain 'choco failed'
        }
    }

    Context 'Install-RequiredApp' {
        It 'throws when no install information exists for an app' {
            { Install-RequiredApp -AppsToInstall @{ 'missing-app' = $null } } |
            Should -Throw '*No install information found for*'
        }

        It 'skips installation for apps that are already up to date' {
            Mock -CommandName installWithWinget -ModuleName install-helpers -MockWith { }

            $apps = [ordered]@{
                'mytool' = [ordered]@{
                    executable = ''
                    version    = '1.2.3'
                    isUpToDate = { $true }
                    winget     = 'Contoso.MyTool'
                }
            }

            Install-RequiredApp -AppsToInstall $apps

            Should -Invoke -CommandName installWithWinget -ModuleName install-helpers -Times 0 -Exactly
        }

        It 'uses ordered app method precedence over package manager discovery order' {
            Mock -CommandName Get-PackageManager -ModuleName install-helpers -MockWith {
                @('winget', 'choco')
            }

            Mock -CommandName installWithWinget -ModuleName install-helpers -MockWith { }
            Mock -CommandName installWithChocolatey -ModuleName install-helpers -MockWith { }

            $apps = [ordered]@{
                'mytool' = [ordered]@{
                    executable = ''
                    isUpToDate = { $false }
                    choco      = 'mytool'
                    winget     = 'Contoso.MyTool'
                }
            }

            Install-RequiredApp -AppsToInstall $apps

            Should -Invoke -CommandName installWithChocolatey -ModuleName install-helpers -Times 1 -Exactly
            Should -Invoke -CommandName installWithWinget -ModuleName install-helpers -Times 0 -Exactly
        }

        It 'writes an error when no supported installation method is available' {
            Mock -CommandName Get-PackageManager -ModuleName install-helpers -MockWith { @('winget') }
            Mock -CommandName Write-Error -ModuleName install-helpers -MockWith { }

            $apps = [ordered]@{
                'mytool' = [ordered]@{
                    executable = ''
                    isUpToDate = { $false }
                    custom     = 'value'
                }
            }

            Install-RequiredApp -AppsToInstall $apps -ErrorAction SilentlyContinue

            Should -Invoke -CommandName Write-Error -ModuleName install-helpers -Times 1
        }
    }

    Context 'Internal helper functions' {
        It 'installWithPackageManager batches package ids and executes custom methods' {
            InModuleScope 'install-helpers' {
                $script:execCalls = @()
                $script:installCalls = @()

                $apps = @(
                    [PSCustomObject]@{
                        Name = 'pkg-a'
                        Info = @{ winget = 'Contoso.A' }
                    }
                    [PSCustomObject]@{
                        Name = 'pkg-b'
                        Info = @{ winget = [string[]]@('upgrade', 'Contoso.B') }
                    }
                    [PSCustomObject]@{
                        Name = 'pkg-c'
                        Info = @{
                            winget = {
                                param($appName, $appInfo, $execute)
                                & $execute -- install 'Contoso.C'
                            }
                        }
                    }
                )

                $execute = { $script:execCalls += , @($args) }
                $installPackages = { $script:installCalls += , @($args) }

                installWithPackageManager `
                    -AppsToInstall $apps `
                    -MethodName 'winget' `
                    -PackageManagerName 'Winget' `
                    -Execute $execute `
                    -InstallPackages $installPackages

                $script:execCalls.Count | Should -Be 2
                $script:installCalls.Count | Should -Be 1
                $script:installCalls[0] | Should -Contain 'Contoso.A'
            }
        }

        It 'installWithPackageManager throws for unsupported method type' {
            InModuleScope 'install-helpers' {
                $apps = @(
                    [PSCustomObject]@{
                        Name = 'bad-app'
                        Info = @{ winget = 42 }
                    }
                )

                { installWithPackageManager -AppsToInstall $apps -MethodName 'winget' -PackageManagerName 'Winget' -Execute {} -InstallPackages {} } |
                Should -Throw '*Unexpected installation type*'
            }
        }

        It 'installWithWinget applies default flags and resets LASTEXITCODE' {
            InModuleScope 'install-helpers' {
                $script:wingetCalls = @()
                Mock -CommandName Invoke-Shell -ModuleName install-helpers -MockWith {
                    param($Command, $CommandArgs, $NoEcho, $AllowedExitCodes)
                    $script:wingetCalls += , [PSCustomObject]@{
                        Command          = $Command
                        CommandArgs      = @($CommandArgs)
                        AllowedExitCodes = @($AllowedExitCodes)
                    }
                    $global:LASTEXITCODE = 0
                }

                $global:LASTEXITCODE = 99
                $apps = @(
                    [PSCustomObject]@{
                        Name = 'git'
                        Info = @{ winget = 'Git.Git' }
                    }
                )

                installWithWinget -AppsToInstall $apps

                Should -Invoke -CommandName Invoke-Shell -ModuleName install-helpers -Times 1 -Exactly
                $global:LASTEXITCODE | Should -Be 0
                $script:wingetCalls[0].Command | Should -BeExactly 'winget'
                $script:wingetCalls[0].CommandArgs | Should -Contain 'install'
                $script:wingetCalls[0].CommandArgs | Should -Contain '--exact'
                $script:wingetCalls[0].CommandArgs | Should -Contain '--silent'
                $script:wingetCalls[0].CommandArgs | Should -Contain '--force'
                $script:wingetCalls[0].CommandArgs | Should -Contain '--accept-package-agreements'
                $script:wingetCalls[0].CommandArgs | Should -Contain '--accept-source-agreements'
            }
        }

        It 'installWithAPT runs update once then installs all packages with yes flag' {
            InModuleScope 'install-helpers' {
                $script:aptCalls = @()
                Mock -CommandName Invoke-Shell -ModuleName install-helpers -MockWith {
                    param($Command, $CommandArgs, $NoEcho, $AllowedExitCodes)
                    $script:aptCalls += , [PSCustomObject]@{
                        Command     = $Command
                        CommandArgs = @($CommandArgs)
                    }
                    $global:LASTEXITCODE = 0
                }

                $apps = @(
                    [PSCustomObject]@{ Name = 'git'; Info = @{ apt = 'git' } }
                    [PSCustomObject]@{ Name = 'curl'; Info = @{ apt = 'curl' } }
                )

                installWithAPT -AppsToInstall $apps

                Should -Invoke -CommandName Invoke-Shell -ModuleName install-helpers -Times 2 -Exactly
                $script:aptCalls[0].Command | Should -BeExactly 'sudo'
                $script:aptCalls[0].CommandArgs | Should -Be @('apt-get', 'update', '-y')
                $script:aptCalls[1].Command | Should -BeExactly 'sudo'
                $script:aptCalls[1].CommandArgs | Should -Contain 'apt-get'
                $script:aptCalls[1].CommandArgs | Should -Contain 'install'
                $script:aptCalls[1].CommandArgs | Should -Contain '--yes'
                $script:aptCalls[1].CommandArgs | Should -Contain 'git'
                $script:aptCalls[1].CommandArgs | Should -Contain 'curl'
            }
        }

        It 'installWithScript runs script method for each app' {
            InModuleScope 'install-helpers' {
                $script:ran = @()
                $apps = @(
                    [PSCustomObject]@{
                        Name = 'app1'
                        Info = @{ script = { param($appName, $appInfo) $script:ran += $appName } }
                    }
                    [PSCustomObject]@{
                        Name = 'app2'
                        Info = @{ script = { param($appName, $appInfo) $script:ran += $appName } }
                    }
                )

                installWithScript -AppsToInstall $apps -MethodName 'script'

                $script:ran | Should -Be @('app1', 'app2')
            }
        }

        It 'isPowerShellUpToDate caches latest version response and avoids a second web request' {
            InModuleScope 'install-helpers' {
                Mock -CommandName Invoke-WebRequest -ModuleName install-helpers -MockWith {
                    [PSCustomObject]@{
                        StatusCode = 302
                        Headers    = @{ Location = @("https://github.com/PowerShell/PowerShell/releases/tag/v$($PSVersionTable.PSVersion)") }
                    }
                }

                $info = [ordered]@{
                    NextVersionCheck = [DateTime]::Now.AddMinutes(-1)
                }

                (& isPowerShellUpToDate 'powershell' $info) | Should -BeTrue
                (& isPowerShellUpToDate 'powershell' $info) | Should -BeTrue

                Should -Invoke -CommandName Invoke-WebRequest -ModuleName install-helpers -Times 1 -Exactly
                $info.LatestVersion.ToString() | Should -BeExactly $PSVersionTable.PSVersion.ToString()
            }
        }
    }

    Context 'Install-PowerShellModule' {
        It 'does not install modules that already satisfy minimum version' {
            Mock -CommandName Get-Module -ModuleName install-helpers -MockWith {
                [PSCustomObject]@{ Version = [version]'5.2.0' }
            }

            Mock -CommandName Install-Module -ModuleName install-helpers -MockWith { }

            Install-PowerShellModule -ModuleVersions @{ Pester = [version]'5.1.0' }

            Should -Invoke -CommandName Install-Module -ModuleName install-helpers -Times 0 -Exactly
        }

        It 'installs modules when minimum version is missing' {
            $script:getModuleCallCount = 0

            Mock -CommandName Get-Module -ModuleName install-helpers -MockWith {
                $script:getModuleCallCount++
                if ($script:getModuleCallCount -ge 2) {
                    [PSCustomObject]@{ Version = [version]'5.1.0' }
                }
            }

            Mock -CommandName Install-Module -ModuleName install-helpers -MockWith { }

            Install-PowerShellModule -ModuleVersions @{ Pester = [version]'5.1.0' }

            Should -Invoke -CommandName Install-Module -ModuleName install-helpers -Times 1 -Exactly
        }

        It 'writes an error when installation does not produce required version' {
            Mock -CommandName Get-Module -ModuleName install-helpers -MockWith { $null }
            Mock -CommandName Install-Module -ModuleName install-helpers -MockWith { }
            Mock -CommandName Write-Error -ModuleName install-helpers -MockWith { }

            Install-PowerShellModule -ModuleVersions @{ Pester = [version]'5.1.0' } -ErrorAction SilentlyContinue

            Should -Invoke -CommandName Write-Error -ModuleName install-helpers -Times 1
        }
    }
}
