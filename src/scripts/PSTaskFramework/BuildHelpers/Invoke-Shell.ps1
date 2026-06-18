<#
.SYNOPSIS
    Part of the PSTaskFramework.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4

param()

Import-Module "$PSScriptRoot/../PSArgs" -Verbose:$false
Import-Module "$PSScriptRoot/../Secrets" -Verbose:$false

function Invoke-Shell {
    <#
    .SYNOPSIS
        Invokes a shell application.
    .DESCRIPTION
        Invokes a shell application with arguments. The full command is echoed
        to the console using Write-Information (suppress with `-InformationAction Ignore`).

        If the command completes with a non-zero exit code, it is considered to have
        failed and an error stating as much is reported/thrown according to the
        -ErrorAction parameter. The $global:LASTEXITCODE variable will always contain
        the command's exit code.

        Best practice is to separate any PowerShell arguments from command arguments
        using `-- `.
        Arguments after the `-- ` separator are guaranteed to be passed verbatim to
        the invoked command, while arguments before the separator _may_ be interpreted
        as PowerShell arguments.

        For example:
            Invoke-Shell -- dotnet build -v quiet

        Without the `-- ` separator, PowerShell would interpret the '-v' as a PowerShell
        argument (-Verbose).
    #>
    [CmdletBinding()]
    param(
        # The command to execute. This can be a simple command name (e.g. "git") or a path
        # to an executable. The command must be an application which completes with an
        # exit code indicating success (0) or failure (non-zero).
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $Command,

        # The arguments to pass to the command.
        # You typically do not use this parameter directly since PowerShell will automatically
        # add any unrecognized arguments to this parameter.
        [Parameter(ValueFromRemainingArguments)]
        [ValidateNotNull()]
        [string[]] $CommandArgs = @(),

        # An array of exit codes that are considered successful. Defaults to 0.
        # An empty array means to ignore the exit code (i.e. consider all exit codes successful).
        [ValidateNotNull()]
        [int[]] $AllowedExitCodes = @(0)
    )

    Sync-CallerPreference -PreferencesToSync ErrorAction, InformationAction

    $cmdPath = assertAppExists $Command -PassThru
    $cmdText = Protect-Secret "$(ConvertTo-PSString $cmdPath) $(ConvertTo-CommandArg $CommandArgs)"
    Write-Information "$($PSStyle.Dim)>> $cmdText$($PSStyle.Reset)"

    $global:LASTEXITCODE = 0
    $PSNativeCommandUseErrorActionPreference = $false # we'll handle errors ourselves
    & $cmdPath @CommandArgs

    if ($AllowedExitCodes.Count -gt 0 -and $global:LASTEXITCODE -notin $AllowedExitCodes) {
        if ($ErrorActionPreference -ne 'Ignore') {
            Write-Error -Exception "Command failed with exit code $global:LASTEXITCODE ($cmdText)." `
                -CategoryActivity $MyInvocation.MyCommand.Name `
                -Category InvalidResult `
                -CategoryReason 'NonZeroExitCode' `
                -TargetObject $Command
        }
    }
}
