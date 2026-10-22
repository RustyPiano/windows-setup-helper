function Show-SetupComputer {
    if ($script:DryRunEnabled) { Write-Status '[预演] 查看电脑型号、系统、架构和磁盘空间'; return }
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem
    $system = Get-CimInstance -ClassName Win32_OperatingSystem
    Write-Status "电脑：$($computer.Manufacturer) $($computer.Model)"
    $architecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    $processor = switch ($architecture) {
        'AMD64' { 'Intel / AMD 64 位（x64）' }
        'ARM64' { 'Arm 处理器（Arm64）' }
        'x86' { '32 位（x86）' }
        default { $architecture }
    }
    Write-Status "系统：$($system.Caption)；版本：$($system.Version)；处理器类型：$processor"
    foreach ($volume in (Get-Volume | Where-Object { $_.DriveLetter })) {
        Write-Status ('{0}: {1}；可用 {2:N1} GB / 总容量 {3:N1} GB' -f $volume.DriveLetter, $volume.FileSystemLabel, ($volume.SizeRemaining / 1GB), ($volume.Size / 1GB))
    }
}

function Import-SetupDrivers {
    param([string]$Source)
    if (-not $script:DryRunEnabled) {
        if (-not (Test-Administrator)) { throw '安装驱动需要以管理员身份运行。' }
        if (-not (Get-ChildItem -LiteralPath $Source -Filter '*.inf' -Recurse | Select-Object -First 1)) { throw "没有找到驱动 INF 文件：$Source" }
    }
    Write-Host "从以下目录安装匹配当前硬件的驱动：$Source"
    if (-not (Confirm-Selection)) { return }
    $result = Invoke-Tool 'pnputil' @('/add-driver', (Join-Path $Source '*.inf'), '/subdirs', '/install') -SuccessExitCodes @(0, 3010) -SkipExitCodes @(259)
    Write-Result '安装备份驱动' $result
}

function Show-ActivationStatus {
    if ($script:DryRunEnabled) { Write-Status '[预演] 查看 Windows 激活状态'; return }
    $licenses = @(Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f'" | Where-Object { $_.PartialProductKey })
    if ($licenses.Count -eq 0) { Write-Status '未读取到 Windows 激活状态。' 'Warn'; return }
    $states = @('未授权', '已授权', '初始宽限期', '附加宽限期', '非正版宽限期', '通知状态', '延长宽限期')
    foreach ($license in $licenses) { Write-Status ("{0}：{1}" -f $license.Name, $states[[int]$license.LicenseStatus]) }
}

function Start-Activation {
    $command = 'irm https://get.activated.win | iex'
    Write-Host '即将启动第三方 Microsoft Activation Scripts，由其交互菜单选择具体操作。'
    Write-Host "来源与命令：$command"
    if (-not (Confirm-Selection)) { return }
    $shell = (Get-Process -Id $PID).Path
    Start-SetupProgram 'Microsoft Activation Scripts' $shell @('-NoProfile', '-Command', $command)
    Show-ActivationStatus
}

function Set-FileExtensionDisplay {
    param([bool]$Visible)
    $label = if ($Visible) { '显示文件扩展名' } else { '隐藏文件扩展名' }
    Write-Host $label
    if (-not (Confirm-Selection)) { return }
    if ($script:DryRunEnabled) { Write-Status "[预演] $label"; return }
    $value = if ($Visible) { 0 } else { 1 }
    [void](New-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name HideFileExt -PropertyType DWord -Value $value -Force)
    Write-Status '设置已保存，重新登录后生效。'
    Write-Result $label $true
}

function Show-ActivationMenu {
    while ($true) {
        Show-Page '安装后设置 / Windows 激活'
        Write-Host '1. 查看激活状态'
        Write-Host '2. 打开激活工具（Microsoft Activation Scripts）'
        Write-Host "`n0. 返回安装后设置"
        $choice = Read-MenuChoice -Count 2
        if ($choice -eq '0') { return }
        Show-Page '安装后设置 / Windows 激活'
        $before = @($script:Succeeded, $script:Skipped, $script:Failed)
        $logCount = $script:LogLines.Count
        switch ($choice) {
            '1' { Show-ActivationStatus }
            '2' { Start-Activation }
        }
        if ($script:LogLines.Count -gt $logCount) {
            Show-Summary -Succeeded ($script:Succeeded - $before[0]) -Skipped ($script:Skipped - $before[1]) -Failed ($script:Failed - $before[2])
            Wait-ForMenu
        }
    }
}

function Show-SettingsMenu {
    while ($true) {
        Show-Page '安装后设置 / 常用设置'
        Write-Host '1. 显示文件扩展名（例如 .pdf、.jpg）'
        Write-Host '2. 隐藏文件扩展名'
        Write-Host '3. 任务栏设置'
        Write-Host '4. 启动应用设置'
        Write-Host '5. 电源设置'
        Write-Host '6. 默认应用设置'
        Write-Host "`n0. 返回安装后设置"
        $choice = Read-MenuChoice -Count 6
        if ($choice -eq '0') { return }
        Show-Page '安装后设置 / 常用设置'
        $before = @($script:Succeeded, $script:Skipped, $script:Failed)
        $logCount = $script:LogLines.Count
        switch ($choice) {
            '1' { Set-FileExtensionDisplay $true }
            '2' { Set-FileExtensionDisplay $false }
            '3' { Open-SetupPage '任务栏设置' 'ms-settings:taskbar' }
            '4' { Open-SetupPage '启动应用设置' 'ms-settings:startupapps' }
            '5' { Open-SetupPage '电源设置' 'ms-settings:powersleep' }
            '6' { Open-SetupPage '默认应用设置' 'ms-settings:defaultapps' }
        }
        if ($script:LogLines.Count -gt $logCount) {
            Show-Summary -Succeeded ($script:Succeeded - $before[0]) -Skipped ($script:Skipped - $before[1]) -Failed ($script:Failed - $before[2])
            Wait-ForMenu
        }
    }
}

function Show-SystemMenu {
    while ($true) {
        Show-Page '安装后设置'
        Write-Host '先安装驱动并更新 Windows，再按需要激活和调整设置。'
        Write-Host "`n1. 安装之前备份的驱动"
        Write-Host '2. 打开 Windows 更新'
        Write-Host '3. Windows 激活'
        Write-Host '4. 常用设置（文件扩展名、任务栏、电源等）'
        Write-Host '5. 查看电脑信息'
        Write-Host "`n0. 返回主菜单"
        $choice = Read-MenuChoice -Count 5
        if ($choice -eq '0') { return }
        if ($choice -in @('1', '2', '5')) { Show-Page '安装后设置' }
        $before = @($script:Succeeded, $script:Skipped, $script:Failed)
        $logCount = $script:LogLines.Count
        switch ($choice) {
            '1' {
                $source = Select-SetupPath '选择之前保存的驱动备份文件夹'
                if ($source) { Import-SetupDrivers $source }
            }
            '2' { Open-SetupPage 'Windows 更新' 'ms-settings:windowsupdate' }
            '3' { Show-ActivationMenu }
            '4' { Show-SettingsMenu }
            '5' { Show-SetupComputer }
        }
        if ($choice -in @('1', '2', '5') -and $script:LogLines.Count -gt $logCount) {
            Show-Summary -Succeeded ($script:Succeeded - $before[0]) -Skipped ($script:Skipped - $before[1]) -Failed ($script:Failed - $before[2])
            Wait-ForMenu
        }
    }
}
