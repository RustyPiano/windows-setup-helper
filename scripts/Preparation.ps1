function Select-SetupPath {
    param([string]$Title, [switch]$File)
    Add-Type -AssemblyName System.Windows.Forms
    if ($File) {
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = $Title
        $dialog.Filter = '系统镜像文件（*.iso）|*.iso'
        $dialog.CheckFileExists = $true
        $dialog.RestoreDirectory = $true
    }
    else {
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = $Title
        $dialog.RootFolder = [Environment+SpecialFolder]::MyComputer
        $dialog.ShowNewFolderButton = -not $script:DryRunEnabled
    }
    try {
        if ($dialog.ShowDialog() -ne 'OK') { return $null }
        if ($File) { return $dialog.FileName }
        return $dialog.SelectedPath
    }
    finally { $dialog.Dispose() }
}

function Get-SetupFolder {
    if (-not $script:SetupFolder) {
        $folder = Select-SetupPath '选择系统镜像和工具的保存文件夹'
        if (-not $folder) { return $null }
        $script:SetupFolder = $folder
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
    $folder = Get-SetupFolder
    if (-not $folder) { return $null }
    $file = Join-Path $folder $Name
    Write-Status "下载：$Name"
    Write-Status "保存到：$file"
    Write-Status "下载地址：$Uri" -LogOnly
    if ($script:DryRunEnabled) { return $file }
    Invoke-WebRequest -Uri $Uri -OutFile ($file + '.download') -UseBasicParsing -TimeoutSec 120
    if ($SHA256 -and (Get-FileHash -LiteralPath ($file + '.download') -Algorithm SHA256).Hash -ne $SHA256) { throw "文件校验失败：$Name" }
    Move-Item -LiteralPath ($file + '.download') -Destination $file -Force
    return $file
}

function Start-WindowsDownload {
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') {
        Open-SetupPage '微软系统镜像下载页（适用于 Arm 处理器电脑）' 'https://www.microsoft.com/zh-cn/software-download/windows11arm64'
        return
    }
    Write-Host '系统镜像是安装 Windows 使用的 ISO 文件。'
    Write-Host '在微软媒体创建工具中选择“为另一台电脑创建安装介质”，再选择“ISO 文件”。'
    if (-not (Confirm-Selection)) { return }
    $file = Receive-SetupFile 'https://go.microsoft.com/fwlink/?linkid=2156295' 'MediaCreationTool.exe'
    if (-not $file) { return }
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
    if (-not $asset -or $asset.digest -notmatch '^sha256:([a-fA-F0-9]{64})$') { throw "未找到包含文件校验信息的 $Name 安装文件。" }
    $file = Receive-SetupFile $asset.browser_download_url $asset.name $asset.digest.Substring(7)
    if (-not $file) { return }
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
    if ($ExpectedHash -notmatch '^[a-fA-F0-9]{64}$') { throw '校验值应为 64 个字符，请完整复制微软下载页中对应文件的校验值。' }
    Write-Status "检查系统镜像是否下载完整：$Path"
    if ($script:DryRunEnabled) { return }
    $actualHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actualHash -ne $ExpectedHash) { throw "系统镜像校验失败，文件与微软公布的内容不一致。实际校验值：$actualHash" }
    Write-Result '系统镜像完整性检查' $true
}

function Backup-UserFiles {
    param([string]$Source, [string]$Destination, [switch]$ContentsOnly, [switch]$PreparationKit)
    $Source = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Source)
    $Destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
    $sourcePath = $Source.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $destinationPath = $Destination.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $separator = [IO.Path]::DirectorySeparatorChar
    if ($sourcePath -eq $destinationPath -or $destinationPath.StartsWith($sourcePath + $separator, [StringComparison]::OrdinalIgnoreCase) -or $sourcePath.StartsWith($destinationPath + $separator, [StringComparison]::OrdinalIgnoreCase)) { throw '备份来源和目标目录不能相同，也不能互相包含。' }
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "来源文件夹不存在：$Source" }
    $target = $null
    if ($PreparationKit) {
        $target = Get-Content -LiteralPath (Join-Path $Source 'target.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if (Test-Path -LiteralPath $Destination) {
            if (-not (Test-Path -LiteralPath $Destination -PathType Container)) { throw '资料保存位置已被同名文件占用，请选择其他位置。' }
            $targetFile = Join-Path $Destination 'target.json'
            if (Test-Path -LiteralPath $targetFile) {
                $existing = Get-Content -LiteralPath $targetFile -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($existing.Architecture -ne $target.Architecture -or $existing.Model -ne $target.Model -or $existing.IsCurrent -ne $target.IsCurrent) {
                    throw '保存位置属于其他目标电脑，请选择其他位置。'
                }
            }
            elseif (@(Get-ChildItem -LiteralPath $Destination -Force).Count -gt 0) { throw '保存位置已有文件，但没有目标电脑信息，无法确认是否属于本次准备，请选择其他位置。' }
        }
    }
    elseif (-not $ContentsOnly) {
        $name = if ($sourcePath -match '^[A-Za-z]:$') { $sourcePath.Substring(0, 1) } else { [IO.Path]::GetFileName($sourcePath) }
        $Destination = Join-Path $destinationPath $name
        $number = 2
        while (Test-Path -LiteralPath $Destination) {
            $Destination = Join-Path $destinationPath ("$name ($number)")
            $number++
        }
    }
    Write-Host "备份来源：$Source`n备份目标：$Destination"
    if (-not (Confirm-Selection)) { return }
    if (-not $script:DryRunEnabled) {
        if ($PreparationKit) {
            [void](New-Item -ItemType Directory -Path $Destination -Force)
            $targetValues = @{}
            foreach ($property in $target.PSObject.Properties) { $targetValues[$property.Name] = $property.Value }
            # 复制大文件前保存目标信息，让中断后的目录能够被识别并继续使用。
            Save-PreparationTarget $Destination $targetValues
        }
        elseif (-not $ContentsOnly) { [void](New-Item -ItemType Directory -Path $Destination) }
    }
    $arguments = @($Source, $Destination, '/E', '/COPY:DAT', '/DCOPY:DAT', '/XJ', '/SL', '/R:0', '/W:0')
    if ($PreparationKit) { $arguments += '/Z' }
    $result = Invoke-Tool 'robocopy' $arguments -SuccessExitCodes (0..7)
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
    $folder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath((Join-Path $Destination 'WindowsSetupHelper'))
    $sourceFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($script:ProjectRoot)
    if ($folder -eq $sourceFolder) { Write-Status '助手已保存在该目录。'; Write-Result '保存安装后助手' $null; return }
    if ($folder.StartsWith($sourceFolder.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw '请选择助手所在目录之外的位置。' }
    Write-Host "保存 Windows 装机助手：$folder"
    if (-not (Confirm-Selection)) { return }
    if ($script:DryRunEnabled) { Write-Status "[预演] 复制助手到 $folder"; return }
    [void](New-Item -ItemType Directory -Path $folder -Force)
    foreach ($name in @('Launch.cmd', 'Launch-Online.cmd', 'Start-DevSetup.ps1', 'README.md', 'data', 'scripts', 'docs')) {
        Copy-Item -LiteralPath (Join-Path $script:ProjectRoot $name) -Destination $folder -Recurse -Force
    }
    Write-Status "安装后运行 $folder\Launch.cmd，可在离线状态下安装备份的驱动。"
    Write-Result '保存 Windows 装机助手' $true
}

