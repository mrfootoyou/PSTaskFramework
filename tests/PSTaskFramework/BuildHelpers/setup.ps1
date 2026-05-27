BeforeAll {
    $ErrorActionPreference = 'Stop'
    $global:LASTEXITCODE = 0

    Import-Module "$PSScriptRoot/../../../src/scripts/PSTaskFramework/BuildHelpers/BuildHelpers" -Scope Local -Verbose:$false

    # Mock Write-Information and Write-Verbose to prevent test output pollution.
    Mock Write-Information -ModuleName BuildHelpers { }
    Mock Write-Verbose -ModuleName BuildHelpers { }
}
