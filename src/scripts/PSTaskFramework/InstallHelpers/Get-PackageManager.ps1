<#
.SYNOPSIS
    Part of the PSTaskFramework.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4
# spell:ignore winget,choco

param()

function Get-PackageManager {
    <#
    .DESCRIPTION
        Detects the supported package managers installed on the system
        and returns their names (e.g. winget, choco, apt, dnf, brew,
        brew:linux, brew:macos).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # If specified, returns all supported package managers, not just the ones currently
        # installed on the system.
        [switch] $AllSupported
    )

    $supportedPackageManagers = [string[]] @(
        if ($IsWindows) { 'winget', 'choco' }
        if ($IsLinux) { 'apt', 'dnf', 'brew', 'brew:linux' }
        if ($IsMacOS) { 'brew', 'brew:macos' }
    )

    if ($AllSupported) {
        Write-Output $supportedPackageManagers
        return
    }

    foreach ($pm in $supportedPackageManagers) {
        if (Get-Command $pm -ErrorAction Ignore) {
            $pm
            if ($pm -eq 'brew' -and $IsMacOS) { 'brew:macos' }
            if ($pm -eq 'brew' -and $IsLinux) { 'brew:linux' }
        }
    }
}
