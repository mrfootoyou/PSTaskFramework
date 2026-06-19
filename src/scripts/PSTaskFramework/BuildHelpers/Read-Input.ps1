<#
.SYNOPSIS
    Part of the PSTaskFramework.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4
# spell:ignore bstr

param()

# Mockable functions for testing purposes. These are not for external use.
function isContinuousIntegration {
    return $env:CI -in @('1', 'true')
}

function Read-Input {
    <#
    .DESCRIPTION
        Reads a string value from the console. If running in a CI environment, returns
        an empty string or throws an error, depending on the -AllowEmpty switch.

        This is a lightweight wrapper around the built-in Read-Host cmdlet and adds
        CI-awareness and optional support for reading secrets as strings.
    .OUTPUTS
        [System.String]
        The value read from the console.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # The prompt to display to the user
        [Parameter(Mandatory)]
        [string] $Prompt,
        # If specified, allows an empty value to be returned. Otherwise, an error is thrown.
        [switch] $AllowEmpty,
        # If specified, reads the input without echoing it to the console.
        [switch] $Secret
    )
    Sync-CallerPreference -PreferencesToSync ErrorAction, WarningAction

    # Do not prompt in CI environments. Instead, return an empty string
    # or throw an error depending on the -AllowEmpty switch.
    if (isContinuousIntegration) {
        if ($AllowEmpty) {
            Write-Warning "CI environment detected. Returning empty value for prompt '$Prompt'."
            return ''
        }
        Write-Error -Exception 'Cannot read input in CI environment.' `
            -CategoryActivity $MyInvocation.MyCommand.Name `
            -Category InvalidOperation `
            -CategoryReason 'CIEnvironment' `
            -TargetObject $Prompt
        return
    }
    if ($Secret) {
        $value = Read-Host $Prompt -AsSecureString
        if ($value) {
            $bstr = [System.IntPtr]::Zero
            try {
                $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($value)
                $value = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            }
            finally {
                if ($bstr -ne [System.IntPtr]::Zero) {
                    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
                }
            }
        }
    }
    else {
        $value = Read-Host $Prompt
    }
    if (!$value -and !$AllowEmpty) {
        Write-Error -Exception 'No value provided.' `
            -CategoryActivity $MyInvocation.MyCommand.Name `
            -Category InvalidData `
            -CategoryReason 'NoValueProvided' `
            -TargetObject $Prompt
        return
    }
    return $value
}
