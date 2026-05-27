<#
.DESCRIPTION
    Unit tests for Get-TaskFrameworkHelp.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4

param()

Describe 'PSTaskFramework Module' {
    . "$PSScriptRoot/setup.ps1"

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

            $TaskContext.HelpTaskName = 'usage'
            $output = Get-TaskFrameworkHelp -TaskName 'someTask'

            $output | Should -Match ([regex]::Escape("$($buildScript) usage someTask"))
        }
    }
}
