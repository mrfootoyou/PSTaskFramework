<#
.DESCRIPTION
    Unit tests for PSArgs module.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4
# spell:ignore pscustomobject

param()

Describe 'PSTaskFramework.PSArgs Module' {
    . "$PSScriptRoot/setup.ps1"

    Context 'ConvertTo-CommandArg' {
        It 'returns an empty string for null input' {
            $result = $null | ConvertTo-CommandArg

            $result | Should -BeExactly ''
        }

        It 'converts arrays into space-separated arguments' {
            $result = ConvertTo-CommandArg -InputObject @('alpha', 'beta value', 42)

            $result | Should -BeExactly "alpha 'beta value' 42"
        }

        It 'converts dictionaries into named arguments' {
            $result = ([ordered]@{ Name = 'value with space'; Count = 2 }) | ConvertTo-CommandArg

            $result | Should -BeExactly "-Name:'value with space' -Count:2"
        }

        It 'converts PSCustomObject into named arguments' {
            $result = ([pscustomobject]@{ Name = 'value with space'; Enabled = $true }) | ConvertTo-CommandArg

            $result | Should -BeExactly "-Name:'value with space' -Enabled:`$True"
        }

        It 'converts single scalar values to argument strings' {
            $result = 'value with space' | ConvertTo-CommandArg

            $result | Should -BeExactly "'value with space'"
        }
    }
}
