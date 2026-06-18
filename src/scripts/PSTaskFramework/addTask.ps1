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

function addTask {
    <#
    .DESCRIPTION
        Private implementation of the `Task` function that adds a task to the task framework.
        This is separated from the public Task function to allow for easier error handling and
        to avoid syncing caller preferences multiple times when adding multiple tasks.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,
        [Parameter(Mandatory, Position = 1)]
        [AllowNull()]
        [ScriptBlock]$Action,
        [ValidateNotNull()]
        [string]$Description,
        [ValidateNotNull()]
        [string[]]$DependsOn = @(),
        [ValidateNotNull()]
        [int[]]$AllowedExitCodes = @(0),
        [ValidateNotNull()]
        [TaskContext]$TaskContext = (Get-TaskFrameworkContext)
    )
    if ($TaskContext.AllTasks.Contains($Name)) {
        Write-Error -Exception "A task with the name '$Name' already exists." -CategoryActivity 'Add task' -Category ResourceExists -TargetObject $Name
        return
    }
    $TaskContext.AllTasks[$Name] = [TaskDefinition]@{
        Name             = $Name
        Description      = $Description
        DependsOn        = $DependsOn
        AllowedExitCodes = $AllowedExitCodes
        Action           = $Action
    }
    $TaskContext.AllTasksSorted = $false
}

function Task {
    <#
    .DESCRIPTION
        Adds a task with an associated action and optional task dependencies to the
        task framework.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    param (
        # The name of the task. Must be unique. Not case-sensitive.
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        # The script block to execute when the task is invoked. May be null or empty for
        # tasks that only serve as a grouping of dependencies.
        [Parameter(Mandatory, Position = 1)]
        [AllowNull()]
        [ScriptBlock]$Action,

        # A brief description of the task.
        [ValidateNotNull()]
        [string]$Description,

        # An array of task names that this task depends on. These tasks will be executed
        # before this task unless -SkipDependencies is specified when invoking.
        [ValidateNotNull()]
        [string[]]$DependsOn = @(),

        # An array of allowed exit codes for the task. If the task completes with an
        # exit code that is not in this array, it will be considered a failure. Pass an
        # empty array to ignore the exit code. Defaults to 0.
        [ValidateNotNull()]
        [int[]]$AllowedExitCodes = @(0),

        # The task context hashtable. Defaults to the current task context returned by Get-TaskFrameworkContext.
        [ValidateNotNull()]
        [TaskContext]$TaskContext = (Get-TaskFrameworkContext)
    )
    Sync-CallerPreference
    addTask @PSBoundParameters
}
