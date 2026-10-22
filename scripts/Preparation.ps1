function Get-SetupFolder {
    if (-not $script:SetupFolder) {
        $defaultFolder = Join-Path $HOME 'Downloads/WinDevPicker'
        $folder = (Read-Host "镜像和工具保存目录（回车使用 $defaultFolder）").Trim().Trim('"')
        $selectedFolder = if ($folder) { $folder } else { $defaultFolder }
        $script:SetupFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($selectedFolder)
    }
    if (-not $script:DryRunEnabled) { [void](New-Item -ItemType Directory -Path $script:SetupFolder -Force) }
    return $script:SetupFolder
}

function Open-SetupPage {
    param([string]$Name, [string]$Uri)
    Write-Status "打开：$Name；$Uri"
    if ($script:DryRunEnabled) { return }
    Start-Process -FilePath $Uri
    Write-Result $Name $true
}

function Start-SetupProgram {
    param([string]$Name, [string]$FilePath, [string[]]$Arguments = @())
    Write-Status ("启动：{0}；{1} {2}" -f $Name, $FilePath, ($Arguments -join ' '))
    if ($script:DryRunEnabled) { return }
    $parameters = @{ FilePath = $FilePath; WorkingDirectory = (Split-Path $FilePath -Parent); Wait = $true; PassThru = $true }
    if ($Arguments.Count -gt 0) { $parameters.ArgumentList = $Arguments }
    $process = Start-Process @parameters
    Write-Status "$Name 已退出，退出代码：$($process.ExitCode)"
    Write-Result "运行 $Name" ($process.ExitCode -eq 0)
}

function Receive-SetupFile {
    param([string]$Uri, [string]$Name, [string]$SHA256 = '')
    $file = Join-Path (Get-SetupFolder) $Name
    Write-Status "下载：$Uri；保存到：$file"
    if ($script:DryRunEnabled) { return $file }
    Invoke-WebRequest -Uri $Uri -OutFile ($file + '.download') -UseBasicParsing -TimeoutSec 120
    if ($SHA256 -and (Get-FileHash -LiteralPath ($file + '.download') -Algorithm SHA256).Hash -ne $SHA256) { throw "文件校验失败：$Name" }
    Move-Item -LiteralPath ($file + '.download') -Destination $file -Force
    return $file
}

function Start-WindowsDownload {
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') {
        Open-SetupPage '微软 Arm64 ISO 下载页' 'https://www.microsoft.com/zh-cn/software-download/windows11arm64'
        return
    }
    Write-Host '在微软媒体创建工具中选择“为另一台电脑创建安装介质”，再选择“ISO 文件”。'
    Write-Host 'Arm64 镜像请使用菜单中的微软官方下载页。'
    if (-not (Confirm-Selection)) { return }
    $file = Receive-SetupFile 'https://go.microsoft.com/fwlink/?linkid=2156295' 'MediaCreationTool.exe'
    if (-not $script:DryRunEnabled) {
        $signature = Get-AuthenticodeSignature -FilePath $file
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notlike '*O=Microsoft Corporation,*') { throw '微软媒体创建工具的签名验证失败。' }
    }
    Start-SetupProgram '微软媒体创建工具' $file
}

function Start-BootTool {
    param([ValidateSet('Rufus', 'Ventoy')][string]$Name)
    Write-Host '在工具界面选择目标 U 盘。写入启动盘会清除所选设备的数据，请在工具中确认设备。'
    if (-not (Confirm-Selection)) { return }
    $repository = if ($Name -eq 'Rufus') { 'pbatard/rufus' } else { 'ventoy/Ventoy' }
    $releaseUri = "https://api.github.com/repos/$repository/releases/latest"
    if ($script:DryRunEnabled) { Write-Status "[预演] 从 $releaseUri 下载并启动 $Name"; return }
    $release = Invoke-RestMethod -Uri $releaseUri -UseBasicParsing -TimeoutSec 60
    $architecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    if ($Name -eq 'Rufus') {
        $pattern = switch ($architecture) {
            'AMD64' { '^rufus-[\d.]+\.exe$' }
            'ARM64' { '^rufus-[\d.]+_arm64\.exe$' }
            'x86' { '^rufus-[\d.]+_x86\.exe$' }
            default { throw "Rufus 不支持当前架构：$architecture" }
        }
    }
    else { $pattern = '^ventoy-[\d.]+-windows\.zip$' }
    $asset = $release.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1
    if (-not $asset -or $asset.digest -notmatch '^sha256:([a-fA-F0-9]{64})$') { throw "未找到具有 SHA-256 校验值的 $Name 安装文件。" }
    $file = Receive-SetupFile $asset.browser_download_url $asset.name $asset.digest.Substring(7)
    if ($Name -eq 'Ventoy') {
        $folder = Join-Path (Get-SetupFolder) $release.tag_name
        Expand-Archive -LiteralPath $file -DestinationPath $folder -Force
        $file = (Get-ChildItem -LiteralPath $folder -Filter 'Ventoy2Disk.exe' -Recurse | Select-Object -First 1).FullName
        if ($architecture -eq 'ARM64') {
            Copy-Item -LiteralPath (Join-Path (Split-Path $file) 'altexe/Ventoy2Disk_ARM64.exe') -Destination $file -Force
        }
    }
    Start-SetupProgram $Name $file
}

function Test-IsoFile {
    param([string]$Path, [string]$ExpectedHash)
    if ($ExpectedHash -notmatch '^[a-fA-F0-9]{64}$') { throw '请输入微软公布的完整 SHA-256 校验值，共 64 个字符。' }
    Write-Status "校验镜像：$Path"
    if ($script:DryRunEnabled) { return }
    $actualHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actualHash -ne $ExpectedHash) { throw "镜像校验失败。实际 SHA-256：$actualHash" }
    Write-Result 'ISO 镜像校验' $true
}

