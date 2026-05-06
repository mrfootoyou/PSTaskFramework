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
├─- build.ps1  <== the entrypoint
└─- scripts/
    └─- PSTaskFramework/  <== the framework
        ├─- ...
        └─- <test files can be omitted>
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
covers the basics of task execution, how to define tasks, how to share variables between tasks, and
how to import frequently used scripts.

### Task Execution Basics

In the simplest case, you can just run `./build.ps1 <taskName>` to execute a task and its
dependencies. You can skip dependencies with the `-noDeps` (or `-SkipDependencies`) switch:
`./build.ps1 <taskName> -noDeps`.

You can execute multiple tasks by providing multiple task names separated by commas, e.g.,
`./build.ps1 taskA, taskB, taskC`. The framework will execute the tasks in dependency order, or if
two tasks have no dependencies, in the order in which they were defined in the build script. You can
also use `-noDeps` to only execute the specified tasks.

You can pass arguments to tasks using standard PowerShell syntax, with a couple caveats:

1. Task arguments can only be used when invoking a _single task_. The arguments are only passed to
   that specific task, not to its dependencies.
2. To disambiguate framework arguments from task arguments, place a double-dash `--` before the
   task-specific arguments. Any arguments after the double-dash will be passed to the task without
   the framework attempting to interpret them.

   For example: `./build.ps1 myTask -v -- -v 2.0.0`.

   Without the `--`, PowerShell would interpret the second `-v` as a duplicate `-Verbose` argument
   instead of a task argument.

### Defining Tasks

Tasks are basically just named script blocks that can be invoked from the command line, similar to
functions. Like functions they can accept parameters and arguments. Unlike functions, however, they
can declare dependencies on other tasks.

Tasks are created and registered with the `Task` command:

```powershell
Task <taskName> [-desc <description>] [-dependsOn <dependency1,dependency2,...>] {
    # Task implementation goes here
}
```

The following example defines a `build` task that accepts an optional `Version` parameter. It
depends on the `restore` task:

```powershell
Task restore -desc 'Restores packages' -dependsOn version {
    <#
    .DESCRIPTION
        Restores package dependencies using...
    #>
    # TODO: Implement restore logic
}

Task build -desc 'Builds the solution' -DependsOn restore {
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

The `build` task can be invoked using `./build.ps1 build`. The PSTaskFramework will execute the
`version`, `restore`, and `build` tasks, in that order. You can specify the Version argument using
`./build.ps1 build -- -Version 2.0.0` or, in this example, `./build.ps1 build 2.0.0`.

**Notes:**

- Every task must have a **unique** name.
- Task names are _not_ case-sensitive: `build` and `Build` refer to the same task and can be used
  interchangeably.
- Public tasks should be added to the `TaskName` parameters list of valid values (toward the top of
  the build.ps1 file).
- Tasks should have a short, one sentence description (`-desc`) explaining their purpose. This is
  displayed in the task listing and in the help output.
- Tasks can depend on other tasks (`-DependsOn`), in which case the framework ensures dependencies
  execute first.
- Task bodies are script blocks that can contain any PowerShell code.
- Use `param(...)` within the task body to define and document task-specific parameters.
- Use comment-based help (`<#...#>`) above the task params to document the task. This will be
  displayed in the help output for that task.

### Understanding Shared Task Variables

Each task executes in an isolated scope. Tasks have access to all global and automatic PowerShell
variables, any declared parameters, and all variables declared in the script's `$Variables`
dictionary.

The `$Variables` dictionary is the intended mechanism for sharing state between tasks without
relying on global variables. The properties of the `$Variables` dictionary will be imported as
variables into each task prior to execution. This allows you to define common variables that are
shared across all tasks, such as the repository root, scripts directory, or any other values that
tasks may need, such as common input parameters like `$Configuration`.

Here is an example of defining common variables. In this example, `$Configuration` is an input
parameter for the ./build.ps1 script:

```powershell
$RepoRoot      = $PSScriptRoot
$ScriptsDir    = Convert-Path "$RepoRoot/scripts"

$Variables = @{
    RepoRoot        = $RepoRoot
    ScriptsDir      = $ScriptsDir
    BuildInvocation = $MyInvocation
    # Make the $Configuration parameter available
    # to all tasks
    Configuration   = $Configuration
    # Add more variables here as needed
}
```

Tasks can then reference these variables directly:

```powershell
Task example {
    Write-Host "Repo root is $RepoRoot"
    Write-Host "Scripts directory is $ScriptsDir"
    Write-Host "Configuration is $Configuration"
}
```

**Notes:**

