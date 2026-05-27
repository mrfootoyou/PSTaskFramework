<#
.DESCRIPTION
    Unit tests for Initialize-TaskFramework.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4

param()

Describe 'PSTaskFramework Module' {
    . "$PSScriptRoot/setup.ps1"

    Describe 'Initialize-TaskFramework' {
        It 'initializes TaskContext with expected values' {
            $TaskContext | Should -Not -Be $null
            $TaskContext.AllTasks | Should -Not -Be $null
            $TaskContext.AllTasks.Count | Should -Be 0
            $TaskContext.AllTasksSorted | Should -Be $true
            $TaskContext.BuildScriptPath | Should -Be $buildScript
            $TaskContext.TaskNameArgName | Should -Be 'TaskName'
            $TaskContext.TaskArgsArgName | Should -Be 'TaskArgs'
        }

        It 'throws an error when build script path does not exist' {
            { Initialize-TaskFramework -BuildScriptPath 'nonexistent.ps1' } |
            Should -Throw "The specified build script path 'nonexistent.ps1' does not exist."
        }

        It 'adds no default tasks by default' {
            $TaskContext = Initialize-TaskFramework -BuildScriptPath $buildScript

            $tasks = $TaskContext.AllTasks
            $tasks.Count | Should -Be 0
        }

        It 'registers TaskNameArgName and TaskArgsArgName in TaskContext' {
            $TaskContext = Initialize-TaskFramework -BuildScriptPath $buildScript -TaskNameArgName 'tName' -TaskArgsArgName 'tArgs'

            $TaskContext.TaskNameArgName | Should -Be 'tName'
            $TaskContext.TaskArgsArgName | Should -Be 'tArgs'
        }
    }
}
