<#
.SYNOPSIS
    Part of the PSTaskFramework.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4
# spell:ignore pscustomobject

function ConvertTo-PSString {
    <#
    .DESCRIPTION
        Convert the given value to a PowerShell string literal.
        - Null values are converted to '$null'.
        - String and Char values are quoted and escaped if needed or requested.
          Single quotes are used for strings that do not contain escape characters.
        - Scalar values (bool, int, etc.) are converted to string literals.
        - DateTime types are converted to ISO 8601 format and quoted
        - HashTables, ordered dictionaries, PSObjects (i.e. custom objects) are converted to object literals `@{...}`.
        - Collections are converted to array literals `@(...)`.
        - ScriptBlocks are converted to a string representation enclosed in braces.
        - Anything else (TimeSpan, Guid, etc.) is treated as a quoted string.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # The value to convert to a PowerShell string literal.
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        $InputObject,
        # Quotes string values, even if not needed.
        [switch] $UseQuotes
    )
    process {
        if ($null -eq $InputObject) { return '$null' }

        if ($InputObject -is [char]) { $InputObject = $InputObject.ToString() }
        if ($InputObject -is [string]) {
            if ($InputObject.IndexOfAny("`r`n`t") -ge 0) {
                # Must use double quotes due to escape characters.
                return '"' + ($InputObject -replace '["$`]', '`$0').Replace("`r", '`r').Replace("`n", '`n').Replace("`t", '`t') + '"'
            }
            if ($UseQuotes -OR $InputObject.IndexOfAny('''"` $(){},;&|') -ge 0) {
                return "'" + $InputObject.Replace("'", "''") + "'"
            }
            return $InputObject
        }

        if ($InputObject -is [bool] -OR $InputObject -is [switch]) { return '$' + $InputObject.ToString() }
        if ($InputObject -is [int] -OR $InputObject -is [int64] -OR $InputObject -is [double]) { return $InputObject.ToString() }
        if ($InputObject -is [datetime] -OR $InputObject -is [System.DateTimeOffset]) { return "'" + $InputObject.ToString('O') + "'" }

        if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
            return '([pscustomobject]@{' + (($InputObject.PSObject.Properties.foreach{ "$(ConvertTo-PSString $_.Name) = $(ConvertTo-PSString $_.Value -UseQuotes)" }) -join ';') + '})'
        }
        if ($InputObject -is [System.Collections.IDictionary]) {
            $val = '@{' + (($InputObject.Keys.foreach{ "$(ConvertTo-PSString $_) = $(ConvertTo-PSString $InputObject[$_] -UseQuotes)" }) -join ';') + '}'
            if ($InputObject -is [System.Collections.Specialized.IOrderedDictionary]) { $val = "([ordered]$val)" }
            return $val
        }
        if ($InputObject -is [System.Collections.ICollection]) {
            return '@(' + (($InputObject | ConvertTo-PSString -UseQuotes) -join ',') + ')'
        }
        if ($InputObject -is [scriptblock]) {
            return "{$InputObject}"
        }

        return ConvertTo-PSString $InputObject.ToString() -UseQuotes
    }
}
