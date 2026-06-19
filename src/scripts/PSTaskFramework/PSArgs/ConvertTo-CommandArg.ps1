<#
.SYNOPSIS
    Part of the PSTaskFramework.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4
# spell:ignore splatable

function ConvertTo-CommandArg {
    <#
    .DESCRIPTION
        Converts the given value to a PowerShell command line argument string.
        - A null value is converted to '' (no args).
        - An array is converted to a space-separated list of literal values.
        - A PSObject or hashtable is converted to a space-separated list of properties in the form `-Name:Value`.
        - A ScriptBlock is converted to a string representation enclosed in braces.
        - Any other value is converted to a string literal using `ConvertTo-PSString`.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # The value to convert to a PowerShell command line argument string.
        # May be a single object or a "splatable" array, hashtable, or PSCustomObject
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        $InputObject
    )
    process {
        if ($null -eq $InputObject) { return '' }
        if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
            return (($InputObject.PSObject.Properties.foreach{ "-$(ConvertTo-PSString $_.Name):$(ConvertTo-PSString $_.Value -UseQuotes)" }) -join ' ')
        }
        if ($InputObject -is [System.Collections.IDictionary]) {
            return (($InputObject.Keys.foreach{ "-$(ConvertTo-PSString $_):$(ConvertTo-PSString $InputObject[$_] -UseQuotes)" }) -join ' ')
        }
        # collections and single values are converted to a space-separated list of literal values
        return ($InputObject | ConvertTo-PSString) -join ' '
    }
}
