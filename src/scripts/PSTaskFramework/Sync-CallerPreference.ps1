<#
.SYNOPSIS
    Part of the PSTaskFramework.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4

param()

# Depends on Get-VariableFromOuterSession.ps1

function Sync-CallerPreference {
    <#
    .SYNOPSIS
        Syncs the calling function's preference variables with the outer session.
    .DESCRIPTION
        Annoyingly, functions exported from a PS script-module do not inherit the preferences
        variables from the caller's session. This function manually imports the preferences
        variables from the outer session into the scope of the caller. See
        https://github.com/PowerShell/PowerShell/issues/4568 for more information about this issue.

        It will NOT sync any variable whose value was passed to the caller via a bound parameter.

        It will emit warnings for any variable it fails to find or sync. Use `-WarningAction Stop`
        to convert these warnings to exceptions, or use `-WarningAction Ignore` to suppress them.

        !IMPORTANT USAGE NOTES!

        - This function MUST only be called from module entry-points. An [ignorable] error will
          occur if called from any other context.

        - This function MUST NOT be exported from a module. Doing so will result in an exception
          when called from outside the module.

        - Each module using this function MUST dot-source this script file. Add it to the
          NestedModules section of the module's manifest, or dot-source it in the .psm1 file.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    param(
        # Preference to sync. Defaults to all common preferences.
        [ValidateSet('ErrorAction', 'WarningAction', 'InformationAction', 'Verbose', 'Debug', 'Confirm', 'WhatIf')]
        [string[]] $PreferencesToSync = @(
            'ErrorAction'
            'WarningAction'
            'InformationAction'
            'Verbose'
            'Debug'
            'Confirm'
            'WhatIf'
        ),

        # Additional variables to sync.
        [string[]] $VariablesToSync = @()
    )
    $callstack = @($PSCmdlet.Host.Runspace.Debugger.GetCallStack())
    $callerScope = 1
    $callerInvocation = $callstack[$callerScope].InvocationInfo
    [PSModuleInfo]$callerModule = getLexicalModule $callerInvocation

    # verify caller is from this module...
    if (!$callerModule -or $callerModule -ne $PSCmdlet.SessionState.Module) {
        throw "$($MyInvocation.MyCommand.Name) can only be used in module $($PSCmdlet.SessionState.Module)."
    }

    # verify the caller is a module entry point, i.e., the caller's caller is not from this module
    $callersCaller = $callstack[$callerScope + 1].InvocationInfo
    if ((getLexicalModule $callersCaller) -eq $callerModule) {
        if ($ErrorActionPreference -ne 'Ignore') {
            Write-Error -Exception "$($MyInvocation.MyCommand.Name) must only be called from module entry points." `
                -Category InvalidOperation -CategoryActivity $PSCmdlet.MyInvocation.MyCommand.Name
        }
        return
    }

    $boundParameters = $callerInvocation.BoundParameters

    @(
        switch ($PreferencesToSync) {
            'ErrorAction' { if (!$boundParameters.ContainsKey($_)) { 'ErrorActionPreference' } }
            'WarningAction' { if (!$boundParameters.ContainsKey($_)) { 'WarningPreference' } }
            'InformationAction' { if (!$boundParameters.ContainsKey($_)) { 'InformationPreference' } }
            'Verbose' { if (!$boundParameters.ContainsKey($_)) { 'VerbosePreference' } }
            'Debug' { if (!$boundParameters.ContainsKey($_)) { 'DebugPreference' } }
            'Confirm' { if (!$boundParameters.ContainsKey($_)) { 'ConfirmPreference' } }
            'WhatIf' { if (!$boundParameters.ContainsKey($_)) { 'WhatIfPreference' } }
        }
        $VariablesToSync.where({ !$boundParameters.ContainsKey($_) })
    ) |
    Select-Object -Unique |
    Get-VariableFromOuterSession -WarningIfNotFound | # benefits from pipeline
    ForEach-Object {
        [PSVariable]$var = $_
        try {
            Set-Variable -Name $var.Name -Value $var.Value -Scope $callerScope -ErrorAction Stop -Confirm:$false -WhatIf:$false
        }
        catch {
            Write-Warning $_
        }
    }
}
