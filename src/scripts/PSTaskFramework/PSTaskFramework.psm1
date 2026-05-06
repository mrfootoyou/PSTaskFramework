<#
.DESCRIPTION
    Task management helpers for PowerShell.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4
# spell:ignore psargs,targs,maml

param()

class TaskDefinition {
    [string]$Name
    [string]$Description
    [string[]]$DependsOn
    [ScriptBlock]$Action
    [int[]]$AllowedExitCodes = @(0)

    [string] ToString() { return $this.Name }

    static hidden [ordered] $AllTasks = [ordered]@{}
    static hidden [bool] $TasksSorted = $true

    static [void] Clear() {
        [TaskDefinition]::AllTasks.Clear()
        [TaskDefinition]::TasksSorted = $true
    }

    static [void] AddTask([TaskDefinition]$task) {
        if ([TaskDefinition]::AllTasks.Contains($task.Name)) {
            throw "A task with the name '$($task.Name)' already exists."
        }
        [TaskDefinition]::AllTasks[$task.Name] = $task
        [TaskDefinition]::TasksSorted = $false
    }

    static [TaskDefinition] TryGetTask([string]$taskName) {
        if (-not [TaskDefinition]::AllTasks.Contains($taskName)) {
            return $null
        }
        return [TaskDefinition]::AllTasks[$taskName]
    }

    static [TaskDefinition] GetTask([string]$taskName) {
        return [TaskDefinition]::TryGetTask($taskName) ?? (throw "Task '$taskName' not found.")
    }

    # Returns an ordered array of TaskDefinition objects corresponding to the specified task
    # names and their dependencies (if $includeDependencies is specified). The tasks are returned
    # in dependency order. For example, if taskA depends on taskB, then GetOrderedTasks('taskA', $true)
    # will return an array with taskB first, followed by taskA.
    static [TaskDefinition[]] GetOrderedTasks([string[]]$taskNames, [switch]$includeDependencies) {
        # get all tasks in dependency order...
        $orderedTaskMap = [TaskDefinition]::GetOrderedTasks()

        # get the set of all tasks to execute, including dependencies if specified.
        $execTaskNames = @{}
        $queue = [System.Collections.Generic.Queue[string]]::new($taskNames)
        while ($queue.Count -gt 0) {
            $taskName = $queue.Dequeue()
            if ($execTaskNames.ContainsKey($taskName)) {
                continue # already visited
            }
            $execTaskNames[$taskName] = $true
            $task = $orderedTaskMap[$taskName]
            if (-not $task) {
                throw "Task '$taskName' not found."
            }
            if ($includeDependencies) {
                foreach ($dep in $task.DependsOn) {
                    $queue.Enqueue($dep)
                }
            }
        }

        # Return the tasks in dependency order...
        return @(
            foreach ($task in $orderedTaskMap.Values) {
                if ($execTaskNames.ContainsKey($task.Name)) {
                    $task
                }
            }
        )
    }

    # Returns an ordered dictionary of all defined tasks, sorted in dependency order.
    # The keys are task names and the values are TaskDefinition objects.
    static [System.Collections.Specialized.IOrderedDictionary] GetOrderedTasks() {
        if ([TaskDefinition]::TasksSorted) {
            return [TaskDefinition]::AllTasks
        }

        # Sort tasks in dependency order using a depth-first search.
        # Preserve the original order of tasks as much as possible while ensuring that
        # dependencies are always defined before the tasks that depend on them.
        # This also detects circular dependencies.
        $visited = @{}
        function visit([TaskDefinition]$task) {
            if ($visited.ContainsKey($task.Name)) {
                # already visited this node; if we're visiting it again, we have a
                # circular dependency
                if ($visited[$task.Name] -eq 'visiting') {
                    throw "Circular dependency detected at task '$($task.Name)'."
                }
                return
            }
            $visited[$task.Name] = 'visiting'
            foreach ($dep in $task.DependsOn) {
                $depTask = [TaskDefinition]::TryGetTask($dep)
                if (-not $depTask) {
                    throw "Dependency '$dep' of task '$($task.Name)' not found."
                }
                visit $depTask
            }
            $visited[$task.Name] = ''
            $task
        }

        $orderedTasks = @(
            foreach ($task in [TaskDefinition]::AllTasks.Values) {
                visit $task
            }
        )

        [TaskDefinition]::AllTasks.Clear()
        foreach ($task in $orderedTasks) {
            [TaskDefinition]::AllTasks[$task.Name] = $task
        }
        [TaskDefinition]::TasksSorted = $true
        return [TaskDefinition]::AllTasks
    }
}

