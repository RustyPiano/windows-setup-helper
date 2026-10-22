Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') {
    Write-Host '管理员子进程测试需要 Windows，当前系统未执行。'
    exit 0
}
$root = Split-Path -Parent $PSScriptRoot
$folder = Join-Path $root ('.work/elevation-tests-' + [guid]::NewGuid().ToString('N'))
$fixture = Join-Path $folder "狗狗 用户's folder"
$originalLocalAppData = $env:LOCALAPPDATA
$originalPolicy = Get-ExecutionPolicy -Scope Process
$env:LOCALAPPDATA = Join-Path $folder 'appdata'
$registryName = 'WindowsSetupHelperTests-' + [guid]::NewGuid().ToString('N')
$machineKey = 'HKLM:\SOFTWARE\' + $registryName
$userKey = 'HKCU:\SOFTWARE\' + $registryName
[void](New-Item -ItemType Directory -Path $fixture -Force)
try {
    foreach ($name in @('Start-DevSetup.ps1', 'scripts', 'data')) {
        Copy-Item -LiteralPath (Join-Path $root $name) -Destination $fixture -Recurse
    }
    $settings = @(
        [pscustomobject]@{ id = 'MachineTest'; name = '管理员测试设置'; recommended = $true; path = $machineKey; valueName = 'TestValue'; type = 'DWord'; value = 7 },
        [pscustomobject]@{ id = 'UserTest'; name = '当前用户测试设置'; recommended = $true; path = $userKey; valueName = 'TestValue'; type = 'DWord'; value = 9 }
    )
    $settings | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $fixture 'data/tweaks.json') -Encoding UTF8
    . (Join-Path $fixture 'Start-DevSetup.ps1') -Action List -DryRun -Yes 6>$null
    if (-not (Test-Administrator)) { throw 'Windows 测试执行器必须具备管理员权限。' }
    $script:DryRunEnabled = $false
    function Test-Administrator { return $false }
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Restricted -Force
    Invoke-SystemOptimization
    if ((Get-ItemPropertyValue -LiteralPath $machineKey -Name 'TestValue') -ne 7 -or (Get-ItemPropertyValue -LiteralPath $userKey -Name 'TestValue') -ne 9 -or $script:Succeeded -ne 2) {
        throw '真实管理员子进程或当前用户设置没有完成。'
    }
    $logs = @(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'WindowsSetupHelper/logs') -Filter 'administrator-*.log')
    if ($logs.Count -ne 1 -or (Get-Content -LiteralPath $logs[0].FullName -Raw) -notmatch '管理员测试设置') { throw '没有保存管理员进程的运行记录。' }

    $settings[0].value = 'invalid-test-value'
    $settings | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $fixture 'data/tweaks.json') -Encoding UTF8
    $failed = $false
    try { Invoke-SystemOptimization }
    catch {
        if ($_.Exception.Message -notmatch 'invalid-test-value' -or $_.Exception.Message -notmatch '管理员运行记录') { throw }
        $failed = $true
    }
    if (-not $failed -or $script:Succeeded -ne 2) { throw '管理员错误没有传回主进程，或错误地增加了成功数量。' }
    $errorFiles = @(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'WindowsSetupHelper/logs') -Filter '*.error.txt')
    if ($errorFiles.Count -ne 1 -or (Get-Content -LiteralPath $errorFiles[0].FullName -Raw -Encoding UTF8) -notmatch 'invalid-test-value') { throw '管理员错误没有保留在磁盘。' }

    $script:ProjectRoot = Join-Path $fixture 'missing-entry'
    $failed = $false
    try { Invoke-ElevatedSetupTask 'OptimizeMachine' @{ Full = $false } }
    catch {
        if ($_.Exception.Message -notmatch 'Start-DevSetup.ps1') { throw }
        $failed = $true
    }
    if (-not $failed) { throw '脚本加载前的错误没有传回。' }
    Write-Host '管理员子进程测试通过：中文、空格和引号路径，受限执行策略，真实 RunAs 与注册表写入，执行错误和启动错误回传。'
}
finally {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy $originalPolicy -Force
    foreach ($key in @($machineKey, $userKey)) {
        if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force }
    }
    $env:LOCALAPPDATA = $originalLocalAppData
    Remove-Item -LiteralPath $folder -Recurse -Force
}