function Backup-UserFiles {
    param([string]$Source, [string]$Destination)
    $Source = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Source)
    $Destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
    $sourcePath = $Source.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $destinationPath = $Destination.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $separator = [IO.Path]::DirectorySeparatorChar
    if ($sourcePath -eq $destinationPath -or $destinationPath.StartsWith($sourcePath + $separator, [StringComparison]::OrdinalIgnoreCase) -or $sourcePath.StartsWith($destinationPath + $separator, [StringComparison]::OrdinalIgnoreCase)) { throw '备份来源和目标目录不能相同，也不能互相包含。' }
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "来源文件夹不存在：$Source" }
    Write-Host "备份来源：$Source`n备份目标：$Destination"
    if (-not (Confirm-Selection)) { return }
    $result = Invoke-Tool 'robocopy' @($Source, $Destination, '/E', '/COPY:DAT', '/DCOPY:DAT', '/XJ', '/SL', '/R:0', '/W:0') -SuccessExitCodes (0..7)
    Write-Result '文件夹备份' $result
}

function Export-SetupDrivers {
    param([string]$Destination)
    if (-not $script:DryRunEnabled -and -not (Test-Administrator)) { throw '备份驱动需要以管理员身份运行。' }
    Write-Host "第三方驱动备份目录：$Destination"
    if (-not (Confirm-Selection)) { return }
    if (-not $script:DryRunEnabled) { [void](New-Item -ItemType Directory -Path $Destination -Force) }
    $result = Invoke-Tool 'dism' @('/Online', '/Export-Driver', "/Destination:$Destination")
    Write-Result '第三方驱动备份' $result
}

function Copy-SetupLauncher {
    param([string]$Destination)
    if (-not (Test-Path -LiteralPath $Destination -PathType Container)) { throw "目标目录不存在：$Destination" }
    $folder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath((Join-Path $Destination 'WinDevPicker'))
    $sourceFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($script:ProjectRoot)
    if ($folder -eq $sourceFolder) { Write-Status '助手已保存在该目录。'; Write-Result '保存安装后助手' $null; return }
    if ($folder.StartsWith($sourceFolder.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw '请选择助手所在目录之外的位置。' }
    Write-Host "保存安装后助手：$folder"
    if (-not (Confirm-Selection)) { return }
    if ($script:DryRunEnabled) { Write-Status "[预演] 复制助手到 $folder"; return }
    [void](New-Item -ItemType Directory -Path $folder -Force)
    foreach ($name in @('Launch.cmd', 'Launch-Online.cmd', 'Start-DevSetup.ps1', 'data', 'scripts')) {
        Copy-Item -LiteralPath (Join-Path $script:ProjectRoot $name) -Destination $folder -Recurse -Force
    }
    Write-Status "安装后运行 $folder\Launch.cmd，可在离线状态下安装备份的驱动。"
    Write-Result '保存安装后助手' $true
}

function Show-InstallationGuide {
    Write-Host @'
1. 将个人文件和驱动备份保存到重装时保留的磁盘或 U 盘。
2. 下载 ISO，在 Rufus 或 Ventoy 中制作启动盘。
3. 重启电脑，从电脑厂商提供的启动菜单选择 U 盘。
4. 按 Windows 安装程序选择系统版本和安装分区，格式化会清除对应分区的数据。
5. 系统安装完成后，运行 U 盘中 WinDevPicker\Launch.cmd，安装备份驱动后联网。
'@
}

function Show-PreparationMenu {
    while ($true) {
        Write-Host "`n装机准备"
        Write-Host '1. 查看电脑信息'
        Write-Host '2. 下载 Windows ISO（微软媒体创建工具）'
        Write-Host '3. 打开微软 ISO 下载页（含 Arm64）'
        Write-Host '4. 校验已有 ISO'
        Write-Host '5. 下载并启动 Rufus'
        Write-Host '6. 下载并启动 Ventoy'
        Write-Host '7. 备份个人文件夹'
        Write-Host '8. 备份第三方驱动'
        Write-Host '9. 保存安装后助手到 U 盘（支持离线安装备份驱动）'
        Write-Host '10. 查看系统安装步骤'
        Write-Host '0. 返回'
        $before = @($script:Succeeded, $script:Skipped, $script:Failed)
        $choice = (Read-Host '请输入操作序号').Trim()
        switch ($choice) {
            '1' { Show-SetupComputer }
            '2' { Start-WindowsDownload }
            '3' { Open-SetupPage '微软 ISO 下载页' 'https://www.microsoft.com/zh-cn/software-download/windows11' }
            '4' { Test-IsoFile ((Read-Host 'ISO 文件完整路径').Trim().Trim('"')) ((Read-Host '微软公布的 SHA-256 校验值').Trim()) }
            '5' { Start-BootTool 'Rufus' }
            '6' { Start-BootTool 'Ventoy' }
            '7' { Backup-UserFiles ((Read-Host '需要备份的文件夹').Trim().Trim('"')) ((Read-Host '备份目标目录（使用重装时保留的磁盘或 U 盘）').Trim().Trim('"')) }
            '8' { Export-SetupDrivers ((Read-Host '驱动备份目录（使用重装时保留的磁盘或 U 盘）').Trim().Trim('"')) }
            '9' { Copy-SetupLauncher ((Read-Host 'U 盘目录，例如 E:\').Trim().Trim('"')) }
            '10' { Show-InstallationGuide }
            '0' { return }
            default { Write-Status '无效的操作序号。' 'Warn'; continue }
        }
        Show-Summary -Succeeded ($script:Succeeded - $before[0]) -Skipped ($script:Skipped - $before[1]) -Failed ($script:Failed - $before[2])
    }
}
