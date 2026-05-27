<#
.DESCRIPTION
    Unit tests for Get-PackageManager.
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

    Context 'Get-PackageManager' {
        It 'returns supported package managers for current platform with AllSupported' {
            $expected = @(
                if ($IsWindows) { 'winget'; 'choco' }
                if ($IsLinux) { 'apt'; 'dnf'; 'brew', 'brew:linux' }
                if ($IsMacOS) { 'brew', 'brew:macos' }
            )

            $result = @(Get-PackageManager -AllSupported)

            $result | Should -Be $expected
        }

        It 'returns only detected package managers when AllSupported is not specified' {
            Mock Get-Command -ModuleName InstallHelpers {
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
                $result | Should -Not -Contain 'winget'
            }
            if ($IsMacOS) {
                $result | Should -Contain 'brew'
                $result | Should -Contain 'brew:macos'
                $result | Should -Not -Contain 'winget'
            }
        }
    }
}
