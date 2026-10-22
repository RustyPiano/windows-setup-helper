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
$userPolicyKey = 'HKCU:\SOFTWARE\Policies\' + $registryName
$otherSid = 'S-1-5-21-123456789-234567890-345678901-1001'
$otherHiveLoaded = $false
[void](New-Item -ItemType Directory -Path $fixture -Force)
try {
    foreach ($name in @('Start-DevSetup.ps1', 'scripts', 'data')) {
        Copy-Item -LiteralPath (Join-Path $root $name) -Destination $fixture -Recurse
    }
    $settings = @(
        [pscustomobject]@{ id = 'MachineTest'; name = '管理员测试设置'; recommended = $true; path = $machineKey; valueName = 'TestValue'; type = 'DWord'; value = 7 },
        [pscustomobject]@{ id = 'UserTest'; name = '当前用户测试设置'; recommended = $true; path = $userKey; valueName = 'TestValue'; type = 'DWord'; value = 9 },
        [pscustomobject]@{ id = 'UserPolicyTest'; name = '当前用户策略测试'; recommended = $true; path = $userPolicyKey; valueName = 'TestValue'; type = 'DWord'; value = 11 }
    )
    $settings | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $fixture 'data/tweaks.json') -Encoding UTF8
    . (Join-Path $fixture 'Start-DevSetup.ps1') -Action List -DryRun -Yes 6>$null
    if (-not (Test-Administrator)) { throw 'Windows 测试执行器必须具备管理员权限。' }
    $userSid = Get-SetupUserSid
    [void](New-Item -Path $userPolicyKey -Force)
    $acl = New-Object Security.AccessControl.RegistrySecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in @(@('S-1-5-32-544', 'FullControl'), @('S-1-5-18', 'FullControl'), @($userSid, 'ReadKey'))) {
        $sid = New-Object Security.Principal.SecurityIdentifier($rule[0])
        $acl.AddAccessRule((New-Object Security.AccessControl.RegistryAccessRule($sid, $rule[1], 'ContainerInherit', 'None', 'Allow')))
    }
    Set-Acl -LiteralPath $userPolicyKey -AclObject $acl
    $policyAcl = (Get-Acl -LiteralPath $userPolicyKey).Sddl
    Add-Type -Path (Join-Path $PSScriptRoot 'fixtures/RegistryPermissionProbe.cs')
    $nativePath = "$userSid\SOFTWARE\Policies\$registryName"
    if ([RegistryPermissionProbe]::CheckWriteAccess($nativePath, $true) -ne 5 -or [RegistryPermissionProbe]::CheckWriteAccess($nativePath, $false) -ne 0) {
        throw '测试未复现普通权限拒绝写入、管理员权限允许写入的用户策略项。'
    }
    $script:DryRunEnabled = $false
    function Test-Administrator { return $false }
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Restricted -Force
    Invoke-SystemOptimization
    if ((Get-ItemPropertyValue -LiteralPath $machineKey -Name 'TestValue') -ne 7 -or (Get-ItemPropertyValue -LiteralPath $userKey -Name 'TestValue') -ne 9 -or
        (Get-ItemPropertyValue -LiteralPath $userPolicyKey -Name 'TestValue') -ne 11 -or $script:Succeeded -ne 3) {
        throw '真实管理员子进程或当前用户设置没有完成。'
    }
    if ((Get-Acl -LiteralPath $userPolicyKey).Sddl -ne $policyAcl) { throw '用户策略写入修改了注册表权限。' }
    $logs = @(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'WindowsSetupHelper/logs') -Filter 'administrator-*.log')
    if ($logs.Count -ne 1 -or (Get-Content -LiteralPath $logs[0].FullName -Raw) -notmatch '管理员测试设置') { throw '没有保存管理员进程的运行记录。' }
    if ((Get-Content -LiteralPath $logs[0].FullName -Raw) -match '软件编号：') { throw '管理员初始化输出了无关软件清单。' }

    $hiveFile = Join-Path $folder 'other-user.hiv'
    & reg.exe save ("HKCU\SOFTWARE\$registryName") $hiveFile /y
    if ($LASTEXITCODE -ne 0) { throw '无法保存隔离测试用的注册表文件。' }
    & reg.exe load ("HKU\$otherSid") $hiveFile
    if ($LASTEXITCODE -ne 0) { throw '无法加载隔离测试用户的注册表。' }
    $otherHiveLoaded = $true
    Set-ItemProperty -LiteralPath $userPolicyKey -Name 'TestValue' -Value 99
    Invoke-ElevatedSetupTask 'OptimizeMachine' @{ Full = $false; UserSid = $otherSid }
    $otherPolicy = "Registry::HKEY_USERS\$otherSid\SOFTWARE\Policies\$registryName"
    if ((Get-ItemPropertyValue -LiteralPath $otherPolicy -Name 'TestValue') -ne 11 -or (Get-ItemPropertyValue -LiteralPath $userPolicyKey -Name 'TestValue') -ne 99) {
        throw '管理员进程没有按原用户账户标识写入独立的用户策略。'
    }

    $settings[0].value = 'invalid-test-value'
    $settings | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $fixture 'data/tweaks.json') -Encoding UTF8
    $failed = $false
    try { Invoke-SystemOptimization }
    catch {
        if ($_.Exception.Message -notmatch 'invalid-test-value' -or $_.Exception.Message -notmatch '管理员运行记录') { throw }
        $failed = $true
    }
    if (-not $failed -or $script:Succeeded -ne 3) { throw '管理员错误没有传回主进程，或错误地增加了成功数量。' }
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
    Write-Host '管理员子进程测试通过：受限令牌实际访问拒绝、管理员写入用户策略、保留注册表权限、按原用户标识写入独立用户配置、初始化无清单输出、执行与启动错误回传。'
}
finally {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy $originalPolicy -Force
    if ($otherHiveLoaded) {
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        & reg.exe unload ("HKU\$otherSid")
        if ($LASTEXITCODE -ne 0) { throw '隔离测试用户的注册表未能卸载。' }
    }
    foreach ($key in @($machineKey, $userKey, $userPolicyKey)) {
        if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force }
    }
    $env:LOCALAPPDATA = $originalLocalAppData
    Remove-Item -LiteralPath $folder -Recurse -Force
}
