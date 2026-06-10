<#
.DESCRIPTION
    Unit tests for Secrets module.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4

[Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'test code')]
param()

Describe 'PSTaskFramework.Secrets Module' {
    . "$PSScriptRoot/setup.ps1"

    Context 'Read-Secret' {
        BeforeEach {
            # Mock isContinuousIntegration to return false by default
            Mock isContinuousIntegration -ModuleName Secrets { $false }

            # Mock Read-Host to avoid hanging tests
            Mock Read-Host -ModuleName Secrets {
                throw "Read-Host called unexpectedly."
            }
        }

        It 'returns plain text from secure input' {
            Mock Read-Host -ModuleName Secrets {
                ConvertTo-SecureString 'my-secret' -AsPlainText -Force
            }

            $result = Read-Secret -Prompt 'Enter value'

            $result | Should -BeExactly 'my-secret'
            Should -Invoke -CommandName Read-Host -ModuleName Secrets `
                -ParameterFilter { $Prompt -eq 'Enter value' -and $AsSecureString } `
                -Times 1 -Exactly
        }

        It 'writes an error when no value is provided and AllowEmpty is not set' {
            Mock Read-Host -ModuleName Secrets {
                [System.Security.SecureString]::new()
            }

            { Read-Secret -Prompt 'Enter value' -ErrorAction Stop } | `
                Should -Throw '*No value provided.*'
        }

        It 'returns empty string and warns in CI when AllowEmpty is set' {
            Mock isContinuousIntegration -ModuleName Secrets { $true }

            $result = Read-Secret -Prompt 'Enter value' -AllowEmpty `
                -WarningAction SilentlyContinue -WarningVariable warnings

            $result | Should -BeExactly ''
            ($warnings -join ' ') | Should -Match 'CI environment detected'
        }

        It 'writes an error in CI when AllowEmpty is not set' {
            Mock isContinuousIntegration -ModuleName Secrets { $true }

            { Read-Secret -Prompt 'Enter value' -ErrorAction Stop } | `
                Should -Throw '*Cannot read input in CI environment.*'
        }

        It 'allows empty values when AllowEmpty is set' {
            Mock Read-Host -ModuleName Secrets {
                [System.Security.SecureString]::new()
            }

            $result = Read-Secret -Prompt 'Enter value' -AllowEmpty

            $result | Should -BeExactly ''
        }
    }
}
