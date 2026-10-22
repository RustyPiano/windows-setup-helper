Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$folder = Join-Path $root ('.work/widgets-tests-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $folder -Force)
$originalLocalAppData = $env:LOCALAPPDATA
$env:LOCALAPPDATA = Join-Path $folder 'appdata'
try {
    & {
        . (Join-Path $root 'Start-DevSetup.ps1') -Action List -DryRun -Yes 6>$null
        $setting = $script:TweakCatalog | Where-Object { $_.id -eq 'WidgetServiceOff' }
        function Get-LocalPolicyTool { throw '预演不应下载工具。' }
        $output = Set-SystemTweak $setting 6>&1 | Out-String
        if ($output -notmatch '\[预演\].*AllowNewsAndInterests') { throw '小组件预演没有显示策略。' }
        $script:DryRunEnabled = $false
        $script:Calls = New-Object 'System.Collections.Generic.List[object]'
        $script:FailTool = $false
        $script:StoredValue = 0
        function Get-LocalPolicyTool { return (Join-Path $folder 'LGPO.exe') }
        function New-ItemProperty { throw '小组件设置不应直接写入受保护的注册表。' }
        function Invoke-Tool {
            param([string]$Name, [string[]]$Arguments)
            $script:Calls.Add([pscustomobject]@{ Name = $Name; Arguments = $Arguments })
            if ($Name -like '*LGPO.exe') {
                $content = [IO.File]::ReadAllText($Arguments[1], [Text.Encoding]::Unicode)
                if ($Arguments[0] -ne '/t' -or $content -ne "Computer`r`nSOFTWARE\Policies\Microsoft\Dsh`r`nAllowNewsAndInterests`r`nDWORD:0`r`n") { throw '提交的本地组策略内容不正确。' }
                $bytes = [IO.File]::ReadAllBytes($Arguments[1])
                if ($bytes[0] -ne 255 -or $bytes[1] -ne 254) { throw '策略文件缺少 Unicode 编码标记。' }
            }
            return (-not $script:FailTool)
        }
        function Get-ItemPropertyValue { return $script:StoredValue }
        Set-SystemTweak $setting
        if ($script:Calls.Count -ne 2 -or $script:Calls[1].Name -ne 'gpupdate' -or $script:Calls[1].Arguments -notcontains '/target:computer') { throw '没有请求 Windows 应用计算机策略。' }
        if (Test-Path -LiteralPath $script:Calls[0].Arguments[1]) { throw '临时策略文件没有清理。' }
        $script:FailTool = $true
        $count = $script:Calls.Count
        $failed = $false
        try { Set-SystemTweak $setting }
        catch { if ($_.Exception.Message -notmatch '没有保存成功') { throw }; $failed = $true }
        if (-not $failed -or $script:Calls.Count -ne $count + 1) { throw '策略工具失败后仍继续执行。' }
        $script:FailTool = $false
        $script:StoredValue = 1
        $failed = $false
        try { Set-SystemTweak $setting }
        catch { if ($_.Exception.Message -notmatch '实际保留的值') { throw }; $failed = $true }
        if (-not $failed) { throw '策略未生效时没有报错。' }
    }

    if ($env:OS -eq 'Windows_NT') {
        & {
            . (Join-Path $root 'Start-DevSetup.ps1') -Action List -DryRun -Yes 6>$null
            $script:DryRunEnabled = $false
            if (-not (Test-Administrator)) { throw '本地组策略测试需要管理员权限。' }
            $tool = Get-LocalPolicyTool
            $setting = $script:TweakCatalog | Where-Object { $_.id -eq 'WidgetServiceOff' }
            $previous = 'DELETE'
            if (Test-Path -LiteralPath $setting.path) {
                $key = Get-Item -LiteralPath $setting.path
                try {
                    if ($key.GetValueNames() -contains $setting.valueName) {
                        if ($key.GetValueKind($setting.valueName) -ne 'DWord') { throw '现有小组件策略的类型不正确，停止测试。' }
                        $previous = 'DWORD:' + $key.GetValue($setting.valueName)
                    }
                }
                finally { $key.Dispose() }
            }
            $restore = Join-Path $folder 'restore.txt'
            [IO.File]::WriteAllText($restore, (@('Computer', 'SOFTWARE\Policies\Microsoft\Dsh', 'AllowNewsAndInterests', $previous, '') -join "`r`n"), [Text.Encoding]::Unicode)
            try {
                Set-SystemTweak $setting
                $policyFile = Join-Path $env:SystemRoot 'System32/GroupPolicy/Machine/Registry.pol'
                $parsed = Invoke-Tool $tool @('/parse', '/q', '/m', $policyFile) 6>&1 | Out-String
                if ($parsed -notmatch 'Computer\s+SOFTWARE\\Policies\\Microsoft\\Dsh\s+AllowNewsAndInterests\s+DWORD:(0|0x0+)\b') { throw '本地组策略文件中没有保存小组件策略。' }
                if ((Get-ItemPropertyValue -LiteralPath $setting.path -Name $setting.valueName) -ne 0) { throw 'Windows 没有应用小组件策略。' }
                Write-Host 'Windows 本地组策略测试通过：微软工具下载校验、策略保存、Windows 刷新和实际注册表值核对。'
            }
            finally {
                if (-not (Invoke-Tool $tool @('/t', $restore))) { throw '没有还原测试前的小组件策略。' }
                if (-not (Invoke-Tool 'gpupdate' @('/target:computer', '/force', '/wait:60'))) { throw '没有刷新还原后的小组件策略。' }
            }
        }
    }
    else { Write-Host '当前系统不是 Windows，本地组策略集成测试未执行。' }
    Write-Host '小组件策略测试通过：官方工具参数、预演、失败停止和生效核对。'
}
finally {
    $env:LOCALAPPDATA = $originalLocalAppData
    Remove-Item -LiteralPath $folder -Recurse -Force
}
