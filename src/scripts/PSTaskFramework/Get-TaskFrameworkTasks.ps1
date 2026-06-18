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

function getTask {
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([TaskDefinition])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$TaskName,
        [ValidateNotNull()]
        [TaskContext]$TaskContext = (Get-TaskFrameworkContext)
    )

    if (!$TaskContext.AllTasks.Contains($TaskName)) {
        Write-Error -Exception "Task '$TaskName' not found." `
            -CategoryActivity 'Get-Task' `
            -Category ObjectNotFound `
            -CategoryReason 'TaskNotFound' `
            -TargetObject $TaskName
        return
    }
    return $TaskContext.AllTasks[$TaskName]
}

function getAllOrderedTasks {
    <#
    .DESCRIPTION
        Gets an ordered dictionary of all defined tasks, sorted in dependency order.
        The keys are task names and the values are [TaskDefinition] objects.
    .OUTPUTS
        [System.Collections.Specialized.OrderedDictionary]
        An ordered dictionary of all defined tasks, sorted in dependency order.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [ValidateNotNull()]
        [TaskContext]$TaskContext = (Get-TaskFrameworkContext)
    )

    if ($TaskContext.AllTasksSorted -eq $true) {
        return $TaskContext.AllTasks
    }

    # Sort tasks in dependency order using a depth-first search.
    # Preserve the original order of tasks as much as possible while ensuring that
    # dependencies are always defined before the tasks that depend on them.
    # This also detects circular dependencies.
    $visited = @{}
    function visit([TaskDefinition]$task) {
        if ($visited.ContainsKey($task.Name)) {
            # already visited this node; if we're visiting it again, we have a
            # circular dependency
            if ($visited[$task.Name] -eq 'visiting') {
                throw "Circular dependency detected at task '$($task.Name)'."
            }
            return
        }
        $visited[$task.Name] = 'visiting'
        foreach ($dep in $task.DependsOn) {
            $depTask = $TaskContext.AllTasks[$dep]
            if (-not $depTask) {
                throw "Dependency '$dep' of task '$($task.Name)' not found."
            }
            visit $depTask
        }
        $visited[$task.Name] = ''
        $task
    }

    $orderedTasks = @(
        foreach ($task in $TaskContext.AllTasks.Values) {
            visit $task
        }
    )

    $allTasks = [ordered]@{}
    foreach ($task in $orderedTasks) {
        $allTasks[$task.Name] = $task
    }

    $TaskContext.AllTasks = $allTasks
    $TaskContext.AllTasksSorted = $true
    return $allTasks
}

function Get-TaskFrameworkTasks {
    <#
    .DESCRIPTION
        Gets all tasks defined in the task framework in dependency order. The returned
        objects are of type TaskDefinition, which has the following properties:
            - Name: The name of the task.
            - Description: A brief description of the task.
            - DependsOn: An array of task names that this task depends on.
            - Action: The script block to execute when the task is invoked.

        This can be useful for listing available tasks or for debugging task definitions.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessage('PSUseSingularNouns', '', Justification = 'Tasks is plural because it manages multiple tasks.')]
    [CmdletBinding(PositionalBinding = $false)]
    param(
        # The task context hashtable. Defaults to the current task context returned by Get-TaskFrameworkContext.
        [ValidateNotNull()]
        [TaskContext]$TaskContext = (Get-TaskFrameworkContext)
    )
    Sync-CallerPreference
    try {
        return (getAllOrderedTasks @PSBoundParameters).Values
    }
    catch {
        Write-Error -Exception $_ -CategoryActivity $MyInvocation.MyCommand.Name
    }
}
