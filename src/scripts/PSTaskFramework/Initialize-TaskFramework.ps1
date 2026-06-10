<#
.SYNOPSIS
    Part of the PSTaskFramework.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4

using module .\PSTaskFramework.classes.psm1
param()

# The name of the external variable containing the current TaskContext object.
# This is set when calling Initialize-TaskFramework and is used by Get-TaskFrameworkContext
# to retrieve the callers TaskContext when it is not passed explicitly.
# This is, unfortunately, global data, but should be okay as long as the callers always use
# the same variable name, or do not interleave runs (it's hard to imagine what that would
# even look like).
$script:ExternalTaskContextVariableName = 'TaskContext'

function Initialize-TaskFramework {
    <#
    .DESCRIPTION
        Initializes the task framework by creating a new TaskContext object.

        !IMPORTANT! The caller must save the returned object to a variable named `TaskContext`.
        If this is not possible for some reason, then the replacement name must be specified
        using the -TaskContextVariableName parameter.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([TaskContext])]
    param(
        # The path to the callers build script.
        # Defaults to caller's `$MyInvocation.MyCommand.Path`.
        [ValidateNotNullOrEmpty()]
        [string]$BuildScriptPath,
        # The name of the parameter used to specify the task name when invoking the build script.
        # This is used for help generation. Defaults to 'TaskName'.
        [ValidateNotNullOrEmpty()]
        [string]$TaskNameArgName = 'TaskName',
        # The name of the parameter used to specify task arguments when invoking the build script.
        # This is used for help generation. Defaults to 'TaskArgs'.
        [ValidateNotNullOrEmpty()]
        [string]$TaskArgsArgName = 'TaskArgs',

        # The name of the variable to save the TaskContext object to. Defaults to 'TaskContext'.
        # Note that this function does _NOT_ create this variable. The caller's must do that,
        # e.g. `$MyTaskContext = Initialize-TaskFramework -TaskContextVariableName 'MyTaskContext'`.
        [ValidateNotNullOrEmpty()]
        [string]$TaskContextVariableName = 'TaskContext'
    )
    & $PSScriptRoot/syncCallerPreferences.ps1 $MyInvocation

    if (!$BuildScriptPath) {
        $callersInvocation = $ExecutionContext.SessionState.Module.GetVariableFromCallersModule("MyInvocation")
        if (!$callersInvocation.Value.MyCommand.Path) {
            Write-Error -Exception "Could not determine caller's script path. Please provide the path via the -BuildScriptPath parameter."
            return
        }
        $BuildScriptPath = $callersInvocation.Value.MyCommand.Path
    }
    if (!(Test-Path $BuildScriptPath -PathType Leaf)) {
        Write-Error -Exception "The specified build script path '$BuildScriptPath' does not exist."
        return
    }

    $TaskContext = [TaskContext]@{
        BuildScriptPath = Get-Item $BuildScriptPath -Force
        TaskNameArgName = $TaskNameArgName
        TaskArgsArgName = $TaskArgsArgName
    }

    # Save the name in a global variable so that Get-TaskFrameworkContext can retrieve it.
    $script:ExternalTaskContextVariableName = $TaskContextVariableName

    return $TaskContext
}
