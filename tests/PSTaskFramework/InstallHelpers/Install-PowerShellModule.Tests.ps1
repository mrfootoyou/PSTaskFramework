<#
.DESCRIPTION
    Unit tests for Install-PowerShellModule.
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

    Context 'Install-PowerShellModule' {
        It 'does not install modules that already satisfy minimum version' {
            Mock Get-Module -ModuleName InstallHelpers {
                [PSCustomObject]@{ Version = [version]'5.2.0' }
            }

            Mock Install-Module -ModuleName InstallHelpers { }

            Install-PowerShellModule -ModuleVersions @{ Pester = [version]'5.1.0' }

            Should -Invoke Install-Module -ModuleName InstallHelpers -Times 0 -Exactly
        }

        It 'installs modules when minimum version is missing' {
            $script:getModuleCallCount = 0

            Mock Get-Module -ModuleName InstallHelpers {
                $script:getModuleCallCount++
                if ($script:getModuleCallCount -ge 2) {
                    [PSCustomObject]@{ Version = [version]'5.1.0' }
                }
            }

            Mock Install-Module -ModuleName InstallHelpers { }

            Install-PowerShellModule -ModuleVersions @{ Pester = [version]'5.1.0' }

            Should -Invoke Install-Module -ModuleName InstallHelpers -Times 1 -Exactly
        }

        It 'writes an error when installation does not produce required version' {
            Mock Get-Module -ModuleName InstallHelpers { $null }
            Mock Install-Module -ModuleName InstallHelpers { }
            Mock Write-Error -ModuleName InstallHelpers { }

            Install-PowerShellModule -ModuleVersions @{ Pester = [version]'5.1.0' } -ErrorAction SilentlyContinue

            Should -Invoke Write-Error -ModuleName InstallHelpers -Times 1
        }
    }
}
