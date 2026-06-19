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

    Context 'ConvertTo-PSString' {
        It 'converts null to a null literal' {
            $result = $null | ConvertTo-PSString

            $result | Should -Be '$null'
        }

        It 'returns unquoted safe strings by default' {
            $result = 'simpleValue' | ConvertTo-PSString

            $result | Should -BeExactly 'simpleValue'
        }

        It 'quotes strings that contain spaces' {
            $result = 'hello world' | ConvertTo-PSString

            $result | Should -BeExactly "'hello world'"
        }

        It 'escapes single quotes inside strings' {
            $result = "A'hoy" | ConvertTo-PSString

            $result | Should -BeExactly "'A''hoy'"
        }

        It 'uses double-quoted escaped form for control characters' {
            $result = "line1`n line2" | ConvertTo-PSString

            $result | Should -BeExactly '"line1`n line2"'
        }

        It 'forces quotes when UseQuotes is set' {
            $result = 'simpleValue' | ConvertTo-PSString -UseQuotes

            $result | Should -BeExactly "'simpleValue'"
        }

        It 'converts booleans to PowerShell literals' {
            ($true | ConvertTo-PSString) | Should -BeExactly '$True'
            ($false | ConvertTo-PSString) | Should -BeExactly '$False'
        }

        It 'converts numeric values without quotes' {
            (123 | ConvertTo-PSString) | Should -BeExactly '123'
            (12.5 | ConvertTo-PSString) | Should -BeExactly '12.5'
        }

        It 'converts collections to array literals' {
            $result = ConvertTo-PSString -InputObject @('alpha', 'beta value')

            $result | Should -BeExactly "@('alpha','beta value')"
        }

        It 'converts hashtable to hashtable literals' {
            $result = @{ Name = 'test value' } | ConvertTo-PSString

            $result | Should -BeExactly "@{Name = 'test value'}"
        }

        It 'converts ordered dictionaries to ordered dictionary literals' {
            $ht = [ordered]@{ Name = 'test value'; Count = 2 }
            $result = $ht | ConvertTo-PSString

            $result | Should -BeExactly "([ordered]@{Name = 'test value';Count = 2})"
        }

        It 'converts PSCustomObject to pscustomobject literals' {
            $result = ([pscustomobject]@{ Name = 'n'; Count = 2 }) | ConvertTo-PSString

            $result | Should -BeExactly "([pscustomobject]@{Name = 'n';Count = 2})"
        }

        It 'converts script blocks into brace-wrapped text' {
            $result = { Get-Date } | ConvertTo-PSString

            $result | Should -BeExactly '{ Get-Date }'
        }
    }
}
