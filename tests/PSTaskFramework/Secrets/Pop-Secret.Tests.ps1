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

    Context 'Pop-Secret' {
        It 'reference counts popped secrets' {
            Push-Secret 'top secret'
            Push-Secret 'top secret'
            Pop-Secret 'top secret'

            $state.secrets.values['top secret'] | Should -Be 1
        }

        It 'treats popped secrets case-sensitively' {
            Push-Secret 'top secret'
            Push-Secret 'Top Secret'
            Push-Secret 'TOP SECRET'
            $state.secrets.Values.Count | Should -Be 3

            Pop-Secret 'top secret'
            Pop-Secret 'Top Secret'
            Pop-Secret 'TOP SECRET'

            $state.secrets.Values.Count | Should -Be 0
        }

        It 'throws when popping a secret that was never pushed' {
            { Pop-Secret 'nonexistent-secret' -ea Stop } | Should -Throw '*Secret not found.*'
        }

        It 'supports ErrorAction ignore when popping a secret that was never pushed' {
            { Pop-Secret 'nonexistent-secret' -ea Ignore } | Should -Not -Throw
        }

        It 'rejects empty secret values' {
            { Pop-Secret '' } | Should -Throw '*because it is an empty string*'
            { Pop-Secret $null } | Should -Throw '*because it is an empty string*'
        }
    }
}