function Show-InstallationGuide {
    Write-Host @'
1. 将个人文件和驱动备份保存到重装时保留的磁盘或 U 盘。
2. 下载系统镜像（ISO 文件），在 Rufus 或 Ventoy 中制作启动盘。
3. 重启电脑，从电脑厂商提供的启动菜单选择 U 盘。
4. 按 Windows 安装程序选择系统版本和安装分区，格式化会清除对应分区的数据。
5. 系统安装完成后，运行 U 盘中 WindowsSetupHelper\Launch.cmd，安装备份驱动后联网。
'@
}

function Show-PreparationMenu {
    while ($true) {
        Show-Page '重装前准备'
        Write-Host '备份文件和驱动'
        Write-Host '1. 备份个人文件夹'
        Write-Host '2. 备份第三方驱动'
        Write-Host "`n准备系统镜像和启动盘"
        Write-Host '3. 下载 Windows 系统镜像（ISO 文件）'
        Write-Host '4. 打开微软系统镜像下载页'
        Write-Host '5. 检查已有系统镜像是否完整'
        Write-Host '6. Rufus：将一个系统镜像写入 U 盘'
        Write-Host '7. Ventoy：在启动 U 盘中保存多个系统镜像'
        Write-Host "`n重装时使用"
        Write-Host '8. 将助手保存到 U 盘，供安装系统后使用'
        Write-Host '9. 查看 Windows 安装步骤'
        Write-Host "`n0. 返回主菜单"
        $choice = Read-MenuChoice -Count 9
        if ($choice -eq '0') { return }
        Show-Page '重装前准备 / 当前操作'
        $before = @($script:Succeeded, $script:Skipped, $script:Failed)
        $logCount = $script:LogLines.Count
        switch ($choice) {
            '1' {
                $source = Select-SetupPath '选择需要备份的文件夹'
                if (-not $source) { break }
                $destination = Select-SetupPath '选择备份保存位置（重装时会保留的磁盘或 U 盘）'
                if ($destination) { Backup-UserFiles $source $destination }
            }
            '2' {
                $destination = Select-SetupPath '选择驱动备份的保存位置（重装时会保留的磁盘或 U 盘）'
                if ($destination) { Export-SetupDrivers $destination }
            }
            '3' { Start-WindowsDownload }
            '4' { Open-SetupPage '微软系统镜像下载页' 'https://www.microsoft.com/zh-cn/software-download/windows11' }
            '5' {
                $path = Select-SetupPath '选择需要检查的系统镜像' -File
                if (-not $path) { break }
                $hash = (Read-Host '请粘贴微软下载页“验证你的下载”中对应文件的校验值；回车返回').Trim()
                if ($hash) { Test-IsoFile $path $hash }
            }
            '6' { Start-BootTool 'Rufus' }
            '7' { Start-BootTool 'Ventoy' }
            '8' {
                $destination = Select-SetupPath '选择 U 盘中的保存位置'
                if ($destination) { Copy-SetupLauncher $destination }
            }
            '9' { Show-InstallationGuide }
        }
        if ($choice -eq '9' -or $script:LogLines.Count -gt $logCount) {
            Show-Summary -Succeeded ($script:Succeeded - $before[0]) -Skipped ($script:Skipped - $before[1]) -Failed ($script:Failed - $before[2])
            Wait-ForMenu
        }
    }
}
