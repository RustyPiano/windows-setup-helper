Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$shell = (Get-Process -Id $PID).Path
$output = @('5', '0') | & $shell -NoProfile -Command 'irm https://raw.githubusercontent.com/RustyPiano/win-dev-picker/main/bootstrap.ps1 | iex'
$output | Out-Host
if ($LASTEXITCODE -ne 0) { throw '在线启动失败。' }
if ([regex]::Matches(($output -join "`n"), '(?m)^\s*\d+\. \[').Count -ne 19) { throw '在线软件清单显示不完整。' }
foreach ($name in @('装机准备', '安装后配置', '安装日常软件')) {
    if (($output -join "`n") -notmatch $name) { throw "在线菜单缺少：$name" }
}
Write-Host '在线命令测试通过：下载、打开菜单、显示 19 项软件、退出。' -ForegroundColor Green
