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
