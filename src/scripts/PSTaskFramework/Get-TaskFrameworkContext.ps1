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

function Get-TaskFrameworkContext {
    <#
    .DESCRIPTION
        Gets the current task framework context object.
    #>
    [OutputType([TaskContext])]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$Name = $script:ExternalTaskContextVariableName
    )

    # First, try the current session state where it is always called 'TaskContext'...
    # Get-Variable will also return variables defined in the global scope...
    $TaskContextVar = Get-Variable -Name 'TaskContext' -ErrorAction Ignore
    if ($TaskContextVar.Module -eq $ExecutionContext.SessionState.Module) {
        $TaskContext = $TaskContextVar.Value
    }
    else {
        $TaskContext = $null
    }

    # if not found, try from caller's session state...
    if ($null -eq $TaskContext -and $ExecutionContext.SessionState.Module) {
        $TaskContext = Get-VariableFromOuterSession $Name -ValueOnly -ErrorAction Ignore
    }

    if ($null -eq $TaskContext) {
        throw "Task context variable '$Name' not found. Make sure to define it in the build script, e.g., `$$Name = Initialize-TaskFramework."
    }
    if ($TaskContext -isnot [TaskContext]) {
        throw "Task context variable '$Name' is not a TaskContext object. Make sure to define it in the build script, e.g., `$$Name = Initialize-TaskFramework."
    }

    # looks good!
    return $TaskContext
}
