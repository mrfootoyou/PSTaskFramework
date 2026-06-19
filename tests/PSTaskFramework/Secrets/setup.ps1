BeforeAll {
    $ErrorActionPreference = 'Stop'
    $global:LASTEXITCODE = 0

    Import-Module "$PSScriptRoot/../../../src/scripts/PSTaskFramework/Secrets" -Scope Local -ArgumentList Local -Verbose:$false

    # Mock Write-Information and Write-Verbose to prevent test output pollution.
    Mock Write-Information -ModuleName Secrets { }
    Mock Write-Verbose -ModuleName Secrets { }
}

BeforeEach {
    # Use a private secret store for testing to avoid interference with
    # any global secrets.
    $state = @{
        secrets = [PSCustomObject]@{
            values = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
            regex  = $null
        }
    }
    Mock getState -ModuleName Secrets { $state.secrets }
}

