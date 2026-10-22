Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') {
    Write-Host '注册表权限测试需要 Windows，当前系统未执行。'
    exit 0
}
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Start-DevSetup.ps1') -Action List -DryRun -Yes 6>$null
if (-not (Test-Administrator)) { throw '注册表权限测试需要管理员权限。' }
$script:DryRunEnabled = $false
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$sid = $identity.User
$identity.Dispose()

foreach ($hive in @('HKLM:', 'HKCU:')) {
    $path = $hive + '\SOFTWARE\WindowsSetupHelperTests-' + [guid]::NewGuid().ToString('N')
    [void](New-Item -Path $path -Force)
    $originalAcl = Get-Acl -LiteralPath $path
    try {
        $setting = [pscustomobject]@{ path = $path; valueName = 'AllowNewsAndInterests'; type = 'DWord'; value = 0 }
        [void](New-ItemProperty -LiteralPath $path -Name $setting.valueName -PropertyType DWord -Value 1)
        $acl = Get-Acl -LiteralPath $path
        $rule = New-Object Security.AccessControl.RegistryAccessRule($sid, [Security.AccessControl.RegistryRights]::CreateSubKey, [Security.AccessControl.AccessControlType]::Deny)
        $acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $path -AclObject $acl
        $before = (Get-Acl -LiteralPath $path).Sddl
        $reproduced = $false
        try { [void](New-ItemProperty -LiteralPath $path -Name $setting.valueName -PropertyType DWord -Value 0 -Force) }
        catch {
            if ($_.CategoryInfo.Category -ne 'PermissionDenied') { throw }
            $reproduced = $true
        }
        if (-not $reproduced) { throw '没有复现 New-ItemProperty 申请额外权限导致的失败。' }
        Set-SystemTweak $setting
        if ((Get-ItemPropertyValue -LiteralPath $path -Name $setting.valueName) -ne 0) { throw '设置值权限允许时没有写入策略。' }
        if ((Get-Acl -LiteralPath $path).Sddl -ne $before) { throw '写入策略改变了注册表权限或所有者。' }
        Write-Host "$hive 验证通过：原命令被创建子项权限拒绝，现有设置写入成功，权限保持不变。"

        Set-Acl -LiteralPath $path -AclObject $originalAcl
        $acl = Get-Acl -LiteralPath $path
        $rule = New-Object Security.AccessControl.RegistryAccessRule($sid, [Security.AccessControl.RegistryRights]::SetValue, [Security.AccessControl.AccessControlType]::Deny)
        $acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $path -AclObject $acl
        $before = (Get-Acl -LiteralPath $path).Sddl
        $setting.value = 1
        $denied = $false
        try { Set-SystemTweak $setting }
        catch {
            if ($_.Exception.ToString() -notmatch 'SecurityException|UnauthorizedAccessException') { throw }
            $denied = $true
        }
        if (-not $denied -or (Get-ItemPropertyValue -LiteralPath $path -Name $setting.valueName) -ne 0 -or (Get-Acl -LiteralPath $path).Sddl -ne $before) { throw '设置值被禁止时仍然写入或更改了权限。' }
        Write-Host "$hive 验证通过：真正禁止设置值时立即失败，原值和权限保持不变。"
    }
    finally {
        Set-Acl -LiteralPath $path -AclObject $originalAcl
        Remove-Item -LiteralPath $path -Recurse -Force
    }
}
Write-Host '注册表权限测试通过：管理员权限下复现错误、按实际所需权限写入、保留访问限制。'
