<#
.SYNOPSIS
    Part of the PSTaskFramework.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4

param()

# The context of the task framework. Stores all tasks and execution metadata.
class TaskContext {
    # A hashtable for storing arbitrary information.
    [hashtable]$State = @{}

    # Details about the build script.
    [System.IO.FileInfo]$BuildScriptPath
    [string]$TaskNameArgName = 'TaskName'
    [string]$TaskArgsArgName = 'TaskArgs'

    # All defined tasks. The keys are task names.
    [ordered]$AllTasks = [ordered]@{}
    [bool]$AllTasksSorted = $true
    [string]$HelpTaskName

    # Execution metadata for the current run.
    [System.IO.DirectoryInfo]$WorkingDirectory
    [bool]$SkipDependencies
    [string[]]$TasksToExecute = @()
    [Nullable[DateTime]]$Start
    [Nullable[TimeSpan]]$Duration
    [Nullable[int]]$ExitCode
    [System.Management.Automation.ErrorRecord]$Error

    # Task execution metadata. This is updated as tasks are executed.
    [TaskDefinition]$CurrentTask
    [ordered]$Results = [ordered]@{}
}

# The definition of a task. Store the task metadata and action.
class TaskDefinition {
    [string]$Name
    [string]$Description = ''
    [string[]]$DependsOn = @()
    [int[]]$AllowedExitCodes = @(0)
    [ScriptBlock]$Action

    [string] ToString() { return $this.Name }
}

# The result of a task execution. Stores the execution metadata and result.
class TaskResult {
    [DateTime]$Start = [DateTime]::UtcNow
    [TaskArgs]$TaskArgs
    [Nullable[TimeSpan]]$Duration
    [Nullable[int]]$ExitCode
    [System.Management.Automation.ErrorRecord]$Error
}

# The arguments passed to a task. Stores the raw, bound, and unbound arguments.
class TaskArgs {
    [object[]]$Raw = @()
    [System.Collections.IDictionary]$Bound = @{}
    [object[]]$Unbound = @()
}
