[CmdletBinding()]
param(
    [ValidateSet('Menu', 'List', 'Install', 'Mirrors', 'Restore', 'Prepare', 'System', 'Apps', 'AppList', 'Optimize')]
    [string]$Action = 'Menu',

    [string[]]$PackageIds = @(),
    [string[]]$Managers = @(),

    [ValidateSet('Auto', 'USTC', 'TUNA', 'Aliyun', 'NpmMirror', 'Tencent', 'GoproxyCN', 'Official')]
    [string]$Mirror = 'Auto',

    [switch]$DryRun,
    [switch]$Yes,
    [switch]$FullOptimization,
    [Parameter(DontShow)][switch]$MachineOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:PackageCatalog = Get-Content (Join-Path $PSScriptRoot 'data/packages.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$script:AppCatalog = Get-Content (Join-Path $PSScriptRoot 'data/apps.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$script:TweakCatalog = Get-Content (Join-Path $PSScriptRoot 'data/tweaks.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$script:ProjectRoot = $PSScriptRoot
$script:SetupFolder = ''
. (Join-Path $PSScriptRoot 'scripts/Preparation.ps1')
. (Join-Path $PSScriptRoot 'scripts/System.ps1')
$script:MirrorCatalog = Get-Content (Join-Path $PSScriptRoot 'data/mirrors.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$script:ManagerNames = @('winget', 'pip', 'uv', 'npm', 'pnpm', 'yarn', 'go', 'cargo')
$script:DryRunEnabled = [bool]$DryRun
$script:LogLines = New-Object 'System.Collections.Generic.List[string]'
$script:LogFile = $null
$script:Failed = 0
$script:Skipped = 0
$script:Succeeded = 0

function Write-Status {
    param([string]$Message, [ValidateSet('Info', 'Warn', 'Error', 'Success')][string]$Kind = 'Info', [switch]$LogOnly)
    $color = switch ($Kind) {
        'Warn' { 'Yellow' }
        'Error' { 'Red' }
        'Success' { 'Green' }
        default { 'Gray' }
    }
    if (-not $LogOnly) { Write-Host $Message -ForegroundColor $color }
    $script:LogLines.Add(('[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Kind, $Message))
}

function Save-Log {
    if ($script:DryRunEnabled -or $script:LogLines.Count -eq 0) { return }
    $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { $HOME }
    $folder = Join-Path $base 'WindowsSetupHelper/logs'
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    if (-not $script:LogFile) { $script:LogFile = Join-Path $folder ('setup-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff')) }
    [System.IO.File]::WriteAllLines($script:LogFile, [string[]]$script:LogLines, [System.Text.UTF8Encoding]::new($false))
}

function Write-Result {
    param([string]$Item, [AllowNull()][object]$Succeeded)
    if ($script:DryRunEnabled) { return }
    if ($null -eq $Succeeded) { $script:Skipped++; Write-Status "跳过：$Item" 'Warn' }
    elseif ($Succeeded) { $script:Succeeded++; Write-Status "成功：$Item" 'Success' }
    else { $script:Failed++; Write-Status "失败：$Item" 'Error' }
}

function Show-Summary {
    param([int]$Succeeded = $script:Succeeded, [int]$Skipped = $script:Skipped, [int]$Failed = $script:Failed)
    if ($script:DryRunEnabled) { return }
    if ($Succeeded + $Skipped + $Failed -eq 0) { Save-Log; return }
    Write-Host ("`n操作结果：成功 {0}，跳过 {1}，失败 {2}" -f $Succeeded, $Skipped, $Failed)
    Save-Log
    if ($script:LogFile) { Write-Host "运行记录：$script:LogFile" }
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Find-Tool {
    param([string]$Name)
    foreach ($candidate in @("$Name.cmd", "$Name.exe", $Name)) {
        $command = Get-Command -Name $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $command) { return $command.Source }
    }
    return $null
}

function Invoke-Tool {
    param([string]$Name, [string[]]$Arguments, [int[]]$SuccessExitCodes = @(0), [int[]]$SkipExitCodes = @())
    Write-Status ("运行：{0} {1}" -f $Name, ($Arguments -join ' ')) -LogOnly:(-not $script:DryRunEnabled)
    if ($script:DryRunEnabled) {
        Write-Status '[预演] 未执行命令'
        return $true
    }
    $command = Find-Tool $Name
    if (-not $command) {
        Write-Status "未找到 $Name，请先安装相应工具并重新打开终端。" 'Warn'
        return $null
    }
    $exitCode = & {
        # Windows PowerShell 5.1 会把程序的标准错误输出转换成错误记录。
        $ErrorActionPreference = 'Continue'
        & $command @Arguments 2>&1 | ForEach-Object {
            $line = $_.ToString()
            Write-Host $line
            $script:LogLines.Add($line)
        }
        $LASTEXITCODE
    }
    if ($SkipExitCodes -contains $exitCode) {
        Write-Status "$Name 无需执行更改，退出代码：$exitCode"
        return $null
    }
    if ($SuccessExitCodes -notcontains $exitCode) {
        Write-Status "$Name 执行失败，退出代码：$exitCode" 'Error'
        return $false
    }
    return $true
}

function Select-Numbers {
    param([string]$Prompt, [int]$Count)
    Write-Host "`n输入序号，可用逗号分隔或选择范围，例如 1,3,5-7。"
    Write-Host '输入 all 选择全部；输入 0 或直接按回车返回。'
    while ($true) {
        $inputText = (Read-Host $Prompt).Trim()
        if ($inputText -eq '0' -or $inputText -eq '') { return @() }
        if ($inputText -ieq 'all') { return @(1..$Count) }
        $indices = New-Object 'System.Collections.Generic.HashSet[int]'
        $valid = $true
        foreach ($part in ($inputText -split '[,，\s]+')) {
            if ($part -match '^(\d+)-(\d+)$') {
                $from = [int]$Matches[1]
                $to = [int]$Matches[2]
                if ($from -lt 1 -or $to -gt $Count -or $from -gt $to) { $valid = $false; break }
                foreach ($index in $from..$to) { [void]$indices.Add($index) }
            }
            elseif ($part -match '^\d+$') {
                $index = [int]$part
                if ($index -lt 1 -or $index -gt $Count) { $valid = $false; break }
                [void]$indices.Add($index)
            }
            else { $valid = $false; break }
        }
        if ($valid -and $indices.Count -gt 0) { return @($indices | Sort-Object) }
        Write-Status "无效的序号，请输入 1 到 $Count 之间的数字。" 'Warn'
    }
}

function Confirm-Selection {
    if ($Yes) { return $true }
    return (Read-Host '确认执行？输入 y 确认，直接按回车取消').Trim() -ieq 'y'
}

function Show-Page {
    param([string]$Title)
    if (-not [Console]::IsOutputRedirected) { Clear-Host }
    Write-Host 'Windows 装机助手' -ForegroundColor Cyan
    Write-Host "$Title`n"
}

function Read-MenuChoice {
    param([int]$Count, [string]$Prompt = '请选择（0 或回车返回）')
    while ($true) {
        $choice = (Read-Host $Prompt).Trim()
        if ($choice -eq '') { return '0' }
        $number = 0
        if ($choice -match '^\d+$' -and [int]::TryParse($choice, [ref]$number) -and $number -ge 0 -and $number -le $Count) {
            return [string]$number
        }
        Write-Host '请输入菜单中的序号。' -ForegroundColor Yellow
    }
}

function Wait-ForMenu {
    [void](Read-Host "`n按回车返回菜单")
}

function Show-Packages {
    param([object[]]$Items = $script:PackageCatalog, [switch]$Detailed)
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $item = $Items[$i]
        Write-Host ('{0,2}. {1}  {2}' -f ($i + 1), $item.name, $item.description)
        if ($Detailed) { Write-Host ('    软件编号：{0}；分类：{1}' -f $item.id, $item.category) }
    }
}

function Get-RequestedPackages {
    param([string[]]$Ids, [object[]]$Catalog = $script:PackageCatalog)
    $selected = @()
    foreach ($id in $Ids) {
        $item = $Catalog | Where-Object { $_.id -ieq $id } | Select-Object -First 1
        if (-not $item) { throw "未知的软件 ID：$id。请查看对应的软件清单。" }
        if (@($selected | Where-Object { $_.id -eq $item.id }).Count -eq 0) { $selected += $item }
    }
    return @($selected)
}

function Select-Packages {
    param([object[]]$Catalog)
    Show-Packages $Catalog
    $indices = @(Select-Numbers -Prompt '选择需要安装的软件' -Count $Catalog.Count)
    if ($indices.Count -eq 0) { return }
    Install-Packages @($indices | ForEach-Object { $Catalog[$_ - 1] })
}

function Test-Installed {
    param([string]$Id)
    $winget = Find-Tool 'winget'
    $output = & $winget list --id $Id --exact --accept-source-agreements 2>&1
    if ($LASTEXITCODE -ne 0) { return $false }
    $escaped = [regex]::Escape($Id)
    return [regex]::IsMatch(($output -join "`n"), ('(?im)(?<![\w.\-]){0}(?![\w.\-])' -f $escaped))
}

function Install-Packages {
    param([object[]]$Items)
    if ($Items.Count -eq 0) { Write-Status '没有选中软件。'; return }
    if (-not $script:DryRunEnabled -and -not (Find-Tool 'winget')) {
        throw '缺少 winget。请先从 Microsoft Store 安装“应用安装程序”(App Installer)。'
    }
    $conflicts = @('OpenJS.NodeJS.LTS', 'CoreyButler.NVMforWindows')
    $selectedIds = @($Items | ForEach-Object { $_.id })
    if (@($conflicts | Where-Object { $selectedIds -contains $_ }).Count -eq 2) {
        if ($Yes) { throw 'Node.js LTS 与 nvm for Windows 请二选一。' }
        Write-Status 'Node.js LTS 与 nvm for Windows 请二选一，本次未安装任何软件。' 'Warn'
        return
    }
    if (-not $script:DryRunEnabled) {
        foreach ($id in $conflicts) {
            $other = $conflicts | Where-Object { $_ -ne $id }
            if (($selectedIds -contains $id) -and (Test-Installed $other)) {
                if ($Yes) { throw "已安装 $other，请先卸载后再安装 $id。" }
                Write-Status "检测到已安装 $other，与 $id 存在冲突，本次未安装任何软件。" 'Warn'
                return
            }
        }
    }
    $pendingItems = @()
    foreach ($item in $Items) {
        Write-Status "检查是否已安装：$($item.name)"
        if (-not $script:DryRunEnabled -and (Test-Installed $item.id)) {
            Write-Status "已安装：$($item.name)"
            Write-Result $item.name $null
            continue
        }
        $pendingItems += $item
    }
    if ($pendingItems.Count -eq 0) { return }
    Write-Host "`n准备安装：$($pendingItems.name -join '、')"
    if (-not (Confirm-Selection)) { return }
    for ($i = 0; $i -lt $pendingItems.Count; $i++) {
        $item = $pendingItems[$i]
        Write-Status ('安装 {0}/{1}：{2}' -f ($i + 1), $pendingItems.Count, $item.name)
        $result = Invoke-Tool 'winget' @('install', '--id', $item.id, '--exact', '--source', 'winget', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
        Write-Result $item.name $result
    }
    if (-not $script:DryRunEnabled) {
        $paths = @([Environment]::GetEnvironmentVariable('Path', 'Machine'), [Environment]::GetEnvironmentVariable('Path', 'User'), $env:PATH)
        $env:PATH = (($paths -join ';') -split ';' | Where-Object { $_ } | Select-Object -Unique) -join ';'
    }
}

function Get-MirrorOption {
    param([string]$Manager, [string]$Key)
    $config = $script:MirrorCatalog.$Manager
    if ($null -eq $config) { throw "未知的包管理器：$Manager" }
    if ($Key -eq 'Auto') { $Key = $config.recommended }
    $option = $config.options | Where-Object { $_.key -ieq $Key } | Select-Object -First 1
    if (-not $option) { throw "$Manager 不支持 $Key 下载源，请选择该工具支持的地址。" }
    return $option
}

function Get-RequestedManagers {
    param([string[]]$Names)
    if ($Names.Count -eq 0) { return @($script:ManagerNames) }
    $selected = @()
    foreach ($name in $Names) {
        $found = $script:ManagerNames | Where-Object { $_ -ieq $name } | Select-Object -First 1
        if (-not $found) { throw "未知的包管理器：$name" }
        if ($selected -notcontains $found) { $selected += $found }
    }
    return @($selected)
}

function Get-PythonCommand {
    if ((Find-Tool 'python')) { return 'python' }
    if ((Find-Tool 'py')) { return 'py' }
    return $null
}

function Set-UserVariable {
    param([string]$Name, [AllowNull()][string]$Value)
    if ($script:DryRunEnabled) {
        if ([string]::IsNullOrEmpty($Value)) { Write-Status "[预演] 清除用户环境变量 $Name" }
        else { Write-Status "[预演] 设置用户环境变量 $Name=$Value" }
        return $true
    }
    $environmentValue = if ([string]::IsNullOrEmpty($Value)) { [System.Management.Automation.Language.NullString]::Value } else { $Value }
    [Environment]::SetEnvironmentVariable($Name, $environmentValue, 'User')
    [Environment]::SetEnvironmentVariable($Name, $environmentValue, 'Process')
    Write-Status "用户环境变量已更新：$Name" 'Success'
    return $true
}

function Get-CargoTemplate {
    param([string]$Url, [switch]$Legacy)
    $header = if ($Legacy) { '# Managed by WinDevPicker. Delete this file to use the default crates.io source.' } else { '# 由 Windows 装机助手管理，删除此文件即可恢复 crates.io 官方源。' }
    $sourceName = if ($Legacy) { 'win-dev-picker' } else { 'windows-setup-helper' }
    return (@(
        $header,
        '[source.crates-io]',
        ('replace-with = "{0}"' -f $sourceName),
        '',
        ('[source.{0}]' -f $sourceName),
        ('registry = "{0}"' -f $Url),
        '',
        ('[registries.{0}]' -f $sourceName),
        ('index = "{0}"' -f $Url),
        ''
    ) -join "`n")
}

function Set-CargoMirror {
    param([AllowNull()][string]$Url)
    $cargoHome = if ($env:CARGO_HOME) { $env:CARGO_HOME } else { Join-Path $HOME '.cargo' }
    $file = Join-Path $cargoHome 'config.toml'
    if ($script:DryRunEnabled) {
        Write-Status ("[预演] 配置文件：{0}；地址：{1}" -f $file, $(if ($Url) { $Url } else { '恢复官方' }))
        return $true
    }
    $legacyFile = Join-Path $cargoHome 'config'
    if (Test-Path -LiteralPath $legacyFile) {
        Write-Status "跳过 Cargo：$legacyFile 优先于 config.toml，请手动维护该配置。" 'Warn'
        return $null
    }
    if (Test-Path -LiteralPath $file) {
        $old = Get-Content -LiteralPath $file -Raw -Encoding UTF8
        $managedTemplates = @($script:MirrorCatalog.cargo.options | Where-Object { $_.key -ne 'Official' } | ForEach-Object {
            Get-CargoTemplate $_.url
            Get-CargoTemplate $_.url -Legacy
        })
        if ($managedTemplates -cnotcontains $old) {
            Write-Status "跳过 Cargo：$file 已存在自定义内容，请手动维护 [source.crates-io] 配置。" 'Warn'
            return $null
        }
    }
    if (-not $Url) {
        if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
        Write-Status 'Cargo 已恢复使用默认 crates.io。' 'Success'
        return $true
    }
    if (-not (Test-Path -LiteralPath $cargoHome)) { New-Item -Path $cargoHome -ItemType Directory -Force | Out-Null }
    $content = Get-CargoTemplate $Url
    [System.IO.File]::WriteAllText($file, $content, [System.Text.UTF8Encoding]::new($false))
    Write-Status "Cargo 下载源已保存：$file" 'Success'
    return $true
}

function Set-WingetMirror {
    param([AllowNull()][string]$Url)
    if ($script:DryRunEnabled) {
        if ($Url) { Write-Status "[预演] WinGet winget 源修改为 $Url" }
        else { Write-Status '[预演] WinGet winget 源恢复默认' }
        return $true
    }
    if (-not (Find-Tool 'winget')) {
        Write-Status '未找到 winget，跳过 WinGet 下载源设置。' 'Warn'
        return $null
    }
    if (-not (Test-Administrator)) {
        Write-Status 'WinGet 修改源需要管理员权限。请以管理员身份运行终端后重试。' 'Warn'
        return $null
    }
    $winget = Find-Tool 'winget'
    $versionText = (& $winget --version | Out-String).Trim()
    $versionMatch = [regex]::Match($versionText, 'v?(\d+)\.(\d+)')
    if ($LASTEXITCODE -ne 0 -or -not $versionMatch.Success) {
        throw '无法获取 WinGet 版本，已取消修改下载源。'
    }
    $major = [int]$versionMatch.Groups[1].Value
    $minor = [int]$versionMatch.Groups[2].Value
    $supportsTrustLevel = ($major -gt 1 -or ($major -eq 1 -and $minor -ge 8))
    if (-not $Url) {
        return (Invoke-Tool 'winget' @('source', 'reset', '--name', 'winget', '--force'))
    }
    $oldSourceOutput = & $winget source export --name winget 2>&1
    if ($LASTEXITCODE -ne 0) { throw '无法读取当前 WinGet 源，已取消修改。' }
    $oldSource = ($oldSourceOutput -join "`n") | ConvertFrom-Json
    if ($oldSource.Arg -eq $Url) { Write-Status 'WinGet 已使用所选下载源。'; return $null }
    if (-not (Invoke-Tool 'winget' @('source', 'remove', '--name', 'winget'))) { return $false }
    $newArgs = @('source', 'add', '--name', 'winget', '--arg', $Url)
    if ($supportsTrustLevel) { $newArgs += @('--trust-level', 'trusted') }
    $newArgs += '--accept-source-agreements'
    if (Invoke-Tool 'winget' $newArgs) { return $true }
    Write-Status '添加下载源失败，尝试恢复原有 WinGet 源。' 'Warn'
    $restoreArgs = @('source', 'add', '--name', 'winget', '--arg', [string]$oldSource.Arg)
    if ($oldSource.Type) { $restoreArgs += @('--type', [string]$oldSource.Type) }
    if ($supportsTrustLevel -and @($oldSource.TrustLevel) -contains 'Trusted') { $restoreArgs += @('--trust-level', 'trusted') }
    $restoreArgs += '--accept-source-agreements'
    [void](Invoke-Tool 'winget' $restoreArgs)
    return $false
}

function Set-YarnMirror {
    param([AllowNull()][string]$Url)
    if ($script:DryRunEnabled) {
        if ($Url) { Write-Status "[预演] 设置 Yarn 下载源：$Url" }
        else { Write-Status '[预演] 恢复 Yarn 官方下载源' }
        return $true
    }
    $tool = Find-Tool 'yarn'
    if (-not $tool) { Write-Status '未安装 yarn，跳过。' 'Warn'; return $null }
    $versionOutput = & $tool --version
    $versionMatch = [regex]::Match(($versionOutput | Out-String).Trim(), '^(\d+)\.')
    if ($LASTEXITCODE -ne 0 -or -not $versionMatch.Success) {
        Write-Status '无法获取 Yarn 版本，跳过。' 'Warn'
        return $null
    }
    $major = [int]$versionMatch.Groups[1].Value
    if ($major -eq 1) {
        if ($Url) { return (Invoke-Tool 'yarn' @('config', 'set', 'registry', $Url)) }
        return (Invoke-Tool 'yarn' @('config', 'delete', 'registry'))
    }
    else {
        if ($Url) { return (Invoke-Tool 'yarn' @('config', 'set', 'npmRegistryServer', $Url, '--home')) }
        return (Invoke-Tool 'yarn' @('config', 'unset', 'npmRegistryServer', '--home'))
    }
}

function Set-ManagerMirror {
    param([string]$Manager, [AllowNull()][string]$Url)
    Write-Status "处理：$Manager"
    switch ($Manager) {
        'winget' { Set-WingetMirror $Url }
        'pip' {
            $python = if ($script:DryRunEnabled) { 'python' } else { Get-PythonCommand }
            if (-not $python) { Write-Status '未安装 Python，跳过 pip。' 'Warn'; return $null }
            $index = if ($Url) { $Url } else { 'https://pypi.org/simple' }
            return (Invoke-Tool $python @('-m', 'pip', 'config', '--user', 'set', 'global.index-url', $index))
        }
        'uv' { Set-UserVariable 'UV_DEFAULT_INDEX' $Url }
        'npm' {
            if ($Url) { return (Invoke-Tool 'npm' @('config', 'set', 'registry', $Url, '--location=user')) }
            return (Invoke-Tool 'npm' @('config', 'delete', 'registry', '--location=user'))
        }
        'pnpm' {
            if ($Url) { return (Invoke-Tool 'pnpm' @('config', 'set', 'registry', $Url, '--global')) }
            return (Invoke-Tool 'pnpm' @('config', 'delete', 'registry', '--global'))
        }
        'yarn' { Set-YarnMirror $Url }
        'go' {
            if ($Url) { return (Invoke-Tool 'go' @('env', '-w', "GOPROXY=$Url,direct")) }
            return (Invoke-Tool 'go' @('env', '-u', 'GOPROXY'))
        }
        'cargo' { Set-CargoMirror $Url }
        default { throw "未知的包管理器：$Manager" }
    }
}

function Invoke-MirrorPlan {
    param([object[]]$Plan)
    foreach ($item in $Plan) {
        $url = if ($item.Key -eq 'Official') { $null } else { [string]$item.Url }
        $result = Set-ManagerMirror $item.Manager $url
        Write-Result $item.Manager $result
    }
}

function Show-MirrorPlan {
    param([object[]]$Plan)
    Write-Host "`n本次软件下载源设置："
    foreach ($item in $Plan) { Write-Host ('  {0,-7} {1,-12} {2}' -f $item.Manager, $item.Name, $item.Url) }
    if (-not $script:DryRunEnabled -and @($Plan | Where-Object { $_.Manager -eq 'winget' }).Count -gt 0 -and -not (Test-Administrator)) {
        Write-Host 'WinGet 源修改需要管理员权限，本次会跳过该项；需要修改时请以管理员身份启动。' -ForegroundColor Yellow
    }
    Write-Host '这些地址供 WinGet 和开发工具查询软件或下载软件包，不用于下载 Windows 系统镜像。'
}

function New-MirrorPlan {
    param([string[]]$Names, [string]$Key)
    $plan = @()
    foreach ($manager in $Names) {
        $option = Get-MirrorOption $manager $Key
        $plan += [pscustomobject]@{ Manager = $manager; Key = $option.key; Name = $option.name; Url = $option.url }
    }
    return @($plan)
}

function Read-MirrorSelection {
    param([string[]]$Names)
    $plan = @()
    foreach ($manager in $Names) {
        $config = $script:MirrorCatalog.$manager
        Show-Page "软件下载源 / $manager"
        for ($i = 0; $i -lt $config.options.Count; $i++) {
            $option = $config.options[$i]
            $preferred = if ($option.key -eq $config.recommended) { '（推荐）' } else { '' }
            Write-Host ('  {0}. {1}{2}  {3}' -f ($i + 1), $option.name, $preferred, $option.url)
        }
        $choice = Read-MenuChoice -Count $config.options.Count -Prompt '选择一个下载源（0 或回车跳过此工具）'
        if ($choice -eq '0') { continue }
        $option = $config.options[[int]$choice - 1]
        $plan += [pscustomobject]@{ Manager = $manager; Key = $option.key; Name = $option.name; Url = $option.url }
    }
    return @($plan)
}

function Show-MirrorMenu {
    while ($true) {
        Show-Page '软件下载源'
        Write-Host '设置 WinGet、Python、Node.js 等工具下载软件包时使用的地址。'
        Write-Host "`n1. 使用推荐的国内下载源"
        Write-Host '2. 自选工具和下载源'
        Write-Host '3. 恢复官方下载源'
        Write-Host "`n0. 返回主菜单"
        $choice = Read-MenuChoice -Count 3
        if ($choice -eq '0') { return }
        Show-Page '软件下载源'
        $before = @($script:Succeeded, $script:Skipped, $script:Failed)
        $logCount = $script:LogLines.Count
        switch ($choice) {
            '1' {
                $plan = @(New-MirrorPlan -Names $script:ManagerNames -Key 'Auto')
                Show-MirrorPlan $plan
                if (Confirm-Selection) { Invoke-MirrorPlan $plan }
            }
            '2' {
                for ($i = 0; $i -lt $script:ManagerNames.Count; $i++) { Write-Host ('{0}. {1}' -f ($i + 1), $script:ManagerNames[$i]) }
                $indices = @(Select-Numbers -Prompt '选择需要设置下载源的工具' -Count $script:ManagerNames.Count)
                if ($indices.Count -eq 0) { break }
                $names = @($indices | ForEach-Object { $script:ManagerNames[$_ - 1] })
                $plan = @(Read-MirrorSelection $names)
                if ($plan.Count -gt 0) {
                    Show-Page '软件下载源 / 确认设置'
                    Show-MirrorPlan $plan
                    if (Confirm-Selection) { Invoke-MirrorPlan $plan }
                }
            }
            '3' {
                for ($i = 0; $i -lt $script:ManagerNames.Count; $i++) { Write-Host ('{0}. {1}' -f ($i + 1), $script:ManagerNames[$i]) }
                $indices = @(Select-Numbers -Prompt '选择需要恢复官方下载源的工具' -Count $script:ManagerNames.Count)
                if ($indices.Count -eq 0) { break }
                $names = @($indices | ForEach-Object { $script:ManagerNames[$_ - 1] })
                $plan = @(New-MirrorPlan -Names $names -Key 'Official')
                Show-MirrorPlan $plan
                if (Confirm-Selection) { Invoke-MirrorPlan $plan }
            }
        }
        if ($script:LogLines.Count -gt $logCount) {
            Show-Summary -Succeeded ($script:Succeeded - $before[0]) -Skipped ($script:Skipped - $before[1]) -Failed ($script:Failed - $before[2])
            Wait-ForMenu
        }
    }
}

function Show-Menu {
    while ($true) {
        Show-Page '主菜单'
        Write-Host '准备重装系统，从第 1 项开始；系统已经装好，从第 2 项开始。'
        Write-Host "`n1. 重装前准备     备份文件、下载系统镜像、制作启动 U 盘"
        Write-Host '2. 安装后设置     安装驱动、更新 Windows、激活和调整设置'
        Write-Host '3. 安装日常软件   聊天、办公、浏览器等'
        Write-Host '4. 安装开发软件   编辑器、编程语言和开发工具'
        Write-Host '5. 软件下载源     使用国内下载源或恢复官方地址'
        Write-Host "`n0. 退出"
        $choice = Read-MenuChoice -Count 5 -Prompt '请选择（0 或回车退出）'
        $before = @($script:Succeeded, $script:Skipped, $script:Failed)
        $logCount = $script:LogLines.Count
        switch ($choice) {
            '1' { Show-PreparationMenu }
            '2' { Show-SystemMenu }
            '3' { Show-Page '安装日常软件'; Select-Packages $script:AppCatalog }
            '4' { Show-Page '安装开发软件'; Select-Packages $script:PackageCatalog }
            '5' { Show-MirrorMenu }
            '0' { return }
        }
        if ($choice -in @('3', '4') -and $script:LogLines.Count -gt $logCount) {
            Show-Summary -Succeeded ($script:Succeeded - $before[0]) -Skipped ($script:Skipped - $before[1]) -Failed ($script:Failed - $before[2])
            Wait-ForMenu
        }
    }
}

if (-not $script:DryRunEnabled -and $env:OS -ne 'Windows_NT') {
    throw 'Windows 装机助手仅支持 Windows。其他系统可使用 -DryRun 查看操作计划。'
}

$completed = $false
try {
    if (($FullOptimization -or $MachineOnly) -and $Action -ne 'Optimize') { throw '优化参数需要与 -Action Optimize 一起使用。' }
    switch ($Action) {
        'List' { Show-Packages -Detailed }
        'AppList' { Show-Packages $script:AppCatalog -Detailed }
        'Prepare' { Show-PreparationMenu }
        'System' { Show-SystemMenu }
        'Optimize' { Invoke-SystemOptimization -Full:$FullOptimization -MachineOnly:$MachineOnly }
        'Apps' {
            if ($PackageIds.Count -gt 0) { Install-Packages @(Get-RequestedPackages $PackageIds $script:AppCatalog) }
            else { Select-Packages $script:AppCatalog }
        }
        'Install' {
            if ($PackageIds.Count -eq 0) { throw '请使用 -PackageIds 指定至少一个软件 ID，或运行交互式菜单。' }
            $items = @(Get-RequestedPackages $PackageIds)
            Install-Packages $items
        }
        'Mirrors' {
            $names = @(Get-RequestedManagers $Managers)
            $plan = @(New-MirrorPlan -Names $names -Key $Mirror)
            Show-MirrorPlan $plan
            if (Confirm-Selection) { Invoke-MirrorPlan $plan }
        }
        'Restore' {
            $names = @(Get-RequestedManagers $Managers)
            $plan = @(New-MirrorPlan -Names $names -Key 'Official')
            Show-MirrorPlan $plan
            if (Confirm-Selection) { Invoke-MirrorPlan $plan }
        }
        'Menu' { Show-Menu }
    }
    $completed = $true
}
finally {
    Save-Log
    if ($completed -and $Action -notin @('Menu', 'Prepare', 'System') -and $script:LogLines.Count -gt 0) { Show-Summary }
    elseif ($script:LogFile) { Write-Host "运行记录：$script:LogFile" }
}
if ($script:Failed -gt 0) { exit 1 }
