<#
.DESCRIPTION
    Unit tests for Install-PackageManager.
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

    Context 'Install-PackageManager' {
        It 'installs explicit package manager and returns its name' {
            Mock installWinget -ModuleName InstallHelpers { }

            $result = @(Install-PackageManager -PackageManager 'winget')

            $result | Should -Contain 'winget'
            Should -Invoke installWinget -ModuleName InstallHelpers -Times 1 -Exactly
        }

        It 'tries alternates for any and succeeds when a later manager installs' {
            Mock Get-PackageManager -ModuleName InstallHelpers -ParameterFilter { $AllSupported } {
                @('winget', 'choco')
            }

            Mock installWinget -ModuleName InstallHelpers {
                throw 'winget failed'
            }

            Mock installChocolatey -ModuleName InstallHelpers { }

            $result = @(
                Install-PackageManager -PackageManager 'any' `
                    -ErrorAction SilentlyContinue `
                    -WarningAction SilentlyContinue `
                    -WarningVariable installWarnings
            )
            $warningMessages = @($installWarnings).Message

            $result | Should -Contain 'choco'
            Should -Invoke installWinget -ModuleName InstallHelpers -Times 1 -Exactly
            Should -Invoke installChocolatey -ModuleName InstallHelpers -Times 1 -Exactly
            $warningMessages | Should -Contain 'winget failed'
        }

        It 'writes an error when any cannot install any supported package manager' {
            Mock Get-PackageManager -ModuleName InstallHelpers -ParameterFilter { $AllSupported } {
                @('winget', 'choco')
            }

            Mock installWinget -ModuleName InstallHelpers {
                throw 'winget failed'
            }

            Mock installChocolatey -ModuleName InstallHelpers {
                throw 'choco failed'
            }

            Mock Write-Error -ModuleName InstallHelpers { }

            $null = Install-PackageManager -PackageManager 'any' `
                -ErrorAction SilentlyContinue `
                -WarningAction SilentlyContinue `
                -WarningVariable installWarnings
            $warningMessages = @($installWarnings).Message

            Should -Invoke Write-Error -ModuleName InstallHelpers -Times 1
            $warningMessages | Should -Contain 'winget failed'
            $warningMessages | Should -Contain 'choco failed'
        }
    }

    Context 'refreshEnvironment' {
        It 'refreshes the PATH variable' -Skip:(-not $IsWindows) {
            $env:PATH += ";$TestDrive"

            InModuleScope 'InstallHelpers' {
                refreshEnvironment
            }

            $env:PATH -split ';' | Should -Not -Contain $TestDrive
        }
    }


    Context 'installWinget' {
        It 'should throw on non-Windows' -Skip:$IsWindows {
            InModuleScope 'InstallHelpers' {
                { installWinget } | Should -Throw '*not supported*'
            }
        }

        It 'should not install when already installed' -Skip:(-not $IsWindows) {
            InModuleScope 'InstallHelpers' {
                Mock -Verifiable Get-Command -ParameterFilter { $name -eq 'winget' } {
                    @{Path = 'C:\winget.exe' }
                }

                installWinget

                Should -InvokeVerifiable
            }
        }

        It 'should install on Windows with refreshed path' -Skip:(-not $IsWindows) {
            InModuleScope 'InstallHelpers' {
                $script:wingetInstalled = $false
                Mock -Verifiable Get-Command -param { $name -eq 'winget' } { $script:wingetInstalled ? @{Path = 'C:\winget.exe' } : $null }
                Mock -Verifiable Get-Command -param { $name -eq 'Get-AppxPackage' } { @{ } }
                Mock -Verifiable Get-AppxPackage { [PSCustomObject]@{ PackageFamilyName = 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' } }
                Mock -Verifiable Add-AppxPackage { }
                Mock -Verifiable refreshEnvironment { $script:wingetInstalled = $true }

                installWinget

                Should -InvokeVerifiable
                Should -Invoke Get-Command -Times 4 -Exactly
            }
        }

        It 'should fail when Get-AppXPackage not found' -Skip:(-not $IsWindows) {
            InModuleScope 'InstallHelpers' {
                Mock -Verifiable Get-Command -ParameterFilter { $name -eq 'winget' } { $null }
                Mock -Verifiable Get-Command -ParameterFilter { $name -eq 'Get-AppxPackage' } { $null }

                { installWinget } | Should -Throw '*Your version of Windows may not support Winget*'

                Should -InvokeVerifiable
            }
        }

        It 'should fail when App Installer package not found' -Skip:(-not $IsWindows) {
            InModuleScope 'InstallHelpers' {
                Mock -Verifiable Get-Command -ParameterFilter { $name -eq 'winget' } { $null }
                Mock -Verifiable Get-Command -ParameterFilter { $name -eq 'Get-AppxPackage' } { @{} }
                Mock -Verifiable Get-AppxPackage { }

                { installWinget } | Should -Throw '*Install ''App Installer'' from the Microsoft Store*'

                Should -InvokeVerifiable
            }
        }

        It 'should fail when Add-AppxPackage fails' -Skip:(-not $IsWindows) {
            InModuleScope 'InstallHelpers' {
                Mock -Verifiable Get-Command -ParameterFilter { $name -eq 'winget' } { $null }
                Mock -Verifiable Get-Command -ParameterFilter { $name -eq 'Get-AppxPackage' } { @{} }
                Mock -Verifiable Get-AppxPackage { [PSCustomObject]@{ PackageFamilyName = 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' } }
                Mock -Verifiable Add-AppxPackage { Write-Error "failed" }

                { installWinget } | Should -Throw '*failed to re-register ''App Installer'' package*'

                Should -InvokeVerifiable
            }
        }
    }

    Context 'installChocolatey' {
        It 'should throw on non-Windows' -Skip:$IsWindows {
            InModuleScope 'InstallHelpers' {
                { installChocolatey } | Should -Throw '*not supported*'
            }
        }

        It 'should not install when already installed' -Skip:(-not $IsWindows) {
            InModuleScope 'InstallHelpers' {
                Mock -Verifiable Get-Command -ParameterFilter { $name -eq 'choco' } {
                    @{Path = 'C:\choco.exe' }
                }

                installChocolatey

                Should -InvokeVerifiable
            }
        }

        It 'should install on Windows' -Skip:(-not $IsWindows) {
            InModuleScope 'InstallHelpers' {
                $script:installed = $false
                Mock -Verifiable Get-Command -ParameterFilter { $name -eq 'choco' } {
                    $script:installed ? @{Path = 'C:\choco.exe' } : $null
                }
                Mock -Verifiable Get-ExecutionPolicy { 'Restricted' }
                Mock -Verifiable Set-ExecutionPolicy -param { $Scope -eq 'Process' -and $ExecutionPolicy -eq 'RemoteSigned' -and $Force } { }
                Mock -Verifiable Invoke-WebRequest -param { $Uri -like 'https://*chocolatey.org/install.ps1' } {
                    [PSCustomObject]@{ Content = 'choco install script' }
                }
                Mock -Verifiable Invoke-Expression -param { $Command -eq 'choco install script' } { }
                Mock -Verifiable refreshEnvironment { $script:installed = $true }

                installChocolatey

                Should -InvokeVerifiable
            }
        }
    }

    Context 'installApt' {
        It 'should throw on Windows' -Skip:($IsMacOS -or $IsLinux) {
            InModuleScope 'InstallHelpers' {
                { installApt } | Should -Throw '*not supported*'
            }
        }

        It 'should succeed when apt-get already installed' -Skip:(-not ($IsMacOS -or $IsLinux)) {
            InModuleScope 'InstallHelpers' {
                Mock -Verifiable Get-Command -param { $name -eq 'apt-get' } { @{Path = "/usr/bin/apt-get" } }

                installApt

                Should -InvokeVerifiable
            }
        }

        It 'should fail when apt-get is not installed' -Skip:(-not ($IsMacOS -or $IsLinux)) {
            InModuleScope 'InstallHelpers' {
                Mock -Verifiable Get-Command -param { $name -eq 'apt-get' } { $null }

                { installApt } | Should -Throw '*Manually install APT and try again*'

                Should -InvokeVerifiable
            }
        }
    }

    Context 'installDNF' {
        It 'should throw on Windows' -Skip:($IsMacOS -or $IsLinux) {
            InModuleScope 'InstallHelpers' {
                { installDNF } | Should -Throw '*not supported*'
            }
        }

        It 'should succeed when dnf already installed' -Skip:(-not ($IsMacOS -or $IsLinux)) {
            InModuleScope 'InstallHelpers' {
                Mock -Verifiable Get-Command -param { $name -eq 'dnf' } { @{Path = "/usr/bin/dnf" } }

                installDNF

                Should -InvokeVerifiable
            }
        }

        It 'should fail when dnf is not installed' -Skip:(-not ($IsMacOS -or $IsLinux)) {
            InModuleScope 'InstallHelpers' {
                Mock -Verifiable Get-Command -param { $name -eq 'dnf' } { $null }

                { installDNF } | Should -Throw '*Manually install DNF and try again*'

                Should -InvokeVerifiable
            }
        }
    }

    Context 'installBrew' {
        It 'should throw on Windows' -Skip:($IsMacOS -or $IsLinux) {
            InModuleScope 'InstallHelpers' {
                { installBrew } | Should -Throw '*not supported*'
            }
        }

        It 'should succeed when brew already installed' -Skip:(-not ($IsMacOS -or $IsLinux)) {
            InModuleScope 'InstallHelpers' {
                Mock -Verifiable Get-Command -param { $name -eq 'brew' } { @{Path = "/usr/bin/brew" } }

                installBrew

                Should -InvokeVerifiable
            }
        }

        It 'should fail when brew is not installed' -Skip:(-not ($IsMacOS -or $IsLinux)) {
            InModuleScope 'InstallHelpers' {
                Mock -Verifiable Get-Command -param { $name -eq 'brew' } { $null }

                { installBrew } | Should -Throw '*Manually install Homebrew*'

                Should -InvokeVerifiable
            }
        }
    }
}
