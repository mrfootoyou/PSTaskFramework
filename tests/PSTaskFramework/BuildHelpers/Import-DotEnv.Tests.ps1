<#
.DESCRIPTION
	Unit tests for Import-DotEnv.
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
}