function Reset-TaskFramework {
    <#
    .DESCRIPTION
        Resets the state of the task framework by clearing all defined tasks. This can be useful
        to ensure a clean slate when invoking multiple tasks or when reloading the task framework.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Resetting the task framework is a state change, but it is not something that users would typically want to confirm.')]
    [CmdletBinding()]
    param()
    [TaskDefinition]::Clear()
}

function addTask {
    <#
    .DESCRIPTION
        Private implementation of the `Task` function that adds a task to the task framework.
        This is separated from the public Task function to allow for easier error handling and
        to avoid syncing caller preferences multiple times when adding multiple tasks.
    #>
    [CmdletBinding()]
    param (
        [string]$Name,
        [ScriptBlock]$Action,
        [string]$Description,
        [string[]]$DependsOn = @(),
        [int[]]$AllowedExitCodes = @(0)
    )
    try {
        [TaskDefinition]::AddTask(@{
                Name             = $Name
                Description      = $Description
                DependsOn        = $DependsOn
                Action           = $Action
                AllowedExitCodes = $AllowedExitCodes
            })
    }
    catch {
        Write-Error -Exception $_.Exception -CategoryActivity 'Add task' -Category ResourceExists -TargetObject $Name
    }
}

function Task {
    <#
    .DESCRIPTION
        Adds a task with an associated action and optional task dependencies to the
        task framework.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    param (
        # The name of the task. Must be unique. Not case-sensitive.
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        # The script block to execute when the task is invoked. May be null or empty for
        # tasks that only serve as a grouping of dependencies.
        [Parameter(Mandatory, Position = 1)]
        [AllowNull()]
        [ScriptBlock]$Action,

        # A brief description of the task.
        [string]$Description,

        # An array of task names that this task depends on. These tasks will be executed
        # before this task unless -SkipDependencies is specified when invoking.
        [string[]]$DependsOn = @(),

        # An array of allowed exit codes for the task. If the task completes with an
        # exit code that is not in this array, it will be considered a failure. Pass an
        # empty array to ignore the exit code. Defaults to 0.
        [int[]]$AllowedExitCodes = @(0)
    )
    & $PSScriptRoot/syncCallerPreferences.ps1 $MyInvocation -PreferencesToSync ErrorAction, InformationAction
    addTask @PSBoundParameters
}

function Get-TaskFrameworkTasks {
    <#
    .DESCRIPTION
        Gets all tasks defined in the task framework in dependency order. The returned
        objects are of type TaskDefinition, which has the following properties:
            - Name: The name of the task.
            - Description: A brief description of the task.
            - DependsOn: An array of task names that this task depends on.
            - Action: The script block to execute when the task is invoked.

        This can be useful for listing available tasks or for debugging task definitions.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessage('PSUseSingularNouns', '', Justification = 'Tasks is plural because it manages multiple tasks.')]
    [CmdletBinding()]
    param()
    return [TaskDefinition]::GetOrderedTasks().Values
}

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
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
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

        The function will import the specified scripts and variables into the scope
        of the invoked task, allowing them to be used in the task action. Mutable variables,
        such as HashTables or lists, can be used to share state across tasks, but be cautious
        of potential side effects.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingInvokeExpression', '', Justification = 'Using Invoke-Expression is necessary to allow task actions to accept named arguments.')]
    param(
        [TaskDefinition]$Task,
        [object[]]$TaskArgs,
        [hashtable]$Variables,
        [string[]]$ImportScripts
    )

    if ($null -eq $Task.Action) {
        Write-Verbose "Skipping task '$($Task.Name)' since it has no action."
        return
    }

    Import-Module PSArgs -Verbose:$false
    Import-Module Secrets -Verbose:$false
    Import-Module BuildHelpers -Verbose:$false

    $ImportScripts.foreach{
        Write-Verbose "Importing script '$_'."
        if ($_ -like '*.ps1') {
            . $_
        }
        else {
            Import-Module $_ -Verbose:$false
        }
    }

    $Variables.Keys.foreach{
        Write-Verbose "Importing variable '$_' with value $(ConvertTo-PSString $Variables[$_] -UseQuotes)."
        Set-Variable -Name $_ -Value $Variables[$_] -Force -ea Ignore
    }

    $TaskName = $Task.Name

    $private:_taskCommandArgs = ConvertTo-CommandArg $TaskArgs
    if ($_taskCommandArgs) {
        Write-Verbose "Invoking task '$TaskName' with arguments: $_taskCommandArgs"
    }
    else {
        Write-Verbose "Invoking task '$TaskName' with no arguments."
    }

    $global:LASTEXITCODE = 0

    try {
        # Use Invoke-Expression to invoke the script block with arguments. This enables
        # $TaskArgs to contain named parameters (i.e. '-foo','bar') not just positional
        # parameters ('bar').
        Invoke-Expression -Command "&{`n$($Task.Action)`n} $_taskCommandArgs"
    }
    catch {
        # Since we used Invoke-Expression to execute the task's action, the stack trace will
        # not contain the action's actual filename and line number. Let's fixup the stack
        # trace to include the task action's filename and line number...
        Repair-TaskStackTrace -ErrorRecord $_ -Task $Task -TaskActionStartLine 2
        throw $_
    }

    if ($Task.AllowedExitCodes.Count -gt 0 -and $global:LASTEXITCODE -notin $Task.AllowedExitCodes) {
        Write-Verbose "Task '$TaskName' failed with exit code $global:LASTEXITCODE."
        throw "Task '$TaskName' failed with exit code $global:LASTEXITCODE."
    }
    Write-Verbose "Completed task '$TaskName' with exit code $global:LASTEXITCODE."
    $global:LASTEXITCODE = 0 # reset to avoid affecting the final exit code
}

