<#
.DESCRIPTION
    Unit tests for Get-VariableFromOuterSession.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4

[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssignments', '')]
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '')]
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingEmptyCatchBlock', '')]
param()

Describe 'Get-VariableFromOuterSession' {
    BeforeAll {
        $ErrorActionPreference = 'Stop'
        $SrcPath = Convert-Path "$PSScriptRoot/../../src"

        # Create a test module that dot-sources Get-VariableFromOuterSession
        $testModule = New-Module -Name 'TestModule' `
            -ArgumentList $SrcPath `
            -ScriptBlock {
            param($SrcPath)

            # Dot-source the function to make it available in module context
            . "$SrcPath/scripts/PSTaskFramework/Get-VariableFromOuterSession.ps1"

            function Invoke-GetVariable {
                # Export a helper function that calls Get-VariableFromOuterSession
                [CmdletBinding()]
                param(
                    [string]$Name,
                    [switch]$ValueOnly,
                    [switch]$WarningIfNotFound
                )
                Get-VariableFromOuterSession @PSBoundParameters
            }

            function Get-VariableValue {
                # Export a helper function that calls Get-VariableFromOuterSession with ValueOnly
                [CmdletBinding()]
                param([string]$Name)
                Get-VariableFromOuterSession @PSBoundParameters -ValueOnly
            }

            function Invoke-GetVariablePipeline {
                # Export a helper that calls via pipeline
                [CmdletBinding()]
                param([string[]]$Name)
                $Name | Get-VariableFromOuterSession
            }

            function Invoke-ScriptInModule {
                # Helper to invoke an external script inside the module context
                param([string]$ScriptPath)
                & $ScriptPath @Args
            }

        } -Verbose:$false
    }

    AfterAll {
        $testModule | Remove-Module -ErrorAction Ignore
    }

    Context 'Get-VariableFromOuterSession from module context' {
        It 'retrieves a script-scoped variable' {
            $testVar = 'hello world'
            $result = Invoke-GetVariable -Name 'testVar'

            $result | Should -Not -Be $null
            $result.Value | Should -BeExactly 'hello world'
            $result.Name | Should -BeExactly 'testVar'
        }

        It 'retrieves only the value with -ValueOnly' {
            $testVar = 'test value'
            $result = Get-VariableValue -Name 'testVar'

            $result | Should -BeExactly 'test value'
            $result -isnot [System.Management.Automation.PSVariable] | Should -Be $true
        }

        It 'accepts variable names via pipeline' {
            $pipelineVar1 = 'piped value 1'
            $pipelineVar2 = 'piped value 2'
            $result = Invoke-GetVariablePipeline -Name 'pipelineVar1', 'pipelineVar2'

            $result | Should -HaveCount 2
            $result[0].Value | Should -BeExactly 'piped value 1'
            $result[1].Value | Should -BeExactly 'piped value 2'
        }

        It 'retrieves variables of different types' {
            $stringVar = 'string'
            $intVar = 42
            $arrayVar = @(1, 2, 3)
            $hashVar = @{ key = 'value' }

            (Get-VariableValue -Name 'stringVar') | Should -BeExactly 'string'
            (Get-VariableValue -Name 'intVar') | Should -BeExactly 42
            (Get-VariableValue -Name 'arrayVar') | Should -HaveCount 3
            (Get-VariableValue -Name 'hashVar').key | Should -BeExactly 'value'
        }

        It 'handles null values' {
            $nullVar = $null
            $result = Get-VariableValue -Name 'nullVar'

            $result | Should -Be $null
        }

        It 'handles empty strings' {
            $emptyVar = ''
            $result = Get-VariableValue -Name 'emptyVar'

            $result | Should -Be ''
        }

        It 'retrieves $PSBoundParameters' {
            # Create a function that calls our module helper
            function TestCaller {
                param([string]$ParamOne, [int]$ParamTwo)

                Get-VariableValue -Name 'PSBoundParameters'
            }

            $boundParams = TestCaller -ParamOne 'test' -ParamTwo 99

            $boundParams.ParamOne | Should -BeExactly 'test'
            $boundParams.ParamTwo | Should -BeExactly 99
        }

        It 'returns PSVariable object without -ValueOnly' {
            $myVar = 'test'
            $result = Invoke-GetVariable -Name 'myVar'

            $result -is [System.Management.Automation.PSVariable] | Should -Be $true
            $result.Name | Should -BeExactly 'myVar'
            $result.Value | Should -BeExactly 'test'
        }
    }

    Context 'Error handling and edge cases' {
        It 'fails when variable not found' {
            { Invoke-GetVariable -Name 'nonexistentVar' -ErrorAction Stop } |
            Should -Throw "Failed to find variable 'nonexistentVar'."
        }

        It 'reports a warning when using -WarningIfNotFound' {
            $result = Invoke-GetVariable -Name 'nonexistentVar' -WarningIfNotFound `
                -WarningAction SilentlyContinue -WarningVariable warning -ErrorAction Stop

            $result | Should -Be $null
            $warning | Should -HaveCount 1
            $warning.Message | Should -Contain "Failed to find variable 'nonexistentVar'."
        }

        It 'handles error when variable not found without WarningIfNotFound' {
            $result = Invoke-GetVariable -Name 'nonexistentVar' -ErrorAction SilentlyContinue

            $result | Should -Be $null
        }

        It 'should execute build script in module context' {
            $simpleBuildScriptPath = Join-Path $TestDrive build.ps1
            Set-Content -Path $simpleBuildScriptPath -Value {
                param([string]$SrcPath)
                Import-Module "$SrcPath/scripts/PSTaskFramework" -Scope Local
                $TaskContext = Initialize-TaskFramework
                Add-TaskFrameworkDefaultTasks
                $null = Invoke-TaskFramework -TaskName 'list'
                return Get-TaskFrameworkContext
            }

            $tc = Invoke-ScriptInModule $simpleBuildScriptPath -- $SrcPath

            $tc | Should -Not -Be $null
            $tc.BuildScriptPath | Should -Be $simpleBuildScriptPath
            $tc.AllTasks.Count | Should -Be 2
        }
    }

    Context 'Module boundary behavior' {
        It 'finds variables from caller scope' {
            $callerVar = 'from caller'
            $result = Get-VariableValue -Name 'callerVar'

            $result | Should -Be 'from caller'
        }

        It 'finds variables in function scope when called from function' {
            $sharedName = 'outer'

            function TestFunc {
                $sharedName = 'inner'
                Get-VariableValue -Name 'sharedName'
            }

            $result = TestFunc
            # The function finds the first outer session state (the function's own scope from the module's perspective)
            $result | Should -Be 'inner'
        }

        It 'handles nested function calls' {
            $nestedVar = 'nested test'

            function Level1 {
                function Level2 {
                    Get-VariableValue -Name 'nestedVar'
                }
                Level2
            }

            $result = Level1
            $result | Should -Be 'nested test'
        }
    }

    Context 'Special variable handling' {
        BeforeEach {
            function getAutoVar {
                [CmdletBinding()]
                param($name)
                Get-VariableValue -Name $name
            }
        }

        It 'can retrieve preference variables' {
            $result = getAutoVar -name 'WarningPreference' -WarningAction Ignore
            $result | Should -BeOfType [System.Management.Automation.ActionPreference]
            $result | Should -Be 'Ignore'
        }

        It 'can retrieve $MyInvocation' {
            $result = getAutoVar -name 'MyInvocation'
            $result | Should -BeOfType [System.Management.Automation.InvocationInfo]
            $result.MyCommand.Name | Should -Be 'getAutoVar'
        }

        It 'can retrieve $PSBoundParameters' {
            $result = getAutoVar -name 'PSBoundParameters'
            $result | Should -BeOfType ($PSBoundParameters.GetType())
            $result['name'] | Should -Be 'PSBoundParameters'
        }

        It 'can retrieve $Args' {
            function getArgs {
                Get-VariableValue -Name 'Args'
            }

            $result = getArgs 'arg1', 'arg2', 'arg3'
            $result.Count | Should -Be 3
        }
    }
}
