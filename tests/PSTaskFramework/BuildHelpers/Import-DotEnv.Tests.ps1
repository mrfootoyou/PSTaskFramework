<#
.DESCRIPTION
	Unit tests for Import-DotEnv.
.NOTES
	SPDX-License-Identifier: Unlicense
	Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4

param()

Describe 'PSTaskFramework.BuildHelpers Module' {
    . "$PSScriptRoot/setup.ps1"

    Context 'Import-DotEnv' {
        AfterEach {
            # clean up any variables we set in the environment
            Get-ChildItem Env:DOTENV_TEST_* | Remove-Item
        }

        It 'loads values from .env file into environment variables' {
            $envFile = Join-Path $TestDrive 'app.env'
            Set-Content -LiteralPath $envFile -Value @(
                'DOTENV_TEST_ALPHA=one'
                'DOTENV_TEST_BETA=two'
            )

            Import-DotEnv -Path $envFile

            $env:DOTENV_TEST_ALPHA | Should -BeExactly 'one'
            $env:DOTENV_TEST_BETA | Should -BeExactly 'two'
        }

        It 'loads empty values from .env file into environment variables' {
            $envFile = Join-Path $TestDrive 'app.env'
            Set-Content -LiteralPath $envFile -Value @(
                'DOTENV_TEST_EMPTY='
            )

            Import-DotEnv -Path $envFile

            if ($PSVersionTable.PSVersion -ge [Version]'7.5') {
                # PowerShell 7.5+ supports empty environment variables
                $env:DOTENV_TEST_EMPTY | Should -BeExactly ''
            }
            else {
                # In earlier versions, environment variables with empty values are treated as null
                $env:DOTENV_TEST_EMPTY | Should -BeNull
            }
        }

        It 'does not overwrite existing values with NoClobber' {
            $envFile = Join-Path $TestDrive 'noclobber.env'
            Set-Content -LiteralPath $envFile -Value 'DOTENV_TEST_NOCLOBBER=file-value'
            Set-Item -LiteralPath Env:DOTENV_TEST_NOCLOBBER -Value 'existing-value'

            Import-DotEnv -Path $envFile -NoClobber

            $env:DOTENV_TEST_NOCLOBBER | Should -BeExactly 'existing-value'
        }

        It 'returns PSVariable objects with AsVariables' {
            $envFile = Join-Path $TestDrive 'vars.env'
            Set-Content -LiteralPath $envFile -Value @(
                'DOTENV_VAR_ONE=1'
                'DOTENV_VAR_TWO=2'
            )

            $result = Import-DotEnv -Path $envFile -AsVariables

            $result | Should -HaveCount 2
            $result[0] | Should -BeOfType ([System.Management.Automation.PSVariable])
            ($result | Where-Object Name -eq 'DOTENV_VAR_ONE').Value | Should -BeExactly '1'
            ($result | Where-Object Name -eq 'DOTENV_VAR_TWO').Value | Should -BeExactly '2'
        }

        It 'errors when file missing and no prototype file' {
            $target = Join-Path $TestDrive '.env'

            $null = Import-DotEnv -Path $target -ErrorAction SilentlyContinue -ErrorVariable errors

            Test-Path -LiteralPath $target | Should -BeFalse
            $errors | Should -HaveCount 1
            $errors[0].Exception.Message | Should -BeLike "File not found at '*[\/].env'.*"
        }

        It 'errors when file and prototype not found' {
            $target = Join-Path $TestDrive '.env'

            $null = Import-DotEnv -Path $target -Prototype 'unknown' -ErrorAction SilentlyContinue -ErrorVariable errors

            Test-Path -LiteralPath $target | Should -BeFalse
            $errors | Should -HaveCount 1
            $errors[0].Exception.Message | Should -BeLike "File not found at '*[\/].env', and prototype file not found at '*[\/]unknown'.*"
        }

        It 'creates missing file from prototype file' {
            $target = Join-Path $TestDrive '.env'
            $prototype = Join-Path $TestDrive '.env.sample'
            Set-Content -LiteralPath $prototype -Value 'DOTENV_TEST_FROM_PROTOTYPE=ok'

            $result = Import-DotEnv -Path $target -Prototype $prototype -CreationAction Continue -AsVariables -WarningVariable warnings -WarningAction SilentlyContinue

            Test-Path -LiteralPath $target | Should -BeTrue
            $result | Should -HaveCount 1
            $result[0].Name | Should -BeExactly 'DOTENV_TEST_FROM_PROTOTYPE'
            $result[0].Value | Should -BeExactly 'ok'
            $warnings | Should -HaveCount 1
            $warnings[0].Message | Should -BeLike "Created '*[\/].env' from prototype '*[\/].env.sample'."
        }

        It 'creates missing file from prototype folder' {
            $target = Join-Path $TestDrive 'foo.env'
            $prototype = Join-Path $TestDrive 'protos/foo.env'
            $null = New-Item -ItemType Directory -Path (Split-Path $prototype) -Force
            Set-Content -LiteralPath $prototype -Value 'DOTENV_TEST_FROM_PROTOTYPE=ok'

            $result = Import-DotEnv -Path $target -Prototype (Split-Path $prototype) -CreationAction Continue -AsVariables -WarningAction Ignore

            Test-Path -LiteralPath $target | Should -BeTrue
            $result | Should -HaveCount 1
            $result[0].Name | Should -BeExactly 'DOTENV_TEST_FROM_PROTOTYPE'
            $result[0].Value | Should -BeExactly 'ok'
        }

        It 'creates missing file from prototype path' {
            $target = Join-Path $TestDrive 'foo.env'
            $prototype = Join-Path $TestDrive './sample.foo'
            Set-Content -LiteralPath $prototype -Value 'DOTENV_TEST_FROM_PROTOTYPE=ok'

            $result = Import-DotEnv -Path $target -Prototype $prototype -CreationAction Continue -AsVariables -WarningAction Ignore

            Test-Path -LiteralPath $target | Should -BeTrue
            $result | Should -HaveCount 1
            $result[0].Name | Should -BeExactly 'DOTENV_TEST_FROM_PROTOTYPE'
            $result[0].Value | Should -BeExactly 'ok'
        }

        It 'silently creates missing file from prototype when CreationAction is Ignore' {
            $target = Join-Path $TestDrive '.env'
            $prototype = Join-Path $TestDrive '.env.sample'
            Set-Content -LiteralPath $prototype -Value 'DOTENV_TEST_FROM_PROTOTYPE=ok'

            $result = Import-DotEnv -Path $target -Prototype $prototype -CreationAction Ignore -AsVariables -WarningVariable warnings -WarningAction SilentlyContinue

            Test-Path -LiteralPath $target | Should -BeTrue
            $result | Should -HaveCount 1
            $result[0].Name | Should -BeExactly 'DOTENV_TEST_FROM_PROTOTYPE'
            $result[0].Value | Should -BeExactly 'ok'
            $warnings | Should -HaveCount 0
        }

        It 'errors after creating file from prototype when CreationAction is Stop' {
            $target = Join-Path $TestDrive '.stop.env'
            $prototype = Join-Path $TestDrive '.stop.env.sample'
            Set-Content -LiteralPath $prototype -Value 'DOTENV_TEST_STOP=should-not-load'

            Import-DotEnv -Path $target -Prototype $prototype -CreationAction Stop -AsVariables `
                -ErrorAction SilentlyContinue -ErrorVariable errors -WarningAction SilentlyContinue -WarningVariable warnings

            Test-Path -LiteralPath $target | Should -BeTrue
            $errors | Should -HaveCount 1
            $errors[0].Exception.Message | Should -BeLike '*Created file from prototype*'
            $warnings | Should -HaveCount 1
            $warnings[0].Message | Should -BeLike "Created '*[\/].stop.env' from prototype '*[\/].stop.env.sample'."
        }

        It 'uses interpolation during import when option is enabled' {
            $envFile = Join-Path $TestDrive 'interpolate.env'
            Set-Content -LiteralPath $envFile -Value @(
                'DOTENV_TEST_MSG=${DOTENV_TEST_GREETING} ${DOTENV_TEST_SUBJECT}'
            )
            $env:DOTENV_TEST_GREETING = 'hello'
            $env:DOTENV_TEST_SUBJECT = 'world'

            Import-DotEnv -Path $envFile -Options Interpolate

            $env:DOTENV_TEST_MSG | Should -BeExactly 'hello world'
        }

        It 'uses case-sensitive interpolation on Linux and case-insensitive interpolation on Windows' {
            $envFile = Join-Path $TestDrive 'interpolate.env'
            Set-Content -LiteralPath $envFile -Value @(
                'DOTENV_TEST_MSG=Hello ${DOTENV_TEST_SUBJECT:-Linux}'
            )
            $env:DOTENV_TEST_Subject = 'Windows'

            Import-DotEnv -Path $envFile -Options Interpolate

            if ($IsWindows) {
                $env:DOTENV_TEST_MSG | Should -BeExactly 'Hello Windows'
            }
            else {
                $env:DOTENV_TEST_MSG | Should -BeExactly 'Hello Linux'
            }
        }

        It 'interpolates weird variable names' {
            $envFile = Join-Path $TestDrive 'interpolate.env'
            Set-Content -LiteralPath $envFile -Value @(
                'DOTENV_TEST_MSG=Hello ${DOTENV_TEST (weird name!#}'
            )
            ${env:DOTENV_TEST (weird name!#} = 'Weird'

            Import-DotEnv -Path $envFile -Options Interpolate

            $env:DOTENV_TEST_MSG | Should -BeExactly 'Hello Weird'
        }
    }

    Context 'parseDotEnvLine' {
        It 'returns nothing for empty lines and comments' {
            InModuleScope 'BuildHelpers' {
                @(parseDotEnvLine '') | Should -BeNullOrEmpty
                @(parseDotEnvLine '  ') | Should -BeNullOrEmpty
                @(parseDotEnvLine '# comment') | Should -BeNullOrEmpty
                @(parseDotEnvLine '   # comment') | Should -BeNullOrEmpty
            }
        }

        It 'parses unquoted key/value and trims by default' {
            InModuleScope 'BuildHelpers' {
                $result = parseDotEnvLine '  FOO  =  bar  '

                $result.Name | Should -BeExactly 'FOO'
                $result.Value | Should -BeExactly 'bar'
            }
        }

        It 'does not trim key/value when NoTrimKeys and NoTrimValues are set' {
            InModuleScope 'BuildHelpers' {
                $result = parseDotEnvLine '  FOO  =  bar  ' -Options NoTrimKeys, NoTrimValues

                $result.Name | Should -BeExactly '  FOO  '
                $result.Value | Should -BeExactly '  bar  '
            }
        }

        It 'parses quoted values as literals when NoQuotedValues option is set' {
            InModuleScope 'BuildHelpers' {
                $result = parseDotEnvLine 'FOO="bar"' -Options NoQuotedValues

                $result.Name | Should -BeExactly 'FOO'
                $result.Value | Should -BeExactly '"bar"'
            }
        }

        It 'parses and unescapes quoted values by default' {
            InModuleScope 'BuildHelpers' {
                $result = parseDotEnvLine 'FOO="newline=\r\n;tab=\t;slash=\\;quote=\";other=\h"'

                $result.Value | Should -BeExactly "newline=`r`n;tab=`t;slash=\;quote=`";other=h"
            }
        }

        It 'preserves escape sequences in non-double-quoted values' -ForEach @(
            'line\nnext'
            "'line\nnext'"
        ) {
            InModuleScope 'BuildHelpers' -ArgumentList $_ {
                $result = parseDotEnvLine "FOO=$($args[0])"

                $result.Value | Should -BeExactly 'line\nnext'
            }
        }

        It 'preserves escape sequences with NoUnescape option' {
            InModuleScope 'BuildHelpers' {
                $result = parseDotEnvLine 'FOO="line\nnext"' -Options NoUnescape

                $result.Value | Should -BeExactly 'line\nnext'
            }
        }

        It 'handles escaped quotes in double-quoted values' {
            InModuleScope 'BuildHelpers' {
                $result = parseDotEnvLine 'FOO="she said ""hello"""'

                $result.Value | Should -BeExactly 'she said "hello"'
            }
        }

        It 'handles escaped quotes in single-quoted values' {
            InModuleScope 'BuildHelpers' {
                $result = parseDotEnvLine "Foo='it''s fine'"

                $result.Value | Should -BeExactly "it's fine"
            }
        }

        It 'includes inline comments for unquoted values by default' {
            InModuleScope 'BuildHelpers' {
                $result = parseDotEnvLine 'FOO=bar  # comment'

                $result.Value | Should -BeExactly 'bar  # comment'
            }
        }

        It 'ignores inline comments for unquoted values when enabled' {
            InModuleScope 'BuildHelpers' {
                $result = parseDotEnvLine 'FOO=bar  # trailing comment' -Options AllowInlineComments

                $result.Value | Should -BeExactly 'bar'
            }
        }

        It 'keeps inline comments for unquoted values by default' {
            InModuleScope 'BuildHelpers' {
                $result = parseDotEnvLine 'FOO=bar # trailing comment'

                $result.Value | Should -BeExactly 'bar # trailing comment'
            }
        }

        It 'treats unterminated single-quoted value as a literal unquoted value' {
            InModuleScope 'BuildHelpers' {
                $result = parseDotEnvLine "FOO='missing end quote"

                $result.Value | Should -BeExactly "'missing end quote"
            }
        }

        It 'treats unterminated double-quoted value as a literal unquoted value' {
            InModuleScope 'BuildHelpers' {
                $result = parseDotEnvLine 'FOO="missing end quote'

                $result.Value | Should -BeExactly '"missing end quote'
            }
        }

        It 'throws in strict mode for empty key' {
            InModuleScope 'BuildHelpers' {
                { parseDotEnvLine '=bar' -Options Strict } | Should -Throw '*Invalid key*'
                { parseDotEnvLine '  =bar' -Options Strict } | Should -Throw '*Key cannot be empty*'
            }
        }

        It 'interpolates variables and defaults' {
            InModuleScope 'BuildHelpers' {
                $vars = @{ NAME = 'world' }

                $result = parseDotEnvLine 'GREETING=hello ${NAME} ${MISSING:-fallback}' -Options Interpolate -InterpolationVariables $vars

                $result.Value | Should -BeExactly 'hello world fallback'
            }
        }

        It 'interpolates variables and defaults' {
            InModuleScope 'BuildHelpers' {
                $result = parseDotEnvLine 'HMMM=$UNKNOWN1 ${UNKNOWN 2}' -Options Interpolate

                $result.Value | Should -BeExactly '$UNKNOWN1 ${UNKNOWN 2}'
            }
        }

        It 'treats $$ as a literal dollar sign during interpolation' {
            InModuleScope 'BuildHelpers' {
                $vars = @{ '5' = '...' }

                $result = parseDotEnvLine 'FOO=cost $$5' -Options Interpolate -InterpolationVariables $vars

                $result.Value | Should -BeExactly 'cost $5'
            }
        }

        It 'adds parsed variables to a mutable interpolation dictionary' {
            InModuleScope 'BuildHelpers' {
                $vars = @{}

                parseDotEnvLine 'A=${A:-foo}' -Options Interpolate -InterpolationVariables $vars | Out-Null
                parseDotEnvLine 'B=${A}' -Options Interpolate -InterpolationVariables $vars | Out-Null

                $vars['A'] | Should -BeExactly 'foo'
                $vars['B'] | Should -BeExactly 'foo'
            }
        }
    }
}