function Add-TaskFrameworkDefaultTasks {
    <#
    .DESCRIPTION
        Adds default tasks to the task framework, such as 'list' and 'help'.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessage('PSUseSingularNouns', '')]
    [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingEmptyCatchBlock', '')]
    param(
        # The tasks to include.
        [ValidateSet('help', 'list')]
        [string[]] $Include = @('help', 'list'),

        # A hashtable specifying custom names for the default tasks.
        [hashtable] $NameMap = @{}
    )
    & $PSScriptRoot/syncCallerPreferences.ps1 $MyInvocation -PreferencesToSync WarningAction, Verbose

    switch ($Include.where{ ![TaskDefinition]::TryGetTask($_) }) {
        'null' {
            $name = $NameMap[$_] ?? $_
            Write-Verbose "Including default 'null' task as '$name'."
            addTask $name -Description 'An empty task that does nothing.'
        }
        'list' {
            $name = $NameMap[$_] ?? $_
            Write-Verbose "Including default 'list' task as '$name'."
            addTask $name -Description 'List all defined tasks' {
                <#
                .DESCRIPTION
                    Lists all tasks defined in the task framework along with their descriptions
                    and dependencies.
                #>
                Get-TaskFrameworkTasks |
                Format-Table Name, Description, DependsOn -AutoSize |
                Out-Host
            }
        }
        'help' {
            $name = $NameMap[$_] ?? $_
            Write-Verbose "Including default 'help' task as '$name'."
            addTask $name -Description 'Show detailed help for a task' {
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
                    [switch]$Examples
                )

                $getHelpArgs = @{} + $PSBoundParameters
                $getHelpArgs.Remove('TaskName') | Out-Null

                $getTaskHelpArgs = @{
                    GetHelpArgs     = $getHelpArgs
                    HelpTaskName    = $Task.Name # this task's name
                    BuildScriptPath = $BuildInvocation.MyCommand.Path ?? './build.ps1'
                    TaskNameArgName = $TaskNameArgName ?? 'TaskName'
                    TaskArgsArgName = $TaskArgsArgName ?? 'TaskArgs'
                }
                if ($TaskName) {
                    $getTaskHelpArgs.TaskName = $TaskName
                }

                Get-TaskFrameworkHelp @getTaskHelpArgs | Out-Host
            }
        }
        default {
            Write-Warning "Unknown default task requested: '$_'."
        }
    }
}

