<#
.SYNOPSIS
    Part of the PSTaskFramework.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4
#spell:ignore nologo

using module .\PSTaskFramework.classes.psm1
param()

function Invoke-TaskAsAdministrator {
    <#
    .DESCRIPTION
        Executes the specified task (and only that task) with elevated privileges by executing
        the active build script with elevated privileges. It is equivalent to running the
        following command at an elevated prompt:

          & $BuildScriptPath $TaskName -TaskArgs $TaskArgs -SkipDependencies

        This is intended to be called from inside a task when elevated privileges are required.
        Therefore the TaskName, TaskArgs, and TaskContext arguments default to the current task's
        context.

        Example usage:

          if (!(Test-Administrator)) {
              Invoke-TaskAsAdministrator
              return
          }
    #>
    [CmdletBinding(PositionalBinding = $false)]
    param(
        # Extra arguments to pass to the script. Use this when the script has additional
        # required arguments (other than TaskName).
        [hashtable] $ExtraScriptArgs = @{},
        # If specified, the script will not wait for a key press in the elevated session.
        # Default is to wait for a key press so the user can review the result.
        [switch] $DoNotWaitForKeyPress,

        # Context for the current task. Defaults to the current context.
        [ValidateNotNull()]
        [TaskContext] $TaskContext = (Get-TaskFrameworkContext),

        # The name of a specific task to execute. Defaults to the current task.
        [ValidateNotNullOrEmpty()]
        [string] $TaskName,
        # Arguments for the task. Defaults to the current task's arguments when the TaskName
        # is not specified, otherwise an empty array.
        [ValidateNotNull()]
        [string[]] $TaskArgs
    )
    Sync-CallerPreference

    if (!$TaskName) {
        if (!$TaskContext.CurrentTask) { throw 'No current task in context.' }
        $TaskName = $TaskContext.CurrentTask.Name
        $TaskArgs ??= $TaskContext.Results[$TaskName].TaskArgs.Raw
    }
    else {
        $null = getTask -TaskName $TaskName -TaskContext $TaskContext -ea Stop
    }
    $TaskArgs ??= @()

    Write-Host 'Running task with elevated privileges. Follow instructions in the UAC prompt...'
    $adminScriptBlock = {
        param(
            [string] $BuildScriptPath,
            [string] $TaskName,
            [object[]] $TaskArgs,
            [bool] $DoNotWaitForKeyPress,
            [hashtable] $ExtraScriptArgs
        )
        Write-Verbose "Executing: '$BuildScriptPath' $TaskName -TaskArgs $(ConvertTo-PSString $TaskArgs) -SkipDependencies @$(ConvertTo-PSString $ExtraScriptArgs)"
        try {
            $LastTaskContext = $null
            & $BuildScriptPath -TaskName $TaskName -TaskArgs $TaskArgs -SkipDependencies @ExtraScriptArgs
        }
        finally {
            $exitCode = $global:LASTEXITCODE
            if ($LastTaskContext) {
                $LastTaskContext | Out-Host
                if ($LastTaskContext.Results.ContainsKey($TaskName)) {
                    $LastTaskContext.Results[$TaskName] | Out-Host
                    $exitCode = $LastTaskContext.Results[$TaskName].ExitCode ?? $exitCode
                }
            }
            if (!$DoNotWaitForKeyPress) {
                Write-Host 'Press any key to continue...' -NoNewline
                $null = [System.Console]::ReadKey()
            }
            exit $exitCode
        }
    }
    $adminScriptArgs = @(
        '-BuildScriptPath', $TaskContext.BuildScriptPath
        '-TaskName', $TaskName
        '-TaskArgs', $TaskArgs
        '-DoNotWaitForKeyPress', $DoNotWaitForKeyPress
        '-ExtraScriptArgs', $ExtraScriptArgs
    )

    $command = @"
Import-Module '$PSScriptRoot' # before setting verbose preference to avoid a bunch of verbose output
`$VerbosePreference = '$VerbosePreference'
function adminTask {$adminScriptBlock}
adminTask $(ConvertTo-CommandArg $adminScriptArgs)
"@

    Write-Verbose "Starting elevated task with command:`n$command"
    # return
    $ps = Start-Process `
        -FilePath (Get-Process -Id $PID).Path `
        -ArgumentList "-nologo -nop -ep bypass -ec $([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command)))" `
        -WorkingDirectory $TaskContext.WorkingDirectory `
        -Verb RunAs `
        -Wait `
        -PassThru

    $global:LASTEXITCODE = $ps.ExitCode ?? -1
    # It is assumed the caller will handle the exit code.
}
