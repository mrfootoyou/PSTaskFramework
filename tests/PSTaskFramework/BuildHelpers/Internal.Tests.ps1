<#
.DESCRIPTION
	Unit tests for dotEnv internal helpers.
.NOTES
	SPDX-License-Identifier: Unlicense
	Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4

param()

Describe 'dotEnv helpers' {
    BeforeAll {
        $ErrorActionPreference = 'Stop'

        . $PSScriptRoot/../../../src/scripts/PSTaskFramework/BuildHelpers/dotEnv.ps1
    }

    Context 'parseDotEnvLine' {
        It 'returns nothing for empty lines and comments' {
            @(parseDotEnvLine '') | Should -BeNullOrEmpty
            @(parseDotEnvLine '  ') | Should -BeNullOrEmpty
            @(parseDotEnvLine '# comment') | Should -BeNullOrEmpty
            @(parseDotEnvLine '   # comment') | Should -BeNullOrEmpty
        }

        It 'parses unquoted key/value and trims by default' {
            $result = parseDotEnvLine '  FOO  =  bar  '

            $result.Name | Should -BeExactly 'FOO'
            $result.Value | Should -BeExactly 'bar'
        }

        It 'does not trim key/value when NoTrimKeys and NoTrimValues are set' {
            $result = parseDotEnvLine '  FOO  =  bar  ' -Options NoTrimKeys, NoTrimValues

            $result.Name | Should -BeExactly '  FOO  '
            $result.Value | Should -BeExactly '  bar  '
        }

        It 'parses quoted values as literals when NoQuotedValues option is set' {
            $result = parseDotEnvLine 'FOO="bar"' -Options NoQuotedValues

            $result.Name | Should -BeExactly 'FOO'
            $result.Value | Should -BeExactly '"bar"'
        }

        It 'parses and unescapes quoted values by default' {
            $result = parseDotEnvLine 'FOO="newline=\r\n;tab=\t;slash=\\;quote=\";other=\h"'

            $result.Value | Should -BeExactly "newline=`r`n;tab=`t;slash=\;quote=`";other=h"
        }

        It 'preserves escape sequences in non-double-quoted values' -ForEach @(
            'line\nnext'
            "'line\nnext'"
        ) {
            $result = parseDotEnvLine "FOO=$_"

            $result.Value | Should -BeExactly 'line\nnext'
        }

        It 'preserves escape sequences with NoUnescape option' {
            $result = parseDotEnvLine 'FOO="line\nnext"' -Options NoUnescape

            $result.Value | Should -BeExactly 'line\nnext'
        }

        It 'handles escaped quotes in double-quoted values' {
            $result = parseDotEnvLine 'FOO="she said ""hello"""'

            $result.Value | Should -BeExactly 'she said "hello"'
        }

        It 'handles escaped quotes in single-quoted values' {
            $result = parseDotEnvLine "Foo='it''s fine'"

            $result.Value | Should -BeExactly "it's fine"
        }

        It 'includes inline comments for unquoted values by default' {
            $result = parseDotEnvLine 'FOO=bar  # comment'

            $result.Value | Should -BeExactly 'bar  # comment'
        }

        It 'ignores inline comments for unquoted values when enabled' {
            $result = parseDotEnvLine 'FOO=bar  # trailing comment' -Options AllowInlineComments

            $result.Value | Should -BeExactly 'bar'
        }

        It 'keeps inline comments for unquoted values by default' {
            $result = parseDotEnvLine 'FOO=bar # trailing comment'

            $result.Value | Should -BeExactly 'bar # trailing comment'
        }

        It 'treats unterminated single-quoted value as a literal unquoted value' {
            $result = parseDotEnvLine "FOO='missing end quote"

            $result.Value | Should -BeExactly "'missing end quote"
        }

        It 'treats unterminated double-quoted value as a literal unquoted value' {
            $result = parseDotEnvLine 'FOO="missing end quote'

            $result.Value | Should -BeExactly '"missing end quote'
        }

        It 'throws in strict mode for empty key' {
            { parseDotEnvLine '=bar' -Options Strict } | Should -Throw '*Invalid key*'
            { parseDotEnvLine '  =bar' -Options Strict } | Should -Throw '*Key cannot be empty*'
        }

        It 'interpolates variables and defaults' {
            $vars = @{ NAME = 'world' }

            $result = parseDotEnvLine 'GREETING=hello ${NAME} ${MISSING:-fallback}' -Options Interpolate -InterpolationVariables $vars

            $result.Value | Should -BeExactly 'hello world fallback'
        }

        It 'interpolates variables and defaults' {
            $result = parseDotEnvLine 'HMMM=$UNKNOWN1 ${UNKNOWN 2}' -Options Interpolate

            $result.Value | Should -BeExactly '$UNKNOWN1 ${UNKNOWN 2}'
        }

        It 'treats $$ as a literal dollar sign during interpolation' {
            $vars = @{ '5' = '...' }

            $result = parseDotEnvLine 'FOO=cost $$5' -Options Interpolate -InterpolationVariables $vars

            $result.Value | Should -BeExactly 'cost $5'
        }

        It 'adds parsed variables to a mutable interpolation dictionary' {
            $vars = @{}

            parseDotEnvLine 'A=${A:-foo}' -Options Interpolate -InterpolationVariables $vars | Out-Null
            parseDotEnvLine 'B=${A}' -Options Interpolate -InterpolationVariables $vars | Out-Null

            $vars['A'] | Should -BeExactly 'foo'
            $vars['B'] | Should -BeExactly 'foo'
        }
    }
}
