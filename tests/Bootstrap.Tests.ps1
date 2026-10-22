Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$bootstrap = Join-Path $root 'bootstrap.ps1'
$bootstrapSource = Get-Content -LiteralPath $bootstrap -Raw -Encoding UTF8
$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($bootstrapSource, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }

$testFolder = Join-Path $root ('.work/bootstrap-tests-' + [guid]::NewGuid().ToString('N'))
$payload = Join-Path $testFolder 'windows-setup-helper-main'
[void](New-Item -ItemType Directory -Path (Join-Path $payload 'data') -Force)
[void](New-Item -ItemType Directory -Path (Join-Path $payload 'scripts') -Force)
Copy-Item (Join-Path $PSScriptRoot 'fixtures/BootstrapEntry.ps1') (Join-Path $payload 'Start-DevSetup.ps1')
Copy-Item (Join-Path $root 'data/*.json') (Join-Path $payload 'data')
Copy-Item (Join-Path $root 'scripts/*.ps1') (Join-Path $payload 'scripts')
Copy-Item (Join-Path $root 'Launch-Online.cmd') $payload
$payloadArchive = Join-Path $testFolder 'payload.zip'
Compress-Archive -Path $payload -DestinationPath $payloadArchive
$originalLocalAppData = $env:LOCALAPPDATA
$originalOS = $env:OS
$env:LOCALAPPDATA = Join-Path $testFolder 'appdata'
$env:OS = 'Windows_NT'
$env:WINDEVPICKER_TEST_BOOTSTRAP_MARKER = Join-Path $testFolder 'started.txt'
$archiveUrl = 'https://github.com/RustyPiano/windows-setup-helper/archive/refs/heads/main.zip'

function Invoke-WebRequest {
    param([string]$Uri, [string]$OutFile, [switch]$UseBasicParsing, [int]$TimeoutSec)
    if ($Uri -ne $archiveUrl) { throw '启动脚本使用了错误的下载地址。' }
    if ($env:WINDEVPICKER_TEST_DOWNLOAD_FAIL -eq '1') { throw 'download-failed' }
    Copy-Item -LiteralPath $payloadArchive -Destination $OutFile
}

try {
    $bootstrapSource | Invoke-Expression
    if (-not (Test-Path $env:WINDEVPICKER_TEST_BOOTSTRAP_MARKER)) { throw '在线启动没有执行入口文件。' }
    Remove-Item -LiteralPath $env:WINDEVPICKER_TEST_BOOTSTRAP_MARKER

    $env:WINDEVPICKER_TEST_DOWNLOAD_FAIL = '1'
    $failed = $false
    try { $bootstrapSource | Invoke-Expression }
    catch {
        if ($_.Exception.Message -notmatch 'download-failed') { throw }
        $failed = $true
    }
    if (-not $failed -or (Test-Path $env:WINDEVPICKER_TEST_BOOTSTRAP_MARKER)) { throw '下载失败后仍启动了入口文件。' }
    Remove-Item Env:WINDEVPICKER_TEST_DOWNLOAD_FAIL

    $env:WINDEVPICKER_TEST_BOOTSTRAP_FAIL = '1'
    $failed = $false
    try { $bootstrapSource | Invoke-Expression }
    catch {
        if ($_.Exception.Message -notmatch '退出代码：9') { throw }
        $failed = $true
    }
    if (-not $failed) { throw '入口执行失败没有向调用者报告。' }
    if (@(Get-ChildItem (Join-Path $env:LOCALAPPDATA 'WindowsSetupHelper/downloads') -Directory).Count -ne 0) { throw '下载文件没有清理。' }
    Write-Host '在线启动测试通过：完整下载后启动、下载失败终止、入口错误传播、下载文件清理。' -ForegroundColor Green
}
finally {
    $env:LOCALAPPDATA = $originalLocalAppData
    $env:OS = $originalOS
    foreach ($name in @('WINDEVPICKER_TEST_BOOTSTRAP_MARKER', 'WINDEVPICKER_TEST_DOWNLOAD_FAIL', 'WINDEVPICKER_TEST_BOOTSTRAP_FAIL')) {
        Remove-Item "Env:$name" -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $testFolder -Recurse -Force
}
exit 0
