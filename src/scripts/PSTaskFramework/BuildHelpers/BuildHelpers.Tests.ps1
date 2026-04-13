# SPDX-License-Identifier: Unlicense
# Source: http://github.com/mrfootoyou/pstaskframework
#Requires -Version 7.4

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseCompatibleCommands', '', Justification = 'Chokes on Pester keywords.')]
param()

Set-StrictMode -Version Latest

Describe 'PSTaskFramework.BuildHelpers Module' {
    BeforeAll {
        $modulePath = Join-Path $PSScriptRoot 'BuildHelpers.psm1'
        Import-Module $modulePath -Force
    }

    AfterAll {
        Remove-Module -Name BuildHelpers -ErrorAction Ignore
    }

    BeforeEach {
        $global:LASTEXITCODE = 0
        $Error.Clear()

        Mock -CommandName 'Write-Host' -ModuleName BuildHelpers -MockWith { } -Verbose:$false
    }

    Context 'Assert-AppExists' {
        It 'returns first discovered application source path with PassThru' {
            Mock -CommandName 'Get-Command' -ModuleName BuildHelpers -ParameterFilter { $Name -eq 'git' -and $CommandType -eq 'Application' -and $TotalCount -eq 1 } -MockWith {
                @(
                    [PSCustomObject]@{ Path = '/mock/bin/git' }
                )
            }

            $result = Assert-AppExists -AppPath 'git' -PassThru

            $result | Should -Be '/mock/bin/git'
            Should -Invoke -CommandName 'Get-Command' -ModuleName BuildHelpers -Times 1 -Exactly
        }

        It 'throws by default when app is missing' {
            Mock -CommandName 'Get-Command' -ModuleName BuildHelpers -MockWith { $null }

            { Assert-AppExists -AppPath 'missing-app' } | Should -Throw '*missing-app*not found*'
        }

        It 'includes AppTitle in error message when app is missing' {
            Mock -CommandName 'Get-Command' -ModuleName BuildHelpers -MockWith { $null }

            { Assert-AppExists -AppPath 'az' -AppTitle 'Azure CLI' } | Should -Throw '*Azure CLI (az) not found*'
        }

        It 'does not throw when ErrorAction Ignore is specified' {
            Mock -CommandName 'Get-Command' -ModuleName BuildHelpers -MockWith { $null }

            $result = Assert-AppExists -AppPath 'missing-app' -ErrorAction Ignore

            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Invoke-Shell' {
        It 'echoes command text and succeeds for zero exit code' {
            Mock -CommandName 'Assert-AppExists' -ModuleName BuildHelpers -MockWith { 'pwsh' }

            Invoke-Shell -- pwsh -NoLogo -NoProfile -Command 'exit 0'

            $global:LASTEXITCODE | Should -Be 0
            Should -Invoke -CommandName 'Write-Host' -ModuleName BuildHelpers -Times 1 -Exactly
        }

        It 'suppresses command echo when NoEcho is specified' {
            Mock -CommandName 'Assert-AppExists' -ModuleName BuildHelpers -MockWith { 'pwsh' }

            Invoke-Shell -NoEcho -- pwsh -NoLogo -NoProfile -Command 'exit 0'

            Should -Invoke -CommandName 'Write-Host' -ModuleName BuildHelpers -Times 0 -Exactly
        }

        It 'throws on non-zero exit code by default' {
            Mock -CommandName 'Assert-AppExists' -ModuleName BuildHelpers -MockWith { 'pwsh' }

            { Invoke-Shell -ErrorAction Stop -- pwsh -NoLogo -NoProfile -Command 'exit 5' } | Should -Throw '*exit code 5*'
            $global:LASTEXITCODE | Should -Be 5
        }

        It 'accepts configured non-zero exit codes' {
            Mock -CommandName 'Assert-AppExists' -ModuleName BuildHelpers -MockWith { 'pwsh' }

            Invoke-Shell -AllowedExitCodes @(0, 5) -- pwsh -NoLogo -NoProfile -Command 'exit 5'

            $global:LASTEXITCODE | Should -Be 5
        }
    }

    Context 'Test-Administrator' {
        It 'returns a boolean value on Windows' -Skip:(-not $IsWindows) {
            $result = Test-Administrator

            $result | Should -BeOfType ([bool])
        }

        It 'returns true for root uid on non-Windows' -Skip:$IsWindows {
            Mock -CommandName 'getUserId' -ModuleName BuildHelpers -MockWith { '0' }

            Test-Administrator | Should -BeTrue
        }

        It 'returns false for non-root uid on non-Windows' -Skip:$IsWindows {
            Mock -CommandName 'getUserId' -ModuleName BuildHelpers -MockWith { '1000' }

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
