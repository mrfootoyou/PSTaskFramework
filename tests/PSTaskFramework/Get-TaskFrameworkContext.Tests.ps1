<#
.DESCRIPTION
    Unit tests for Get-TaskFrameworkContext.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4

param()

Describe 'PSTaskFramework Module' {
    . "$PSScriptRoot/setup.ps1"

    Describe 'Get-TaskFrameworkContext' {
        It 'returns the current TaskContext' {
            $context = Get-TaskFrameworkContext
            $context | Should -Be $TaskContext
        }

        It 'returns any context variable' {
            $Foo = Initialize-TaskFramework -BuildScriptPath $buildScript
            $context = Get-TaskFrameworkContext -Name 'Foo'
            $context | Should -Be $Foo
        }

        It 'throws an error when context variable is not found' {
            { Get-TaskFrameworkContext -Name ([guid]::NewGuid().ToString('n')) } |
            Should -Throw "Task context variable '*' not found*"
        }

        It 'throws an error when context variable is not a TaskContext' {
            $Foo = 'NotAHashtable'
            $null = $Foo
            { Get-TaskFrameworkContext -Name 'Foo' } |
            Should -Throw "Task context variable '*' is not a TaskContext*"
        }
    }
}
