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

function getOrderedTasks {
    <#
    .DESCRIPTION
        Returns an ordered array of TaskDefinition objects corresponding to the specified task
        names and their dependencies (if $TaskContext.SkipDependencies is not specified).
        The tasks are returned in dependency order. For example, if taskA depends on taskB, then
        `getOrderedTasks taskA` will return an array with taskB first, followed by taskA.
    .OUTPUTS
        [TaskDefinition]
        An array of TaskDefinition objects corresponding to the specified task names and their
        dependencies (if $TaskContext.SkipDependencies is not specified), sorted in dependency order.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([TaskDefinition])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string[]]$TaskNames,
        [TaskContext]$TaskContext = (Get-TaskFrameworkContext)
    )

    # get all tasks in dependency order...
    $orderedTaskMap = getAllOrderedTasks -TaskContext $TaskContext

    # get the set of all tasks to execute, including dependencies if specified.
    $execTaskNames = @{}
    $queue = [System.Collections.Generic.Queue[string]]::new($TaskNames)
    while ($queue.Count -gt 0) {
        $taskName = $queue.Dequeue()
        if ($execTaskNames.ContainsKey($taskName)) {
            continue # already visited
        }
        $execTaskNames[$taskName] = $true
        $task = $orderedTaskMap[$taskName]
        if (-not $task) {
            throw "Task '$taskName' not found."
        }
        if (-not $TaskContext.SkipDependencies) {
            foreach ($dep in $task.DependsOn) {
                $queue.Enqueue($dep)
            }
        }
    }

    # Return the tasks in dependency order...
    return $orderedTaskMap.Values.foreach{
        if ($execTaskNames.ContainsKey($_.Name)) {
            $_
        }
    }
}

function Invoke-TaskFramework {
    <#
    .DESCRIPTION
        Invokes one or more tasks defined in the task framework.

        Tasks will be executed in the order they were defined. If a task has dependencies,
        those will be executed first unless $SkipDependencies is specified.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    param(
        # The name(s) of the task(s) to invoke.
        [Parameter(Mandatory)]
        [string[]]$TaskName,

        # Task-specific arguments. Can only be used when invoking a _single_ task.
        [ValidateNotNull()]
        [object[]]$TaskArgs = @(),

        # Indicates whether to skip invoking dependencies of specified tasks. Defaults to $false.
        [switch]$SkipDependencies,

        # The working directory in which to invoke the task(s).
        # Defaults to the BuildScriptPath's directory.
        [ValidateNotNullOrEmpty()]
        [string]$WorkingDirectory,

        # Indicates that the function should exit the script if a failure occurs. If not specified,
        # the function will throw an exception failure.
        [switch]$ExitOnError,

        # The task context hashtable. Defaults to the current task context returned by Get-TaskFrameworkContext.
        [ValidateNotNull()]
        [TaskContext]$TaskContext = (Get-TaskFrameworkContext)
    )
    & $PSScriptRoot/syncCallerPreferences.ps1 $MyInvocation
    $ErrorActionPreference = 'Stop'
    $null = $ExitOnError # avoid unused parameter warning

    $isInvokeTaskError = $false
    trap {
        if ($global:LASTEXITCODE -eq 0) { $global:LASTEXITCODE = -1 }
        $TaskContext.ExitCode = $global:LASTEXITCODE
        $TaskContext.Error = $_
        Write-Verbose "Error executing task(s):`n$(($_ | Format-List -Force | Out-String).Trim())"

        if ($ExitOnError) {
            # Write a user-friendly error message...
            $msg = "$($PSStyle.Formatting.Error)ERROR: $_"
            if ($isInvokeTaskError) {
                # Include a focused stack trace that only includes the stack frames above
                # Invoke-Task, i.e., the user's code...
                $taskStackTrace = $_.ScriptStackTrace.Split("`n").where({ $_.StartsWith('at Invoke-Task,') }, 'until')
                if ($taskStackTrace) { $msg += "$($PSStyle.BoldOff)$($PSStyle.Dim)`n$($taskStackTrace -join "`n")$($PSStyle.DimOff)" }
            }
            Write-Host "$msg$($PSStyle.Reset)"
            Write-Verbose "Exiting with code $global:LASTEXITCODE."
            exit $global:LASTEXITCODE
        }

        break # rethrow the error as an exception failure
    }

    if (!$WorkingDirectory) {
        $WorkingDirectory = $TaskContext.BuildScriptPath.DirectoryName
    }
    elseif (!(Test-Path $WorkingDirectory -PathType Container)) {
        throw "The specified working directory '$WorkingDirectory' does not exist."
    }
    if ($TaskArgs.Count -gt 0 -and $TaskName.Count -gt 1) {
        throw 'Task arguments cannot be used when invoking multiple tasks.'
    }

    $TaskContext.WorkingDirectory = Get-Item $WorkingDirectory -Force
    $TaskContext.SkipDependencies = $SkipDependencies.IsPresent
    $TaskContext.TasksToExecute = @()
    $TaskContext.Start = [datetime]::UtcNow
    $TaskContext.Duration = $null
    $TaskContext.ExitCode = $null
    $TaskContext.Error = $null
    $TaskContext.CurrentTask = $null
    $TaskContext.Results = [ordered]@{}

    $tasksToExecute = getOrderedTasks $TaskName -TaskContext $TaskContext
    $TaskContext.TasksToExecute = $tasksToExecute.Name

    $origPSModulePath = $env:PSModulePath
    $origLocation = Get-Location

    try {
        # Add this scripts directory to the module path so that task actions
        # can import our helper modules using the module's folder name.
        $pathSeparator = $IsWindows ? ';' : ':'
        $env:PSModulePath = "$PSScriptRoot$pathSeparator$env:PSModulePath"
        Write-Verbose "Prepended '$PSScriptRoot' to `$env:PSModulePath."
        Write-Verbose "Working directory: '$($TaskContext.WorkingDirectory)'."
        Write-Verbose "Executing tasks: $($TaskContext.TasksToExecute -join ', ')"

        foreach ($task in $tasksToExecute) {
            Set-Location $TaskContext.WorkingDirectory
            try {
                Invoke-Task -Task $task -TaskArgs ($task.Name -eq $TaskName ? $TaskArgs : @()) -TaskContext $TaskContext
            }
            catch {
                $isInvokeTaskError = $true
                throw # rethrow to be caught by the trap
            }
        }

        Write-Verbose "Done executing tasks."
        $TaskContext.ExitCode = $global:LASTEXITCODE
    }
    finally {
        $TaskContext.Duration = [datetime]::UtcNow - $TaskContext.Start
        $env:PSModulePath = $origPSModulePath
        Set-Location $origLocation
    }
}

# !Important! Remember to update the module manifest (.psd1) when adding or removing exports.
