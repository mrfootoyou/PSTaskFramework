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

    Context 'Clear-SecretStore' {
        It 'clears all secrets from the store' {
            Push-Secret 'secret1'
            Push-Secret 'secret2'
            Push-Secret 'secret1'
            $null = Protect-Secret -Message 'secret1 and secret2 are here'

            Clear-SecretStore

            $state.secrets.values.Count | Should -Be 0
            $state.secrets.regex | Should -BeNull
        }
    }
}
