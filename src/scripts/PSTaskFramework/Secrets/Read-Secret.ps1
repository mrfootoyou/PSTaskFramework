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

function Read-Secret {
    <#
    .DESCRIPTION
        Reads a secret value from the console without echoing it to the screen.
        The secret is returned as a plain string.
    .OUTPUTS
        [System.String]
        The secret value read from the console.
    #>
    # TODO: Add a "-Secret" switch, rename to "Read-Input", and move to BuildHelpers.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # The prompt to display to the user
        [Parameter(Mandatory)]
        [string] $Prompt,
        [switch] $AllowEmpty
    )
    & $PSScriptRoot/../syncCallerPreferences.ps1 $MyInvocation -PreferencesToSync ErrorAction, WarningAction

    if (isContinuousIntegration) {
        if ($AllowEmpty) {
            Write-Warning "CI environment detected. Returning empty value for prompt '$Prompt'."
            return ''
        }
        Write-Error -Exception 'Cannot read input in CI environment.' -CategoryActivity 'Read-Secret'
        return
    }
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
    if (!$value -and !$AllowEmpty) {
        Write-Error -Exception 'No value provided.' -CategoryActivity 'Read-Secret'
        return
    }
    return $value
}
