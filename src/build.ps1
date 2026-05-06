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
# spell:ignore winget,choco

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

    # Task-specific arguments for the task specified in -TaskName.
    # Cannot be used when -TaskName contains multiple tasks.
    # Arguments are _not_ passed to dependencies of the specified task.
    #
    # Tip: Use `-- ` to clearly separate build-script arguments from task arguments.
    # Anything after the `-- ` will be passed verbatim to the invoked task.
    # For example:
    #   ./build.ps1 myTask -v -- -v
    # In this example, the first '-v' is shorthand for PowerShell's -Verbose argument,
    # while the second '-v' is passed to 'myTask' as a task-specific argument.
    [Parameter(ValueFromRemainingArguments)]
    [ValidateNotNull()]
    [object[]] $TaskArgs = @(),

    # When specified, dependencies of the task(s) will not be executed.
    # Default is execute all dependencies (and their dependencies).
    [Alias("noDeps")]
    [switch] $SkipDependencies
)
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# Define the repository root and scripts directory. All tasks will be executed in the
# context of the repository root ($RepoRoot).
# Assume this script is located in the repository root.
$RepoRoot = $PSScriptRoot
$ScriptsDir = Convert-Path "$RepoRoot/scripts"

####################################################################################
# Define tasks variables
####################################################################################
# The properties of the $Variables dictionary will be imported as variables
# into each task prior to execution. This allows you to define common variables that
# are shared across all tasks, such as the repository root, scripts directory, or any
# other values that tasks may need, such as input parameters like $Configuration.
#
# The following variables are always available:
# - $Task: The currently executing task definition.
# - $TaskName: The name of the currently executing task (same as $Task.Name).
# - $TaskArgs: An array of the arguments passed to the currently executing task.
# - $SkipDependencies: Indicates if the task's dependencies were executed.
# - $TasksToExecute: The ordered list of all tasks to execute.
# - $Variables: The dictionary of variables to import into each task's scope.
$Variables = @{
    RepoRoot        = $RepoRoot
    ScriptsDir      = $ScriptsDir
    BuildInvocation = $MyInvocation
    Configuration   = $Configuration
    # Add more variables here as needed
}

# These scripts will be imported into each task prior to execution.
$ImportScripts = @(
    # Add more scripts here as needed
)

####################################################################################
# Define all tasks
####################################################################################
Import-Module "$ScriptsDir/PSTaskFramework" -Verbose:$false
Reset-TaskFramework
Add-TaskFrameworkDefaultTasks list, help

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
    Write-Host 'TODO: Implement build logic.'
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
    -Variables $Variables `
    -ImportScripts $ImportScripts `
    -ExitOnError
