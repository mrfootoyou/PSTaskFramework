<#
.SYNOPSIS
    Part of the PSTaskFramework.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4
# spell:ignore winget,choco,8wekyb3d8bbwe

param()

function refreshEnvironment {
    # only supported on Windows
    if (!$IsWindows) {
        return
    }

    # Refresh the PATH environment variable for the current session.
    $rawPath = (
        [System.Environment]::GetEnvironmentVariable('PATH', [System.EnvironmentVariableTarget]::Machine) + ';' +
        [System.Environment]::GetEnvironmentVariable('PATH', [System.EnvironmentVariableTarget]::User))

    $env:PATH = (
        $rawPath.Split(';') |
        Where-Object { $_ } |
        ForEach-Object { [System.Environment]::ExpandEnvironmentVariables($_.Trim()) } |
        Select-Object -Unique
    ) -join ';'
}

function installWinget {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseCompatibleCommands', 'Get-AppxPackage')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseCompatibleCommands', 'Add-AppxPackage')]
    param()
    $ErrorActionPreference = 'Stop'

    if (!$IsWindows) {
        throw 'Winget is not supported on this OS platform.'
    }

    if (Get-Command 'winget' -ErrorAction Ignore) {
        Write-Information "$($PSStyle.Foreground.Green)Winget is already installed.$($PSStyle.Reset)"
        return
    }

    # Winget (App Installer) is included by default in modern versions of Windows 10 and
    # later, but the App Installer package can sometimes become corrupted. Re-registering
    # the package can often fix issues with Winget without requiring a full reinstall.
    $packageName = 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe'
    $storeUrl = 'https://apps.microsoft.com/detail/9nblggh4nns1'

    if (!(Get-Command 'Get-AppxPackage' -ErrorAction Ignore)) {
        throw "Your version of Windows may not support Winget. Try installing 'App Installer' from the Microsoft Store: $storeUrl."
    }

    if (!(Get-AppxPackage | Where-Object PackageFamilyName -eq $packageName -ErrorAction Ignore)) {
        throw "Winget not found. Install 'App Installer' from the Microsoft Store: $storeUrl."
    }

    Write-Information "$($PSStyle.Foreground.Yellow)Winget not found, but 'App Installer' is present. Attempting to re-register the package to restore Winget functionality...$($PSStyle.Reset)"
    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage $packageName

        if (!(Get-Command 'winget' -ErrorAction Ignore)) {
            refreshEnvironment
            if (!(Get-Command 'winget' -ErrorAction Ignore)) {
                throw "Re-registered 'App Installer' package, but Winget is still not found. Maybe try opening a new terminal or restarting your computer?"
            }
        }

        Write-Information "$($PSStyle.Foreground.Green)Winget was successfully installed.$($PSStyle.Reset)"
    }
    catch {
        throw "Winget not found and failed to re-register 'App Installer' package: $_"
    }
}

function installChocolatey {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '', Justification = 'Needed for chocolatey installation script.')]
    param()
    $ErrorActionPreference = 'Stop'

    if (!$IsWindows) {
        throw 'Chocolatey is not supported on this OS platform.'
    }

    if (Get-Command 'choco' -ErrorAction Ignore) {
        Write-Information "$($PSStyle.Foreground.Green)Chocolatey is already installed.$($PSStyle.Reset)"
        return
    }

    Write-Information "$($PSStyle.Foreground.Yellow)Attempting to install Chocolatey package manager...$($PSStyle.Reset)"
    try {
        # The ExecutionPolicy needs to be at least RemoteSigned
        if ((Get-ExecutionPolicy) -notin 'RemoteSigned', 'AllSigned', 'Bypass', 'Unrestricted') {
            # Try to set the ExecutionPolicy for the current process, but don't
            # fail if we can't.
            Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force -ea Ignore
        }

        $ProgressPreference = 'SilentlyContinue'
        $resp = Invoke-WebRequest 'https://community.chocolatey.org/install.ps1' -Verbose:$false
        Invoke-Expression $resp.Content

        if (!(Get-Command 'choco' -ErrorAction Ignore)) {
            refreshEnvironment
            if (!(Get-Command 'choco' -ErrorAction Ignore)) {
                throw 'Chocolatey installation script ran, but Chocolatey (choco) is still not found. Maybe try opening a new terminal or restarting your computer?'
            }
        }

        Write-Information "$($PSStyle.Foreground.Green)Chocolatey was successfully installed.$($PSStyle.Reset)"
    }
    catch {
        throw "Failed to install Chocolatey: $_"
    }
}

