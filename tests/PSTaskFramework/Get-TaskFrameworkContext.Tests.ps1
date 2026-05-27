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
