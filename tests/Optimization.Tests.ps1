Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$entry = Join-Path $root 'Start-DevSetup.ps1'
$catalog = Get-Content (Join-Path $root 'data/tweaks.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$testFolder = Join-Path $root ('.work/optimization-tests-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $testFolder -Force)

try {
    & {
        $script:OriginalSettings = @()
        $script:DevConfigAction = 'Full'
        function New-DevConfigRegistryStep { param([hashtable]$Setting, [switch]$Reset) return $Setting }
        function Invoke-DevConfigSteps { param([object[]]$Steps) $script:OriginalSettings += $Steps }
        $base = 'https://raw.githubusercontent.com/microsoft/WindowsDeveloperConfig/fe21c03a486a1076c425720c1ebe4e25404e0e6b/windows-dev-config/steps'
        foreach ($name in @('registry-system', 'registry-explorer', 'registry-taskbar-search', 'edge')) {
            $file = Join-Path $testFolder "$name.ps1"
            Invoke-WebRequest -Uri "$base/$name.ps1" -OutFile $file -UseBasicParsing -TimeoutSec 60
            . $file
        }
        Invoke-RegistrySystemPhase
        Invoke-RegistryExplorerPhase
        Invoke-RegistryTaskbarSearchPhase
        Invoke-EdgePhase
        if ($catalog.Count -ne 23 -or $script:OriginalSettings.Count -ne $catalog.Count -or
            @($catalog.id | Select-Object -Unique).Count -ne $catalog.Count) { throw '原版系统设置清单不完整。' }
        foreach ($original in $script:OriginalSettings) {
            $setting = $catalog | Where-Object { $_.id -eq $original.Name }
            $path = $original.KeyPath -replace '^(HKCU|HKLM)\\', '$1:\'
            $type = if ($original.ContainsKey('Type')) { $original.Type } else { 'DWord' }
            if (-not $setting -or $setting.path -ne $path -or $setting.valueName -ne $original.ValueName -or
                $setting.type -ne $type -or ($setting.value -join ',') -ne ($original.Value -join ',')) {
                throw "设置与微软原脚本不一致：$($original.Name)"
            }
        }
    }

    $optional = @('Sudo', 'DeveloperMode', 'RemoteDesktop', 'DoNotDisturb', 'BluetoothOff')
    if (@($catalog | Where-Object { $_.recommended }).Count -ne 18 -or
        @(Compare-Object ($catalog | Where-Object { -not $_.recommended } | ForEach-Object { $_.id }) $optional).Count -ne 0) {
        throw '推荐配置包含了不应默认启用的项目。'
    }

    & {
        . $entry -Action List -DryRun 6>$null
        function New-ItemProperty { throw '预演修改了注册表。' }
        function Start-Process { throw '预演启动了管理员进程。' }
        function Test-Administrator { throw '预演不应检查管理员身份。' }
        $Yes = $true
        $output = Invoke-SystemOptimization 6>&1 | Out-String
        if ([regex]::Matches($output, '\[预演\]').Count -ne 18 -or $output -match 'AllowDevelopmentWithoutDevLicense') { throw '推荐配置预演错误。' }
        $output = Invoke-SystemOptimization -Full 6>&1 | Out-String
        if ([regex]::Matches($output, '\[预演\]').Count -ne 23 -or $output -notmatch 'about:blank') { throw '完整配置预演错误。' }
        $output = Invoke-SystemOptimization -MachineOnly 6>&1 | Out-String
        if ([regex]::Matches($output, '\[预演\]').Count -ne 4 -or $output -match '\[预演\] HKCU:') { throw '管理员进程包含了当前用户的设置。' }
    }

    & {
        . $entry -Action List -DryRun 6>$null
        $script:DryRunEnabled = $false
        function Confirm-Selection { return $false }
        function Set-SystemTweak { throw '取消后仍然写入了设置。' }
        function Start-Process { throw '取消后仍然启动了管理员进程。' }
        Invoke-SystemOptimization 6>$null
    }

    & {
        . $entry -Action List -DryRun 6>$null
        $script:DryRunEnabled = $false
        $Yes = $true
        $script:UserSettings = @()
        function Test-Administrator { return $false }
        function Start-Process {
            param([string]$FilePath, [string[]]$ArgumentList, [string]$Verb, [switch]$Wait, [switch]$PassThru)
            if ($Verb -ne 'RunAs' -or $ArgumentList -notcontains '-MachineOnly' -or $ArgumentList -notcontains '-Yes' -or -not $Wait) {
                throw '管理员进程的参数错误。'
            }
            return [pscustomobject]@{ ExitCode = 0 }
        }
        function Set-SystemTweak {
            param([object]$Setting)
            if ($Setting.path -notlike 'HKCU:*') { throw '普通用户进程尝试修改系统范围的设置。' }
            $script:UserSettings += $Setting.id
        }
        Invoke-SystemOptimization 6>$null
        if ($script:UserSettings.Count -ne 14 -or $script:Succeeded -ne 18) { throw '提升权限后的当前用户设置或结果统计错误。' }
    }

    & {
        . $entry -Action List -DryRun 6>$null
        $script:DryRunEnabled = $false
        $Yes = $false
        $script:Selections = New-Object 'System.Collections.Generic.Queue[string]'
        foreach ($choice in @('4', 'y', '', '0')) { $script:Selections.Enqueue($choice) }
        $script:AppliedSettings = @()
        function Read-Host { param([string]$Prompt) return $script:Selections.Dequeue() }
        function Test-Administrator { return $true }
        function Set-SystemTweak { param([object]$Setting) $script:AppliedSettings += $Setting.id }
        $output = Show-SystemMenu 6>&1 | Out-String
        if ($script:AppliedSettings.Count -ne 18 -or $script:Selections.Count -ne 0 -or $output -notmatch '成功 18') {
            throw '推荐优化菜单没有在一次确认后执行全部默认设置。'
        }
    }

    & {
        . $entry -Action List -DryRun 6>$null
        $script:DryRunEnabled = $false
        $Yes = $true
        function Test-Administrator { return $true }
        function Set-SystemTweak { throw 'write-failed' }
        $failed = $false
        try { Invoke-SystemOptimization 6>$null }
        catch {
            if ($_.Exception.Message -ne 'write-failed') { throw }
            $failed = $true
        }
        if (-not $failed -or $script:Succeeded -ne 0) { throw '设置写入失败后没有停止或错误地显示成功。' }
    }

    if ($env:OS -eq 'Windows_NT') {
        & {
            . $entry -Action List -DryRun 6>$null
            $script:DryRunEnabled = $false
            $registryRoot = 'HKCU:\Software\WindowsSetupHelperTests-' + [guid]::NewGuid().ToString('N')
            try {
                foreach ($setting in $catalog) {
                    $target = $setting | Select-Object *
                    $target.path = Join-Path $registryRoot $setting.id
                    Set-SystemTweak $target
                    $key = Get-Item -LiteralPath $target.path
                    $kind = $key.GetValueKind($setting.valueName).ToString()
                    $value = $key.GetValue($setting.valueName)
                    $key.Dispose()
                    if ($kind -ne $setting.type -or ($value -join ',') -ne ($setting.value -join ',')) { throw "注册表类型或数值错误：$($setting.id)" }
                }
            }
            finally {
                if (Test-Path -LiteralPath $registryRoot) { Remove-Item -LiteralPath $registryRoot -Recurse -Force }
            }
        }
    }

    $output = & $entry -Action Optimize -FullOptimization -DryRun -Yes 6>&1 | Out-String
    if ([regex]::Matches($output, '\[预演\]').Count -ne 23) { throw '完整配置命令行入口错误。' }
    Write-Host '系统优化测试通过：原版 23 项配置、推荐默认项、预演、取消、权限提升、错误传播和注册表类型。' -ForegroundColor Green
}
finally { Remove-Item -LiteralPath $testFolder -Recurse -Force }
