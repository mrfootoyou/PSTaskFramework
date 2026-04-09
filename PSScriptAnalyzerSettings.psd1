@{
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
        'PSUseBOMForUnicodeEncodedFile' # git preference is utf-8 without BOM
    )
}
