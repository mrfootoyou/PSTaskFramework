<#
.SYNOPSIS
    Part of the PSTaskFramework.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4

param()

function parseDotEnvLine {
    <#
    .DESCRIPTION
        Parses a single key=value pair from a .env file line.

        Empty lines and lines starting with # (comments) are ignored.

        Keys may contain any characters. By default, whitespace around keys is
        trimmed, but this can be customized with the 'NoTrimKeys' option.

        Values can be unquoted or quoted with single or double quotes. By default,
        whitespace around unquoted values is trimmed, but this can be customized
        with the 'NoTrimValues' option. By default, backslash escape sequences
        are processed in double quoted values, but this can be disabled with the
        'NoUnescape' option. Quoted values can span multiple lines (assuming the
        passed string contains the entire value).

        Comments after quoted values are ignored. Comments after unquoted values
        are included in the value unless 'AllowInlineComments' option is specified,
        in which case the comment and preceding whitespace are ignored.

        Use the 'Strict' option to throw errors for invalid lines instead of
        silently skipping them.

        Use the 'Interpolate' option along with -InterpolationVariables parameter
        to support variable interpolation in values using $VAR, ${VAR}, and
        ${VAR:-DEFAULT} syntax. Use $$ to escape a literal $ character.
    .INPUTS
        [string]
        A single name=value pair from a .env file. Quoted values can span multiple lines.
    .OUTPUTS
        [PSCustomObject]
        An object with 'Name' and 'Value' properties representing the parsed name-value pair
        from the .env line.
    #>
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string] $Line,
        [ValidateSet('NoQuotedValues', 'NoTrimKeys', 'NoTrimValues', 'NoUnescape', 'AllowInlineComments', 'Strict', 'Interpolate')]
        [string[]] $Options = @(),
        [System.Collections.IDictionary] $InterpolationVariables
    )
    begin {
        $noUnescape = $Options -contains 'NoUnescape'

        # allow all characters in the name. We'll trim it later if requested
        $namePatternWithWS = "^(?<n>.+)$"

        # include whitespace. we'll trim it later if requested
        $literalValuePatternWithWS = $Options -contains 'AllowInlineComments' `
            ? '(?<v>.*?)(\s+#|$)' `
            : '(?<v>.*)$'

        if ($Options -contains 'NoQuotedValues') {
            $valuePatternWithWS = "^($literalValuePatternWithWS)"
        }
        else {
            $singleQuoteValuePattern = "((?<q>')(?<v>(''|[^'])*)')"
            $doubleQuoteValuePattern = $noUnescape `
                ? '((?<q>")(?<v>(""|[^"])*)")' `
                : '((?<q>")(?<v>(""|\\.|[^"])*)")'

            $quotedValuePatternWithWS = "\s*($singleQuoteValuePattern|$doubleQuoteValuePattern)\s*(#|$)" # always allow trailing comments
            $valuePatternWithWS = "^($quotedValuePatternWithWS|$literalValuePatternWithWS)"
        }

        $reNameWithWS = [regex]::new($namePatternWithWS, ('Compiled', 'ExplicitCapture', 'CultureInvariant'))
        $reValueWithWS = [regex]::new($valuePatternWithWS, ('Compiled', 'ExplicitCapture', 'CultureInvariant'))
    }
    process {
        # skip empty lines and comments
        if ($Line -match '^\s*($|#)') { return }

        $name, $value = $Line.Split('=', 2)

        $m = $reNameWithWS.Match($name)
        if (-not $m.Success) {
            # invalid name
            if ($Options -contains 'Strict') { throw "Invalid key: '$Line'" }
            return
        }
        $name = $m.Groups['n'].Value
        if ($Options -notcontains 'NoTrimKeys') {
            $name = $name.Trim()
        }
        if ($name -eq '') {
            # empty name
            if ($Options -contains 'Strict') { throw "Key cannot be empty: '$Line'" }
            return
        }

        $m = $reValueWithWS.Match($value)
        if (!$m.Success) {
            # invalid value - I think this is unreachable, but we'll keep it just in case
            if ($Options -contains 'Strict') { throw "Invalid value: '$Line'" }
            return
        }
        $value = $m.Groups['v'].Value
        if ($m.Groups['q'].Success) {
            # quoted value
            # unescape double quotes, and optionally unescape escape sequences in double quoted values
            $value = switch ($m.Groups['q'].Value) {
                "'" { $value.Replace("''", "'") }
                '"' {
                    $noUnescape `
                        ? $value.Replace('""', '"') `
                        : ($value -replace '""|\\.', {
                            switch -CaseSensitive ($_.Value[1]) {
                                'n' { "`n" }
                                'r' { "`r" }
                                't' { "`t" }
                                default { "$_" }
                            }
                        })
                }
            }
        }
        else {
            # unquoted value.
            if ($Options -notcontains 'NoTrimValues') {
                $value = $value.Trim()
            }
        }

        if ($Options -contains 'Interpolate') {
            # support $VAR or ${VAR} or ${VAR:-DEFAULT} syntax for interpolation.
            # Use $$ to escape a literal $ character.
            $value = $value -replace '\$\$|\${(?<var>[^:}\n]+)(:-(?<default>[^}\n]*))?}|\$(?<var>\w+)', {
                if ($_.Groups['var'].Success) {
                    $var = $_.Groups['var'].Value
                    if ($InterpolationVariables -and $InterpolationVariables.ContainsKey($var)) {
                        return $InterpolationVariables[$var]
                    }
                    if ($_.Groups['default'].Success) {
                        return $_.Groups['default'].Value
                    }
                    return $_.Value # leave it as-is
                }
                else {
                    return '$' # literal dollar sign
                }
            }

            if ($InterpolationVariables -and !$InterpolationVariables.IsReadOnly) {
                $InterpolationVariables[$name] = $value
            }
        }

        [PSCustomObject]@{ Name = $name; Value = $value }
    }
}

