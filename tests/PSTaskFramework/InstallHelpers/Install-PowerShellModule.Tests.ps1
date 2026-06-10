<#
.DESCRIPTION
    Unit tests for Install-PowerShellModule.
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

    BeforeEach {
        # Mock Install-Module to prevent actual module installation in a poorly written test.
        Mock Install-Module -ModuleName InstallHelpers {
            throw 'Install-Module called from unit test!'
        }
    }

    Context 'Install-PowerShellModule' {
        It 'does not install modules that already satisfy minimum version' {
            Mock Get-Module -ModuleName InstallHelpers {
                [PSCustomObject]@{ Version = [version]'5.2.0' }
            }

            Mock Install-Module -ModuleName InstallHelpers { }

            Install-PowerShellModule -ModuleVersions @{ Pester = [version]'5.1.0' }

            Should -Invoke Install-Module -ModuleName InstallHelpers -Times 0 -Exactly
        }

        It 'installs modules when minimum version is missing' {
            $script:getModuleCallCount = 0

            Mock Get-Module -ModuleName InstallHelpers {
                $script:getModuleCallCount++
                if ($script:getModuleCallCount -ge 2) {
                    [PSCustomObject]@{ Version = [version]'5.1.0' }
                }
            }

            Mock Install-Module -ModuleName InstallHelpers { }

            Install-PowerShellModule -ModuleVersions @{ Pester = [version]'5.1.0' }

            Should -Invoke Install-Module -ModuleName InstallHelpers -Times 1 -Exactly
        }

        It 'writes an error when installation does not produce required version' {
            Mock Get-Module -ModuleName InstallHelpers { $null }
            Mock Install-Module -ModuleName InstallHelpers { }
            Mock Write-Error -ModuleName InstallHelpers { }

            Install-PowerShellModule -ModuleVersions @{ Pester = [version]'5.1.0' } -ErrorAction SilentlyContinue

            Should -Invoke Write-Error -ModuleName InstallHelpers -Times 1
        }
    }

    Context "isPowerShellUpToDate" {
        It 'caches last version response' {
            InModuleScope 'InstallHelpers' {
                $latestVersion = $PSVersionTable.PSVersion.ToString()
                Mock Invoke-WebRequest {
                    [PSCustomObject]@{
                        StatusCode = 302
                        Headers    = @{ Location = @("https://github.com/PowerShell/PowerShell/releases/tag/v$latestVersion") }
                    }
                }

                $appInfo = [ordered]@{
                    data = @{
                        LatestVersion    = $latestVersion
                        NextVersionCheck = [DateTime]::Now.AddMinutes(-1) # past
                    }
                }

                isPowerShellUpToDate 'powershell' $appInfo | Should -BeTrue

                Should -Invoke Invoke-WebRequest -Times 1 -Exactly
                $appInfo.data.LatestVersion.ToString() | Should -BeExactly $latestVersion
                $appInfo.data.NextVersionCheck | Should -BeGreaterThan ([DateTime]::Now.AddMinutes(1))
            }
        }

        It 'uses cached latest version when NextVersionCheck is in the future' {
            InModuleScope 'InstallHelpers' {
                Mock Invoke-WebRequest { }

                $latestVersion = $PSVersionTable.PSVersion.ToString()
                $appInfo = [ordered]@{
                    data = @{
                        LatestVersion    = $latestVersion
                        NextVersionCheck = [DateTime]::Now.AddMinutes(1) # future
                    }
                }

                isPowerShellUpToDate 'powershell' $appInfo | Should -BeTrue

                Should -Invoke Invoke-WebRequest -Times 0 -Exactly
            }
        }

        It 'return false when a newer version exists' {
            InModuleScope 'InstallHelpers' {
                $latestVersion = [version]::new($PSVersionTable.PSVersion.Major, $PSVersionTable.PSVersion.Minor + 1, 0).ToString()
                Mock Invoke-WebRequest {
                    [PSCustomObject]@{
                        StatusCode = 302
                        Headers    = @{ Location = @("https://github.com/PowerShell/PowerShell/releases/tag/v$latestVersion") }
                    }
                }

                $appInfo = [ordered]@{
                    data = @{
                        LatestVersion    = '1.0.0'
                        NextVersionCheck = [DateTime]::Now.AddMinutes(-1)
                    }
                }

                isPowerShellUpToDate 'powershell' $appInfo | Should -BeFalse

                Should -Invoke Invoke-WebRequest -Times 1 -Exactly
                $appInfo.data.LatestVersion | Should -BeExactly $latestVersion
                $appInfo.data.NextVersionCheck | Should -BeGreaterThan ([DateTime]::Now.AddMinutes(1))
            }
        }

        It 'uses cached latest version when web request fails' {
            InModuleScope 'InstallHelpers' {
                Mock Invoke-WebRequest {
                    Write-Error "Web request failed" -ErrorAction SilentlyContinue
                    [PSCustomObject]@{ StatusCode = 501 }
                }

                $latestVersion = $PSVersionTable.PSVersion.ToString()
                $appInfo = [ordered]@{
                    data = @{
                        LatestVersion    = $latestVersion
                        NextVersionCheck = [DateTime]::Now.AddMinutes(-1) # past
                    }
                }

                $WarningPreference = 'Ignore'
                $result = isPowerShellUpToDate 'powershell' $appInfo

                $result | Should -BeTrue
                Should -Invoke Invoke-WebRequest -Times 1 -Exactly
                $appInfo.data.LatestVersion | Should -BeExactly $latestVersion
                $appInfo.data.NextVersionCheck | Should -BeGreaterThan ([DateTime]::Now.AddMinutes(1))
            }
        }

        It 'uses cached latest version when web request does not return 302' {
            InModuleScope 'InstallHelpers' {
                Mock Invoke-WebRequest {
                    [PSCustomObject]@{ StatusCode = 200 }
                }

                $latestVersion = $PSVersionTable.PSVersion.ToString()
                $appInfo = [ordered]@{
                    data = @{
                        LatestVersion    = $latestVersion
                        NextVersionCheck = [DateTime]::Now.AddMinutes(-1) # past
                    }
                }

                $WarningPreference = 'Ignore'
                (& isPowerShellUpToDate 'powershell' $appInfo) | Should -BeTrue

                Should -Invoke Invoke-WebRequest -Times 1 -Exactly
                $appInfo.data.LatestVersion | Should -BeExactly $latestVersion
                $appInfo.data.NextVersionCheck | Should -BeGreaterThan ([DateTime]::Now.AddMinutes(1))
            }
        }
    }
}
