<#
.DESCRIPTION
    Unit tests for Invoke-TaskFramework.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4

param()

Describe 'PSTaskFramework Module' {
    BeforeAll {
        $ErrorActionPreference = 'Stop'
        $global:LASTEXITCODE = 0

        Import-Module "$PSScriptRoot/../../src/scripts/PSTaskFramework/PSTaskFramework" -Scope Local -Verbose:$false

        # Mock Write-Information and Write-Verbose to prevent test output pollution.
        Mock Write-Information -ModuleName PSTaskFramework { }
        Mock Write-Verbose -ModuleName PSTaskFramework { }
    }

    BeforeEach {
        # Initialize a fresh TaskContext for each test to ensure test isolation.
        $buildScript = Join-Path $TestDrive 'dummyBuild.ps1'
        '<# dummy script #>' | Out-File $buildScript

        $TaskContext = Initialize-TaskFramework -BuildScriptPath $buildScript
        $null = $TaskContext
    }

    Describe 'Invoke-TaskFramework' {
        It 'fails when no tasks are specified' {
            { Invoke-TaskFramework -TaskName 'foo' } | Should -Throw "Task 'foo' not found."
            $global:LASTEXITCODE | Should -Be -1
        }

        It 'executes registered tasks' {
            $shared = [ordered]@{ State = [System.Collections.Generic.List[string]]::new() }

            Task 'alpha' -Description 'first task' -Action { $Shared.State.Add('alpha') } -DependsOn @('beta')
            Task 'beta' -Description 'second task' -Action { $Shared.State.Add('beta') }

            Invoke-TaskFramework -TaskName @('alpha')

            $shared.State | Should -Be @('beta', 'alpha')
        }

        It 'executes dependencies before task by default' {
            $shared = [ordered]@{ State = [System.Collections.Generic.List[string]]::new() }

            Task 'dep' { $Shared.State.Add('dep') }
            Task 'main' { $Shared.State.Add('main') } -DependsOn @('dep')

            Invoke-TaskFramework -TaskName @('main')

            $shared.State | Should -Be @('dep', 'main')
        }

        It 'skips dependencies when SkipDependencies is specified' {
            $shared = [ordered]@{ State = [System.Collections.Generic.List[string]]::new() }

            Task 'dep' { $Shared.State.Add('dep') }
            Task 'main' { $Shared.State.Add('main') } -DependsOn @('dep')

            Invoke-TaskFramework -TaskName @('main') -SkipDependencies

            $shared.State | Should -Be @('main')
        }

        It 'passes TaskArgs to a single task' {
            $shared = [ordered]@{ Captured = '' }

            Task 'echo' {
                param([string]$Name, [int]$Count)
                $Shared.Captured = ("{0}:{1}" -f $Name, $Count)
            }

            Invoke-TaskFramework -TaskName @('echo') -TaskArgs @('sample', 3)

            $shared.Captured | Should -Be 'sample:3'
        }

        It 'fails when TaskArgs are used with multiple tasks' {
            Task 'first' {}
            Task 'second' {}

            { Invoke-TaskFramework -TaskName @('first', 'second') -TaskArgs @('x') } |
            Should -Throw '*Task arguments cannot be used when invoking multiple tasks.*'

            $global:LASTEXITCODE | Should -Be -1
        }

        It 'executes task in script-scope' {
            $shared = [ordered]@{ Result = '' }
            $Greeting = 'hello'
            $Name = 'world'

            Task 'use-vars' {
                $Shared.Result = "$Greeting, $Name"
            }

            Invoke-TaskFramework -TaskName @('use-vars')

            $shared.Result | Should -Be 'hello, world'
        }

        It 'executes task in task-scope' {
            $Name = 'outer scope'

            Task 'use-vars' {
                # modifying an outer variable is not seen outside the task
                $Name = 'task scope'
                $null = $Name # avoid unused variable warning
            }

            Invoke-TaskFramework -TaskName @('use-vars')

            $Name | Should -Be 'outer scope'
        }

        It 'preserves non-zero task exit code on failure' {
            Task 'fails' {
                $global:LASTEXITCODE = 42
            }

            { Invoke-TaskFramework -TaskName 'fails' } |
            Should -Throw "Task 'fails' failed with exit code 42."

            $global:LASTEXITCODE | Should -Be 42
        }

        It 'ignores non-zero AllowedExitCodes' {
            Task 'fails' -AllowedExitCodes @('42') {
                $global:LASTEXITCODE = 42
            }

            Invoke-TaskFramework -TaskName 'fails'
            $global:LASTEXITCODE | Should -Be 0
        }

        It 'ignores exit code when no AllowedExitCodes' {
            Task 'fails' -AllowedExitCodes @() {
                $global:LASTEXITCODE = 42
            }

            Invoke-TaskFramework -TaskName 'fails'
            $global:LASTEXITCODE | Should -Be 0
        }

        It 'does not reset framework state after invocation' {
            Task 'run-once' {}

            Invoke-TaskFramework -TaskName @('run-once')
            Invoke-TaskFramework -TaskName @('run-once')

            $global:LASTEXITCODE | Should -Be 0
        }

        It 'fails when dependency is missing' {
            Task 'main' {} -DependsOn @('missing')

            { Invoke-TaskFramework -TaskName @('main') } |
            Should -Throw "Dependency 'missing' of task 'main' not found."

            $global:LASTEXITCODE | Should -Be -1
        }

        It 'fails when dependencies are circular' {
            Task 'a' {} -DependsOn @('b')
            Task 'b' {} -DependsOn @('a')

            { Invoke-TaskFramework -TaskName @('a') } |
            Should -Throw "Circular dependency detected at *"

            $global:LASTEXITCODE | Should -Be -1
        }

        It 'provides correct TaskContext during execution' {
            Task null -Action $null
            Task alpha -DependsOn null {
                $TaskContext.WorkingDirectory | Should -Be $TestDrive
                $TaskContext.SkipDependencies | Should -Be $false
                $TaskContext.TasksToExecute | Should -Be @('null', 'alpha', 'before', 'check')
                $TaskContext.Start | Should -Not -Be $Null
                $TaskContext.Duration | Should -Be $Null
                $TaskContext.ExitCode | Should -Be $Null
                $TaskContext.CurrentTask | Should -Not -Be $Null
                $TaskContext.CurrentTask.Name | Should -Be 'alpha'
                $TaskContext.Results['alpha'].Start | Should -Not -Be $Null
                $TaskContext.Results['alpha'].TaskArgs.Raw.Count | Should -Be 0
                $TaskContext.Results['alpha'].Duration | Should -Be $Null
                $TaskContext.Results['alpha'].ExitCode | Should -Be $Null
            }
            Task before -DependsOn alpha {
                $TaskContext.WorkingDirectory | Should -Be $TestDrive
                $TaskContext.SkipDependencies | Should -Be $false
                $TaskContext.TasksToExecute | Should -Be @('null', 'alpha', 'before', 'check')
                $TaskContext.CurrentTask | Should -Not -Be $Null
                $TaskContext.CurrentTask.Name | Should -Be 'before'
                $TaskContext.Results['before'].Start | Should -Not -Be $Null
                $TaskContext.Results['before'].TaskArgs.Raw.Count | Should -Be 0
                $TaskContext.Results['before'].Duration | Should -Be $Null
                $TaskContext.Results['before'].ExitCode | Should -Be $Null
            }
            Task check -DependsOn before, alpha {
                $TaskContext.WorkingDirectory | Should -Be $TestDrive
                $TaskContext.SkipDependencies | Should -Be $false
                $TaskContext.TasksToExecute | Should -Be @('null', 'alpha', 'before', 'check')
                $TaskContext.CurrentTask | Should -Not -Be $Null
                $TaskContext.CurrentTask.Name | Should -Be 'check'
                $TaskContext.Results['check'].Start | Should -Not -Be $Null
                $TaskContext.Results['check'].TaskArgs.Raw | Should -Be @('arg1', 'arg2')
                $TaskContext.Results['check'].TaskArgs.Unbound | Should -Be @('arg1', 'arg2')
                $TaskContext.Results['check'].TaskArgs.Bound.Count | Should -Be 0
                $TaskContext.Results['check'].Duration | Should -Be $Null
                $TaskContext.Results['check'].ExitCode | Should -Be $Null
            }

            Invoke-TaskFramework -TaskName 'check' -TaskArgs 'arg1', 'arg2'

            $TaskContext.Results['null'].Duration | Should -Be ([TimeSpan]::Zero)
            $TaskContext.Results['null'].ExitCode | Should -Be 0
            $TaskContext.Results['alpha'].Duration | Should -BeGreaterThan ([TimeSpan]::Zero)
            $TaskContext.Results['alpha'].ExitCode | Should -Be 0
            $TaskContext.Results['before'].Duration | Should -BeGreaterThan ([TimeSpan]::Zero)
            $TaskContext.Results['before'].ExitCode | Should -Be 0
            $TaskContext.Results['check'].Duration | Should -BeGreaterThan ([TimeSpan]::Zero)
            $TaskContext.Results['check'].ExitCode | Should -Be 0
            $TaskContext.Duration | Should -BeGreaterThan ([TimeSpan]::Zero)
            $TaskContext.ExitCode | Should -Be 0
        }

        It 'provides correct TaskContext after execution' {
            Task check -AllowedExitCodes 45 {
                $Global:LASTEXITCODE = 45
            }

            Invoke-TaskFramework -TaskName 'check'

            $TaskContext.CurrentTask | Should -Be $Null
            $TaskContext.Results['check'].ExitCode | Should -Be 45
        }

        It 'provides correct TaskContext after task exception execution' {
            Task check {
                throw 'Task error'
            }

            { Invoke-TaskFramework -TaskName 'check' } |
            Should -Throw "Task error"

            $TaskContext.CurrentTask | Should -Not -Be $Null
            $TaskContext.CurrentTask.Name | Should -Be 'check'
            $TaskContext.Results['check'].Error | Should -Not -Be $Null
            $TaskContext.Results['check'].ExitCode | Should -Be $Null
            $TaskContext.Error | Should -Not -Be $Null
            $TaskContext.ExitCode | Should -Be -1
        }

        It 'provides correct TaskContext after failed task' {
            Task dependency { $Global:LASTEXITCODE = 666 }
            Task check -DependsOn dependency { }

            { Invoke-TaskFramework -TaskName 'check' } |
            Should -Throw "Task 'dependency' failed with exit code 666."

            $TaskContext.CurrentTask | Should -Not -Be $Null
            $TaskContext.CurrentTask.Name | Should -Be 'dependency'
            $TaskContext.Results.Count | Should -Be 1
            $TaskContext.Results['dependency'].ExitCode | Should -Be 666
            $TaskContext.ExitCode | Should -Be 666
        }
    }
}
