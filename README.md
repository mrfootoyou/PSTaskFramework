# PSTaskFramework

A fast, lightweight, easy-to-use **build automation tool** built on **modern PowerShell**. It is
**cross-platform** by design and intended to work anywhere PowerShell 7+ is supported (Windows,
Linux, and macOS).

This repository is designed as a starter kit: simply copy the contents of the `src` folder into your
repository root, then customize `build.ps1` to suit the needs of your project/repository. Examples
and documentation are included to get you up and running quickly.

## What This Is For

Use this when you want:

- A single entrypoint for local dev tasks and CI tasks.
- Replace long-winded README instructions with simple, repeatable, scripted tasks.
- A script that runs the same way on Windows, Linux, and macOS.
- Small vendored scripts you can keep in-repo and customize directly.
- PowerShell-native task definitions with standard `param()` support.

## Getting Started (Adopter Flow)

The intended adoption model is:

1. Copy everything from the `src` folder into the **root** of your repository.
2. Keep the `scripts` folder next to `build.ps1`.
3. Edit `build.ps1` and define tasks for your repo.
4. Execute tasks with `./build.ps1 <taskName(s)> -- <taskArgs>`.

Expected structure within your target repo:

```text
<repo-root>/
  build.ps1
  scripts/
    task-framework.psm1
    build-helpers.ps1
    psargs.psm1
    secrets.psm1
```

### Requirements

- PowerShell 7.4 or newer.
- A modern OS supported by PowerShell (Windows, Linux, macOS).

