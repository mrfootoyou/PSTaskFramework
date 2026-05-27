    BeforeAll {
        $ErrorActionPreference = 'Stop'
        $global:LASTEXITCODE = 0

        Import-Module "$PSScriptRoot/../../../src/scripts/PSTaskFramework/InstallHelpers/InstallHelpers" -Scope Local -Verbose:$false

        # Mock Install-Module to prevent actual module installation in a poorly written test.
        Mock Install-Module -ModuleName InstallHelpers {
            throw 'Install-Module called from unit test!'
        }

        # Mock Write-Information and Write-Verbose to prevent test output pollution.
        Mock Write-Information -ModuleName InstallHelpers { }
        Mock Write-Verbose -ModuleName InstallHelpers { }
    }

    BeforeEach {
        # Cache original PATH to restore after tests
        $script:originalPath = $env:PATH
    }
    AfterEach {
        # Restore original PATH after each test
        $env:PATH = $script:originalPath
    }
