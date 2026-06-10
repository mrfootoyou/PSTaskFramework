<#
.SYNOPSIS
    Part of the PSTaskFramework.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4

param()

function Read-Secret {
    <#
    .DESCRIPTION
        Reads a secret value from the console without echoing it to the screen.
        The secret is returned as a plain string.

        This cmdlet is identical to `BuildHelpers\Read-Input -Secret ...`.
    .OUTPUTS
        [System.String]
        The secret value read from the console.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # The prompt to display to the user
        [Parameter(Mandatory)]
        [string] $Prompt,
        # If specified, allows an empty value to be returned. Otherwise, an error is thrown.
        [switch] $AllowEmpty
    )
    & $PSScriptRoot/../syncCallerPreferences.ps1 $MyInvocation -PreferencesToSync ErrorAction, WarningAction

    Read-Input -Secret @PSBoundParameters
}
