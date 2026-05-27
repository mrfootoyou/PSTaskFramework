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
}
