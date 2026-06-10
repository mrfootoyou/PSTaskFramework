BeforeAll {
    $ErrorActionPreference = 'Stop'
    $global:LASTEXITCODE = 0

    Import-Module "$PSScriptRoot/../../../src/scripts/PSTaskFramework/PSArgs" -Verbose:$false

    # Mock Write-Information and Write-Verbose to prevent test output pollution.
    Mock Write-Information -ModuleName PSArgs { }
    Mock Write-Verbose -ModuleName PSArgs { }
}