Install PowerShell: [https://aka.ms/install-powershell](https://aka.ms/install-powershell)

### Quickstart

The following commands will work immediately after copying the src files, even before you customize
any tasks. You can remove or edit these example tasks as needed.

From your repo root:

```powershell
# List available tasks
./build.ps1 list

# Install common prerequisites (template task)
./build.ps1 bootstrap

# Show environment and tool versions
./build.ps1 version

# Clean ignored build outputs
./build.ps1 clean
```

## Core Concepts

Most adopters will only need to interact with `build.ps1` to define tasks and variables. The main
things to understand when customizing `build.ps1` are:

1. Understanding tasks.
2. Understanding shared task variables.
3. Understanding how to import frequently used scripts.

### Understanding tasks

Tasks are the core unit of work in the framework. They are basically just named script blocks that
can be invoked from the command line, similar to functions. And like functions they can accept
parameters and arguments. Unlike functions, however, they can depend on other tasks.

Tasks are registered with the `Task` command (an alias for the `Add-TaskFrameworkTask` cmdlet).

The following example defines a `build` task that depends on a `restore` task and accepts a
`Version` parameter:

```powershell
Task build -desc 'Compile source' -DependsOn restore {
    <#
    .DESCRIPTION
    Compiles the solution using the given version (defaults to 1.0.0).
    #>
    param(
        [string]$Version = '1.0.0'
    )

    Invoke-Shell -- dotnet build --no-restore -p:Version=$Version
}
```

It can be invoked using `./build.ps1 build`, which will first execute the `restore` task, then the
`build` task. You can also pass a specific version with `./build.ps1 build -- -Version 2.0.0`:

```powershell
# use the default version
./build.ps1 build

# use a specific version:
./build.ps1 build -- -Version 2.0.0
```

Notes:

- Every task must have a **unique** name.
- Task names are _not_ case-sensitive: `build` and `Build` refer to the same task and can be used
  interchangeably.
- Public tasks should be added to the `$TaskName` parameter's set of valid values, toward the top of
  the build.ps1 file.
- Tasks should have a short description (`-desc`) to explain their purpose when listed.
- Tasks can depend on other tasks (`-DependsOn`), in which case the framework ensures dependencies
  execute first.
- Task bodies are script blocks that can contain any PowerShell code.
- Use `param(...)` to define task-specific parameters.

### Understanding shared task variables

Each task executes in an isolated scope. Tasks have access to all global and automatic PowerShell
variables, any declared parameters, and all variables declared in the script's `$Variables`
dictionary.

The `$Variables` dictionary is the intended mechanism for sharing state between tasks without
relying on global variables. The properties of the `$Variables` dictionary will be imported as
variables into each task prior to execution. This allows you to define common variables that are
shared across all tasks, such as the repository root, scripts directory, or any other values that
tasks may need, such as common input parameters like `$Configuration`.

Here is an example of defining common variables. In this example, `$Configuration` is a top-level
parameter of the ./build.ps1 script:

```powershell
$RepoRoot      = $PSScriptRoot
$ScriptsDir    = Join-Path $PSScriptRoot 'scripts'

$Variables = @{
    RepoRoot      = $RepoRoot
    ScriptsDir    = $ScriptsDir
    Configuration = $Configuration # <== Make the $Configuration parameter available to all tasks
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

Notes:

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

  For example, a `version` task could determine the version number and store it in
  `$Variables.Version`, and then a dependent `build` task could use that value when building:

  ```Powershell
  Task version {
      # Determine version number (e.g. from git tags)
      $Variables.Version = '1.2.3'
  }

  Task build -DependsOn version {
      $Version ??= '1.0.0' # default if version task was skipped
      Invoke-Shell -- dotnet build -c $Configuration -p:Version=$Version
  }
  ```

  Be careful when using this pattern, as it can create hidden coupling between tasks, resulting in
  unexpected behavior when dependencies are skipped.

### Define import scripts

Tasks are free to import any scripts or modules they need to accomplish their work. However
sometimes we have scripts that are used frequently by many tasks, resulting in lots of duplication.
To avoid this, any scripts listed in the `$ImportScripts` array will automatically be imported into
each task prior to execution.

```powershell
$ImportScripts = @(
    Join-Path $ScriptsDir 'build-helpers.ps1' # includes the Invoke-Shell function
    # Add more scripts here as needed
)
```

### Execute tasks

In the simplest case, you can just run `./build.ps1 <taskName>` to execute a task and its
dependencies. You can skip dependencies with the `-noDeps` switch: `./build.ps1 <taskName> -noDeps`.

You can also execute multiple tasks by providing multiple task names separated by commas:
`./build.ps1 taskA, taskB, taskC`. The framework will execute the tasks in dependency order, or if
two tasks have no dependencies, in the order in which they were defined in the build script. You can
also use `-noDeps` to only execute the specified tasks.

You can pass arguments to tasks with task-specific parameters using standard PowerShell syntax, with
a couple limitations:

1. Task arguments can only be passed when invoking a single task.
   - The arguments will only be passed to the named task, not its dependencies.
2. To disambiguate framework arguments from task arguments, use `--` before the task-specific
   arguments.

   For example: `./build.ps1 build -v -- -v 2.0.0`.

   Without the `--`, PowerShell would interpret the second `-v` as a duplicate `-Verbose` argument.
   With the `--`, anything after it is passed directly to the task.

## Pitfalls and Troubleshooting

### Task arguments fail when running multiple tasks

Symptom:

- You pass task args and multiple task names in the same command.

Cause:

- `TaskArgs` are only supported for single-task invocation.

Fix:

- Run one task at a time when using `--` arguments.

### Task or dependency not found

Symptom:

- Runtime error indicates a missing task or missing dependency.

Cause:

- A task name in `-TaskName` or `-DependsOn` does not exist.

Fix:

- Run `./build.ps1 list` and confirm names match exactly.

### Circular dependency detected

Symptom:

- Runtime error reports a circular dependency.

Cause:

- Two or more tasks depend on each other directly or indirectly.

Fix:

- Break the cycle by extracting a shared prerequisite task that both depend on.

### Unexpected failure from external command exit code

Symptom:

- Task fails even when the command output looks acceptable.

Cause:

- Non-zero exit code was returned and is not in `AllowedExitCodes`.

Fix:

- Keep command behavior strict by default.
- If non-zero is expected, set `-AllowedExitCodes` on that task.

### Task cannot see expected variables

Symptom:

- Variable exists in `build.ps1` but is missing inside a task.

Cause:

- Tasks run in isolated scope and only receive variables imported through `$Variables`.

Fix:

- Add the value to the `$Variables` dictionary.

### Secret prompting issues in CI

Symptom:

- Task prompts for input or fails when running non-interactively.

Cause:

- CI environments are non-interactive; secret prompts are not reliable there.

Fix:

- Pass secrets via environment variables in CI.
- Keep interactive secret prompts for local development only.

## Maintainer Pointers

If you need to adjust framework behavior (not just tasks), these are the key files:

- `src/scripts/task-framework.psm1`: task registration, dependency ordering, and execution engine.
- `src/scripts/build-helpers.ps1`: shell invocation and prerequisite helpers used by tasks.
- `src/scripts/psargs.psm1`: argument-to-command conversion helpers.
- `src/scripts/secrets.psm1`: secret masking and CI-aware secret input behavior.

For most adopters, you should not need to modify the framework modules at all.

## Documentation Roadmap

This README intentionally prioritizes adoption and day-to-day task authoring.

If the project needs deeper documentation later, split content into:

1. `docs/reference.md`: Parameter-level reference for exported task framework and helper functions.
2. `docs/patterns.md`: Task authoring patterns, argument passing conventions, dependency design, and
   CI practices.

Until then, detailed comment-based help in the scripts remains the source of truth for deep
internals.
