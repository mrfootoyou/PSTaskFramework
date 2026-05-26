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
# spell:ignore dont,pester,sarif,nunit

[Diagnostics.CodeAnalysis.SuppressMessage('PSReviewUnusedParameter', '')]
[Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidGlobalVars', 'global:LastTaskContext')]
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
        'test',
        'analysis'
    )]
    [string[]] $TaskName = @('test', 'analysis'),

    # When specified, dependencies of the task(s) will not be executed.
    # Default is execute all dependencies (and their dependencies).
    [Alias("noDeps")]
    [switch] $SkipDependencies,

    # Receives task-specific arguments for the _single task_ specified in -TaskName.
    [Parameter(ValueFromRemainingArguments, DontShow)]
    [ValidateNotNull()]
    [object[]] $TaskArgs = @()
)
# Initialize some default PowerShell preferences...
$ErrorActionPreference = 'Stop'     # throw exception on any unhandled error
$InformationPreference = 'Continue' # display informational messages

# Initialize some repository variables...
$RepoRoot = $PSScriptRoot # assumes this script is located in the repo root
$ScriptsDir = Convert-Path "$RepoRoot/scripts"

# Import and initialize the PSTaskFramework...
Import-Module "$ScriptsDir/PSTaskFramework" -Verbose:$false
$TaskContext = Initialize-TaskFramework

####################################################################################
# Define shared variables and functions...
####################################################################################

$PSModuleVersions = @{
    Pester           = '5.7.1'
    PSScriptAnalyzer = '1.25.0'
    ConvertToSARIF   = '1.0.0'
}

####################################################################################
# Define all tasks
# - Tasks will execute in the order they are defined below, unless they have
#   dependencies, in which case the dependencies will always be executed first.
# - The task's working directory is the folder containing this script.
# - Tasks can assign values to script-scope variables using the `$script:` modifier.
####################################################################################
#region Task definitions

# Add the default list and help tasks...
Add-TaskFrameworkDefaultTasks list, help

Task bootstrap -desc 'Installs required tools' {
    <#
    .DESCRIPTION
        Bootstraps the repository by installing required tools.

        Required tools include:
        - Git (probably already installed).
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

    Write-Host "$($PSStyle.Dim)>> Invoke-Pester -Configuration $(ConvertTo-PSString $configuration)"
    Invoke-Pester -Configuration $configuration

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

#endregion Task definitions

####################################################################################
# Execute the specified task(s)...
####################################################################################
try {
    Invoke-TaskFramework `
        -TaskName $TaskName `
        -TaskArgs $TaskArgs `
        -SkipDependencies:$SkipDependencies `
        -ExitOnError
}
finally {
    # Save TaskContext in a global variable so that it can be inspected
    $global:LastTaskContext = $TaskContext
}
