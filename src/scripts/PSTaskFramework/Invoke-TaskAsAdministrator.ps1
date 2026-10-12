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
        [string[]] $TaskArgs,
        # Environment variables to pass to the elevated session. Can be an array of variable
        # names or a dictionary of name-value pairs. Values must be string or $null ($null will
        # remove the variable from the elevated session).
        [ValidateNotNull()]
        [object] $EnvVars = @{}
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

    # Normalize EnvVars by converting to a hashtable of name-value pairs.
    if ($EnvVars -is [string]) { $EnvVars = @($EnvVars) }
    if ($EnvVars -is [System.Collections.IList]) {
        # Convert list of environment variable names to a hashtable of name-value pairs.
        $keys = $EnvVars
        $EnvVars = @{}
        foreach ($key in $keys) {
            $var = Get-Item -LiteralPath "env:$key" -ErrorAction Ignore
            $EnvVars[$key] = $var.Value # string or $null
        }
    }
    if ($EnvVars -isnot [System.Collections.IDictionary]) {
        throw 'EnvVars must be a hashtable or a list of environment variable names.'
    }

    # Script block to execute as an administrator. All inputs must be passed as
    # parameters since this will execute in a different process.
    $adminScriptBlock = {
        param(
            [string] $BuildScriptPath,
            [string] $TaskName,
            [object[]] $TaskArgs,
            [switch] $DoNotWaitForKeyPress,
            [hashtable] $ExtraScriptArgs,
            [hashtable] $EnvVars
        )
        # Set environment variables for the elevated session.
        foreach ($key in $EnvVars.Keys) {
            if ($null -ne $EnvVars[$key]) {
                Write-Verbose "Setting environment variable '$key' = '$($EnvVars[$key])'"
                $null = New-Item "env:$key" -Value $EnvVars[$key] -Force
            }
            else {
                Write-Verbose "Removing environment variable '$key'"
                Remove-Item "env:$key" -ErrorAction Ignore
            }
        }
        $buildScriptArgs = @{
            TaskName         = $TaskName
            TaskArgs         = $TaskArgs
            SkipDependencies = $true
        }
        Write-Verbose "Executing: '$BuildScriptPath' $(ConvertTo-CommandArg $buildScriptArgs) $(ConvertTo-CommandArg $ExtraScriptArgs)"
        try {
            $global:LASTEXITCODE = 0
            $LastTaskContext = $null
            & $BuildScriptPath @buildScriptArgs @ExtraScriptArgs
        }
        catch {
            if ($global:LASTEXITCODE -eq 0) {
                $global:LASTEXITCODE = -1
            }
            Write-Error -ErrorRecord $_ -ea Continue
        }
        $exitCode = $global:LASTEXITCODE
        # check for a task-specific exit code...
        if ($LastTaskContext) {
            $exitCode = $LastTaskContext.ExitCode ?? $exitCode
            if ($LastTaskContext.Results -and $LastTaskContext.Results.ContainsKey($TaskName)) {
                $exitCode = $LastTaskContext.Results[$TaskName].ExitCode ?? $exitCode
            }
        }
        if (!$DoNotWaitForKeyPress) {
            Write-Host 'Press any key to continue...' -NoNewline
            $null = [System.Console]::ReadKey()
        }
        exit $exitCode
    }
    $adminScriptArgs = @{
        TaskName             = $TaskName
        TaskArgs             = $TaskArgs
        BuildScriptPath      = $TaskContext.BuildScriptPath
        ExtraScriptArgs      = $ExtraScriptArgs
        EnvVars              = $EnvVars
        DoNotWaitForKeyPress = $DoNotWaitForKeyPress
    }

    # Import before setting verbose preference to avoid a bunch of verbose output
    $command = @(
        "Import-Module '$PSScriptRoot'"
        "`$VerbosePreference = '$VerbosePreference'"
        "function adminTask {$adminScriptBlock}"
        "adminTask $(ConvertTo-CommandArg $adminScriptArgs)"
    ) -join "`n"

    $pwshArgs = @(
        '-nologo'
        '-noprofile'
        '-executionpolicy', 'bypass'
        '-encodedcommand', [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    )

    Write-Host 'Running task with elevated privileges. Follow instructions in the UAC prompt...'
    Write-Verbose "Starting elevated task with command:`n$command"
    $ps = Start-Process `
        -FilePath (Get-Process -Id $PID).Path `
        -ArgumentList $pwshArgs `
        -WorkingDirectory $TaskContext.WorkingDirectory `
        -Verb RunAs `
        -Wait `
        -PassThru

    $global:LASTEXITCODE = $ps.ExitCode ?? -1
    # It is assumed the caller will handle the exit code.
}
