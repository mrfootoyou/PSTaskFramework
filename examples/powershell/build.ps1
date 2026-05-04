<#
.SYNOPSIS
    A lightweight task runner for common PowerShell repository tasks.
.DESCRIPTION
    This script defines a set of common PowerShell repository tasks that can be executed from
    the command line.

    See the task definitions below for more details on each task and how to use them.

    PowerShell 7.4 or later is required to use this script. See https://aka.ms/install-powershell.
.EXAMPLE
    PS> ./build.ps1

    Executes the default 'test' and 'analysis' tasks.
.EXAMPLE
    PS> ./build.ps1 list

    Lists all available tasks.
.EXAMPLE
    PS> ./build.ps1 test -noDeps

    Executes the 'test' task without executing its dependencies.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4
# spell:ignore pester,sarif,nunit

[CmdletBinding(PositionalBinding = $false)]
param (
    # The name of the task(s) to execute.
    [Parameter(Position = 0)]
    [ValidateSet(
        'list',
        'bootstrap',
        'version',
        'clean',
        'test',
        'analysis'
    )]
    [string[]]
    $TaskName = @('test', 'analysis'),

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
    [object[]] $TaskArgs,

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
$PSModuleVersions = @{
    Pester           = '5.7.1'
    PSScriptAnalyzer = '1.25.0'
    ConvertToSARIF   = '1.0.0'
}

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
    RepoRoot         = $RepoRoot
    ScriptsDir       = $ScriptsDir
    PSModuleVersions = $PSModuleVersions
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
        - Pester
        - PSScriptAnalyzer
        - ConvertToSARIF
    #>
    param()
    Import-Module InstallHelpers -Verbose:$false

    $appsToInstall = [ordered]@{
        'git'        = $null # well-known app
        'powershell' = $null # well-known app
    }
    Install-RequiredApp $appsToInstall -InstallPackageManagers
    Install-PowerShellModule -ModuleVersions $PSModuleVersions
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

Task test -desc 'Execute tests' -dependsOn version {
    <#
    .DESCRIPTION
        Executes all Pester tests in the repo and optionally collect code coverage.
    .EXAMPLE
        PS> ./build.ps1 test

        Run all Pester tests in the repo.
    .EXAMPLE
        PS> ./build.ps1 test -TestReport -CoverageReport

        Run all Pester tests in the repo and generate a JUnit XML report and a
        Cobertura code coverage report.
    #>
    param(
        # Optional list of test filters to apply. Each is a wildcard pattern
        # used to match test names.
        [string[]] $TestFilter,
        # Indicates that a test report should be written to
        # "./artifacts/results/junit.xml" in JUnit XML format.
        [switch] $TestReport,
        # Indicates that a code coverage report should be written to
        # "./artifacts/results/coverage.cobertura.xml" in Cobertura XML format.
        [switch] $CoverageReport,
        # Return result object to the pipeline after finishing the test run.
        [switch] $PassThru,
        # If specified, will set the Pester output verbosity to "Detailed" to
        # include more information about each test in the console output.
        [switch] $Verbose
    )

    $ReportPath = './artifacts/results/junit.xml'
    $CoverageOutputPath = './artifacts/results/coverage.cobertura.xml'

    if (!(Import-Module Pester -MinimumVersion $PSModuleVersions['Pester'] -PassThru -Verbose:$false -ErrorAction Ignore)) {
        throw 'Pester module is not installed. Run the "bootstrap" task to install required tools.'
    }

    # Using a hashtable to construct the configuration object so that we can
    # log the configuration ([PesterConfiguration] does not support logging).
    # $configuration = New-PesterConfiguration
    $configuration = @{}
    $configuration.Run = @{}
    $configuration.Run.Path = $ScriptsDir # excludes build.ps1
    $configuration.Run.PassThru = $PassThru.IsPresent
    $configuration.Output = @{}
    $configuration.Output.Verbosity = $Verbose ? 'Detailed' : 'Normal'
    if ($TestFilter) {
        $configuration.Filter = @{}
        $configuration.Filter.FullName = $TestFilter # apply test filters if specified
    }
    if ($TestReport) {
        Remove-Item $ReportPath -ErrorAction Ignore
        $configuration.TestResult = @{}
        $configuration.TestResult.Enabled = $true
        $configuration.TestResult.OutputPath = $ReportPath
        $configuration.TestResult.OutputFormat = 'JUnitXml'
        $configuration.TestResult.TestSuiteName = 'PowerShell Tests'
    }
    if ($CoverageReport) {
        Remove-Item $CoverageOutputPath -ErrorAction Ignore
        $configuration.CodeCoverage = @{}
        $configuration.CodeCoverage.Enabled = $true
        $configuration.CodeCoverage.OutputPath = $CoverageOutputPath
        $configuration.CodeCoverage.OutputFormat = 'Cobertura'
        $configuration.CodeCoverage.CoveragePercentTarget = 75
    }

    # Run tests within a temporary module (private session) to prevent the
    # TaskFramework tests from clobbering the current TaskFramework state.
    $tempModule = New-Module -ArgumentList $PSModuleVersions['Pester'] -ScriptBlock {
        param($PesterVersion)
        Import-Module Pester -MinimumVersion $PesterVersion
        Export-ModuleMember -Function Invoke-Pester
    }

    Write-Host "$($PSStyle.Dim)>> Invoke-Pester -Configuration $(ConvertTo-PSString $configuration)"
    & $tempModule Invoke-Pester -Configuration $configuration

    if ($TestReport -and (Test-Path $ReportPath)) {
        Write-Host "Test report: '$ReportPath'." -ForegroundColor Green
    }

    # Pester always sets LASTEXITCODE to the number of failed tests.
    if ($global:LASTEXITCODE -gt 0) {
        throw "$global:LASTEXITCODE tests failed."
    }

    if ($CoverageReport -and (Test-Path $CoverageOutputPath)) {
        Write-Host "Coverage report: '$CoverageOutputPath'." -ForegroundColor Green
    }
}

Task analysis -desc 'Execute analysis' -dependsOn version {
    <#
    .DESCRIPTION
        Run PSScriptAnalyzer on the repo.

        This will check for common issues in PowerShell scripts and modules.

        The results will be output to the console and, if specified, to a SARIF report
        which can be used to integrate with other tools, such as GitHub Actions.

        The script will set the LASTEXITCODE to the number of issues found (0 or more).
    .EXAMPLE
        PS> ./build.ps1 analysis

        Run PSScriptAnalyzer on the repo.
    .EXAMPLE
        PS> ./build.ps1 analysis -CreateSarifReport

        Run PSScriptAnalyzer on the repo and generate a SARIF report.
    #>
    param(
        # Indicates that a SARIF report should be written to "./artifacts/results/analysis.sarif".
        [switch] $CreateSarifReport,
        # Whether to automatically fix issues found by PSScriptAnalyzer.
        [switch] $Fix
    )
    $SarifPath = './artifacts/results/analysis.sarif'

    if (!(Import-Module PSScriptAnalyzer -MinimumVersion $PSModuleVersions['PSScriptAnalyzer'] -PassThru -Verbose:$false -ErrorAction Ignore)) {
        throw 'PSScriptAnalyzer module is not installed. Run the "bootstrap" task to install required tools.'
    }
    if (!(Get-Command 'Invoke-ScriptAnalyzer' -ea Ignore)) {
        # This is known to happen in the VSCode integrated terminal, possibly
        # due to a conflict with the the VSCode PowerShell extension.
        # Running the script in a different console window seems to fix it.
        throw "PSScriptAnalyzer is not available. Try again in a different console window."
    }

    if ($CreateSarifReport) {
        if (!(Import-Module ConvertToSARIF -MinimumVersion $PSModuleVersions['ConvertToSARIF'] -PassThru -Verbose:$false -ErrorAction Ignore)) {
            throw 'ConvertToSARIF module is not installed. Run the "bootstrap" task to install required tools.'
        }
    }

    # run PSScriptAnalyzer...
    $saArgs = [ordered]@{
        Path     = '.'
        Recurse  = $true
        Settings = './PSScriptAnalyzerSettings.psd1'
        Fix      = $Fix.IsPresent
    }
    Write-Host "$($PSStyle.Dim)>> Invoke-ScriptAnalyzer $(ConvertTo-CommandArg $saArgs)"
    $results = Invoke-ScriptAnalyzer @saArgs
    $results | Out-Host

    if ($CreateSarifReport) {
        if (!(Test-Path (Split-Path $SarifPath))) {
            $null = New-Item (Split-Path $SarifPath) -ItemType Directory -Force
        }

        Write-Host "$($PSStyle.Dim)>> ConvertTo-SARIF -FilePath $(ConvertTo-CommandArg $SarifPath)"
        $results | ConvertTo-SARIF -FilePath $SarifPath
        Write-Host "SARIF report saved to '$SarifPath'." -ForegroundColor Green
    }

    # Always set the global LASTEXITCODE to the number of issues found.
    $global:LASTEXITCODE = $results.Count

    $resultMsg = "PSScriptAnalyzer found $($results.Count) issue(s)."
    if ($results.Count -gt 0) {
        throw $resultMsg
    }
    Write-Host $resultMsg -ForegroundColor Green
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
