<!-- spell:ignore hashtable -->

# PSTaskFramework

[![pr_validation](https://github.com/mrfootoyou/PSTaskFramework/actions/workflows/pr-validation.yml/badge.svg)](https://github.com/mrfootoyou/PSTaskFramework/actions/workflows/pr-validation.yml)
[![codecov](https://codecov.io/gh/mrfootoyou/PSTaskFramework/graph/badge.svg?token=DROsxp0TrB)](https://codecov.io/gh/mrfootoyou/PSTaskFramework)

PSTaskFramework is a fast, lightweight, easy-to-use **task automation tool** built on **modern
PowerShell**. It is **cross-platform** by design and intended to work anywhere PowerShell 7+ is
supported (Windows, Linux, and macOS).

Use PSTaskFramework when you want:

- To replace tedious README instructions with easy-to-remember executable tasks (ex:
  `./build.ps1 updateTools,updatePackages`).
- A simple way to bootstrap your local development environment with a single command
  (`./build.ps1 bootstrap`).
- A single entrypoint for local dev tasks and CI tasks (ex:
  `./build.ps1 build,test,publish -config Release`).
- A task automation tool that runs the same way on Windows, Linux, and macOS.
- Small vendored scripts you can keep in-repo and customize directly (no external dependencies).
- PowerShell-native task definitions with task-specific parameters and comment-based help.

## Getting Started

This repository is designed as a starter kit: simply copy the contents of the `src` folder into your
repository and commit everything. Some example `build.ps1` scripts are included to get you up and
running quickly.

### Requirements

- PowerShell 7.4 or newer.
- A modern OS supported by PowerShell (Windows, Linux, macOS).

Install PowerShell: [https://aka.ms/install-powershell](https://aka.ms/install-powershell)

### Copy the Framework into Your Repo

Copy everything from the [`src`](src/) folder into the **root** of your repository. You may omit the
test files.

Your repo structure should look something like this:

```text
<repo-root>/
├── build.ps1  <== the entrypoint
└── scripts/
    └── PSTaskFramework/  <== the framework
        ├── ...
        └── <test files can be omitted>
```

> **NOTE:** The `PSTaskFramework` folder can be located elsewhere if desired, just update the
> `build.ps1` file's `$ScriptsDir` variable to point to the new location.

### Execute Tasks

From your repo root (or the folder containing the `build.ps1` file), run the following commands to
get a feel for how to interact with the framework. More details are available in the
[Core Concepts](#core-concepts) section below.

```powershell
# List available tasks
./build.ps1 list

# Show help for a specific task (including the 'help' task itself)
./build.ps1 help <taskName>

# Install required development tools
./build.ps1 bootstrap

# Clean repository (interactive)
./build.ps1 clean
```

## Core Concepts

It should come as no surprise that **tasks** are the core unit of work in the PSTaskFramework.
Understanding how to define and execute them is key to using the framework effectively. This section
covers the basics of task execution, and how to define tasks.

### Task Execution Basics

In the simplest case, you can just run `./build.ps1 <taskName>` to execute a task and its
dependencies. You can skip dependencies with the `-noDeps` (or `-SkipDependencies`) switch:
`./build.ps1 <taskName> -noDeps`.

You can execute multiple tasks by providing multiple task names separated by commas, e.g.,
`./build.ps1 taskA,taskB,taskC`. The framework will execute all the tasks (and their dependencies)
in dependency order. If two tasks have no dependencies, they will be executed in the order in which
they were defined in the build script. You can also use `-noDeps` to skip dependencies tasks.

> **Tip:** Use `./build.ps1 list` to get a list of all available tasks.

You can pass task-specific arguments using standard PowerShell syntax, with a couple caveats:

1. Task-specific arguments can only be used when invoking a _single task_. The arguments are only
   passed to that specific task, not to its dependencies.
2. To disambiguate build script arguments from task-specific arguments, place a double-dash `--`
   before the task-specific arguments. Any arguments after the double-dash will be passed to the
   task without the build script attempting to interpret them.

   For example: `./build.ps1 myTask -v -- -v 2.0.0`.

   Without the `--`, PowerShell would interpret the second `-v` as a duplicate `-Verbose` argument
   instead of a task-specific argument.

   > **Tip:** While the use of `--` is a best-practice in production quality scripts, it is only
   > _required_ when the task-specific arguments can be confused with build script arguments. If
   > there is no ambiguity, you can omit it.

> **Tip:** Display the help documentation for a task using `./build.ps1 help <taskName>`. This will
> show the task's description, syntax, and dependencies. Use `./build.ps1 help help -full` for more
> information on the help task.

### Defining Tasks

Tasks are basically glorified PowerShell functions - they have a name, an executable script block,
optional parameters, and inline-documentation. Tasks can also declare dependencies on other tasks.

Tasks are created and registered with the `Task` command:

```text
Task <taskName> [-Description <description>] [-DependsOn <dependency1,dependency2,...>] [-AllowedExitCodes <code1,code2,...>] [-Action] {
    # Task implementation goes here
}
```

The following example defines two tasks: `restore` and `build`. The `build` task has a dependency on
`restore` and accepts an optional task-specific `Version` parameter:

```powershell
Task restore -desc 'Restores packages' {
    <#
    .DESCRIPTION
        Restores package dependencies using...
    #>
    # TODO: Implement restore logic
}

Task build -desc 'Builds the solution' -dependsOn restore {
    <#
    .DESCRIPTION
        Builds the solution using...
    #>
    param(
        # The version number of the build. Defaults to 1.0.0.
        [string]$Version = '1.0.0'
    )
    # TODO: Implement build logic
}
```

The `build` task can be invoked using `./build.ps1 build`. The PSTaskFramework will execute both the
`restore` and `build` tasks, in that order. You can specify the Version argument using
`./build.ps1 build -- -Version 2.0.0`.

**Notes:**

- Every task must have a **unique** name.
  - Task names are _not_ case-sensitive: `build` and `Build` refer to the same task and can be used
    interchangeably.
- Tasks should have a short, one sentence description (`-desc`) explaining their purpose. This is
  displayed in the task listing and in the help output.
- Tasks may depend on zero or more other tasks (`-dependsOn`), in which case the framework ensures
  dependencies execute first.
- Task actions are standard PowerShell script blocks.
  - Use a `param(...)` block to define and document task-specific parameters.
  - Use comment-based help (`<#...#>`) block to document the task. This will be displayed in the
    help output.
- Public tasks should be added to the `TaskName` parameter's list of valid values (toward the top of
  the file).

### Task Scope

Tasks execute in a _child scope_ of the script they are defined in (e.g. `build.ps1`). This means
they have access to all script-scoped variables and functions, in addition to all global-scope
variables and functions.

Since the tasks are running in a child scope, they cannot **assign** a new value to script-scoped
variables unless they use the `$script:` scope modifier, for example `$script:MyVariable = 123`.
Without the `$script:` modifier, a new variable named `MyVariable` would be created in the task's
local scope, leaving the script-scoped variable unchanged. Use the `$global:` scope modifier for
global-scoped variables.

Note that while tasks cannot **assign** new values to script-scoped variables without the `$script:`
modifier, they can modify the **properties/elements** of those variables. For example, if there is a
script-scoped variable `$MyConfig` that is a hashtable, a task can modify its properties like this:
`$MyConfig.Setting1 = 'NewValue'`. This will update the `Setting1` property of the `$MyConfig`
hashtable in the script scope.

### Task Context

When you call `Initialize-TaskFramework`, it creates and returns a new TaskContext object that
contains all information about the current execution context, including all the registered tasks,
the currently executing task, the result of all executed tasks, and other information.

```powershell
$TaskContext = Initialize-TaskFramework
```

> IMPORTANT: The TaskContext data should be stored in a variable named `$TaskContext`. If this isn't
> possible for some reason, then you have two options:
>
> 1. Explicitly pass the TaskContext to every PSTaskFramework function call (e.g.
>    `Task foo -TaskContext $MyTaskContext {...}`,
>    `Invoke-TaskFramework -TaskContext $MyTaskContext ...`, etc).
> 2. Tell the PSTaskFramework the name of the replacement variable when initializing the framework.
>    For example,
>    `$MyTaskContext = Initialize-TaskFramework -TaskContextVariableName 'MyTaskContext'`.

**TaskContext Properties:**

- `State` [hashtable]: A place where tasks can store arbitrary data. This can be useful for sharing
  data between tasks without using global/script variables (although those usually work great too).

- `BuildScriptPath` [FileInfo]: Information about the current build script (e.g. `build.ps1`). This
  defaults to the script file which called `Initialize-TaskFramework`.

- `AllTasks` [OrderedDictionary[string, TaskDefinition]]: An ordered dictionary of all registered
  task definitions (name, description, dependencies, script block, etc), keyed by task name. The
  `Task` command simply adds a new TaskDefinition to this dictionary.
- `AllTasksSorted` [bool]: Indicates whether `AllTasks` are sorted in dependency order (`$true`) or
  registration order (`$false`). Call `Get-TaskFrameworkTasks` to sort them in dependency order.
  They will be in dependency order while tasks are executing.

- `WorkingDirectory` [DirectoryInfo]: The directory where all tasks are executed. Defaults to the
  build script's folder, which is usually the repository root.
- `TasksToExecute` [string[]]: A list of the tasks that will be executed in the current run, in
  execution order.
- `SkipDependencies` [bool]: Whether dependencies are being skipped in the current run.
- `Start` [datetime]: The time the current run started.
- `Duration` [timespan]: The duration of the current run.
- `ExitCode` [int]: The exit code of the current run.
- `Error` [ErrorRecord]: The exception that ended the current run (if any).

- `CurrentTask` [TaskDefinition]: The task definition of the currently executing task.
- `Results` [OrderedDictionary[string, TaskResult]]: An ordered dictionary containing the result of
  each executed task, keyed by task name. Each `TaskResult` contains the following properties:
  - `TaskArgs` [TaskArgs]: The arguments passed to the task when it was invoked.
    - `Raw` [object[]]: The raw list of arguments passed to the task.
    - `Bound` [IDictionary[string, object]]: The parameter names and argument values that were
      successfully bound to the task's parameters.
    - `Unbound` [object[]]: The list of arguments that were not bound to specific parameters (the
      task's `$args`).
  - `Start` [datetime]: The time the task started.
  - `Duration` [timespan]: The duration of the task.
  - `ExitCode` [int]: The task's exit code.
  - `Error` [ErrorRecord]: The exception that occurred while executing the task (if any).

> **Warning:** Do not manually modify TaskContext properties (other than `State`).

### Helper Functions

The PSTaskFramework includes several useful functions to help in writing your tasks. These are
located in submodules within the `PSTaskFramework` folder (see below for details).

Within the body of a _task_, you can load these submodules using only the module's name. For
example, `Import-Module InstallHelpers` will load the `PSTaskFramework/InstallHelpers` module.
Outside of a task, you must specify the full path to the module folder, e.g.
`Import-Module $ScriptsDir/PSTaskFramework/InstallHelpers`.

**`PSTaskFramework/BuildHelpers`** (automatically imported):

- `Invoke-Shell`: Invokes a shell application with arguments. Echoes the full command to the console
  (suppress with `-InformationAction Ignore`). Reports an error if the command exits with a non-zero
  exit code (configurable via `-ErrorAction` and `-AllowedExitCodes`).
- `Assert-AppExists`: Checks if a specified application exists on `PATH`. Returns the full path if
  the `-PassThru` switch is used.
- `Test-Administrator`: Returns `$true` if the current user has administrator (Windows) or root
  (Linux/macOS) privileges.

**`PSTaskFramework/Secrets`** (automatically imported):

- `Push-Secret` / `Pop-Secret`: Register and unregister secret values (reference-counted) to be
  masked from output.
- `Protect-Secret`: Replaces all registered secrets in a string with a masked value (default
  `****`).
- `Read-Secret`: Reads a secret interactively without echoing it to the console. CI-aware: returns
  an empty string (or errors) when running non-interactively.

**`PSTaskFramework/InstallHelpers`**:

- `Install-RequiredApp`: Installs applications using the best available package manager (winget,
  Chocolatey, apt, dnf, Homebrew) or a custom script block. Accepts a dictionary mapping app names
  to installation metadata.
- `Get-WellKnownAppInfo`: Returns the built-in installation metadata for a named well-known
  application (supports wildcards).
- `Get-PackageManager`: Detects which supported package managers are currently installed on the
  system.
- `Install-PackageManager`: Installs a supported package manager (winget, Chocolatey, Homebrew,
  etc.) if not already present.
- `Install-PowerShellModule`: Ensures the specified PowerShell modules are installed at a minimum
  version, installing from the PowerShell Gallery if needed.

**`PSTaskFramework/PSArgs`** (automatically imported):

- `ConvertTo-PSString`: Converts a value (string, bool, int, hashtable, collection, etc.) to a valid
  PowerShell literal string representation.
- `ConvertTo-CommandArg`: Converts a value to a command-line argument string, suitable for passing
  to external applications (e.g. splatting a hashtable as `-Name:Value` pairs).

## Pitfalls and Troubleshooting

### Avoid positional script parameters

**Symptom:** You have defined positional parameters in your build script and now the script is
eagerly binding to your task-specific arguments, resulting in excessive use of `--` argument
separator.

**Cause:** Positional parameters in the build script can cause PowerShell to bind task-specific
arguments to the scripts positional parameters.

**Cure:** Avoid defining positional parameters in your build script. Use
`[CmdletBinding(PositionalBinding = $false)]` to disable positional binding. The `TaskName`
parameter should be the only positional parameter `[Parameter(Position = 0)]`.

### Script variable modification not persisting across tasks

**Symptom:** You have a script-scoped variable that you are trying to modify in a task, but the
modification does not persist after the task finishes.

**Cause:** Tasks execute in a child scope of the script, so they cannot assign new values to
script-scoped variables without using the `$script:` scope modifier.

**Cure:** Use the `$script:` scope modifier when assigning a new value to a script-scoped variable
within a task. For example, `$script:MyVariable = 123`. This will ensure the assignment modifies the
variable in the script scope rather than creating a new/temporary variable in the task's local
scope.

### Task arguments fail when running multiple tasks

**Symptom:** You pass task-specific arguments and multiple task names (or zero) in the same command.

**Cause:** Task-specific arguments are only supported for explicit single-task invocations.

**Cure:** Run one task at a time. Use `-NoDeps` to skip dependencies when necessary.

### Task or dependency not found

**Symptom:** Runtime error indicates a missing task or missing dependency.

**Cause:** A task in `-TaskName` or `-DependsOn` does not exist.

**Cure:** Run `./build.ps1 list` to get the list of available tasks.

### Circular task dependency detected

**Symptom:** Framework reports a circular task dependency.

**Cause:** Two or more tasks depend on each other directly or indirectly.

**Cure:** Break the cycle by extracting a shared prerequisite task that both depend on.

### Unexpected failure from external command

**Symptom:** Task fails even when the command output looks acceptable.

**Cause:** Task completed with a non-zero exit code.

**Cure:**

- Use `Invoke-Shell` to run external commands. It is designed to handle this specific scenario.
- Update the task's `-AllowedExitCodes` parameter to include the expected exit code(s). Setting it
  to an empty array (`@()`) disables exit code checking.
- Alternatively, set `$global:LASTEXITCODE = 0` before exiting the task.

### Secret prompting issues in CI

**Symptom:** Task prompts for input or fails when running non-interactively.

**Cause:** CI environments are non-interactive; secret prompts are not reliable there.

**Cure:** Prefer to pass secrets via environment variables, especially in CI. Only prompt for a
secret value when the environment variable is missing. See the dotnet `push` task in the
[examples](examples/dotnet/build.ps1#L458).

## Contributing

To get started, run `./build.ps1 bootstrap` (yes, we eat our own dog food here). This will
install/update required tools, such as Pester and PSScriptAnalyzer.

Run `./build.ps1` to execute the tests and perform static analysis. Calculate code coverage using
`./build.ps1 test -coverage`. Use a tool like
[Coverage Gutters](https://marketplace.visualstudio.com/items?itemName=ryanluker.vscode-coverage-gutters)
to visualize code coverage in your editor.

If you want to understand or modify core behavior, these are the files to look at:

- [`src/scripts/PSTaskFramework/PSTaskFramework.psm1`](src/scripts/PSTaskFramework/PSTaskFramework.psm1)
  - Task registration
  - Dependency ordering
  - Default tasks
  - Core execution engine
- [`src/scripts/PSTaskFramework/BuildHelpers/BuildHelpers.psm1`](src/scripts/PSTaskFramework/BuildHelpers/BuildHelpers.psm1)
  - Helpers related to execution
- [`src/scripts/PSTaskFramework/PSArgs/PSArgs.psm1`](src/scripts/PSTaskFramework/PSArgs/PSArgs.psm1)
  - PowerShell argument conversion helpers
- [`src/scripts/PSTaskFramework/Secrets/Secrets.psm1`](src/scripts/PSTaskFramework/Secrets/Secrets.psm1)
  - CI-aware secret input
  - Secret masking
- [`src/scripts/PSTaskFramework/InstallHelpers/InstallHelpers.psm1`](src/scripts/PSTaskFramework/InstallHelpers/InstallHelpers.psm1)
  - Application installation helpers
  - PowerShell module installation helpers

## License

This project is licensed under the Unlicense. See [UNLICENSE.txt](UNLICENSE.txt) for details.
