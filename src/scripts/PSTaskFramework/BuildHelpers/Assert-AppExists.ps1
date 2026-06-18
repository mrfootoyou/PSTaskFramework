<#
.SYNOPSIS
    Part of the PSTaskFramework.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4

param()

function assertAppExists {
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $AppPath,
        [string] $AppTitle,
        [switch] $PassThru
    )

    # Set the ErrorActionPreference to 'Stop' if not explicitly specified.
    if (!$PSBoundParameters.ContainsKey('ErrorAction')) {
        $ErrorActionPreference = 'Stop'
    }

    # When multiple commands with the same name are found, Get-Command returns
    # them in execution precedence order. So take the first one
    $cmd = Get-Command $AppPath -CommandType Application -ea Ignore -TotalCount 1
    if (!$cmd) {
        if ($ErrorActionPreference -ne 'Ignore') {
            $appName = $AppTitle ? "$AppTitle ($AppPath)" : $AppPath
            Write-Error -Exception "$appName not found. Please bootstrap first using './build.ps1 bootstrap'." `
                -CategoryActivity 'Assert-AppExists' -CategoryReason 'App not found' -CategoryTargetName $AppPath
        }
        return
    }
    if ($PassThru) {
        return $cmd.Path
    }
}

function Assert-AppExists {
    <#
    .DESCRIPTION
        Check if the specified application exists.
    .NOTES
        The ErrorAction parameter (-ea) defaults to 'Stop'. Specify an explicit value to override.
    .OUTPUTS
        None
        By default, this cmdlet returns no output.

        [System.String]
        If you specify the PassThru parameter, the cmdlet returns the full path to the application.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([string])]
    [Diagnostics.CodeAnalysis.SuppressMessage('PSUseSingularNouns', '', Justification = 'Exists is not plural.')]
    param(
        # The name or path to the application to check.
        # For maximum compatibility on non-Windows platforms, use the app name without the
        # file extension (e.g. "git" instead of "git.exe").
        [Parameter(Mandatory, Position = 0)]
        [string] $AppPath,
        # An optional friendly name to use in error messages. For example, "Azure CLI".
        [string] $AppTitle,
        # If specified, the cmdlet will return the full path to the application if it exists.
        [switch] $PassThru
    )
    Sync-CallerPreference -PreferencesToSync ErrorAction
    assertAppExists @PSBoundParameters
}
