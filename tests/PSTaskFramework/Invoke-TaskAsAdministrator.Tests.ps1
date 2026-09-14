<#
.DESCRIPTION
    Unit tests for Invoke-TaskAsAdministrator.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4

param()

Describe 'PSTaskFramework Module' {
    . "$PSScriptRoot/setup.ps1"

    Context 'Invoke-TaskAsAdministrator' {
        BeforeEach {
            $dummyBuildScript = New-Item $TestDrive/build.ps1 -Force
            $TaskContext = Initialize-TaskFramework -BuildScriptPath $dummyBuildScript
            $TaskContext.WorkingDirectory = $TestDrive

            $global:LASTEXITCODE = 0

            Mock Get-Process -ModuleName PSTaskFramework {
                [PSCustomObject]@{ Path = 'C:\Program Files\PowerShell\7\pwsh.exe' }
            }
            Mock Start-Process -ModuleName PSTaskFramework {
                [PSCustomObject]@{ ExitCode = 23 }
            }
            Mock Write-Host -ModuleName PSTaskFramework { }
        }

        It 'elevates the requested task with its arguments and preserves the process exit code' {
            Task 'publish' {}
            $extraScriptArgs = @{ Configuration = 'Release' }

            Invoke-TaskAsAdministrator -TaskName 'publish' -TaskArgs @('package.zip') `
                -ExtraScriptArgs $extraScriptArgs -DoNotWaitForKeyPress

            $global:LASTEXITCODE | Should -Be 23
            Should -Invoke Start-Process -ModuleName PSTaskFramework -Times 1 -Exactly `
                -ParameterFilter {
                $encodedCommand = $ArgumentList -replace '^.* -ec ', ''
                $command = [Text.Encoding]::Unicode.GetString(
                    [Convert]::FromBase64String($encodedCommand)
                )

                $FilePath -eq 'C:\Program Files\PowerShell\7\pwsh.exe' -and
                $WorkingDirectory -eq $TaskContext.WorkingDirectory -and
                $Verb -eq 'RunAs' -and $Wait -and $PassThru -and
                $command.Contains("adminTask -BuildScriptPath '$($TaskContext.BuildScriptPath)' ") -and
                $command.Contains('-TaskName publish ') -and
                $command.Contains("-TaskArgs @('package.zip') ") -and
                $command.Contains('-DoNotWaitForKeyPress $True ') -and
                $command.Contains("-ExtraScriptArgs @{Configuration = 'Release'}")
            }
        }

        It 'executes the active task' {
            Task foo {}
            $TaskContext.CurrentTask = $TaskContext.AllTasks['foo']

            Invoke-TaskAsAdministrator -TaskArgs @()

            $global:LASTEXITCODE | Should -Be 23
            Should -Invoke Start-Process -ModuleName PSTaskFramework -Times 1 -Exactly
        }

        It 'fails when there is no active task' {
            { Invoke-TaskAsAdministrator } | Should -Throw 'No current task in context.'

            Should -Invoke Start-Process -ModuleName PSTaskFramework -Times 0 -Exactly
        }

        It 'fails to launch unknown task' {
            { Invoke-TaskAsAdministrator -TaskName 'unknown' } | Should -Throw 'Task ''unknown'' not found.'

            Should -Invoke Start-Process -ModuleName PSTaskFramework -Times 0 -Exactly
        }
    }
}
