Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw '工具下载与数字签名测试需要 Windows。' }
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Start-DevSetup.ps1') -Action List -DryRun 6>$null
$testFolder = Join-Path $root ('.work/download-tests-' + [guid]::NewGuid().ToString('N'))
$script:SetupFolder = $testFolder
$script:DryRunEnabled = $false
$script:DownloadedTools = New-Object 'System.Collections.Generic.List[string]'
$Yes = $true

function Start-SetupProgram {
    param([string]$Name, [string]$FilePath, [string[]]$Arguments)
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { throw "工具文件不存在：$FilePath" }
    $script:DownloadedTools.Add($Name)
    Write-Host "已下载并验证：$Name"
}

try {
    Start-BootTool 'Rufus'
    Start-BootTool 'Ventoy'
    Start-WindowsDownload
    if ($script:DownloadedTools.Count -ne 3) { throw '官方工具下载验证不完整。' }
    Write-Host '官方下载测试通过：Rufus、Ventoy 哈希校验与微软媒体创建工具签名。' -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $testFolder) { Remove-Item -LiteralPath $testFolder -Recurse -Force }
}
exit 0
