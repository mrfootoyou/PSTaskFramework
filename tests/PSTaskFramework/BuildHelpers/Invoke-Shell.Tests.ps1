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

    Context 'Invoke-Shell' {
        It 'echoes command text and succeeds for zero exit code' {
            Mock Assert-AppExists -ModuleName BuildHelpers { 'pwsh' }

            Invoke-Shell -InformationAction Continue -- pwsh -NoLogo -NoProfile -Command 'exit 0'

            $global:LASTEXITCODE | Should -Be 0
            Should -Invoke -CommandName 'Write-Information' -ModuleName BuildHelpers -Times 1 -Exactly
        }

        It 'suppresses command echo when InformationAction Ignore is specified' {
            Mock Assert-AppExists -ModuleName BuildHelpers { 'pwsh' }

            $output = Invoke-Shell -- pwsh -NoLogo -NoProfile -Command 'exit 0' *>&1

            $output | Should -BeNullOrEmpty
        }

        It 'throws on non-zero exit code by default' {
            Mock Assert-AppExists -ModuleName BuildHelpers { 'pwsh' }

            { Invoke-Shell -ErrorAction Stop -- pwsh -NoLogo -NoProfile -Command 'exit 5' } | Should -Throw '*exit code 5*'
            $global:LASTEXITCODE | Should -Be 5
        }

        It 'accepts configured non-zero exit codes' {
            Mock Assert-AppExists -ModuleName BuildHelpers { 'pwsh' }

            Invoke-Shell -AllowedExitCodes @(0, 5) -- pwsh -NoLogo -NoProfile -Command 'exit 5'

            $global:LASTEXITCODE | Should -Be 5
        }

        It 'ignores non-zero exit codes when AllowedExitCodes is empty' {
            Mock Assert-AppExists -ModuleName BuildHelpers { 'pwsh' }

            Invoke-Shell -AllowedExitCodes @() -- pwsh -NoLogo -NoProfile -Command 'exit 5'

            $global:LASTEXITCODE | Should -Be 5
        }
    }
}
