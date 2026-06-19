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

function Add-TaskFrameworkDefaultTasks {
    <#
    .DESCRIPTION
        Adds default tasks to the task framework, such as 'list' and 'help'.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessage('PSUseSingularNouns', '')]
    [CmdletBinding(PositionalBinding = $false)]
    param(
        # The tasks to include.
        [Parameter(Position = 0)]
        [ValidateSet('help', 'list', 'null')]
        [string[]] $Include = @('help', 'list'),

        # A hashtable specifying custom names for the default tasks.
        [ValidateNotNull()]
        [hashtable] $NameMap = @{},

        # The task context hashtable. Defaults to the current task context returned by Get-TaskFrameworkContext.
        [ValidateNotNull()]
        [TaskContext]$TaskContext = (Get-TaskFrameworkContext)

    )
    Sync-CallerPreference

    switch ($Include.where{ !(getTask ($NameMap[$_] ?? $_) -ea Ignore -TaskContext $TaskContext) }) {
        'null' {
            $name = $NameMap[$_] ?? $_
            Write-Verbose "Including default 'null' task as '$name'."
            Task $name -Description 'An empty task that does nothing.' -TaskContext $TaskContext -Action $null
        }
        'list' {
            $name = $NameMap[$_] ?? $_
            Write-Verbose "Including default 'list' task as '$name'."
            Task $name -Description 'List all defined tasks' -TaskContext $TaskContext {
                <#
                .DESCRIPTION
                    Lists all tasks defined in the task framework along with their descriptions
                    and dependencies.
                #>
                (getAllOrderedTasks).Values |
                Select-Object Name, Description, DependsOn
            }
        }
        'help' {
            $name = $NameMap[$_] ?? $_
            Write-Verbose "Including default 'help' task as '$name'."
            $TaskContext.HelpTaskName = $name
            Task $name -Description 'Show detailed help for a task' -TaskContext $TaskContext {
                <#
                .DESCRIPTION
                    Generates help for a task defined in the task framework. If a task name is not
                    specified, it generates help for the build script itself.
                .EXAMPLE
                    PS> .\build.ps1 help

                    Shows help for the build script.
                .EXAMPLE
                    PS> .\build.ps1 help test -full

                    Shows detailed help for the 'test' task, including its description, parameters,
                    usage, dependencies, and examples.
                .EXAMPLE
                    PS> .\build.ps1 help test -examples

                    Shows the 'test' task examples.
                #>
                [CmdletBinding(PositionalBinding = $false)]
                param(
                    # The name of the task to show help for. If not specified, shows help for the build script itself.
                    [Parameter(Position = 0)]
                    [string]$TaskName,

                    # Displays the entire help article for a cmdlet. Full includes parameter descriptions and attributes,
                    # examples, input and output object types, and additional notes.
                    [Parameter(ParameterSetName = 'Full')]
                    [switch]$Full,

                    # Adds parameter descriptions and examples to the basic help display.
                    [Parameter(ParameterSetName = 'Detailed', Mandatory)]
                    [switch]$Detailed,

                    # Displays only the name, synopsis, and examples.
                    [Parameter(ParameterSetName = 'Examples', Mandatory)]
                    [switch]$Examples,

                    # When specified, the help output will not be paged. By default, the help output is paged
                    # if it exceeds the console height.
                    [switch]$NoPaging
                )

                $getHelpArgs = [hashtable]$PSBoundParameters
                $null = $getHelpArgs.Remove('TaskName')
                $null = $getHelpArgs.Remove('NoPaging')
                $help = Get-TaskFrameworkHelp -TaskName $TaskName -GetHelpArgs $getHelpArgs

                if ($NoPaging) { $help | Out-Host }
                elseif ($IsWindows -and (Get-Command 'more' -ErrorAction Ignore)) { $help | more }
                elseif (!$IsWindows -and (Get-Command 'less' -ErrorAction Ignore)) { $help | less }
                else { $help | Out-Host -Paging }
            }
        }
        default {
            Write-Warning "Unknown default task requested: '$_'."
        }
    }
}
