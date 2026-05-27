<#
.DESCRIPTION
    Unit tests for the Task command (DSL keyword).
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4

param()

Describe 'PSTaskFramework Module' {
    . "$PSScriptRoot/setup.ps1"

    Describe 'Task command' {
        It 'registers simple Task' {
            Task 'foo' { }

            $TaskContext.AllTasks.Count | Should -Be 1
            $TaskContext.AllTasksSorted | Should -Be $false
            $task = $TaskContext.AllTasks['foo']
            $task | Should -Not -Be $null
            $task.Name | Should -Be 'foo'
            $task.Description | Should -Be ''
            $task.DependsOn | Should -Be @()
            $task.Action | Should -BeOfType [scriptblock]
            $task.AllowedExitCodes | Should -Be @(0)
        }

        It 'registers Task with allowed exit codes' {
            Task 'beta' -Description 'second task' -AllowedExitCodes 1, 2, 3 { }

            $TaskContext.AllTasks.Count | Should -Be 1
            $TaskContext.AllTasksSorted | Should -Be $false
            $task = $TaskContext.AllTasks['beta']
            $task | Should -Not -Be $null
            $task.Name | Should -Be 'beta'
            $task.Description | Should -Be 'second task'
            $task.DependsOn | Should -Be @()
            $task.Action | Should -BeOfType [scriptblock]
            $task.AllowedExitCodes | Should -Be @(1, 2, 3)
        }

        It 'registers Task without action' {
            Task 'noop' -Action $null

            $TaskContext.AllTasks.Count | Should -Be 1
            $TaskContext.AllTasksSorted | Should -Be $false
            $task = $TaskContext.AllTasks['noop']
            $task | Should -Not -Be $null
            $task.Name | Should -Be 'noop'
            $task.Description | Should -Be ''
            $task.DependsOn | Should -Be @()
            $task.Action | Should -Be $null
            $task.AllowedExitCodes | Should -Be @(0)
        }

        It 'registers Task with undefined dependency' {
            Task 'alpha' -DependsOn 'beta' {}

            $TaskContext.AllTasks.Count | Should -Be 1
            $TaskContext.AllTasksSorted | Should -Be $false
            $task = $TaskContext.AllTasks['alpha']
            $task | Should -Not -Be $null
            $task.Name | Should -Be 'alpha'
            $task.Description | Should -Be ''
            $task.DependsOn | Should -Be @('beta')
            $task.Action | Should -Not -Be $null
            $task.AllowedExitCodes | Should -Be @(0)
        }

        It 'registers multiple Tasks' {
            Task 't1' { }
            Task 't2' { }

            $TaskContext.AllTasks.Count | Should -Be 2
            $TaskContext.AllTasksSorted | Should -Be $false
            $TaskContext.AllTasks['t1'] | Should -Not -Be $null
            $TaskContext.AllTasks['t2'] | Should -Not -Be $null
        }

        It 'rejects duplicate task names case-insensitively' {
            Task 'Build' {}

            { Task 'build' {} } | Should -Throw '*already exists*'
        }

    }
}
