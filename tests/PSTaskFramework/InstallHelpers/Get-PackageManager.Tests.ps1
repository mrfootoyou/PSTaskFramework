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
    . "$PSScriptRoot/setup.ps1"

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
