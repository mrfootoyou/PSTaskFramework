<#
.SYNOPSIS
    Part of the PSTaskFramework.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4

[Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidGlobalVars', 'global:__PSTaskFramework_Secrets', Justification = 'Intended to be used this way.')]
param(
    # The scope of the secret storage. Can be 'Local' or 'Global'. Defaults to 'Global'.
    [ValidateSet('Local', 'Global')]
    [string] $SecretScope = 'Global'
)

# We cant put these in the manifest because of the '../' in the path
. "$PSScriptRoot/../Get-VariableFromOuterSession.ps1"
. "$PSScriptRoot/../Sync-CallerPreference.ps1"

if ($SecretScope -eq 'Local') {
    $script:secrets = [PSCustomObject]@{
        values = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
        regex  = $null
    }
}
else {
    $global:__PSTaskFramework_Secrets ??= [PSCustomObject]@{
        values = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
        regex  = $null
    }
    $script:secrets = $global:__PSTaskFramework_Secrets

    if ($ExecutionContext.SessionState.Module) {
        $ExecutionContext.SessionState.Module.OnRemove = {
            Get-Variable -Scope Global -Name __PSTaskFramework_Secrets -ErrorAction Ignore |
            Remove-Variable -Scope Global -Force -ErrorAction Ignore
        }
    }
}

# Mockable functions for testing purposes. These are not for external use.
function getState {
    return $script:secrets
}

function Clear-SecretStore {
    <#
    .DESCRIPTION
        Clears all secrets from the secret store.
    #>
    [CmdletBinding()]
    param()
    $secrets = getState
    $secrets.values.Clear()
    $secrets.regex = $null
}

function Push-Secret {
    <#
    .DESCRIPTION
        Registers a secret value to be masked in the output of Protect-Secret.

        Secret values are case-sensitive and are compared using ordinal string
        comparison.

        Note that secrets are reference counted, thus if a secret value is pushed
        multiple times, it must be popped the same number of times to be fully
        unregistered.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Value
    )
    process {
        $secrets = getState
        $n = ($secrets.values[$Value] += 1)
        if ($n -eq 1) {
            $secrets.regex = $null
        }
    }
}

function Pop-Secret {
    <#
    .DESCRIPTION
        Unregisters a secret value previously registered with Push-Secret.

        Secret values are case-sensitive and are compared using ordinal string
        comparison.

        Note that secrets are reference counted, thus if a secret value is pushed
        multiple times, it must be popped the same number of times to be fully
        unregistered.

        An error is reported if the secret value was not previously registered or
        if it has already been popped the same number of times it was pushed.
        Use `-ErrorAction SilentlyContinue` or `-ErrorAction Ignore` to suppress
        such errors.
    #>
    [CmdletBinding()]
    param (
        # The secret value which was previously registered with Push-Secret.
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Value
    )
    begin {
        Sync-CallerPreference
    }
    process {
        $secrets = getState
        if (!$secrets.values.ContainsKey($Value)) {
            Write-Error -Exception 'Secret not found.' `
                -CategoryActivity $MyInvocation.MyCommand.Name `
                -Category ObjectNotFound `
                -ErrorId 'SecretNotFound' `
                -TargetObject $Value
            return
        }
        $n = ($secrets.values[$Value] -= 1)
        if ($n -eq 0) {
            $null = $secrets.values.Remove($Value)
            $secrets.regex = $null
        }
    }
}

function Protect-Secret {
    <#
    .DESCRIPTION
        Replaces all registered secret values in the given string by replacing them with
        the specified mask value (default is '****').
    .OUTPUTS
        [System.String]
        The input string with all registered secrets replaced by the mask.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([string])]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowEmptyString()]
        [string]$Message,
        [ValidateNotNull()]
        [string]$Mask = '****'
    )
    process {
        $secrets = getState
        if (!$secrets.regex -and $secrets.values.Count) {
            $pattern = ($secrets.values.Keys |
                Sort-Object Length -Descending |
                ForEach-Object { [regex]::Escape($_) }) -join '|'
            $secrets.regex = [regex]::new($pattern)
        }
        if ($secrets.regex) {
            # Use a match-evaluator overload to prevent '$0' from reintroducing the secret value
            $secrets.regex.Replace($Message, { $Mask })
            $null = $Mask # Avoid incorrect "unused parameter" warning
        }
        else {
            $Message
        }
    }
}