function installAPT {
    param()
    $ErrorActionPreference = 'Stop'

    if (!$IsMacOS -and !$IsLinux) {
        throw 'APT (Advanced Package Tool) is not supported on this OS platform.'
        return
    }

    if (Get-Command 'apt-get' -ErrorAction Ignore) {
        Write-Information "$($PSStyle.Foreground.Green)APT (Advanced Package Tool) is already installed.$($PSStyle.Reset)"
        return
    }

    # Not gonna try it!
    throw 'APT (Advanced Package Tool) not found. Manually install APT and try again.'
}

function installDNF {
    param()
    $ErrorActionPreference = 'Stop'

    if (!$IsMacOS -and !$IsLinux) {
        throw 'DNF (Dandified Yum) is not supported on this OS platform.'
        return
    }

    if (Get-Command 'dnf' -ErrorAction Ignore) {
        Write-Information "$($PSStyle.Foreground.Green)DNF (Dandified Yum) is already installed.$($PSStyle.Reset)"
        return
    }

    # Not gonna try it!
    throw 'DNF (Dandified Yum) not found. Manually install DNF and try again.'
}

function installBrew {
    param()

    if (!$IsMacOS -and !$IsLinux) {
        throw 'Homebrew is not supported on this OS platform.'
    }

    if (Get-Command 'brew' -ErrorAction Ignore) {
        Write-Information "$($PSStyle.Foreground.Green)Homebrew is already installed.$($PSStyle.Reset)"
        return
    }

    # Not gonna attempt automated installation! Installation itself is easy enough, but it
    # requires some post-setup manual steps to integrate with the shell that I am not
    # comfortable automating.
    throw 'Homebrew (brew) not found. Manually install Homebrew from https://brew.sh/ and try again.'
}

function Install-PackageManager {
    <#
    .DESCRIPTION
        Attempts to install a supported package manager on the system.

        See 'Get-PackageManager -AllSupported' for the list of supported package managers.
    .OUTPUTS
        The names of the package managers that were [already] installed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # The package manager(s) to install. Use 'any' to install any supported
        # package manager.
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet('any', 'winget', 'choco', 'apt', 'dnf', 'brew', 'brew:linux', 'brew:macos')]
        [string[]] $PackageManager
    )
    Sync-CallerPreference

    $PackageManager = @(
        $PackageManager |
        ForEach-Object {
            if ($_ -eq 'brew:macos' -and $IsMacOS) { 'brew' }
            elseif ($_ -eq 'brew:linux' -and $IsLinux) { 'brew' }
            else { $_ }
        } |
        Select-Object -Unique
    )

    $installed = @{}

    function install([string]$pm) {
        Write-Information "Installing $pm if needed..."
        switch ($pm) {
            'winget' { installWinget }
            'choco' { installChocolatey }
            'apt' { installAPT }
            'dnf' { installDNF }
            'brew' { installBrew }
            default { throw "Unsupported package manager: $_." }
        }

        # success
        $installed[$pm] = $true
        if ($pm -eq 'brew' -and $IsMacOS) { $installed['brew:macos'] = $true }
        if ($pm -eq 'brew' -and $IsLinux) { $installed['brew:linux'] = $true }
    }

    foreach ($pm in $PackageManager) {
        try {
            if ($pm -eq 'any') { continue } # see below
            install $pm
        }
        catch {
            # Keep trying remaining candidates; this cmdlet reports partial failures.
            Write-Error -ErrorRecord $_ -CategoryActivity $MyInvocation.MyCommand.Name
        }
    }

    if (!$installed.Count -and $PackageManager -contains 'any') {
        # just the ones not already tried...
        $otherSupportedPMs = Get-PackageManager -AllSupported | Where-Object { $_ -notin $PackageManager }
        foreach ($pm in $otherSupportedPMs) {
            try {
                install $pm
                break
            }
            catch {
                Write-Warning $_.Exception.Message
            }
        }
        if (!$installed.Count) {
            Write-Error -Exception "Failed to install any supported package manager (tried $($otherSupportedPMs -join ', '))." `
                -CategoryActivity $MyInvocation.MyCommand.Name `
                -Category ObjectNotFound `
                -CategoryReason 'NoPackageManagerInstalled'
        }
    }

    Write-Output $installed.Keys
}
