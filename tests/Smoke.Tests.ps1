Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$entry = Join-Path $root 'Start-DevSetup.ps1'
$packagesPath = Join-Path $root 'data/packages.json'
$mirrorsPath = Join-Path $root 'data/mirrors.json'
$appsPath = Join-Path $root 'data/apps.json'

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($entry, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }
foreach ($file in Get-ChildItem (Join-Path $root 'scripts') -Filter '*.ps1') {
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }
}

$packages = Get-Content $packagesPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($packages.Count -ne 19) { throw '软件清单应保留 19 项。' }
$ids = @($packages | ForEach-Object { $_.id })
if (@($ids | Select-Object -Unique).Count -ne $ids.Count) { throw '软件 ID 存在重复。' }
foreach ($item in $packages) {
    if ($item.id -notmatch '^[A-Za-z0-9][A-Za-z0-9.+-]*$') { throw "非法软件 ID：$($item.id)" }
    if (-not $item.description) { throw "缺少软件用途说明：$($item.id)" }
}
$apps = Get-Content $appsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$allIds = @(@($packages) + @($apps) | ForEach-Object { $_.id })
if (@($allIds | Select-Object -Unique).Count -ne $allIds.Count) { throw '日常软件和开发软件的 ID 存在重复。' }
foreach ($item in $apps) {
    if (-not $item.description -or $item.id -notmatch '^[A-Za-z0-9][A-Za-z0-9.+-]*$') { throw "日常软件清单无效：$($item.name)" }
}
$appOutput = & $entry -Action Apps -PackageIds Tencent.WeChat,VideoLAN.VLC -DryRun -Yes 6>&1 | Out-String
if ($appOutput -notmatch 'winget install --id Tencent.WeChat' -or $appOutput -notmatch 'winget install --id VideoLAN.VLC') { throw '日常软件安装预演失败。' }

$catalog = Get-Content $mirrorsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$managers = @('winget', 'pip', 'uv', 'npm', 'pnpm', 'yarn', 'go', 'cargo')
foreach ($manager in $managers) {
    $config = $catalog.$manager
    if (-not $config) { throw "缺少 $manager 镜像清单。" }
    if (-not @($config.options | Where-Object { $_.key -eq $config.recommended }).Count) {
        throw "$manager 推荐镜像不存在。"
    }
    if (-not @($config.options | Where-Object { $_.key -eq 'Official' }).Count) {
        throw "$manager 缺少官方镜像。"
    }
    foreach ($option in $config.options) {
        if ($option.url -notmatch '^(sparse\+)?https://') { throw "$manager 镜像不是 HTTPS：$($option.url)" }
    }
}

$listOutput = (& $entry -Action List -DryRun 6>&1 | Out-String)
if ($listOutput -notmatch 'Git.Git' -or $listOutput -notmatch 'Microsoft.VisualStudioCode') {
    throw '软件列表预演失败。'
}

$installOutput = (& $entry -Action Install -PackageIds Git.Git,Microsoft.PowerShell -DryRun -Yes 6>&1 | Out-String)
if ($installOutput -notmatch 'winget install --id Git.Git' -or $installOutput -notmatch 'winget install --id Microsoft.PowerShell') {
    throw '软件安装预演失败。'
}

$mirrorOutput = (& $entry -Action Mirrors -Mirror Auto -DryRun -Yes 6>&1 | Out-String)
if ($mirrorOutput -notmatch 'mirrors.ustc.edu.cn/winget-source' -or
    $mirrorOutput -notmatch 'registry.npmmirror.com' -or
    $mirrorOutput -notmatch 'GOPROXY=https://goproxy.cn,direct') {
    throw '推荐镜像预演失败。'
}

$tunaOutput = (& $entry -Action Mirrors -Managers pip,uv,cargo -Mirror TUNA -DryRun -Yes 6>&1 | Out-String)
if ($tunaOutput -notmatch 'pypi.tuna.tsinghua.edu.cn' -or $tunaOutput -notmatch 'sparse\+https://mirrors.tuna.tsinghua.edu.cn') {
    throw '自选镜像预演失败。'
}

$restoreOutput = (& $entry -Action Restore -Managers winget,uv,cargo -DryRun -Yes 6>&1 | Out-String)
if ($restoreOutput -notmatch 'WinGet winget 源恢复默认' -or $restoreOutput -notmatch '清除用户环境变量 UV_DEFAULT_INDEX') {
    throw '恢复官方镜像预演失败。'
}

Write-Host '全部测试通过：语法、软件清单、镜像清单、安装预演、镜像配置预演、恢复预演。' -ForegroundColor Green
