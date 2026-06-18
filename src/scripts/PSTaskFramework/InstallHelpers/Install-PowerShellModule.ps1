<#
.SYNOPSIS
    Part of the PSTaskFramework.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4

param()

function Install-PowerShellModule {
    <#
    .DESCRIPTION
        Checks if the specified PowerShell module(s) are installed with at least
        the given minimum version. If any module is missing or does not meet the version
        requirement, it will be installed from the PowerShell Gallery.
    .EXAMPLE
        $modules = @{
            'Pester' = '5.1.0'
            'PSScriptAnalyzer' = '1.25.0'
        }
        Install-PowerShellModule -ModuleVersions $modules

        This example checks if Pester v5.1.0 or higher and PSScriptAnalyzer v1.25.0
        or higher are installed, and installs them if not.
    .NOTES
        Use the -InformationAction parameter to see status messages.
    #>
    [CmdletBinding()]
    param(
        # A dictionary where the keys are module names and values are the minimum required
        # versions (as [version] compatible values).
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $ModuleVersions,

        # The scope for installing modules. Defaults to 'CurrentUser' to avoid requiring
        # administrator privileges.
        [ValidateSet('CurrentUser', 'AllUsers')]
        [string]$Scope = 'CurrentUser'
    )

    Sync-CallerPreference

    function tryGetModule([string]$Name, [version]$MinimumVersion) {
        Get-Module -Name $Name -ListAvailable -ea Ignore |
        Where-Object Version -ge $MinimumVersion
    }

    function installIfNeeded([string]$Name, [version]$MinimumVersion, $Scope) {
        if (!($installed = tryGetModule @PSBoundParameters)) {
            Write-Information "$($PSStyle.Foreground.Yellow)Installing $Name $MinimumVersion (or greater) in $Scope scope...$($PSStyle.Reset)"
            Install-Module @PSBoundParameters -Force

            # Re-query after install to verify the expected minimum version is visible.
            if (!($installed = tryGetModule @PSBoundParameters)) {
                throw "Failed to install $Name $MinimumVersion (or greater) in $Scope scope."
            }
        }
        Write-Information "$($PSStyle.Foreground.Green)$Name $($installed.Version) is installed.$($PSStyle.Reset)"
    }

    try {
        foreach ($module in $ModuleVersions.Keys) {
            installIfNeeded -Name $module -MinimumVersion $ModuleVersions[$module] -Scope $Scope
        }
    }
    catch {
        Write-Error -ErrorRecord $_ -CategoryActivity 'Install-PowerShellModule'
    }
}
