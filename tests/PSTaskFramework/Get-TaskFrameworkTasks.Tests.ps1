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
}
