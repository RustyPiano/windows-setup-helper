$global:LASTEXITCODE = 0
if ($args[0] -eq '--version') { Write-Output 'v1.12.0'; return }
if ($args[1] -eq 'export') {
    Write-Output '{"Arg":"https://cdn.winget.microsoft.com/cache","Type":"Microsoft.PreIndexed.Package","TrustLevel":["Trusted","StoreOrigin"]}'
    return
}
if ($args[1] -eq 'add' -and $args -contains 'https://mirrors.ustc.edu.cn/winget-source' -and $env:WINDEVPICKER_TEST_SOURCE_FAIL -eq '1') {
    $global:LASTEXITCODE = 7
    Write-Output 'source-add-failed'
}
