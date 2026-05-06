<#
.DESCRIPTION
    Unit tests for PSTaskFramework module.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseCompatibleCommands', '', Justification = 'Chokes on Pester keywords.')]
param()

Describe 'PSTaskFramework Module' {
    BeforeAll {
        Import-Module "$PSScriptRoot/PSTaskFramework" -Scope Local -Verbose:$false

        # Mock Write-Information and Write-Verbose to prevent test output pollution.
        Mock Write-Information -ModuleName PSTaskFramework { }
        Mock Write-Verbose -ModuleName PSTaskFramework { }

        Reset-TaskFramework
    }

    AfterEach {
        Reset-TaskFramework
    }

    It 'fails when no tasks are specified' {
        { Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName 'foo' } | Should -Throw "Task 'foo' not found."
        $global:LASTEXITCODE | Should -Be -1
    }

    It 'registers and executes tasks via Task command' {
        $shared = [ordered]@{ State = [System.Collections.Generic.List[string]]::new() }

        Task 'alpha' -Description 'first task' -Action { $Shared.State.Add('alpha') } -DependsOn @('beta')
        Task 'beta' -Description 'second task' -Action { $Shared.State.Add('beta') }

        Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName @('alpha') -Variables @{ Shared = $shared }

        $shared.State | Should -Be @('beta', 'alpha')
    }

    It 'rejects duplicate task names case-insensitively' {
        Task -Name 'Build' -Action {}

        { Task -Name 'build' -Action {} } | Should -Throw '*already exists*'
    }

    It 'executes dependencies before task by default' {
        $shared = [ordered]@{ State = [System.Collections.Generic.List[string]]::new() }

        Task 'dep' { $Shared.State.Add('dep') }
        Task 'main' { $Shared.State.Add('main') } -DependsOn @('dep')

        Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName @('main') -Variables @{ Shared = $shared }

        $shared.State | Should -Be @('dep', 'main')
    }

    It 'skips dependencies when SkipDependencies is specified' {
        $shared = [ordered]@{ State = [System.Collections.Generic.List[string]]::new() }

        Task 'dep' { $Shared.State.Add('dep') }
        Task 'main' { $Shared.State.Add('main') } -DependsOn @('dep')

        Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName @('main') -SkipDependencies -Variables @{ Shared = $shared }

        $shared.State | Should -Be @('main')
    }

    It 'passes TaskArgs to a single task' {
        $shared = [ordered]@{ Captured = '' }

        Task 'echo' {
            param([string]$Name, [int]$Count)
            $Shared.Captured = ("{0}:{1}" -f $Name, $Count)
        }

        Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName @('echo') -TaskArgs @('sample', 3) -Variables @{ Shared = $shared }

        $shared.Captured | Should -Be 'sample:3'
    }

    It 'marks invocation as failed when TaskArgs are used with multiple tasks' {
        Task 'first' {}
        Task 'second' {}

        { Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName @('first', 'second') -TaskArgs @('x') } |
        Should -Throw '*Task arguments cannot be used when invoking multiple tasks.*'

        $global:LASTEXITCODE | Should -Be -1
    }

    It 'imports variables into task scope' {
        $shared = [ordered]@{ Result = '' }

        Task 'use-vars' {
            $Shared.Result = "$Greeting, $Name"
        }

        Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName @('use-vars') -Variables @{
            Greeting = 'hello'
            Name     = 'world'
            Shared   = $shared
        }

        $shared.Result | Should -Be 'hello, world'
    }

    It 'imports helper scripts before task invocation' {
        $shared = [ordered]@{ Result = '' }
        $helperPath = Join-Path $TestDrive 'helper.ps1'
        Set-Content -Path $helperPath -Value @'
function Get-Message {
    'from helper'
}
'@

        Task 'use-helper' {
            $Shared.Result = Get-Message
        }

        Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName @('use-helper') -ImportScripts @($helperPath) -Variables @{ Shared = $shared }

        $shared.Result | Should -Be 'from helper'
    }

    It 'preserves non-zero task exit code on failure' {
        Task 'fails' {
            $global:LASTEXITCODE = 42
        }

        { Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName 'fails' } |
        Should -Throw "Task 'fails' failed with exit code 42."

        $global:LASTEXITCODE | Should -Be 42
    }

    It 'ignores non-zero AllowedExitCodes' {
        Task 'fails' -AllowedExitCodes @('42') {
            $global:LASTEXITCODE = 42
        }

        Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName 'fails'
        $global:LASTEXITCODE | Should -Be 0
    }

    It 'ignores exit code when no AllowedExitCodes' {
        Task 'fails' -AllowedExitCodes @() {
            $global:LASTEXITCODE = 42
        }

        Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName 'fails'
        $global:LASTEXITCODE | Should -Be 0
    }

    It 'does not reset framework state after invocation' {
        Task 'run-once' {}

        Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName @('run-once')
        Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName @('run-once')

        $global:LASTEXITCODE | Should -Be 0
    }

    It 'fails when dependency is missing' {
        Task 'main' {} -DependsOn @('missing')

        { Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName @('main') } | Should -Throw "Dependency 'missing' of task 'main' not found."

        $global:LASTEXITCODE | Should -Be -1
    }

    It 'fails when dependencies are circular' {
        Task 'a' {} -DependsOn @('b')
        Task 'b' {} -DependsOn @('a')

        { Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName @('a') } | Should -Throw "Circular dependency detected at *"

        $global:LASTEXITCODE | Should -Be -1
    }

    Describe 'Repair-TaskStackTrace' {
        It 'rewrites task frame and removes the wrapper line-1 frame' {
            $nl = [System.Environment]::NewLine
            $fakeStack = @(
                'at <ScriptBlock>, <No file>: line 5'
                'at <ScriptBlock>, <No file>: line 1'
                'at Invoke-Task, F:\test\PSTaskFramework.psm1: line 264'
                'at Invoke-TaskFramework, F:\test\PSTaskFramework.psm1: line 346'
                'at <ScriptBlock>, F:\test\build.ps1: line 20'
            ) -join $nl

            $trace = InModuleScope PSTaskFramework -ArgumentList $fakeStack {
                param($fakeStack)
                $exception = [System.Exception]::new('task error')
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception, 'TestError', [System.Management.Automation.ErrorCategory]::NotSpecified, $null)
                $bindingFlags = [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic
                $field = $errorRecord.GetType().GetField('_scriptStackTrace', $bindingFlags)
                $field.SetValue($errorRecord, $fakeStack)

                # Action.Ast.Extent.StartLineNumber == 1 for inline scriptblocks
                # rewritten line = 1 + 5 - 2 = 4
                $task = [TaskDefinition]@{ Name = 'test-task'; Action = [scriptblock]::Create("throw 'error'") }
                Repair-TaskStackTrace -ErrorRecord $errorRecord -Task $task -TaskActionStartLine 2
                $errorRecord.ScriptStackTrace
            }

            $frames = $trace -split '\r?\n'
            $frames | Should -Contain 'at <ScriptBlock>, <No file>: line 4'
            $frames | Should -Not -Contain 'at <ScriptBlock>, <No file>: line 5'
            $frames | Should -Not -Contain 'at <ScriptBlock>, <No file>: line 1'
            $frames | Should -Contain 'at Invoke-Task, F:\test\PSTaskFramework.psm1: line 264'
            $frames | Should -Contain 'at Invoke-TaskFramework, F:\test\PSTaskFramework.psm1: line 346'
            $frames | Should -Contain 'at <ScriptBlock>, F:\test\build.ps1: line 20'
        }

        It 'rewrites multiple consecutive task frames above the wrapper' {
            $nl = [System.Environment]::NewLine
            $fakeStack = @(
                'at some-other-function, F:\test\other.psm1: line 10'
                'at <ScriptBlock>, <No file>: line 8'
                'at <ScriptBlock>, <No file>: line 5'
                'at <ScriptBlock>, <No file>: line 1'
                'at Invoke-Task, F:\test\PSTaskFramework.psm1: line 264'
            ) -join $nl

            $trace = InModuleScope PSTaskFramework -ArgumentList $fakeStack {
                param($fakeStack)
                $exception = [System.Exception]::new('task error')
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception, 'TestError', [System.Management.Automation.ErrorCategory]::NotSpecified, $null)
                $bindingFlags = [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic
                $field = $errorRecord.GetType().GetField('_scriptStackTrace', $bindingFlags)
                $field.SetValue($errorRecord, $fakeStack)

                # line 5 -> 1 + 5 - 2 = 4; line 8 -> 1 + 8 - 2 = 7
                $task = [TaskDefinition]@{ Name = 'test-task'; Action = [scriptblock]::Create("throw 'error'") }
                Repair-TaskStackTrace -ErrorRecord $errorRecord -Task $task -TaskActionStartLine 2
                $errorRecord.ScriptStackTrace
            }

            $frames = $trace -split '\r?\n'
            $frames | Should -HaveCount 4
            $frames[0] | Should -Be 'at some-other-function, F:\test\other.psm1: line 10'
            $frames[1] | Should -Be 'at <ScriptBlock>, <No file>: line 7'
            $frames[2] | Should -Be 'at <ScriptBlock>, <No file>: line 4'
            $frames[3] | Should -Be 'at Invoke-Task, F:\test\PSTaskFramework.psm1: line 264'
        }

        It 'leaves stack trace unchanged when Invoke-Task frame is absent' {
            $nl = [System.Environment]::NewLine
            $fakeStack = @(
                'at <ScriptBlock>, <No file>: line 5'
                'at some-other-function, F:\test\other.psm1: line 10'
                'at <ScriptBlock>, F:\test\build.ps1: line 20'
            ) -join $nl

            $trace = InModuleScope PSTaskFramework -ArgumentList $fakeStack {
                param($fakeStack)
                $exception = [System.Exception]::new('task error')
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception, 'TestError', [System.Management.Automation.ErrorCategory]::NotSpecified, $null)
                $bindingFlags = [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic
                $field = $errorRecord.GetType().GetField('_scriptStackTrace', $bindingFlags)
                $field.SetValue($errorRecord, $fakeStack)

                $task = [TaskDefinition]@{ Name = 'test-task'; Action = [scriptblock]::Create("throw 'error'") }
                Repair-TaskStackTrace -ErrorRecord $errorRecord -Task $task -TaskActionStartLine 2
                $errorRecord.ScriptStackTrace
            }

            $trace | Should -Be $fakeStack
        }
    }
}