function Import-DotEnv {
    <#
    .SYNOPSIS
        Load .env files as environment variables or PowerShell variables.
    .DESCRIPTION
        Loads all name-value pairs from one or more .env files. By default, the values are
        loaded as environment variables, but you can use the -AsVariables switch to return
        them as PowerShell variables instead which can then be imported into the desired scope.
    .EXAMPLE
        PS> Import-DotEnv .env

        Loads environment variables from the .env file, overwriting existing values.
    .EXAMPLE
        PS> Import-DotEnv *.env -NoClobber

        Loads all *.env files in the current directory without overwriting existing values.
    .EXAMPLE
        PS> Import-DotEnv ./media/.env -Prototype .env.sample -CreationAction Continue

        Loads environment variables from './media/.env'. If the file doesn't exist, it will be
        copied from './media/.env.sample' file. A warning will be issued but the cmdlet will
        continue loading variables from the newly created file (which may be empty or contain
        placeholder values).
    .EXAMPLE
        PS> Import-DotEnv './media/.env' -AsVariables | Add-Variable -Force

        Get variables from the './media/.env' as PowerShell variables, and immediately imports
        them into the local scope, overwriting any existing variables.
    .OUTPUTS
        None
        By default, this cmdlet does not return any output.

        [System.Management.Automation.PSVariable]
        If the -AsVariables switch is specified, the cmdlet returns the loaded variables.
    #>
    [CmdletBinding(PositionalBinding = $false, DefaultParameterSetName = 'AsEnvVars')]
    [OutputType([System.Management.Automation.PSVariable])]
    param(
        # The path(s) to the .env file(s) to load. Wildcards are supported.
        [Parameter(Mandatory, Position = 0)]
        [SupportsWildcards()]
        [string[]] $Path,

        # Identifies a "prototype" file to copy when the target .env file doesn't exist.
        # If the prototype contains a plain file name (no path info), the cmdlet expects
        # the prototype file to be next to the target .env file. For example, if the target
        # file is './media/.env' and the prototype is 'env.sample', the cmdlet will use
        # './media/env.sample' as the prototype file.
        # If the prototype includes path info, it will be used as-is. For example, if the
        # prototype is './env.sample', the cmdlet will use that exact file as the prototype.
        # If the prototype is an existing directory, the cmdlet will look in that directory
        # for a prototype with the same name as the target .env file. For example, if the
        # target file is './foo.env' and the prototype is './prototypes', the cmdlet will
        # use './prototypes/foo.env' as the prototype file.
        [ValidateNotNullOrEmpty()]
        [string] $Prototype,

        # Indicates how the cmdlet should behave after the .env file is created from its
        # prototype (see above).
        # - 'Continue' emits a warning for each created .env file but continues loading
        #   variables from them.
        # - 'Ignore' is similar to Continue without the warnings.
        # - 'Stop' (default) is similar to Continue except instead of loading variables
        #   it exits with an error urging the user to update placeholder values and retry.
        # Ignored if -Prototype not specified.
        [ValidateSet('Stop', 'Continue', 'Ignore')]
        [string] $CreationAction = 'Stop',

        # Do not overwrite existing environment variables.
        [Parameter(ParameterSetName = 'AsEnvVars')]
        [switch] $NoClobber,

        # When this switch is used, the cmdlet returns the loaded variables as PSVariable
        # objects instead of loading them into the environment.
        [Parameter(ParameterSetName = 'AsVariables')]
        [switch] $AsVariables,

        # Parsing options. Multiple options should be separated by commas.
        # - 'NoQuotedValues': Do not treat quoted values differently from unquoted values.
        # - 'NoTrimKeys': Do not trim whitespace from keys. By default, keys are trimmed.
        # - 'NoTrimValues': Do not trim whitespace from values. By default, _unquoted_ values are trimmed.
        # - 'NoUnescape': Do not unescape backslash escape sequences in double quoted values.
        # - 'AllowInlineComments': Allow comments after unquoted values (e.g. `FOO=bar # this is a comment`).
        # - 'Strict': Enable strict mode, which enforces stricter parsing rules. In strict mode, invalid lines
        #   will cause the cmdlet to throw an error instead of silently skipping them.
        # - 'Interpolate': Support $VAR, ${VAR}, and  ${VAR:-DEFAULT} syntax for interpolating variables in
        #   values. Use $$ to escape a literal $ character. When this option is used, the -InterpolationVariables
        #   parameter can be used to provide variables for interpolation.
        [ValidateSet('NoQuotedValues', 'NoTrimKeys', 'NoTrimValues', 'NoUnescape', 'AllowInlineComments', 'Strict', 'Interpolate')]
        [string[]] $Options = @(),

        # When -Options includes 'Interpolate', this parameter can be used to provide variables for interpolation.
        # Defaults to the current environment variables. If the provided dictionary is not read-only,
        # the cmdlet will add loaded variables to it as well.
        [System.Collections.IDictionary] $InterpolationVariables
    )
    Sync-CallerPreference
    $null = $Prototype # avoid "unused parameter" warning

    function writeError ([string]$msg) {
        Write-Error -Exception $msg -CategoryActivity 'Import-DotEnv' @args
    }

    function tryCreateFromPrototype ([string]$file) {
        # if Prototype includes a directory, use it as-is. Otherwise assume it is a file name
        # and look for the prototype file in the same directory as the target file...
        $prototypeFile = $Prototype `
            ? ((Split-Path $Prototype -Parent) `
                ? $Prototype `
                : (Join-Path (Split-Path $file -Parent) $Prototype)) `
            : $null
        # if the prototype file is a directory, look for a file with the same name as the target
        # file inside that directory...
        if ($prototypeFile -and (Test-Path -LiteralPath $prototypeFile -PathType Container)) {
            $prototypeFile = Join-Path $prototypeFile (Split-Path $file -Leaf)
        }
        if (!$prototypeFile -or !(Test-Path -LiteralPath $prototypeFile -PathType Leaf)) {
            $msg = "File not found at '$file'"
            if ($prototypeFile) { $msg += ", and prototype file not found at '$prototypeFile'" }
            $msg += '. Please create the file with the appropriate values.'
            writeError $msg -Category ObjectNotFound -CategoryTargetName $file
            return
        }

        Write-Verbose "Creating '$file' from prototype '$prototypeFile'..."
        if (!(Copy-Item -LiteralPath $prototypeFile -Destination $file -Force -PassThru)) {
            return # error handled by Copy-Item
        }
        if ($CreationAction -ne 'Ignore') {
            Write-Warning "Created '$file' from prototype '$prototypeFile'."
        }
        return $file
    }

    $createdFile = $false
    $Path = @(
        foreach ($file in $Path) {
            $file = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($file)
            if (Test-Path $file -PathType Leaf) {
                Convert-Path $file # in case it contains wildcards
            }
            elseif (tryCreateFromPrototype $file) {
                $createdFile = $true
                $file
            }
        }
    )
    if ($createdFile -and $CreationAction -eq 'Stop') {
        writeError 'Created file from prototype. Please update any placeholder values and retry.'
        return
    }

    if ($Options -contains 'Interpolate' -and !$PSBoundParameters.ContainsKey('InterpolationVariables')) {
        # Uses the current environment variables for interpolation. On Windows, use a case-insensitive
        # dictionary since environment variables are case-insensitive, while on Linux/macOS use a
        # case-sensitive dictionary.
        $InterpolationVariables = $IsWindows ? @{} : [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        Get-ChildItem 'Env:' | ForEach-Object { $InterpolationVariables[$_.Name] = $_.Value }
    }

    foreach ($file in $Path) {
        Write-Verbose "Loading .env variables from '$file'..."
        Get-Content $file |
        parseDotEnvLine -Options $Options -InterpolationVariables $InterpolationVariables |
        ForEach-Object {
            $name = $_.Name
            $value = $_.Value

            if ($AsVariables) {
                return [PSVariable]::new($name, $value)
            }

            # Load as environment variables...
            $fqName = "env:$name"
            if ($NoClobber -and ($var = Get-Item -LiteralPath $fqName -ErrorAction Ignore)) {
                Write-Verbose "Environment variable '$name' already exists ($($var.Value)). Skipping it."
                return
            }
            if (Set-Item -LiteralPath $fqName -Value $value -Force:(!$NoClobber) -PassThru) {
                Write-Verbose "Loaded Environment Variable: `$$fqName = '$value'"
            }
        }
    }
}
