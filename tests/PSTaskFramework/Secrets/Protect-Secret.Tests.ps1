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

    Context 'Protect-Secret' {
        It 'returns the input unchanged when no secrets are registered' {
            $result = Protect-Secret -Message 'hello world'

            $result | Should -BeExactly 'hello world'
            $state.secrets.regex | Should -BeNull
        }

        It 'masks registered secrets with the default mask' {
            Push-Secret 'token123'

            $result = Protect-Secret -Message 'Authorization: token123'

            $result | Should -BeExactly 'Authorization: ****'
        }

        It 'uses a custom mask when provided' {
            Push-Secret 'token123'

            $result = Protect-Secret -Message 'Authorization: token123' -Mask '[REDACTED]'

            $result | Should -BeExactly 'Authorization: [REDACTED]'
        }

        It 'mask with $0 cannot be used to reveal part of the secret' {
            Push-Secret 'token123'

            $result = Protect-Secret -Message 'Authorization: token123' -Mask '$0'

            $result | Should -BeExactly 'Authorization: $0'
        }

        It 'supports pipeline input for message values' {
            Push-Secret 'top secret'

            $result = 'a top secret value' | Protect-Secret

            $result | Should -BeExactly 'a **** value'
        }

        It 'honors push and pop reference counting' {
            Push-Secret 'shared-secret'
            Push-Secret 'shared-secret'

            Pop-Secret 'shared-secret'
            $stillMasked = Protect-Secret -Message 'shared-secret'

            Pop-Secret 'shared-secret'
            $unmasked = Protect-Secret -Message 'shared-secret'

            $stillMasked | Should -BeExactly '****'
            $unmasked | Should -BeExactly 'shared-secret'
        }

        It 'supports pushing and popping from the pipeline' {
            'pipelined-secret' | Push-Secret
            $masked = Protect-Secret -Message 'pipelined-secret'

            'pipelined-secret' | Pop-Secret
            $unmasked = Protect-Secret -Message 'pipelined-secret'

            $masked | Should -BeExactly '****'
            $unmasked | Should -BeExactly 'pipelined-secret'
        }

        It 'masks longer secrets that contain shorter ones as substrings' {
            Push-Secret 'secret_key'
            Push-Secret 'secret'

            $result1 = Protect-Secret -Message 'hello secret_key'
            $result2 = Protect-Secret -Message 'hello secret'

            $result1 | Should -BeExactly 'hello ****'
            $result2 | Should -BeExactly 'hello ****'
        }
    }
}
