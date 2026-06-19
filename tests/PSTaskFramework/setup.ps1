BeforeAll {
    $ErrorActionPreference = 'Stop'
    $global:LASTEXITCODE = 0

    Import-Module "$PSScriptRoot/../../src/scripts/PSTaskFramework" -Scope Local -Verbose:$false

    # Mock Write-Information and Write-Verbose to prevent test output pollution.
    Mock Write-Information -ModuleName PSTaskFramework { }
    Mock Write-Verbose -ModuleName PSTaskFramework { }
}

BeforeEach {
    # Initialize a fresh TaskContext for each test to ensure test isolation.
    $buildScript = Join-Path $TestDrive 'dummyBuild.ps1'
    '<# dummy script #>' | Out-File $buildScript

    $TaskContext = Initialize-TaskFramework -BuildScriptPath $buildScript
    $null = $TaskContext
}
