<#
.SYNOPSIS
    A lightweight task runner for common repository tasks.
.DESCRIPTION
    This script defines a set of common repository tasks that can be executed from
    the command line.

    See the task definitions below for more details on each task and how to use them.

    PowerShell 7.4 or later is required to use this script. See https://aka.ms/install-powershell.
.EXAMPLE
    PS> ./build.ps1

    Executes the default 'build' task, including all of its dependencies (e.g. 'restore').
.EXAMPLE
    PS> ./build.ps1 list

    Lists all available tasks.
.EXAMPLE
    PS> ./build.ps1 clean -noDeps

    Executes the 'clean' task without executing its dependencies.
.EXAMPLE
    PS> ./build.ps1 help clean -full

    Displays the help documentation for the 'clean' task.
    Run `./build.ps1 help help -full` for more information on the help system.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4
# spell:ignore dont,winget,choco

[CmdletBinding(PositionalBinding = $false)]
param (
    # The name of the task(s) to execute.
    [Parameter(Position = 0)]
    [ValidateSet(
        'list',
        'help',
        'bootstrap',
        'version',
        'clean',
        'build'
    )]
    [string[]] $TaskName = @('build'),

    # The build configuration to use when executing tasks that support it (e.g. 'build', 'test').
    # Defaults to 'debug'.
    [ValidateSet('debug', 'release')]
    [string] $Configuration = 'debug',

    # When specified, dependencies of the task(s) will not be executed.
    # Default is execute all dependencies (and their dependencies).
    [Alias("noDeps")]
    [switch] $SkipDependencies,

    # Receives task-specific arguments for the _single task_ specified in -TaskName.
    [Parameter(ValueFromRemainingArguments, DontShow)]
    [ValidateNotNull()]
    [object[]] $TaskArgs = @()
)
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# Define the repository root and scripts directory. All tasks will be executed in the
# context of the repository root ($RepoRoot).
$RepoRoot = $PSScriptRoot
$ScriptsDir = Convert-Path "$RepoRoot/scripts"

Import-Module "$ScriptsDir/PSTaskFramework" -Verbose:$false
$TaskContext = Initialize-TaskFramework

# Trick to suppress "parameter/variable never used" warning on vars that are only used in tasks.
$null = $TaskContext # used implicitly by the Task Framework
$null = $Configuration

####################################################################################
# Define all tasks
####################################################################################

Task bootstrap -desc 'Installs required tools' {
    <#
    .DESCRIPTION
        Bootstraps the repository by installing required tools.

        Required tools include:
        - Git (probably already installed, but we'll update if necessary).
        - PowerShell 7.4 or later (assumed to be already be installed).
        - ...
    #>
    param()
    Import-Module InstallHelpers -Verbose:$false

    $appsToInstall = [ordered]@{
        'git'        = $null # well-known app
        'powershell' = $null # well-known app
    }
    Install-RequiredApp $appsToInstall -InstallPackageManagers
}

Task version -desc 'Display tool versions' {
    [PSCustomObject]@{
        'PowerShell'  = $PSVersionTable.PSVersion
        'OS Platform' = "$($PSVersionTable.OS) ($($PSVersionTable.Platform))"
        'RepoRoot'    = $RepoRoot
    } | Format-List
}

Task clean -desc 'Clean the repository' -DependsOn version {
    <#
    .DESCRIPTION
        Cleans the repository using 'git clean'. By default it will run in interactive mode,
        prompting the user to confirm which files to delete. To skip the confirmation prompt,
        use the -Force switch.

        By default this uses 'git clean -X' to remove all untracked files that are
        ignored by git (e.g. build outputs, .vs folders, etc). This is typically safer since
        it leaves behind untracked files that are _not_ ignored by git, such as new source files.

        If you want to remove all untracked files, including those not ignored by git, use
        the -Pristine switch to run 'git clean -x' instead.
    #>
    param(
        # If specified, will run 'git clean -x' instead of 'git clean -X'
        [switch]$Pristine,
        # If specified, will skip the confirmation prompt and run 'git clean' with the -force option.
        [switch]$Force
    )
    $cleanArgs = @(
        '-d' # remove untracked directories in addition to untracked files
        ($Pristine ? '-x' : '-X')
        ($Force ? '--force' : '--interactive')
        '--exclude=.env' # never delete .env files since they often contain secrets
    )
    Invoke-Shell -- git clean @cleanArgs
}

Task build -desc 'Build the project' -dependsOn version {
    Write-Host "TODO: Implement $Configuration build logic."
}

##############################################################
# Execute the specified task(s) with the Task Framework. See
# the documentation for Invoke-TaskFramework for more details.
##############################################################

Invoke-TaskFramework `
    -TaskName $TaskName `
    -TaskArgs $TaskArgs `
    -SkipDependencies:$SkipDependencies `
    -WorkingDirectory $RepoRoot `
    -ExitOnError
