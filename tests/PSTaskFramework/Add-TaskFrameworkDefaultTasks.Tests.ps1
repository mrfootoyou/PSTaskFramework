<#
.DESCRIPTION
    Unit tests for Add-TaskFrameworkDefaultTasks.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4

param()

Describe 'PSTaskFramework Module' {
    . "$PSScriptRoot/setup.ps1"

    Context 'Add-TaskFrameworkDefaultTasks' {
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

        Context 'default "list" task' {
            BeforeEach {
                Task 'task2' -Description 'described task 2' -DependsOn 'task1' {}
                Task 'task1' -Description 'described task 1' -DependsOn 'list' {}
                Add-TaskFrameworkDefaultTasks -Include 'list'

                $output = [System.Collections.Generic.List[object]]::new()
                Mock Out-Host -ModuleName PSTaskFramework {
                    $output.AddRange(@($InputObject))
                }

                Invoke-TaskFramework -TaskName 'list'
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

        Context 'default "help" task' {
            BeforeEach {
                Mock Get-TaskFrameworkHelp -ModuleName PSTaskFramework { 'mocked help' }
                Mock Out-Host -ModuleName PSTaskFramework {}
                if (Get-Command more -ea Ignore) { Mock more -ModuleName PSTaskFramework {} }
                if (Get-Command less -ea Ignore) { Mock less -ModuleName PSTaskFramework {} }
            }

            It 'calls Get-TaskFrameworkHelp when invoked' {
                Add-TaskFrameworkDefaultTasks -Include 'help'

                Invoke-TaskFramework -TaskName 'help' -TaskArgs @('-NoPaging')

                Should -Invoke Get-TaskFrameworkHelp -ModuleName PSTaskFramework -Times 1
                Should -Invoke Out-Host -ModuleName PSTaskFramework -Times 1
                if ($IsWindows) { Should -Invoke more -ModuleName PSTaskFramework -Times 0 }
                else { Should -Invoke less -ModuleName PSTaskFramework -Times 0 }
            }

            It 'calls Get-TaskFrameworkHelp when context is customized' {
                $TaskContext = Initialize-TaskFramework `
                    -BuildScriptPath $buildScript `
                    -TaskNameArgName 'tName' `
                    -TaskArgsArgName 'tArgs'

                Add-TaskFrameworkDefaultTasks -Include 'list', 'help' -NameMap @{ help = 'getHelp' }

                $TaskContext.HelpTaskName | Should -Be 'getHelp'
                $TaskContext.TaskNameArgName | Should -Be 'tName'
                $TaskContext.TaskArgsArgName | Should -Be 'tArgs'

                Invoke-TaskFramework -TaskName 'getHelp' -TaskArgs 'list', '-full'

                Should -Invoke Get-TaskFrameworkHelp -ModuleName PSTaskFramework -Times 1 -ParameterFilter {
                    $TaskName | Should -Be 'list'
                    $GetHelpArgs.Keys | Should -Contain 'Full'
                    $true
                }

                if ($IsWindows) { Should -Invoke more -ModuleName PSTaskFramework -Times 1 }
                else { Should -Invoke less -ModuleName PSTaskFramework -Times 1 }
            }
        }

        Context 'default "null" task' {
            It 'should do nothing when invoked' {
                Add-TaskFrameworkDefaultTasks -Include 'null'

                Invoke-TaskFramework -TaskName 'null'

                $global:LASTEXITCODE | Should -Be 0
            }
        }
    }
}
