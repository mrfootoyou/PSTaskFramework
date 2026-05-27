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
    BeforeAll {
        $ErrorActionPreference = 'Stop'
        $global:LASTEXITCODE = 0

        Import-Module "$PSScriptRoot/../../../src/scripts/PSTaskFramework/InstallHelpers/InstallHelpers" -Scope Local -Verbose:$false

        # Mock Install-Module to prevent actual module installation in a poorly written test.
        Mock Install-Module -ModuleName InstallHelpers {
            throw 'Install-Module called from unit test!'
        }

        # Mock Write-Information and Write-Verbose to prevent test output pollution.
        Mock Write-Information -ModuleName InstallHelpers { }
        Mock Write-Verbose -ModuleName InstallHelpers { }
    }

    BeforeEach {
        # Cache original PATH to restore after tests
        $script:originalPath = $env:PATH
    }
    AfterEach {
        # Restore original PATH after each test
        $env:PATH = $script:originalPath
    }

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
}
