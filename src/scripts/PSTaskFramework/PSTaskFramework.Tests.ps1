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
        $ErrorActionPreference = 'Stop'
        $global:LASTEXITCODE = 0

        Import-Module "$PSScriptRoot/PSTaskFramework" -Scope Local -Verbose:$false

        # Mock Write-Information and Write-Verbose to prevent test output pollution.
        Mock Write-Information -ModuleName PSTaskFramework { }
        Mock Write-Verbose -ModuleName PSTaskFramework { }
    }

    BeforeEach {
        # Initialize a fresh TaskContext for each test to ensure test isolation.
        $buildScript = Join-Path $TestDrive 'dummyBuild.ps1'
        '<# dummy script #>' | Out-File $buildScript

        $TaskContext = Initialize-TaskFramework -BuildScriptPath $buildScript -AddDefaultTasks @()
        $null = $TaskContext
    }

    Describe 'Get-TaskFrameworkContext' {
        It 'returns the current TaskContext' {
            $context = Get-TaskFrameworkContext
            $context | Should -Be $TaskContext
        }

        It 'returns any context variable' {
            $Foo = @{ Bar = 233 }
            $context = Get-TaskFrameworkContext -Name 'Foo'
            $context | Should -Be $Foo
        }

        It 'throws an error when context variable is not found' {
            { Get-TaskFrameworkContext -Name ([guid]::NewGuid().ToString('n')) } |
            Should -Throw "Task context variable '*' not found*"
        }

        It 'throws an error when context variable is not a hashtable' {
            $Foo = 'NotAHashtable'
            $null = $Foo
            { Get-TaskFrameworkContext -Name 'Foo' } |
            Should -Throw "Task context variable '*' is not a hashtable*"
        }
    }

    Describe 'Initialize-TaskFramework' {
        It 'initializes TaskContext with expected values' {
            $TaskContext | Should -Not -BeNullOrEmpty
            $TaskContext['AllTasks'] | Should -BeOfType 'System.Collections.Specialized.OrderedDictionary'
            $TaskContext['AllTasks'].Count | Should -Be 0
            $TaskContext['TasksSorted'] | Should -Be $true
            $TaskContext['BuildScriptPath'] | Should -Be $buildScript
            $TaskContext['TaskNameArgName'] | Should -Be 'TaskName'
            $TaskContext['TaskArgsArgName'] | Should -Be 'TaskArgs'
        }

        It 'throws an error when build script path does not exist' {
            { Initialize-TaskFramework -BuildScriptPath 'nonexistent.ps1' } | Should -Throw "Cannot find path*"
        }

        It 'adds default tasks by default' {
            $context = Initialize-TaskFramework -BuildScriptPath $buildScript

            $tasks = $context['AllTasks']
            $tasks.Count | Should -Be 2
            $tasks['list'] | Should -Not -BeNullOrEmpty
            $tasks['help'] | Should -Not -BeNullOrEmpty
        }

        It 'registers TaskNameArgName and TaskArgsArgName in TaskContext' {
            $context = Initialize-TaskFramework -BuildScriptPath $buildScript -TaskNameArgName 'tName' -TaskArgsArgName 'tArgs'

            $context['TaskNameArgName'] | Should -Be 'tName'
            $context['TaskArgsArgName'] | Should -Be 'tArgs'
        }
    }

    Describe 'Task command' {
        It 'registers simple Task' {
            Task 'foo' { }

            $TaskContext['AllTasks'].Count | Should -Be 1
            $TaskContext['TasksSorted'] | Should -Be $false
            $task = $TaskContext['AllTasks']['foo']
            $task | Should -Not -BeNullOrEmpty
            $task.Name | Should -Be 'foo'
            $task.Description | Should -BeNullOrEmpty
            $task.DependsOn | Should -Be @()
            $task.Action | Should -BeOfType [scriptblock]
            $task.AllowedExitCodes | Should -Be @(0)
        }

        It 'registers Task with allowed exit codes' {
            Task 'beta' -Description 'second task' -AllowedExitCodes 1, 2, 3 { }

            $TaskContext['AllTasks'].Count | Should -Be 1
            $TaskContext['TasksSorted'] | Should -Be $false
            $task = $TaskContext['AllTasks']['beta']
            $task | Should -Not -BeNullOrEmpty
            $task.Name | Should -Be 'beta'
            $task.Description | Should -Be 'second task'
            $task.DependsOn | Should -Be @()
            $task.Action | Should -BeOfType [scriptblock]
            $task.AllowedExitCodes | Should -Be @(1, 2, 3)
        }

        It 'registers Task without action' {
            Task 'noop' -Action $null

            $TaskContext['AllTasks'].Count | Should -Be 1
            $TaskContext['TasksSorted'] | Should -Be $false
            $task = $TaskContext['AllTasks']['noop']
            $task | Should -Not -BeNullOrEmpty
            $task.Name | Should -Be 'noop'
            $task.Description | Should -BeNullOrEmpty
            $task.DependsOn | Should -Be @()
            $task.Action | Should -BeNullOrEmpty
            $task.AllowedExitCodes | Should -Be @(0)
        }

        It 'registers Task with undefined dependency' {
            Task 'alpha' -DependsOn 'beta' {}

            $TaskContext['AllTasks'].Count | Should -Be 1
            $TaskContext['TasksSorted'] | Should -Be $false
            $task = $TaskContext['AllTasks']['alpha']
            $task | Should -Not -BeNullOrEmpty
            $task.Name | Should -Be 'alpha'
            $task.Description | Should -BeNullOrEmpty
            $task.DependsOn | Should -Be @('beta')
            $task.Action | Should -BeNullOrEmpty
            $task.AllowedExitCodes | Should -Be @(0)
        }

        It 'registers multiple Tasks' {
            Task 't1' { }
            Task 't2' { }

            $TaskContext['AllTasks'].Count | Should -Be 2
            $TaskContext['TasksSorted'] | Should -Be $false
            $TaskContext['AllTasks']['t1'] | Should -Not -BeNullOrEmpty
            $TaskContext['AllTasks']['t2'] | Should -Not -BeNullOrEmpty
        }

        It 'rejects duplicate task names case-insensitively' {
            Task 'Build' {}

            { Task 'build' {} } | Should -Throw '*already exists*'
        }

    }

    Describe 'Get-TaskFrameworkTasks' {
        It 'returns all registered tasks' {
            Task t1 { }
            Task t2 { }

            $tasks = Get-TaskFrameworkTasks
            $tasks.Name | Should -Contain 't1'
            $tasks.Name | Should -Contain 't2'
        }

        It 'returns tasks in dependency order' {
            Task t1 -DependsOn t3 { }
            Task t2 { }
            Task t3 { }

            $tasks = Get-TaskFrameworkTasks
            $tasks[0].Name | Should -Be 't3' -Because 't1 depends on t3'
            $tasks[1].Name | Should -Be 't1' -Because 't1 defined before t2'
            $tasks[2].Name | Should -Be 't2'
        }
    }

    Describe 'Invoke-TaskFramework' {
        It 'fails when no tasks are specified' {
            { Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName 'foo' } | Should -Throw "Task 'foo' not found."
            $global:LASTEXITCODE | Should -Be -1
        }

        It 'executes registered tasks' {
            $shared = [ordered]@{ State = [System.Collections.Generic.List[string]]::new() }

            Task 'alpha' -Description 'first task' -Action { $Shared.State.Add('alpha') } -DependsOn @('beta')
            Task 'beta' -Description 'second task' -Action { $Shared.State.Add('beta') }

            Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName @('alpha')

            $shared.State | Should -Be @('beta', 'alpha')
        }

        It 'executes dependencies before task by default' {
            $shared = [ordered]@{ State = [System.Collections.Generic.List[string]]::new() }

            Task 'dep' { $Shared.State.Add('dep') }
            Task 'main' { $Shared.State.Add('main') } -DependsOn @('dep')

            Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName @('main')

            $shared.State | Should -Be @('dep', 'main')
        }

        It 'skips dependencies when SkipDependencies is specified' {
            $shared = [ordered]@{ State = [System.Collections.Generic.List[string]]::new() }

            Task 'dep' { $Shared.State.Add('dep') }
            Task 'main' { $Shared.State.Add('main') } -DependsOn @('dep')

            Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName @('main') -SkipDependencies

            $shared.State | Should -Be @('main')
        }

        It 'passes TaskArgs to a single task' {
            $shared = [ordered]@{ Captured = '' }

            Task 'echo' {
                param([string]$Name, [int]$Count)
                $Shared.Captured = ("{0}:{1}" -f $Name, $Count)
            }

            Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName @('echo') -TaskArgs @('sample', 3)

            $shared.Captured | Should -Be 'sample:3'
        }

        It 'fails when TaskArgs are used with multiple tasks' {
            Task 'first' {}
            Task 'second' {}

            { Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName @('first', 'second') -TaskArgs @('x') } |
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

            Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName @('use-vars')

            $shared.Result | Should -Be 'hello, world'
        }

        It 'executes task in task-scope' {
            $Name = 'outer scope'

            Task 'use-vars' {
                # modifying an outer variable is not seen outside the task
                $Name = 'task scope'
                $null = $Name # avoid unused variable warning
            }

            Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName @('use-vars')

            $Name | Should -Be 'outer scope'
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

            { Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName @('main') } |
            Should -Throw "Dependency 'missing' of task 'main' not found."

            $global:LASTEXITCODE | Should -Be -1
        }

        It 'fails when dependencies are circular' {
            Task 'a' {} -DependsOn @('b')
            Task 'b' {} -DependsOn @('a')

            { Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName @('a') } |
            Should -Throw "Circular dependency detected at *"

            $global:LASTEXITCODE | Should -Be -1
        }

        It 'provides correct TaskContext during execution' {
            Task alpha {
                $TaskContext['WorkingDirectory'] | Should -Be $TestDrive
                $TaskContext['SkipDependencies'] | Should -Be $false
                $TaskContext['TasksToExecute'] | Should -Be @('alpha', 'before', 'check')
                $TaskContext['Task'] | Should -Not -BeNullOrEmpty
                $TaskContext['Task'].Name | Should -Be 'alpha'
                $TaskContext['TaskArgs'] | Should -BeNullOrEmpty
            }
            Task before -DependsOn alpha {
                $TaskContext['WorkingDirectory'] | Should -Be $TestDrive
                $TaskContext['SkipDependencies'] | Should -Be $false
                $TaskContext['TasksToExecute'] | Should -Be @('alpha', 'before', 'check')
                $TaskContext['Task'] | Should -Not -BeNullOrEmpty
                $TaskContext['Task'].Name | Should -Be 'before'
                $TaskContext['TaskArgs'] | Should -BeNullOrEmpty
            }
            Task check -DependsOn before, alpha {
                $TaskContext['WorkingDirectory'] | Should -Be $TestDrive
                $TaskContext['SkipDependencies'] | Should -Be $false
                $TaskContext['TasksToExecute'] | Should -Be @('alpha', 'before', 'check')
                $TaskContext['Task'] | Should -Not -BeNullOrEmpty
                $TaskContext['Task'].Name | Should -Be 'check'
                $TaskContext['TaskArgs'] | Should -Be @('arg1', 'arg2')
            }

            Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName 'check' -TaskArgs 'arg1', 'arg2'
        }

        It 'provides correct TaskContext after execution' {
            Task check -AllowedExitCodes 45 {
                $Global:LASTEXITCODE = 45
            }

            Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName 'check' -TaskArgs 'arg1', 'arg2'

            $TaskContext['Task'] | Should -Not -BeNullOrEmpty
            $TaskContext['Task'].Name | Should -Be 'check'
            $TaskContext['TaskArgs'] | Should -Be @('arg1', 'arg2')
            $TaskContext['ExitCode'] | Should -Be 45
        }

        It 'provides correct TaskContext after failed task' {
            Task dependency { $Global:LASTEXITCODE = 666 }
            Task check -DependsOn dependency { }

            { Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName 'check' -TaskArgs 'arg1', 'arg2' } |
            Should -Throw "Task 'dependency' failed with exit code 666."

            $TaskContext['Task'] | Should -Not -BeNullOrEmpty
            $TaskContext['Task'].Name | Should -Be 'dependency'
            $TaskContext['TaskArgs'] | Should -BeNullOrEmpty
            $TaskContext['ExitCode'] | Should -Be 666
        }
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

                # Action.Ast.Extent.StartLineNumber == 1 for inline script blocks
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

    Describe 'Add-TaskFrameworkDefaultTasks' {
        It 'adds list and help tasks by default' {
            Add-TaskFrameworkDefaultTasks

            $tasks = Get-TaskFrameworkTasks
            $tasks.Name | Should -Contain 'list'
            $tasks.Name | Should -Contain 'help'
        }

        It 'adds only list when -Include list' {
            Add-TaskFrameworkDefaultTasks -Include 'list'

            $tasks = Get-TaskFrameworkTasks
            $tasks.Name | Should -Contain 'list'
            $tasks.Name | Should -Not -Contain 'help'
        }

        It 'adds only help when -Include help' {
            Add-TaskFrameworkDefaultTasks -Include 'help'

            $tasks = Get-TaskFrameworkTasks
            $tasks.Name | Should -Contain 'help'
            $tasks.Name | Should -Not -Contain 'list'
        }

        It 'uses NameMap to rename list task' {
            Add-TaskFrameworkDefaultTasks -Include 'list' -NameMap @{ list = 'tasks' }

            $tasks = Get-TaskFrameworkTasks
            $tasks.Name | Should -Contain 'tasks'
            $tasks.Name | Should -Not -Contain 'list'
        }

        It 'uses NameMap to rename help task' {
            Add-TaskFrameworkDefaultTasks -Include 'help' -NameMap @{ help = 'usage' }

            $tasks = Get-TaskFrameworkTasks
            $tasks.Name | Should -Contain 'usage'
            $tasks.Name | Should -Not -Contain 'help'
        }

        It 'skips default task if a task with that name already exists' {
            Task 'list' { 'custom list' }
            $countBefore = @(Get-TaskFrameworkTasks).Count

            Add-TaskFrameworkDefaultTasks -Include 'list'

            $tasks = Get-TaskFrameworkTasks
            @($tasks).Count | Should -Be $countBefore
            $tasks.Name | Should -Contain 'list'
        }

        Describe 'default "list" task' {
            BeforeEach {
                Task 'task2' -Description 'described task 2' -DependsOn 'task1' {}
                Task 'task1' -Description 'described task 1' -DependsOn 'list' {}
                Add-TaskFrameworkDefaultTasks -Include 'list'

                $output = [System.Collections.Generic.List[object]]::new()
                Mock Out-Host -ModuleName PSTaskFramework {
                    $output.AddRange(@($InputObject))
                }

                Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName 'list'
            }

            It 'should invoke Out-Host to display output' {
                Should -Invoke Out-Host -ModuleName PSTaskFramework -Times 1
            }

            It 'lists all tasks with descriptions in dependency order' {
                $text = ($output | Out-String).Trim()
                $text | Should -BeExactly @'
Name  Description            DependsOn
----  -----------            ---------
list  List all defined tasks {}
task1 described task 1       {list}
task2 described task 2       {task1}
'@
            }
        }

        Describe 'default "help" task' {
            BeforeEach {
                Mock Get-TaskFrameworkHelp -ModuleName PSTaskFramework { 'mocked help' }
                Mock Out-Host -ModuleName PSTaskFramework {}
                if (Get-Command more -ea Ignore) { Mock more -ModuleName PSTaskFramework {} }
                if (Get-Command less -ea Ignore) { Mock less -ModuleName PSTaskFramework {} }
            }

            It 'calls Get-TaskFrameworkHelp when invoked' {
                Add-TaskFrameworkDefaultTasks -Include 'help'

                Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName 'help' -TaskArgs @('-NoPaging')

                Should -Invoke Get-TaskFrameworkHelp -ModuleName PSTaskFramework -Times 1
                Should -Invoke Out-Host -ModuleName PSTaskFramework -Times 1
                if ($IsWindows) { Should -Invoke more -ModuleName PSTaskFramework -Times 0 }
                else { Should -Invoke less -ModuleName PSTaskFramework -Times 0 }
            }

            It 'calls Get-TaskFrameworkHelp when context is customized' {
                $TaskContext = Initialize-TaskFramework `
                    -BuildScriptPath $buildScript `
                    -AddDefaultTasks @() `
                    -TaskNameArgName 'tName' `
                    -TaskArgsArgName 'tArgs'

                Add-TaskFrameworkDefaultTasks -Include 'list', 'help' -NameMap @{ help = 'getHelp' }

                $TaskContext['HelpTaskName'] | Should -Be 'getHelp'
                $TaskContext['TaskNameArgName'] | Should -Be 'tName'
                $TaskContext['TaskArgsArgName'] | Should -Be 'tArgs'

                Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName 'getHelp' -TaskArgs 'list', '-full'

                Should -Invoke Get-TaskFrameworkHelp -ModuleName PSTaskFramework -Times 1 -ParameterFilter {
                    $TaskName | Should -Be 'list'
                    $GetHelpArgs.Keys | Should -Contain 'Full'
                    $true
                }

                if ($IsWindows) { Should -Invoke more -ModuleName PSTaskFramework -Times 1 }
                else { Should -Invoke less -ModuleName PSTaskFramework -Times 1 }
            }
        }

        Describe 'default "null" task' {
            It 'should do nothing when invoked' {
                Add-TaskFrameworkDefaultTasks -Include 'null'

                Invoke-TaskFramework -WorkingDirectory $TestDrive -TaskName 'null'

                $global:LASTEXITCODE | Should -Be 0
            }
        }
    }

    Describe 'Get-TaskFrameworkHelp' {
        BeforeEach {
            # Minimal build script with the parameters Get-TaskFrameworkHelp needs to merge help from.
            Set-Content -Path $buildScript -Value @'
<#
.DESCRIPTION
    A test build script.
#>
[CmdletBinding(PositionalBinding = $false)]
param (
    # The name of the task(s) to execute.
    [Parameter(Position = 0)]
    [string[]] $TaskName,
    # Task-specific arguments.
    [Parameter(ValueFromRemainingArguments)]
    [object[]] $TaskArgs
)
'@
        }

        It 'returns build script help when no TaskName is specified' {
            $output = Get-TaskFrameworkHelp

            $output | Should -Not -BeNullOrEmpty
            $output | Should -Match 'A test build script\.'
        }

        It 'throws when TaskName refers to a nonexistent task' {
            { Get-TaskFrameworkHelp -TaskName 'nonexistent' } |
            Should -Throw "Task 'nonexistent' not found."
        }

        It 'uses TASK NAME heading instead of NAME for a task' {
            Task 'myTask' { param() }

            $output = Get-TaskFrameworkHelp -TaskName 'myTask'

            $output | Should -Match '(?m)^TASK NAME'
            $output | Should -Not -Match '(?m)^NAME$'
        }

        It 'includes the action comment-based description in the output' {
            Task 'described' {
                <#
                .DESCRIPTION
                    A very descriptive task.
                #>
                param()
            }

            $output = Get-TaskFrameworkHelp -TaskName 'described'

            $output | Should -Match 'A very descriptive task'
        }

        It 'shows no dependencies in DEPENDS ON when task has none' {
            Task 'noDeps' { param() }

            $output = Get-TaskFrameworkHelp -TaskName 'noDeps'

            $output | Should -Match '(?m)^DEPENDS ON'
            $output | Should -Match 'This task has no task dependencies\.'
        }

        It 'lists dependencies in DEPENDS ON when task has DependsOn' {
            Task 'preReq' { param() }
            Task 'withDeps' { param() } -DependsOn @('preReq')

            $output = Get-TaskFrameworkHelp -TaskName 'withDeps'

            $output | Should -Match '(?m)^DEPENDS ON'
            $output | Should -Match 'This task depends on the following tasks'
            $output | Should -Match '\- preReq'
        }

        It 'generates help for a meta-task with null action' {
            Task 'meta' $null -Description 'A grouping task'

            $output = Get-TaskFrameworkHelp -TaskName 'meta'

            $output | Should -Match '(?m)^TASK NAME'
            $output | Should -Match 'A grouping task'
        }

        It 'includes the build script path in the syntax section' {
            Task 'myTask2' { param() }

            $output = Get-TaskFrameworkHelp -TaskName 'myTask2'

            $output | Should -Match ([regex]::Escape($buildScript))
        }

        It 'respects custom HelpTaskName in the remarks section' {
            Task 'someTask' {
                <#
                .DESCRIPTION
                    A task with a description.
                #>
                param()
            }

            $TaskContext['HelpTaskName'] = 'usage'
            $output = Get-TaskFrameworkHelp -TaskName 'someTask'

            $output | Should -Match ([regex]::Escape("$($buildScript) usage someTask"))
        }
    }
}
