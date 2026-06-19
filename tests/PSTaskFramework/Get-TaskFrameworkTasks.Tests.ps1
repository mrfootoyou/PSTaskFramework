<#
.DESCRIPTION
    Unit tests for Get-TaskFrameworkTasks.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4

param()

Describe 'PSTaskFramework Module' {
    . "$PSScriptRoot/setup.ps1"

    Context 'Get-TaskFrameworkTasks' {
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
}
