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

function Repair-TaskStackTrace {
    <#
    .DESCRIPTION
        Fixes the stack trace of an error that occurs when invoking a task using
        Invoke-Expression.

        The invocation looks like this:
            Invoke-Expression -Command "&{`n<task action body>`n} <task args>"

        The call stack will look something like this:
            ...
            at <ScriptBlock>, <No file>: line 5
            at <ScriptBlock>, <No file>: line 1
            at Invoke-Task, F:\repo\scripts\task-framework.psm1: line 264
            at Invoke-TaskFramework, F:\repo\scripts\task-framework.psm1: line 346
            at <ScriptBlock>, F:\repo\build.ps1: line 198
            at <ScriptBlock>, <No file>: line 1

        The "<No file>" stack frames above "Invoke-Task" are from Invoke-Expression.
        The frame at line 1 is the script block invocation (&{...}) used to pass
        parameters into the task action. This should be ignored since it would not
        appear in a normal stack trace.
        The next one (at line 5) is an actual task frame. We will replace it
        with the filename and line number of the task action.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [Parameter(Mandatory)]
        [TaskDefinition]$Task,
        # The line where the task action starts within the Invoke-Expression command.
        [int]$TaskActionStartLine = 2
    )

    # Unfortunately, we have to use reflection to set the 'StackTrace'. This may
    # break in future versions of PowerShell so we proceed with caution.
    # See https://github.com/PowerShell/PowerShell for the ErrorRecord definition.
    $bindingFlags = [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic
    $field = $ErrorRecord.GetType().GetField("_scriptStackTrace", $bindingFlags)
    if (!$field) {
        Write-Verbose "Unable to fix task stacktrace: could not find '_scriptStackTrace' field via reflection."
        return
    }

    $taskFile = $Task.Action.Ast.Extent.File ?? '<No file>'
    $taskLineNumber = $Task.Action.Ast.Extent.StartLineNumber

    # split and reverse the stack frames to simplify things
    $frames = $ErrorRecord.ScriptStackTrace -split '\r?\n'
    [array]::Reverse($frames)

    # use a state machine to rewrite the frames. Remember we reversed the frames so we're going bottom-up.
    $state = 'beforeInvokeTaskFrame'
    $fixedFrames = foreach ($frame in $frames) {
        switch ($state) {
            'beforeInvokeTaskFrame' {
                $frame
                if ($frame.StartsWith('at Invoke-Task,')) { $state = 'afterInvokeTaskFrame' }
            }
            'afterInvokeTaskFrame' {
                # ignore frame at line 1
                if ($frame -eq 'at <ScriptBlock>, <No file>: line 1') {
                    $state = 'afterFrameAtLine1'
                }
                else {
                    # should not happen
                    $frame
                    $state = 'beforeInvokeTaskFrame'
                }
            }
            'afterFrameAtLine1' {
                if ($frame -match '^at <ScriptBlock>, <No file>: line (\d+)') {
                    "at <ScriptBlock>, ${taskFile}: line $($taskLineNumber + $Matches[1] - $TaskActionStartLine)"
                }
                else { $frame; $state = 'afterInvokeExpression'; }
            }
            'afterInvokeExpression' { $frame }
        }
    }

    [array]::Reverse($fixedFrames)
    $fixedStackTrace = $fixedFrames -join [System.Environment]::NewLine
    $field.SetValue($ErrorRecord, $fixedStackTrace)
}

function Invoke-Task {
    <#
    .DESCRIPTION
        Invokes a task defined in the task framework.

        This is typically not called directly; use Invoke-TaskFramework instead.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingInvokeExpression', '', Justification = 'Using Invoke-Expression is necessary to allow task actions to accept named arguments.')]
    [CmdletBinding(PositionalBinding = $false)]
    param(
        [Parameter(Mandatory)]
        [TaskDefinition]$Task,
        [ValidateNotNull()]
        [object[]]$TaskArgs = @(),
        [ValidateNotNull()]
        [TaskContext]$TaskContext = (Get-TaskFrameworkContext)
    )

    $TaskName = $Task.Name

    $global:LASTEXITCODE = 0
    $result = [TaskResult]@{
        Start    = [datetime]::UtcNow
        TaskArgs = [TaskArgs]@{
            Raw = $TaskArgs
        }
    }
    $TaskContext.CurrentTask = $Task
    $TaskContext.Results[$TaskName] = $result

    if ($null -eq $Task.Action) {
        Write-Verbose "Skipping task '$TaskName' since it has no action."
        $result.Duration = [TimeSpan]::Zero
        $result.ExitCode = 0
        $TaskContext.CurrentTask = $null
        return
    }

    $taskCommandArgs = @()
    if ($TaskArgs) {
        Import-Module PSArgs -Verbose:$false
        $taskCommandArgs = ConvertTo-CommandArg $TaskArgs
        Write-Verbose "Invoking task '$TaskName' with arguments: $taskCommandArgs"
    }
    else {
        Write-Verbose "Invoking task '$TaskName' with no arguments."
    }

    try {
        # Use Invoke-Expression to parse $TaskArgs in the context of the task's action.
        # This enables $TaskArgs to contain named arguments (i.e. '-foo','bar') not
        # just positional arguments ('bar')...
        try {
            $tArgs = Invoke-Expression "&{`n$($Task.Action.Ast.ParamBlock) return @{Bound=`$PSBoundParameters;Unbound=`$args}} $taskCommandArgs"
            $result.TaskArgs.Bound = $tArgs.Bound
            $result.TaskArgs.Unbound = $tArgs.Unbound
        }
        catch {
            Repair-TaskStackTrace -ErrorRecord $_ -Task $Task -TaskActionStartLine 2
            throw
        }

        # Now invoke the task action with the parsed arguments...
        $bound = $result.TaskArgs.Bound
        $unbound = $result.TaskArgs.Unbound
        & $Task.Action @bound @unbound
    }
    catch {
        $result.Error = $_
        throw
    }
    finally {
        $result.Duration = [datetime]::UtcNow - $result.Start
    }

    $result.ExitCode = $global:LASTEXITCODE
    if ($Task.AllowedExitCodes.Count -gt 0 -and $result.ExitCode -notin $Task.AllowedExitCodes) {
        throw "Task '$TaskName' failed with exit code $($result.ExitCode)."
    }

    # Success!
    Write-Verbose "Completed task '$TaskName' with exit code $($result.ExitCode)."
    $TaskContext.CurrentTask = $null
    $global:LASTEXITCODE = 0 # reset to avoid affecting the final exit code
}
