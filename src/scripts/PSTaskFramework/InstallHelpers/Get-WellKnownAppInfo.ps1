<#
.SYNOPSIS
    Part of the PSTaskFramework.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4
# spell:ignore psargs,winget,choco,8wekyb3d8bbwe,assumeyes,myapp

param()

function Get-WellKnownAppInfo {
    <#
    .DESCRIPTION
        Gets the metadata dictionary for a well-known app by name.
    .OUTPUTS
        [PSObject] with properties:
        - Name: the app name that was looked up
        - Info: the metadata dictionary for the app
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([PSObject])]
    param(
        # The name of the well-known app to get info for. Wildcards supported.
        # Defaults to '*'.
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [SupportsWildcards()]
        [ValidateNotNullOrEmpty()]
        [string[]] $Name = @('*')
    )
    process {
        Sync-CallerPreference -PreferencesToSync ErrorAction

        switch ($Name) {
            { $_.IndexOfAny([char[]]'*?[') -ge 0 } {
                $n = $_
                $WellKnownApps.GetEnumerator() |
                Where-Object { $_.Key -like $n } |
                ForEach-Object {
                    [PSCustomObject]@{
                        Name = $_.Key
                        Info = $_.Value
                    }
                }
            }
            { $WellKnownApps.Contains($_) } {
                [PSCustomObject]@{
                    Name = $_
                    Info = $WellKnownApps[$_]
                }
            }
            default {
                Write-Error -Exception "App '$_' is not a well-known app." -CategoryActivity 'Get-WellKnownAppInfo'
            }
        }
    }
}
