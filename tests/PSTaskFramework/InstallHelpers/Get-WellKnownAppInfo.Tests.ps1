<#
.DESCRIPTION
    Unit tests for Get-WellKnownAppInfo.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4
# spell:ignore appx,winget,choco,mytool,Contoso,8wekyb3d8bbwe

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Mocked functions may have unused parameters.')]
param()

Describe 'PSTaskFramework.InstallHelpers Module' {
    . "$PSScriptRoot/setup.ps1"

    Context 'Get-WellKnownAppInfo' {
        It 'returns all app info by default' {
            $result = Get-WellKnownAppInfo

            $result.Count | Should -BeGreaterThan 1
            $result.Name | Should -Contain 'dotnet-sdk-10'
            $result.Name | Should -Contain 'git'
            $result.Name | Should -Contain 'docker'
        }

        It 'returns app metadata for an exact app name' {
            $result = Get-WellKnownAppInfo -Name 'git'

            $result.Name | Should -BeExactly 'git'
            $result.Info | Should -BeOfType ([System.Collections.IDictionary])
            $result.Info['winget'] | Should -BeExactly 'Git.Git'
        }

        It 'supports wildcard app name lookup' {
            $result = @(Get-WellKnownAppInfo -Name 'dotnet*')

            $result.Count | Should -Be 1
            $result[0].Name | Should -BeExactly 'dotnet-sdk-10'
        }

        It 'throws for unknown app names with ErrorAction Stop' {
            { Get-WellKnownAppInfo -Name 'not-a-real-app' -ErrorAction Stop } | `
                Should -Throw "*not-a-real-app*not a well-known app*"
        }

        It 'does not throw for unknown wildcard' {
            $result = Get-WellKnownAppInfo -Name 'not-a-real-app*' -ErrorAction Stop

            $result | Should -BeNullOrEmpty
        }
    }
}
