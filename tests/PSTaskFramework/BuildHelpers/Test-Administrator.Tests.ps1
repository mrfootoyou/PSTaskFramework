<#
.DESCRIPTION
    Unit tests for BuildHelpers module.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4

param()

Describe 'PSTaskFramework.BuildHelpers Module' {
    . "$PSScriptRoot/setup.ps1"

    Context 'Test-Administrator' {
        It 'returns a boolean value on Windows' -Skip:(-not $IsWindows) {
            $result = Test-Administrator

            $result | Should -BeOfType ([bool])
        }

        It 'returns true for root uid on non-Windows' -Skip:$IsWindows {
            Mock getUserId -ModuleName BuildHelpers { '0' }

            Test-Administrator | Should -BeTrue
        }

        It 'returns false for non-root uid on non-Windows' -Skip:$IsWindows {
            Mock getUserId -ModuleName BuildHelpers { '1000' }

            Test-Administrator | Should -BeFalse
        }

        It 'matches Windows principal admin evaluation' -Skip:(-not $IsWindows) {
            $expected = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

            Test-Administrator | Should -Be $expected
        }

        It 'matches Unix uid root evaluation' -Skip:$IsWindows {
            $expected = (id -u) -eq 0

            Test-Administrator | Should -Be $expected
        }
    }
}