function Get-TaskFrameworkHelp {
    <#
    .DESCRIPTION
        Generates help for a task defined in the task framework. If a task name is not
        specified, it generates help for the build script itself.

        The help output is generated by merging the help info from the build script and the
        task action. This allows the task help to include information about the build script's
        parameters and syntax, which is relevant when invoking the task via the build script.
    .OUTPUTS
        [System.String]
        The formatted help string.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingInvokeExpression', '', Justification = 'Necessary for dynamic function creation.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # The name of the task to show help for. If not specified, shows help for the build script itself.
        [string]$TaskName,

        # The arguments to pass to Get-Help when retrieving help info for the build script and task action.
        [hashtable]$GetHelpArgs = @{},

        # The name of the Help task. Defaults to 'help'.
        [string]$HelpTaskName = 'help',

        # The path to the build script. This is used to get the help info for
        # the build script so that we can merge it with the task help.
        # Defaults to './build.ps1'.
        [string]$BuildScriptPath = './build.ps1',
        # The name of the parameter used to specify the task name when invoking the build script.
        [string]$TaskNameArgName = 'TaskName',
        # The name of the parameter used to specify task arguments when invoking the build script.
        [string]$TaskArgsArgName = 'TaskArgs'
    )
    & $PSScriptRoot/syncCallerPreferences.ps1 $MyInvocation

    $null = $TaskArgsArgName # avoid "unused parameter" warning

    # Get the help info for the build script. We will merge it's parameters and syntax
    # with the task help info to produce the final help output.
    $buildHelp = Get-Help -Name $BuildScriptPath @GetHelpArgs
    if (!$buildHelp) { return }

    function normalizeText([string]$text) {
        # trim and normalize line endings to CR to simplify regexes
        $text = $text -creplace '\s*?\r?\n', "`n"
        return $text
    }
    function finalizeText([string]$text) {
        # Assumes CR line endings.
        # remove empty section
        $text = $text -creplace '(?m)^(SYNOPSIS|DESCRIPTION|INPUTS|OUTPUTS|RELATED LINKS)\n\n+', ''
        # collapse consecutive empty lines
        $text = $text -creplace '\n\n\n+', "`n`n"
        # trim trailing empty lines to at most 1
        $text = $text -creplace '\n\n$', "`n"
        # convert to the environment's newline
        $text = $text -creplace '\r?\n', [Environment]::NewLine
        return $text
    }

    # If no task name specified, show the build script help
    if (!$TaskName) {
        $text = normalizeText ($buildHelp | Out-String)
        return finalizeText $text
    }

    # Get the specified task...
    $task = [TaskDefinition]::TryGetTask($TaskName)
    if (-not $task) {
        throw "Task '$TaskName' not found."
    }

    $TaskName = $task.Name # use the canonical name
    $taskDescription = $task.Description
    if ($taskDescription) {
        # ensure ends with a period
        $taskDescription = $taskDescription -replace '\.\s*$', '.'
    }
    $taskAction = $task.Action ?? ([scriptblock]::Create("
        <#
        .DESCRIPTION
            This is a `"meta-task`" that only serves as a grouping of dependencies.
            No additional help is available for this task.
        #>
        param()"))

    # Use the taskAction to generate a temporary function that we can call Get-Help on to generate the
    # help info. We use a unique name to aid in regex replacements later.
    $functionName = "_$([Guid]::NewGuid().ToString('N'))"
    $tempModule = New-Module -ScriptBlock ([scriptblock]::Create("function $functionName {$taskAction}"))
    $taskHelp = Get-Help $functionName @GetHelpArgs
    $tempModule | Remove-Module

    # Fixup the help object...
    function mamlParaTextItem($text) {
        return [PSObject]@{ Text = $text; type = 'text' } |
        Add-Member -TypeName 'MamlParaTextItem' -PassThru
    }
    function mamlParaText([string[]]$text) {
        # must return an array of ParaTextItem
        return , $text.ForEach{ mamlParaTextItem $_ }
    }

    # remove the ModuleName member
    if ($taskHelp.ModuleName) {
        $null = $taskHelp.PSObject.Members.Remove('ModuleName')
    }

    # fix the name
    $taskHelp.details | Add-Member 'name' $TaskName -Force
    $taskHelp | Add-Member 'Name' $TaskName -Force

    # set Synopsis using the task description, if missing
    if ($taskDescription) {
        if (!$taskHelp.details.description) {
            $taskHelp.details | Add-Member 'description' (mamlParaText $taskDescription) -Force
        }
        if (!$taskHelp.Synopsis) {
            $taskHelp | Add-Member 'Synopsis' $taskDescription -Force
        }
    }

    # merge the build script's parameters and syntax into the task's help...
    $taskCommonParameters = $task.Action -and ($taskHelp.CommonParameters ?? $true)
    $buildCommonParameters = $task.Action -and ($buildHelp.CommonParameters ?? $true)

    $dashSwitch = [PSObject]@{
        name          = '-'
        description   = mamlParaText 'A meta-parameter used to separate build script parameters from task parameters.'
        required      = $false
        globbing      = $false
        pipelineInput = $false
        position      = 'named'
    } | Add-Member -TypeName 'MamlCommandHelpInfo#parameter' -PassThru

    # Update the description of the 'TaskName' parameter to indicate the value it should have to invoke the task.
    foreach ($param in $buildHelp.parameters.parameter) {
        if ($param.name -eq $TaskNameArgName) {
            $param.description = mamlParaText "The name of the task to execute. '$TaskName' in this case."
            break
        }
    }

    # Merge parameters:
    # We omit the build script's 'TaskArgs' parameters since the actual task args are already included.
    if ($null -eq $taskHelp.parameters) {
        $taskHelp | Add-Member 'parameters' ([PSCustomObject]@{ parameter = @() } | Add-Member -TypeName 'ExtendedCmdletHelpInfo#parameters' -PassThru) -Force
    }
    if ($null -eq $taskHelp.parameters.parameter) {
        $taskHelp.parameters | Add-Member 'parameter' @() -Force
    }
    $taskHelp.parameters.parameter = @(
        $buildHelp.parameters.parameter.where{ $_.name -ne $TaskArgsArgName }
        if ($taskHelp.parameters.parameter.Count -or $taskCommonParameters) { $dashSwitch }
        $taskHelp.parameters.parameter
    )

    # Merge Syntax:
    # We omit the 'TaskName' parameter itself since the task name is fixed in this context.
    # We only include those build script syntax items that include the 'TaskName' parameter
    # since those are the ones relevant to invoking tasks.
    $buildSyntaxItems = $buildHelp.syntax.syntaxItem.where{ $_.parameter.name -eq $TaskNameArgName }

    if ($null -eq $taskHelp.syntax) {
        $taskHelp | Add-Member 'syntax' ([PSCustomObject]@{ syntaxItem = @() }) -Force
    }
    if ($null -eq $taskHelp.syntax.syntaxItem) {
        $taskHelp.syntax | Add-Member 'syntaxItem' @() -Force
    }
    if ($taskHelp.syntax.syntaxItem.Count -eq 0) {
        # add a default syntaxItem so that we have somewhere to merge the build script syntax into
        $taskHelp.syntax.syntaxItem += [PSCustomObject]@{
            name      = $functionName
            parameter = @()
        } | Add-Member -TypeName 'MamlCommandHelpInfo#syntaxItem' -PassThru
    }
    $taskHelp.syntax.syntaxItem = @(
        foreach ($buildSyntaxItem in $buildSyntaxItems) {
            $buildParams = $buildSyntaxItem.parameter.where{ $_.name -notin $TaskNameArgName, $TaskArgsArgName }
            foreach ($item in $taskHelp.syntax.syntaxItem) {
                $copy = $item.PSObject.Copy() # shallow copy
                $copy.name = "$BuildScriptPath [-$TaskNameArgName] $TaskName"
                $copy | Add-Member 'parameter' @(
                    $buildParams
                    if ($item.parameter.Count -or $taskCommonParameters) { $dashSwitch }
                    $item.parameter
                ) -Force
                $copy
            }
        }
    )

    # The remaining fixups are done via text manipulation on the help output.
    $text = normalizeText ($taskHelp | Out-String)
    function escapeRegex([string]$s) { return [regex]::Escape($s) }
    function escapeReplacement([string]$s) { return $s.Replace('$', '$$') }

    # change NAME heading to TASK NAME
    $text = $text -creplace '(?m)^NAME$', 'TASK NAME'
    # replace the temp function name with the build script help invocation.
    $text = $text -creplace $functionName, (escapeReplacement "$BuildScriptPath $TaskName")

    # Insert 'DEPENDS ON' section before RELATED LINKS or REMARKS
    if ($text -match '(?m)^(RELATED LINKS|REMARKS)$') {
        $insertBefore = $Matches[1]
        $dependsOnText = @(
            if ($task.DependsOn) {
                'This task depends on the following tasks:'
                $task.DependsOn.foreach{ "- $_" }
            }
            else {
                'This task has no task dependencies.'
            }
        )
        $dependsOnText = "DEPENDS ON`n    $($dependsOnText -join "`n    ")"
        $text = $text -creplace "(?m)^$insertBefore`$", "$(escapeReplacement $dependsOnText)`n`n`$0"
    }

    if ($buildCommonParameters) {
        # Insert build script's "[<CommonParameters>]" before the '--' separator
        $text = $text -creplace "($(escapeRegex $BuildScriptPath) .*?)(\[--])", '$1[<CommonParameters>] $2'
    }
    if ($taskCommonParameters) {
        # Rename the task's [<CommonParameters>] (the one after the '--') to avoid confusion with the
        # build script's common parameters
        $text = $text -creplace "($(escapeRegex $BuildScriptPath) .*? \[--] .*?)\[\<CommonParameters\>\]", '$1[<TaskCommonParameters>]'
    }

    # fixup the additional help remarks
    $text = $text -creplace "Get-Help $(escapeRegex $TaskName) ", "$(escapeReplacement "$BuildScriptPath $HelpTaskName $TaskName") -- "

    return finalizeText $text
}

function Invoke-TaskFramework {
    <#
    .DESCRIPTION
        Invokes one or more tasks defined in the task framework.

        Tasks will be executed in the order they were defined. If a task has dependencies,
        those will be executed first unless $SkipDependencies is specified.

        The function will import the specified scripts and variables into the scope
        of each invoked task, allowing them to be used in task actions. Mutable variables,
        such as HashTables or lists, can be used to share state across tasks, but be cautious
        of potential side effects.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    param(
        # The working directory in which to invoke the task(s).
        [Parameter(Mandatory)]
        [string]$WorkingDirectory,

        # The name(s) of the task(s) to invoke.
        [Parameter(Mandatory)]
        [string[]]$TaskName,

        # Task-specific arguments. Can only be used when invoking a _single_ task.
        [object[]]$TaskArgs = @(),

        # Indicates whether to skip invoking dependencies of specified tasks. Defaults to $false.
        [switch]$SkipDependencies,

        # A list of scripts to import into the scope of invoked tasks. This can be used to share
        # helper functions across tasks.
        [string[]]$ImportScripts = @(),

        # A hashtable of variables to import into the scope of invoked tasks. This can be used to
        # pass configuration or state to tasks.
        [hashtable]$Variables = @{},

        # Indicates that the function should exit the script if a failure occurs. If not specified,
        # the function will throw an exception failure.
        [switch]$ExitOnError
    )
    & $PSScriptRoot/syncCallerPreferences.ps1 $MyInvocation
    $ErrorActionPreference = 'Stop'

    $private:_orig = @{
        PSModulePath = $env:PSModulePath
        Location     = Get-Location
    }

    Write-Verbose "Working directory: '$WorkingDirectory'."
    Set-Location $WorkingDirectory
    try {
        if ($TaskArgs.Count -gt 0 -and $TaskName.Count -gt 1) {
            throw 'Task arguments cannot be used when invoking multiple tasks.'
        }

        $TasksToExecute = [TaskDefinition]::GetOrderedTasks($TaskName, !$SkipDependencies)

        # Add the scripts directory to the module path so that task actions
        # can more easily import helper modules if needed.
        $pathSeparator = $IsWindows ? ';' : ':'
        $env:PSModulePath = "$PSScriptRoot$pathSeparator$env:PSModulePath"

        $private:targs = @{
            Task          = $null
            TaskArgs      = @()
            ImportScripts = $ImportScripts
            Variables     = $Variables
        }

        Write-Verbose "Executing tasks: $($TasksToExecute.Name -join ', ')"

        foreach ($task in $TasksToExecute) {
            $targs.Task = $task
            $targs.TaskArgs = $task.Name -eq $TaskName ? $TaskArgs : @()
            Invoke-Task @targs
        }

        Write-Verbose "Done executing tasks."
    }
    catch {
        if ($global:LASTEXITCODE -eq 0) { $global:LASTEXITCODE = -1 }
        Write-Verbose "Error: $_`n$(($_ | Format-List -Force | Out-String).Trim())"
        if ($ExitOnError) {
            # Output a user-friendly error message with a stack trace
            Write-Host "Error: $_`n$($_.Exception.GetType().FullName)`n$($_.ScriptStackTrace)" -ForegroundColor Red
            Write-Verbose "Exiting with code $global:LASTEXITCODE."
            exit $global:LASTEXITCODE
        }
        throw
    }
    finally {
        $env:PSModulePath = $_orig.PSModulePath
        Set-Location $_orig.Location
    }
}

# reset the task framework state when the module is [force] imported to ensure a clean slate
Reset-TaskFramework

# !Important! Remember to update the module manifest (.psd1) when adding or removing exports.
$exportModuleMemberParams = @{
    Function = @(
        'Reset-TaskFramework'
        'Task'
        'Get-TaskFrameworkTasks'
        'Invoke-TaskFramework'
        'Get-TaskFrameworkHelp'
        'Add-TaskFrameworkDefaultTasks'
    )
}

Export-ModuleMember @exportModuleMemberParams
