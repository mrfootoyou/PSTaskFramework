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

    Context 'Assert-AppExists' {
        It 'returns first discovered application source path with PassThru' {
            Mock Get-Command -ModuleName BuildHelpers -ParameterFilter { $Name -eq 'git' -and "$CommandType" -eq 'ExternalScript, Application' -and $TotalCount -eq 1 } {
                @(
                    [PSCustomObject]@{ Path = '/mock/bin/git' }
                )
            }

            $result = Assert-AppExists -AppPath 'git' -PassThru

            $result | Should -Be '/mock/bin/git'
            Should -Invoke -CommandName 'Get-Command' -ModuleName BuildHelpers -Times 1 -Exactly
        }

        It 'throws by default when app is missing' {
            Mock Get-Command -ModuleName BuildHelpers { $null }

            { Assert-AppExists -AppPath 'missing-app' } | Should -Throw '*missing-app*not found*'
        }

        It 'includes AppTitle in error message when app is missing' {
            Mock Get-Command -ModuleName BuildHelpers { $null }

            { Assert-AppExists -AppPath 'az' -AppTitle 'Azure CLI' } | Should -Throw '*Azure CLI (az) not found*'
        }

        It 'does not throw when ErrorAction Ignore is specified' {
            Mock Get-Command -ModuleName BuildHelpers { $null }

            $result = Assert-AppExists -AppPath 'missing-app' -ErrorAction Ignore

            $result | Should -BeNullOrEmpty
        }
    }
}
