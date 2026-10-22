Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$shell = (Get-Process -Id $PID).Path
$output = @('4', '0', '0') | & $shell -NoProfile -Command 'irm https://setup.rustypiano.com | iex'
$output | Out-Host
if ($LASTEXITCODE -ne 0) { throw '在线启动失败。' }
$root = Split-Path -Parent $PSScriptRoot
$packages = Get-Content (Join-Path $root 'data/packages.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($package in $packages) {
    if (-not ($output -join "`n").Contains($package.name)) { throw "在线软件清单缺少：$($package.name)" }
}
foreach ($name in @('重装前准备', '安装后设置', '安装日常软件')) {
    if (($output -join "`n") -notmatch $name) { throw "在线菜单缺少：$name" }
}
Write-Host '在线命令测试通过：下载、打开菜单、显示 19 项软件、退出。' -ForegroundColor Green