- Each property of `$Variables` becomes a local variable in each task.
- Changes to variables with mutable state (e.g. collections and mutable objects) will be visible to
  subsequent tasks (so be careful).
- The following variables are always available:
  - `$Task`: Metadata about the currently executing task.
  - `$TaskName`: The name of the currently executing task (same as `$Task.Name`).
  - `$TaskArgs`: An array of the arguments passed to the currently executing task.
  - `$SkipDependencies`: Indicates if the task's dependencies were executed.
  - `$TasksToExecute`: The ordered list of all tasks being executed.
  - `$Variables`: The dictionary of variables to import into each task's scope.
- Since the `$Variables` dictionary is available to all tasks, tasks can use it to pass information
  to subsequent tasks.

  For example, a `getNextVersion` task might calculate the next version and store it in
  `$Variables.nextVersion`. A dependent task could then use that value:

  ```Powershell
  Task getNextVersion {
      # Determine next version (e.g. from git tags)
      $Variables.nextVersion = '1.2.3'
  }

  Task build -DependsOn getNextVersion {
      param(
          $Version = $nextVersion ?? '1.0.0'
      )
      Invoke-Shell -- dotnet build -c $Configuration -p:Version=$Version
  }
  ```

  > **Warning:** Be careful when using this pattern since it creates non-trivial coupling between
  > tasks and can result in unexpected behavior when dependencies are skipped.

### Import Frequently Used Scripts

Tasks are free to import any scripts or modules needed to accomplish their work. Sometimes we have
scripts that are used frequently by many tasks, resulting in lots of duplicate code. To avoid this,
the PSTaskFramework will automatically import any scripts listed in the `$ImportScripts` array prior
to task execution.

For example, if we have a `my-task-helpers.ps1` script we want to use in all/most tasks, then we can
add it to the `$ImportScripts` array like this:

```powershell
$ImportScripts = @(
    Convert-Path "$ScriptsDir\my-task-helpers.ps1"
    # Add more scripts here as needed
)
```

**Notes:**

- `.ps1` script files will be dot-sourced (`. <path_to_script>`) just before task execution.
- `.psm1`/`.psd1` module files will be imported using `Import-Module <path_to_module>` just before
  task execution.
- Tasks can load `PSTaskFramework` submodules using only the module's name. For example,
  `Import-Module InstallHelpers` will load the `PSTaskFramework/InstallHelpers` module.
- The following modules are automatically imported into all tasks and do not need to be explicitly
  imported:
  - `BuildHelpers` (functions like `Invoke-Shell`)
  - `Secrets` (secret input and masking)
  - `PSArgs` (argument parsing and conversion)

## Pitfalls and Troubleshooting

### Task arguments fail when running multiple tasks

**Symptom:** You pass task-specific arguments and multiple task names in the same command.

**Cause:** Task-specific arguments are only supported for single-task invocations.

**Cure:** Run one task at a time.

### Task or dependency not found

**Symptom:** Runtime error indicates a missing task or missing dependency.

**Cause:** A task in `-TaskName` or `-DependsOn` does not exist.

**Cure:** Run `./build.ps1 list` and confirm names match exactly.

### Circular task dependency detected

**Symptom:** Framework reports a circular task dependency.

**Cause:** Two or more tasks depend on each other directly or indirectly.

**Cure:** Break the cycle by extracting a shared prerequisite task that both depend on.

### Unexpected failure from external command

**Symptom:** Task fails even when the command output looks acceptable.

**Cause:** Task completed with an exit code not in the task's `AllowedExitCodes`.

**Cure:**

- Update the task's `-AllowedExitCodes` parameter to include the expected exit code(s). Setting it
  to an empty array (`@()`) disables exit code checking.
- Alternatively, set `$global:LASTEXITCODE = 0` before exiting the task.

### Task cannot access script variables

**Symptom:** Variable exists in `build.ps1` but is missing inside a task.

**Cause:** Tasks run in isolated scope and only receive variables imported through the `$Variables`
dictionary.

**Cure:** Add the value to the `$Variables` dictionary or set the value in the global scope, e.g.,
`$global:MyVariable = 123`.

### Secret prompting issues in CI

**Symptom:** Task prompts for input or fails when running non-interactively.

**Cause:** CI environments are non-interactive; secret prompts are not reliable there.

**Cure:**

Prefer to pass secrets via environment variables, especially in CI. Only prompt for a secret value
when the environment variable is missing.

## Contributing

To get started, run `./build.ps1 bootstrap` (yes, we eat our own dog food here). This will
install/update required tools, such as Pester and PSScriptAnalyzer.

Run `./build.ps1` to execute the tests and perform static analysis. Calculate code coverage using
`./build.ps1 test -coverage`.

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
