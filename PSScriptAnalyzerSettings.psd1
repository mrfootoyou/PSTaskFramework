@{
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
        'PSUseBOMForUnicodeEncodedFile' # git preference is utf-8 without BOM
    )
    Rules        = @{
        PSUseCompatibleSyntax   = @{
            Enable         = $true
            TargetVersions = @(
                '7.4'
            )
        }
        PSUseCompatibleCommands = @{
            Enable         = $true
            # Lists the PowerShell platforms we want to check compatibility with
            # See https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/rules/usecompatiblecommands
            TargetProfiles = @(
                'win-8_x64_10.0.14393.0_7.0.0_x64_3.1.2_core',
                'ubuntu_x64_18.04_7.0.0_x64_3.1.2_core'
            )
        }
    }
}
