<#
.SYNOPSIS
    Part of the PSTaskFramework.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4
# spell:ignore GVFCM

param()

function getLexicalModule {
    [OutputType([PSModuleInfo])]
    param(
        [System.Management.Automation.InvocationInfo] $invocation
    )
    # If the command has an underlying ScriptBlock, use it's lexical module instead of the
    # dynamic module from the stack frame, since the latter can be misleading due to how
    # PowerShell handles script blocks in modules.
    $cmd = $invocation.MyCommand
    $cmd.ScriptBlock.Module ?? $cmd.Module
}

function Get-VariableFromOuterSession {
    <#
    .SYNOPSIS
        Gets a variable from the outer session.
    .DESCRIPTION
        Modules normally cannot access the local and script-scope variables in other modules
        and functions. This function pierces that encapsulation and attempts to return the
        exact variable the caller would get if they referenced it directly (w/o scope qualifier).

        More accurately, this function attempts to retrieve a variable from the outer session
        state, i.e., the first stack frame whose lexical session state is different from this
        module's session state.

        It will emit a warning if it fails to find the variable. Use `-WarningAction Stop`
        to convert the warning to an exception, or use `-WarningAction Ignore` to suppress it.

        !IMPORTANT USAGE NOTES!

        - This function MUST be called from within a module context. If it is called without a
          module context, it will throw an exception.

        - This function should NOT be exported from a module. Doing so will result in incorrect
          behavior when called from outside that module (it will effectively function like
          `Get-Variable -Name $Name`).

        - Each module using this function MUST dot-source this script file. Add it to the
          NestedModules section of the module's manifest, or dot-source it in the .psm1 file.

        This function emulates the behavior of PSModuleInfo.GetVariableFromCallersModule()
        with fixes for a few edge cases where that function does not work as expected.
    .OUTPUTS
        [PSVariable]
        The found variable.

        [object]
        If the -ValueOnly switch is used, the value of the found variable.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([PSVariable])]
    [OutputType([object])]
    param(
        # The name of the variable to get.
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string] $Name,
        # Indicates that only the value of the variable should be returned.
        [switch] $ValueOnly,
        # Indicates that a warning should be emitted if the variable is not found.
        [switch] $WarningIfNotFound
    )
    begin {
        $thisModule = $ExecutionContext.SessionState.Module
        if (!$thisModule) {
            throw 'Must be called from within a module.'
        }

        # In many cases we can simply call GetVariableFromCallersModule() and get the correct value,
        # but there are some edge cases where it doesn't work. To handle these cases, we will
        # emulate GetVariableFromCallersModule with fixes for those edge cases.
        #
        # The algorithm is simple: Walk the call stack looking for the *first* frame with a lexical
        # session state different from this module. If a session state is found, ask it for the
        # variable, otherwise search the top-level session state.
        # See https://github.com/PowerShell/PowerShell/blob/master/src/System.Management.Automation/engine/Modules/PSModuleInfo.cs
        #
        # The known issues are:
        # 1) GVFCM does not account for module-invoked script file frames, e.g. `& script.ps1`, which
        #    do not have a session state. This is likely a PS bug since only script-scoped invocations
        #    have this behavior; functions called by the script file have the correct session state.
        # 2) GVFCM does not account for module-invoked scriptblock frames, e.g. `& <scriptblock>`,
        #    whose scriptblock session state (the "lexical" session state) is different from the stack
        #    frame's session state. This might also be a PS bug, but it is less clear.
        $moduleToSearch = $null
        $debugger = $PSCmdlet.Host.Runspace.Debugger
        foreach ($frame in $debugger.GetCallStack()) {
            # Issue #1 fix: Use lexical module/session state...
            # If the command has an underlying ScriptBlock, use it's lexical module instead of the
            # dynamic module from the stack frame, since the latter can be misleading due to how
            # PowerShell handles script blocks in modules.
            $command = $frame.InvocationInfo.MyCommand
            [PSModuleInfo]$lexicalModule = getLexicalModule $frame.InvocationInfo

            if (!$lexicalModule) {
                if ($command.CommandType -band 'ExternalScript') {
                    # Issue #2 fix: Ignore ExternalScript frames. The next frame should have the
                    # correct session state.
                    continue;
                }
                # found caller in a different (top-level) session state
                break;
            }

            if ($lexicalModule.SessionState -ne $thisModule.SessionState) {
                # found caller in a different module session state
                $moduleToSearch = $lexicalModule
                break;
            }
        }

        $topLevelSessionState = $null
    }
    process {
        $sessionStateToSearch = $null
        if ($moduleToSearch) {
            # search the found session state
            $sessionStateToSearch = $moduleToSearch.SessionState
        }
        else {
            # search the top-level session state
            # Unfortunately, there is no public API to get the top-level session state, so we
            # have to use reflection to access it. This is pretty hacky and may break in future
            # versions of PowerShell, but there doesn't seem to be a better option.
            if ($null -eq $topLevelSessionState) {
                $script:_localPipelineType ??= [runspace].Assembly.GetType('System.Management.Automation.Runspaces.LocalPipeline')
                $internalEC ??= $script:_localPipelineType.GetMethod('GetExecutionContextFromTLS', [System.Reflection.BindingFlags] 'NonPublic, Static').Invoke($null, $null)
                $internalTLS = $internalEC.GetType().GetProperty('TopLevelSessionState', [System.Reflection.BindingFlags] 'NonPublic, Instance').GetValue($internalEC)
                $topLevelSessionState = $internalTLS.GetType().GetProperty('PublicSessionState', [System.Reflection.BindingFlags] 'NonPublic, Instance').GetValue($internalTLS)
            }
            $sessionStateToSearch = $topLevelSessionState
        }

        $callerFoo = $sessionStateToSearch.PSVariable.Get($Name)
        if (!$callerFoo) {
            if ($WarningIfNotFound) {
                Write-Warning "Failed to find variable '$Name'."
            }
            else {
                Write-Error -Exception "Failed to find variable '$Name'." `
                    -CategoryActivity $MyInvocation.MyCommand.Name `
                    -Category ObjectNotFound `
                    -CategoryReason 'VariableNotFound' `
                    -TargetObject $Name
            }
            return
        }

        return $ValueOnly ? $callerFoo.Value : $callerFoo
    }
}
