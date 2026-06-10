<#
.SYNOPSIS
    Part of the PSTaskFramework.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4

param()

# Mockable functions for testing purposes. These are not intended to be used directly.
function getUserId {
    id -u
}

function Test-Administrator {
    <#
    .DESCRIPTION
        Check if the current user has administrative (Windows) or root (Linux/macOS) privileges.
    #>
    if ($IsWindows) {
        # test for administrator on Windows
        return [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    else {
        # test for root user on Linux/macOS
        return (getUserId) -eq 0
    }
}
