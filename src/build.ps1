# SPDX-License-Identifier: Unlicense
# Source: http://github.com/mrfootoyou/pstaskframework
#Requires -Version 7.4
<#
.SYNOPSIS
    A lightweight task runner for common repository tasks.
.DESCRIPTION
    This script defines a set of common repository tasks that can be executed from
    the command line.

    See the task definitions below for more details on each task and how to use them.

    PowerShell 7.4 or later is required to use this script. See https://aka.ms/install-powershell.
.EXAMPLE
    PS> .\build.ps1
    Executes the default 'build' task, including all of its dependencies (e.g. 'restore').
.EXAMPLE
    PS> .\build.ps1 test -noDeps
    Executes the 'test' task without executing its dependencies.
#>
[CmdletBinding(PositionalBinding = $false)]
param (
    # The name of the task(s) to execute.
    [Parameter(Position = 0)]
    [ValidateSet(
        'list',
        'bootstrap',
        'version',
        'clean',
        'build'
    )]
    [string[]]
    $TaskName = @('build'),

    # The build configuration to use when executing tasks that support it (e.g. 'build', 'test').
    # Defaults to 'debug'.
    [ValidateSet('debug', 'release')]
    [string]
    $Configuration = 'debug',

    # Task-specific arguments for the task specified in -TaskName.
    # Cannot be used when -TaskName contains multiple tasks.
    # Arguments are _not_ passed to dependencies of the specified task.
    #
    # Tip: Use `-- ` to clearly separate build-script arguments from task arguments.
    # Anything after the `-- ` will be passed verbatim to the invoked task.
    # For example:
    #   .\build.ps1 myTask -v -- -v
    # In this example, the first '-v' is shorthand for PowerShell's -Verbose argument,
    # while the second '-v' is passed to 'myTask' as a task-specific argument.
    [Parameter(ValueFromRemainingArguments)]
    [object[]] $TaskArgs,

    # When specified, dependencies of the task(s) will not be executed.
    # Default is execute all dependencies (and their dependencies).
    [Alias("noDeps")]
    [switch] $SkipDependencies
)
$ErrorActionPreference = 'Stop'

# Define the repository root and scripts directory. All tasks will be executed in the
# context of the repository root ($RepoRoot).
# Assume this script is located in the repository root.
$RepoRoot = $PSScriptRoot
$ScriptsDir = Convert-Path "$RepoRoot/scripts"

# Import the Task Framework and clear any previous state...
Import-Module "$ScriptsDir/task-framework.psm1" -Force -Scope Local -Verbose:$false
Reset-TaskFramework

####################################################################################
# Define tasks variables
#
# Each task is executed in an isolated scope, meaning they only have access to
# global variables and variables defined in the $Variables dictionary.
#
# The properties of the $Variables dictionary will be imported as variables
# into each task prior to execution. This allows you to define common variables that
# are shared across all tasks, such as the repository root, scripts directory, or any
# other values that tasks may need, such as input parameters like $Configuration.
#
# The $Variables dictionary itself is available to all tasks, enabling tasks to
# pass information to subsequent tasks.
#
# The following variables are always available:
# - $Task: The currently executing task definition.
# - $TaskName: The name of the currently executing task (same as $Task.Name).
# - $TaskArgs: An array of the arguments passed to the currently executing task.
# - $SkipDependencies: Indicates if the task's dependencies were executed.
# - $TasksToExecute: The ordered list of all tasks to execute.
# - $Variables: The dictionary of variables to import into each task's scope.
$Variables = @{
    RepoRoot      = $RepoRoot
    ScriptsDir    = $ScriptsDir
    Configuration = $Configuration
    # Add more variables here as needed
}

# These scripts will be imported into each task prior to execution.
$ImportScripts = @(
    Join-Path $ScriptsDir 'build-helpers.ps1'
    # Add more scripts here as needed
)

####################################################################################
# Define all tasks
####################################################################################

Task list -desc 'List all tasks' {
    Get-TaskFrameworkTasks | Format-Table Name, Description, DependsOn -AutoSize
}

Task bootstrap -desc 'Installs required tools' {
    <#
    .DESCRIPTION
        Bootstraps the repository by installing required tools.

        Required tools include:
        - Git (probably already installed, but we'll update if necessary).
        - PowerShell 7.4 or later (assumed to be already be installed).
        - ...

        On Windows it will attempt to install the required tools using WinGet or Chocolatey.
        If these are not available, it will prompt the user to install the tools manually.

        On non-Windows platforms, it will prompt the user to install the required tools
        manually.
    #>
    param()
    $wingetPackageIds = @('Git.Git') # WinGet package IDs. See `winget search <appname>`.
    $chocoPackageIds = @('git') # Chocolatey package IDs. See `choco search <appname>`.

    $installed = $false

    # Check if WinGet is available. See https://learn.microsoft.com/en-us/windows/package-manager/winget/
    if (!$installed -and $IsWindows -and (Get-Command 'WinGet' -ErrorAction Ignore)) {
        # WinGet will prompt for admin privileges when necessary.
        $allowedExitCodes = @(
            0,
            0x8A15002B # No applicable update found
        )
        Invoke-Shell -AllowedExitCodes $allowedExitCodes -- WinGet install @wingetPackageIds --exact --accept-package-agreements --accept-source-agreements
        $global:LASTEXITCODE = 0
        $installed = $true
    }

    # Check if Chocolatey is available. See https://chocolatey.org/
    if (!$installed -and $IsWindows -and (Get-Command 'choco' -ErrorAction Ignore)) {
        # Chocolatey requires admin privileges to install packages.
        if (Test-Administrator) {
            Invoke-Shell -- choco install @chocoPackageIds --yes
        }
        else {
            Write-Host 'Running Chocolatey as administrator. Expect a prompt.' -ForegroundColor Yellow
            Start-Process cmd -ArgumentList "/K choco install $($chocoPackageIds -join ' ') --yes" -Verb RunAs -Wait
        }
        $installed = $true
    }

    if (-not $installed) {
        Write-Host 'Install latest Git from https://git-scm.com/downloads' -ForegroundColor Magenta
    }
    Write-Host 'Install latest PowerShell from https://aka.ms/powershell' -ForegroundColor Magenta
}

Task version -desc 'Display tool versions' {
    [pscustomobject]@{
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
    -ExitOnError `
    -Verbose:($VerbosePreference -eq 'Continue')
