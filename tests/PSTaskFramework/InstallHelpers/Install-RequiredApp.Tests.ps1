<#
.DESCRIPTION
    Unit tests for Install-RequiredApp.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4
# spell:ignore appx,winget,choco,mytool,Contoso,8wekyb3d8bbwe

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Mocked functions may have unused parameters.')]
param()

Describe 'PSTaskFramework.InstallHelpers Module' {
    . "$PSScriptRoot/setup.ps1"

    Context 'Install-RequiredApp' {
        It 'throws when no install information exists for an app' {
            { Install-RequiredApp -AppsToInstall @{ 'missing-app' = $null } } |
            Should -Throw '*No install information found for*'
        }

        It 'skips installation for apps that are already up to date' {
            Mock installWithWinget -ModuleName InstallHelpers { }

            $apps = [ordered]@{
                'mytool' = [ordered]@{
                    executable = ''
                    version    = '1.2.3'
                    isUpToDate = { $true }
                    winget     = 'Contoso.MyTool'
                }
            }

            Install-RequiredApp -AppsToInstall $apps

            Should -Invoke installWithWinget -ModuleName InstallHelpers -Times 0 -Exactly
        }

        It 'uses ordered app method precedence over package manager discovery order' {
            Mock Get-PackageManager -ModuleName InstallHelpers {
                @('winget', 'choco')
            }

            Mock installWithWinget -ModuleName InstallHelpers { }
            Mock installWithChocolatey -ModuleName InstallHelpers { }

            $apps = [ordered]@{
                'mytool' = [ordered]@{
                    executable = ''
                    isUpToDate = { $false }
                    choco      = 'mytool'
                    winget     = 'Contoso.MyTool'
                }
            }

            Install-RequiredApp -AppsToInstall $apps

            Should -Invoke installWithChocolatey -ModuleName InstallHelpers -Times 1 -Exactly
            Should -Invoke installWithWinget -ModuleName InstallHelpers -Times 0 -Exactly
        }

        It 'writes an error when no supported installation method is available' {
            Mock Get-PackageManager -ModuleName InstallHelpers { @('winget') }
            Mock Write-Error -ModuleName InstallHelpers { }

            $apps = [ordered]@{
                'mytool' = [ordered]@{
                    executable = ''
                    isUpToDate = { $false }
                    custom     = 'value'
                }
            }

            Install-RequiredApp -AppsToInstall $apps -ErrorAction SilentlyContinue

            Should -Invoke Write-Error -ModuleName InstallHelpers -Times 1
        }
    }

    Context 'installWithPackageManager' {
        It 'batches package ids and executes custom methods' {
            InModuleScope 'InstallHelpers' {
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
                    [PSCustomObject]@{
                        Name = 'pkg-d'
                        Info = @{
                            winget = [ordered]@{
                                PMArgs           = 'install', 'Contoso.D'
                                DoNotAppendArgs  = $true
                                AllowedExitCodes = 0, 3010
                            }
                        }
                    }
                    [PSCustomObject]@{
                        Name = 'pkg-a'
                        Info = @{ winget = 'Contoso.E' }
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

                $apps | Should -HaveCount 5
                $script:installCalls | Should -HaveCount 1
                $script:installCalls[0] | Should -Be ('Contoso.A', 'Contoso.E')
                $script:execCalls | Should -HaveCount 3
                $script:execCalls[0] | Should -Be ('upgrade', 'Contoso.B')
                $script:execCalls[1] | Should -Be ('install', 'Contoso.C')
                $script:execCalls[2] | Should -Be @('-PMArgs:', @('install', 'Contoso.D'), '-DoNotAppendArgs:', $true, '-AllowedExitCodes:', @(0, 3010))
            }
        }
        It 'works with hash table installation method' {
            InModuleScope 'InstallHelpers' {
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

        It 'throws for unsupported method type' {
            InModuleScope 'InstallHelpers' {
                $apps = @(
                    [PSCustomObject]@{
                        Name = 'bad-app'
                        Info = @{ winget = 42 }
                    }
                )

                { installWithPackageManager -AppsToInstall $apps -MethodName 'winget' -PackageManagerName 'Winget' -Execute {} -InstallPackages {} } | `
                    Should -Throw '*Unexpected installation type*'
            }
        }
    }

    Context 'installWithWinget' {
        It 'applies default flags and resets LASTEXITCODE' {
            InModuleScope 'InstallHelpers' {
                $script:wingetCalls = @()
                Mock Invoke-Shell {
                    param($Command, $CommandArgs, $AllowedExitCodes)
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

                Should -Invoke Invoke-Shell -Times 1 -Exactly
                $global:LASTEXITCODE | Should -Be 0
                $script:wingetCalls[0].Command | Should -BeExactly 'winget'
                $script:wingetCalls[0].CommandArgs | Should -BeExactly @('install', 'Git.Git', '--exact', '--source', 'winget', '--silent', '--force', '--accept-package-agreements', '--accept-source-agreements')
            }
        }
    }

    Context 'installWithChocolatey' {
        It 'applies default flags and resets LASTEXITCODE' {
            InModuleScope 'InstallHelpers' {
                $script:chocoCalls = @()
                Mock Test-Administrator { $true }
                Mock Invoke-Shell {
                    param($Command, $CommandArgs, $AllowedExitCodes)
                    $script:chocoCalls += , [PSCustomObject]@{
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
                        Info = @{ choco = 'git' }
                    }
                )

                installWithChocolatey -AppsToInstall $apps

                Should -Invoke Invoke-Shell -Times 1 -Exactly
                $global:LASTEXITCODE | Should -Be 0
                $script:chocoCalls[0].Command | Should -BeExactly 'choco'
                $script:chocoCalls[0].CommandArgs | Should -BeExactly @('upgrade', 'git', '--yes')
            }
        }

        It 'uses Start-Process when non-admin' {
            InModuleScope 'InstallHelpers' {
                $script:spCalls = @()
                Mock Test-Administrator { $false }
                Mock Assert-AppExists { 'c:\path\to\choco.exe' }
                Mock Start-Process {
                    param($FilePath, $ArgumentList, $Verb)
                    $script:spCalls += , [PSCustomObject]@{
                        FilePath     = $FilePath
                        ArgumentList = @($ArgumentList)
                        Verb         = $Verb
                    }
                    [PSCustomObject]@{ ExitCode = 2 } # nothing to do
                }

                $apps = @(
                    [PSCustomObject]@{
                        Name = 'foo-app'
                        Info = @{ choco = 'foo' }
                    }
                )

                installWithChocolatey -AppsToInstall $apps

                Should -Invoke Start-Process -Times 1 -Exactly
                $global:LASTEXITCODE | Should -Be 0
                $script:spCalls[0].FilePath | Should -BeExactly 'c:\path\to\choco.exe'
                $script:spCalls[0].ArgumentList | Should -BeExactly @('upgrade', 'foo', '--yes')
            }
        }
    }

    Context 'installWithAPT' {
        It 'runs update once then installs all packages with yes flag' {
            InModuleScope 'InstallHelpers' {
                $script:aptCalls = @()
                Mock Invoke-Shell {
                    param($Command, $CommandArgs, $AllowedExitCodes)
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

                Should -Invoke Invoke-Shell -Times 2 -Exactly
                $script:aptCalls[0].Command | Should -BeExactly 'sudo'
                $script:aptCalls[0].CommandArgs | Should -BeExactly @('apt-get', 'update', '-y')
                $script:aptCalls[1].Command | Should -BeExactly 'sudo'
                $script:aptCalls[1].CommandArgs | Should -BeExactly @('apt-get', 'install', 'git', 'curl', '--yes')
            }
        }
    }

    Context 'installWithDNF' {
        It 'installs all packages with yes flag' {
            InModuleScope 'InstallHelpers' {
                $script:dnfCalls = @()
                Mock Invoke-Shell {
                    param($Command, $CommandArgs, $AllowedExitCodes)
                    $script:dnfCalls += , [PSCustomObject]@{
                        Command     = $Command
                        CommandArgs = @($CommandArgs)
                    }
                    $global:LASTEXITCODE = 0
                }

                $apps = @(
                    [PSCustomObject]@{ Name = 'git'; Info = @{ dnf = 'git' } }
                    [PSCustomObject]@{ Name = 'curl'; Info = @{ dnf = 'curl' } }
                )

                installWithDNF -AppsToInstall $apps

                Should -Invoke Invoke-Shell -Times 1 -Exactly
                $script:dnfCalls[0].Command | Should -BeExactly 'sudo'
                $script:dnfCalls[0].CommandArgs | Should -BeExactly @('dnf', 'install', 'git', 'curl', '-y')
            }
        }
    }

    Context 'installWithBrew' {
        It 'installs all packages with yes flag' {
            InModuleScope 'InstallHelpers' {
                $script:brewCalls = @()
                Mock Invoke-Shell {
                    param($Command, $CommandArgs, $AllowedExitCodes)
                    $script:brewCalls += , [PSCustomObject]@{
                        Command     = $Command
                        CommandArgs = @($CommandArgs)
                    }
                    if ($CommandArgs[0] -eq 'list' -and $CommandArgs[1] -eq 'git') {
                        $global:LASTEXITCODE = 1 # not installed
                    }
                    elseif ($CommandArgs[0] -eq 'upgrade' -and $CommandArgs[1] -eq 'curl') {
                        $global:LASTEXITCODE = 1 # nothing to upgrade
                    }
                    else {
                        $global:LASTEXITCODE = 0
                    }
                }

                $apps = @(
                    [PSCustomObject]@{ Name = 'git'; Info = @{ brew = 'git' } }
                    [PSCustomObject]@{ Name = 'curl'; Info = @{ brew = 'curl' } }
                )

                installWithBrew -AppsToInstall $apps

                Should -Invoke Invoke-Shell -Times 6 -Exactly
                $script:brewCalls[0].Command | Should -BeExactly 'brew'
                $script:brewCalls[0].CommandArgs | Should -BeExactly @('list', 'git')
                $script:brewCalls[1].Command | Should -BeExactly 'brew'
                $script:brewCalls[1].CommandArgs | Should -BeExactly @('update')
                $script:brewCalls[2].Command | Should -BeExactly 'brew'
                $script:brewCalls[2].CommandArgs | Should -BeExactly @('install', 'git', '--quiet')
                $script:brewCalls[3].Command | Should -BeExactly 'brew'
                $script:brewCalls[3].CommandArgs | Should -BeExactly @('list', 'curl')
                $script:brewCalls[4].Command | Should -BeExactly 'brew'
                $script:brewCalls[4].CommandArgs | Should -BeExactly @('upgrade', 'curl', '--quiet')
                $script:brewCalls[5].Command | Should -BeExactly 'brew'
                $script:brewCalls[5].CommandArgs | Should -BeExactly @('list', 'curl')
            }
        }
    }

    Context 'installWithScript' {
        It 'runs script method for each app' {
            InModuleScope 'InstallHelpers' {
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
    }
}
