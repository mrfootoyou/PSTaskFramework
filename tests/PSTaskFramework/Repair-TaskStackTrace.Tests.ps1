<#
.DESCRIPTION
    Unit tests for Repair-TaskStackTrace.
.NOTES
    SPDX-License-Identifier: Unlicense
    Source: http://github.com/mrfootoyou/pstaskframework
#>
#Requires -Version 7.4

param()

Describe 'PSTaskFramework Module' {
    . "$PSScriptRoot/setup.ps1"

    Describe 'Repair-TaskStackTrace' {
        It 'rewrites task frame and removes the wrapper line-1 frame' {
            $nl = [System.Environment]::NewLine
            $fakeStack = @(
                'at <ScriptBlock>, <No file>: line 5'
                'at <ScriptBlock>, <No file>: line 1'
                'at Invoke-Task, F:\test\PSTaskFramework.psm1: line 264'
                'at Invoke-TaskFramework, F:\test\PSTaskFramework.psm1: line 346'
                'at <ScriptBlock>, F:\test\build.ps1: line 20'
            ) -join $nl

            $trace = InModuleScope PSTaskFramework -ArgumentList $fakeStack {
                param($fakeStack)
                $exception = [System.Exception]::new('task error')
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception, 'TestError', [System.Management.Automation.ErrorCategory]::NotSpecified, $null)
                $bindingFlags = [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic
                $field = $errorRecord.GetType().GetField('_scriptStackTrace', $bindingFlags)
                $field.SetValue($errorRecord, $fakeStack)

                # Action.Ast.Extent.StartLineNumber == 1 for inline script blocks
                # rewritten line = 1 + 5 - 2 = 4
                $task = [TaskDefinition]@{ Name = 'test-task'; Action = [scriptblock]::Create("throw 'error'") }
                Repair-TaskStackTrace -ErrorRecord $errorRecord -Task $task -TaskActionStartLine 2
                $errorRecord.ScriptStackTrace
            }

            $frames = $trace -split '\r?\n'
            $frames | Should -Contain 'at <ScriptBlock>, <No file>: line 4'
            $frames | Should -Not -Contain 'at <ScriptBlock>, <No file>: line 5'
            $frames | Should -Not -Contain 'at <ScriptBlock>, <No file>: line 1'
            $frames | Should -Contain 'at Invoke-Task, F:\test\PSTaskFramework.psm1: line 264'
            $frames | Should -Contain 'at Invoke-TaskFramework, F:\test\PSTaskFramework.psm1: line 346'
            $frames | Should -Contain 'at <ScriptBlock>, F:\test\build.ps1: line 20'
        }

        It 'rewrites multiple consecutive task frames above the wrapper' {
            $nl = [System.Environment]::NewLine
            $fakeStack = @(
                'at some-other-function, F:\test\other.psm1: line 10'
                'at <ScriptBlock>, <No file>: line 8'
                'at <ScriptBlock>, <No file>: line 5'
                'at <ScriptBlock>, <No file>: line 1'
                'at Invoke-Task, F:\test\PSTaskFramework.psm1: line 264'
            ) -join $nl

            $trace = InModuleScope PSTaskFramework -ArgumentList $fakeStack {
                param($fakeStack)
                $exception = [System.Exception]::new('task error')
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception, 'TestError', [System.Management.Automation.ErrorCategory]::NotSpecified, $null)
                $bindingFlags = [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic
                $field = $errorRecord.GetType().GetField('_scriptStackTrace', $bindingFlags)
                $field.SetValue($errorRecord, $fakeStack)

                # line 5 -> 1 + 5 - 2 = 4; line 8 -> 1 + 8 - 2 = 7
                $task = [TaskDefinition]@{ Name = 'test-task'; Action = [scriptblock]::Create("throw 'error'") }
                Repair-TaskStackTrace -ErrorRecord $errorRecord -Task $task -TaskActionStartLine 2
                $errorRecord.ScriptStackTrace
            }

            $frames = $trace -split '\r?\n'
            $frames | Should -HaveCount 4
            $frames[0] | Should -Be 'at some-other-function, F:\test\other.psm1: line 10'
            $frames[1] | Should -Be 'at <ScriptBlock>, <No file>: line 7'
            $frames[2] | Should -Be 'at <ScriptBlock>, <No file>: line 4'
            $frames[3] | Should -Be 'at Invoke-Task, F:\test\PSTaskFramework.psm1: line 264'
        }

        It 'leaves stack trace unchanged when Invoke-Task frame is absent' {
            $nl = [System.Environment]::NewLine
            $fakeStack = @(
                'at <ScriptBlock>, <No file>: line 5'
                'at some-other-function, F:\test\other.psm1: line 10'
                'at <ScriptBlock>, F:\test\build.ps1: line 20'
            ) -join $nl

            $trace = InModuleScope PSTaskFramework -ArgumentList $fakeStack {
                param($fakeStack)
                $exception = [System.Exception]::new('task error')
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception, 'TestError', [System.Management.Automation.ErrorCategory]::NotSpecified, $null)
                $bindingFlags = [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic
                $field = $errorRecord.GetType().GetField('_scriptStackTrace', $bindingFlags)
                $field.SetValue($errorRecord, $fakeStack)

                $task = [TaskDefinition]@{ Name = 'test-task'; Action = [scriptblock]::Create("throw 'error'") }
                Repair-TaskStackTrace -ErrorRecord $errorRecord -Task $task -TaskActionStartLine 2
                $errorRecord.ScriptStackTrace
            }

            $trace | Should -Be $fakeStack
        }
    }
}
