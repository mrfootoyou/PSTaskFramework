<#
.DESCRIPTION
    Unit tests for BuildHelpers module.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4

[Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'test code')]
param()

Describe 'PSTaskFramework.BuildHelpers Module' {
    . "$PSScriptRoot/setup.ps1"

    Context 'Read-Input' {
        BeforeEach {
            # Mock isContinuousIntegration to return false by default
            Mock isContinuousIntegration -ModuleName BuildHelpers { $false }

            # Mock Read-Host to avoid hanging tests
            Mock Read-Host -ModuleName BuildHelpers {
                throw "Read-Host called unexpectedly."
            }
        }

        It 'returns value from Read-Host' {
            Mock Read-Host -ModuleName BuildHelpers {
                'my-input'
            }

            $result = Read-Input -Prompt 'Enter value'

            $result | Should -BeExactly 'my-input'
            Should -Invoke Read-Host -ModuleName BuildHelpers `
                -ParameterFilter { $Prompt -eq 'Enter value' } `
                -Times 1 -Exactly
        }

        It 'writes an error when no value is provided and AllowEmpty is not set' {
            Mock Read-Host -ModuleName BuildHelpers {
                ''
            }

            { Read-Input -Prompt 'Enter value' -ErrorAction Stop } | `
                Should -Throw '*No value provided.*'
        }

        It 'returns empty string and warns in CI when AllowEmpty is set' {
            Mock isContinuousIntegration -ModuleName BuildHelpers { $true }

            $result = Read-Input -Prompt 'Enter value' -AllowEmpty `
                -WarningAction SilentlyContinue -WarningVariable warnings

            $result | Should -BeExactly ''
            ($warnings -join ' ') | Should -Match 'CI environment detected'
        }

        It 'writes an error in CI when AllowEmpty is not set' {
            Mock isContinuousIntegration -ModuleName BuildHelpers { $true }

            { Read-Input -Prompt 'Enter value' -ErrorAction Stop } | `
                Should -Throw '*Cannot read input in CI environment.*'
        }

        It 'allows empty values when AllowEmpty is set' {
            Mock Read-Host -ModuleName BuildHelpers {
                ''
            }

            $result = Read-Input -Prompt 'Enter value' -AllowEmpty

            $result | Should -BeExactly ''
        }

        Context 'as secret' {
            It 'returns plain text from secure input' {
                Mock Read-Host -ModuleName BuildHelpers {
                    ConvertTo-SecureString 'my-secret' -AsPlainText -Force
                }

                $result = Read-Input -Secret -Prompt 'Enter value'

                $result | Should -BeExactly 'my-secret'
                Should -Invoke -CommandName Read-Host -ModuleName BuildHelpers `
                    -ParameterFilter { $Prompt -eq 'Enter value' -and $AsSecureString } `
                    -Times 1 -Exactly
            }

            It 'writes an error when no value is provided and AllowEmpty is not set' {
                Mock Read-Host -ModuleName BuildHelpers {
                    [System.Security.SecureString]::new()
                }

                { Read-Input -Secret -Prompt 'Enter value' -ErrorAction Stop } | `
                    Should -Throw '*No value provided.*'
            }

            It 'returns empty string and warns in CI when AllowEmpty is set' {
                Mock isContinuousIntegration -ModuleName BuildHelpers { $true }

                $result = Read-Input -Secret -Prompt 'Enter value' -AllowEmpty `
                    -WarningAction SilentlyContinue -WarningVariable warnings

                $result | Should -BeExactly ''
                ($warnings -join ' ') | Should -Match 'CI environment detected'
            }

            It 'writes an error in CI when AllowEmpty is not set' {
                Mock isContinuousIntegration -ModuleName BuildHelpers { $true }

                { Read-Input -Secret -Prompt 'Enter value' -ErrorAction Stop } | `
                    Should -Throw '*Cannot read input in CI environment.*'
            }

            It 'allows empty values when AllowEmpty is set' {
                Mock Read-Host -ModuleName BuildHelpers {
                    [System.Security.SecureString]::new()
                }

                $result = Read-Input -Secret -Prompt 'Enter value' -AllowEmpty

                $result | Should -BeExactly ''
            }
        }
    }
}
