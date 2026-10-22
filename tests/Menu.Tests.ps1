Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$entry = Join-Path $root 'Start-DevSetup.ps1'

& {
    . $entry -Action List -DryRun 6>$null
    $script:Selections = New-Object 'System.Collections.Generic.Queue[string]'
    foreach ($choice in @('all', '4', '99999999999999999999', '2')) { $script:Selections.Enqueue($choice) }
    function Read-Host { param([string]$Prompt) return $script:Selections.Dequeue() }
    $choice = Read-MenuChoice -Count 3 6>$null
    if ($choice -ne '2' -or $script:Selections.Count -ne 0) { throw '单选菜单没有拒绝无效序号。' }

    foreach ($choice in @('1,2', '0')) { $script:Selections.Enqueue($choice) }
    $plan = @(Read-MirrorSelection @('pip') 6>$null)
    if ($plan.Count -ne 0 -or $script:Selections.Count -ne 0) { throw '下载源单选没有正确处理多选和跳过。' }
}

& {
    . $entry -Action List -DryRun 6>$null
    $script:Selections = New-Object 'System.Collections.Generic.Queue[string]'
    foreach ($choice in @('1', '0', '2', '3', '0', '5', '0', '0', '3', '0', '4', '0', '5', '0', '0')) {
        $script:Selections.Enqueue($choice)
    }
    function Read-Host { param([string]$Prompt) return $script:Selections.Dequeue() }
    function Wait-ForMenu { throw '直接返回或取消选择后不应额外等待。' }
    Write-Status '已有运行记录' -LogOnly
    $output = Show-Menu 6>&1 | Out-String
    foreach ($title in @('重装前准备', '安装后设置 / Windows 激活', '安装后设置 / 常用设置', '安装日常软件', '安装开发软件', '软件下载源')) {
        if ($output -notmatch [regex]::Escape($title)) { throw "菜单无法进入或返回：$title" }
    }
    foreach ($package in $script:PackageCatalog) {
        if (-not $output.Contains($package.name)) { throw "交互式清单缺少软件：$($package.name)" }
    }
    if ($output -match 'Git\.Git|Microsoft\.WindowsTerminal|操作结果：' -or $script:Selections.Count -ne 0) {
        throw '取消选择后出现了多余的技术信息、结果统计或输入。'
    }
}

& {
    . $entry -Action List -DryRun 6>$null
    $script:Selections = New-Object 'System.Collections.Generic.Queue[string]'
    foreach ($choice in @('2', '', '0')) { $script:Selections.Enqueue($choice) }
    function Read-Host { param([string]$Prompt) return $script:Selections.Dequeue() }
    function Open-SetupPage {
        param([string]$Name, [string]$Uri)
        Write-Status "已打开：$Name"
    }
    $output = Show-SystemMenu 6>&1 | Out-String
    if ($output -notmatch '已打开：Windows 更新' -or $script:Selections.Count -ne 0) {
        throw '操作结果没有停留到按回车返回。'
    }
}

Write-Host '交互测试通过：菜单层级、单选校验、清单展示、取消返回和结果停留。' -ForegroundColor Green
