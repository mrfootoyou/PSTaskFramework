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

    Context 'Push-Secret' {
        It 'reference counts pushed secrets' {
            Push-Secret 'top secret'
            Push-Secret 'top secret'
            Push-Secret 'top secret'

            $state.secrets.values['top secret'] | Should -Be 3
        }

        It 'treats pushed secrets case-sensitively' {
            Push-Secret 'top secret'
            Push-Secret 'Top Secret'
            Push-Secret 'TOP SECRET'

            $state.secrets.values['top secret'] | Should -Be 1
            $state.secrets.values['Top Secret'] | Should -Be 1
            $state.secrets.values['TOP SECRET'] | Should -Be 1
        }

        It 'rejects empty secret values' {
            { Push-Secret '' } | Should -Throw '*because it is an empty string*'
            { Push-Secret $null } | Should -Throw '*because it is an empty string*'
        }
    }
}
