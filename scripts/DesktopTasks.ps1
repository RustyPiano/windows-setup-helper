function Get-SetupArchitecture {
    $architecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    switch ($architecture) {
        'AMD64' { return 'x64' }
        'ARM64' { return 'arm64' }
        default { throw '请确认目标电脑支持 Windows 11，并选择 x64 或 Arm64。' }
    }
}

function Get-WindowsDownloadUrl {
    param([ValidateSet('x64', 'arm64')][string]$Architecture)
    if ($Architecture -eq 'arm64') { return 'https://www.microsoft.com/zh-cn/software-download/windows11arm64' }
    return 'https://www.microsoft.com/zh-cn/software-download/windows11'
}

function Save-PreparationTarget {
    param([string]$Folder, [hashtable]$Target)
    if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { throw '请选择存在的准备目录。' }
    if ($Target.Architecture -notin @('x64', 'arm64')) { throw '请确认目标电脑的处理器类型。' }
    if (-not $Target.IsCurrent -and [string]::IsNullOrWhiteSpace($Target.Model)) { throw '请填写另一台电脑的品牌和完整型号。' }
    $targetFile = Join-Path $Folder 'target.json'
    if (Test-Path -LiteralPath $targetFile) {
        $existing = Get-Content -LiteralPath $targetFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($existing.Architecture -ne $Target.Architecture -or $existing.Model -ne $Target.Model -or $existing.IsCurrent -ne $Target.IsCurrent) {
            throw '这个目录已有其他目标电脑的资料，请为新的目标电脑选择另一个目录。'
        }
    }
    foreach ($name in @('Images', 'Drivers', 'Software')) { [void](New-Item -ItemType Directory -Path (Join-Path $Folder $name) -Force) }
    $Target | ConvertTo-Json | Set-Content -LiteralPath $targetFile -Encoding UTF8
}

function Get-PreparationChecks {
    param([string]$Folder)
    $targetFile = Join-Path $Folder 'target.json'
    if (-not (Test-Path -LiteralPath $targetFile)) { throw '请先保存目标电脑信息。' }
    $target = Get-Content -LiteralPath $targetFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $images = @(Get-ChildItem -LiteralPath (Join-Path $Folder 'Images') -Filter '*.iso' -File | Where-Object { $_.Length -gt 0 })
    $drivers = @(Get-ChildItem -LiteralPath (Join-Path $Folder 'Drivers') -File -Recurse | Where-Object { $_.Extension -in @('.inf', '.exe', '.msi') })
    $software = @(Get-ChildItem -LiteralPath (Join-Path $Folder 'Software') -File -Recurse | Where-Object { $_.Extension -in @('.exe', '.msi', '.msix', '.msixbundle', '.appx', '.appxbundle') })
    $assistantFiles = @('Launch.cmd', 'Start-DevSetup.ps1', 'scripts/Desktop.ps1', 'scripts/DesktopTasks.ps1', 'scripts/Preparation.ps1', 'scripts/System.ps1', 'data/guide.json', 'data/apps.json', 'data/packages.json', 'data/mirrors.json', 'data/tweaks.json')
    $assistantFolder = Join-Path $Folder 'WindowsSetupHelper'
    $assistantReady = @($assistantFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $assistantFolder $_) -PathType Leaf) }).Count -eq 0
    @(
        [pscustomobject]@{ Name = 'Windows 系统镜像'; Ready = $images.Count -gt 0; Required = $true; Detail = 'Images 中需要有与目标电脑处理器匹配的 ISO 文件。' }
        [pscustomobject]@{ Name = '离线助手'; Ready = $assistantReady; Required = $true; Detail = '启动文件、功能脚本和软件清单必须完整；使用本地 Launch.cmd。' }
        [pscustomobject]@{ Name = '目标电脑驱动'; Ready = $drivers.Count -gt 0; Required = [bool]$target.Offline; Detail = 'Drivers 中应有目标型号的网卡驱动；文件存在不代表兼容性已经验证。' }
        [pscustomobject]@{ Name = '软件安装包'; Ready = $software.Count -gt 0; Required = $false; Detail = 'Software 中的安装包供离线使用；联网下载器仍需网络。' }
    )
}

function Invoke-ElevatedSetupTask {
    param([ValidateSet('ExportDrivers', 'ImportDrivers', 'WingetMirror', 'OptimizeMachine')][string]$Operation, [hashtable]$Values)
    $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { $HOME }
    $logFolder = Join-Path $base 'WindowsSetupHelper/logs'
    [void](New-Item -ItemType Directory -Path $logFolder -Force)
    $logFile = Join-Path $logFolder ('administrator-' + [guid]::NewGuid().ToString('N') + '.log')
    $errorFile = $logFile + '.error.txt'
    $request = @{ Operation = $Operation; Values = $Values; Root = $script:ProjectRoot; LogFile = $logFile; ErrorFile = $errorFile } | ConvertTo-Json -Depth 5 -Compress
    $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($request))
    $command = @'
$ErrorActionPreference = 'Stop'
$request = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PAYLOAD__')) | ConvertFrom-Json
$elevationFinished = $false
$transcriptStarted = $false
try {
    Start-Transcript -LiteralPath $request.LogFile -Force | Out-Null
    $transcriptStarted = $true
    . (Join-Path $request.Root 'Start-DevSetup.ps1') -Action List -DryRun -Yes 6>$null
    $script:DryRunEnabled = $false
    $values = @{}
    foreach ($property in $request.Values.PSObject.Properties) { $values[$property.Name] = $property.Value }
    Invoke-SetupTask $request.Operation $values
    if ($script:Failed -gt 0) { throw '管理员操作报告失败，详细输出见管理员运行记录。' }
    $elevationFinished = $true
}
finally {
    if (-not $elevationFinished -and $Error.Count -gt 0) {
        $failure = $Error[0]
        [IO.File]::WriteAllText($request.ErrorFile, $failure.Exception.Message, [Text.UTF8Encoding]::new($false))
        Write-Host ($failure | Out-String)
    }
    if (Test-Path Function:Save-Log) { Save-Log }
    if ($transcriptStarted) { Stop-Transcript | Out-Null }
}
'@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command.Replace('__PAYLOAD__', $payload)))
    Write-Status '请在 Windows 授权窗口中允许操作；取消授权后可以重新尝试。'
    Write-Status "管理员运行记录：$logFile"
    $process = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded) -Verb RunAs -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        $reason = if (Test-Path -LiteralPath $errorFile) { Get-Content -LiteralPath $errorFile -Raw -Encoding UTF8 } else { '管理员进程没有返回具体错误，请查看管理员运行记录。' }
        throw "管理员操作未完成（退出代码 $($process.ExitCode)）：$reason`n管理员运行记录：$logFile"
    }
    if ($Operation -ne 'OptimizeMachine') { Write-Result '管理员操作' $true }
}

function Copy-PreparationFile {
    param([string]$Source, [string]$Destination)
    if ([IO.Path]::GetFullPath($Source) -eq [IO.Path]::GetFullPath($Destination)) { return }
    if (Test-Path -LiteralPath $Destination) { throw "目标位置已有同名文件，请先在文件夹中确认或移走文件：$Destination" }
    Copy-Item -LiteralPath $Source -Destination $Destination
}

function Invoke-SetupTask {
    param(
        [ValidateSet('Computer', 'BackupFiles', 'ExportDrivers', 'ImportDrivers', 'CopyDrivers', 'CopyIso', 'VerifyIso', 'BootRufus', 'BootVentoy', 'CopyAssistant', 'CopyKit', 'CheckKit', 'Install', 'Download', 'Optimize', 'OptimizeMachine', 'ActivationStatus', 'Activate', 'Mirrors', 'WingetMirror')]
        [string]$Operation,
        [hashtable]$Values = @{}
    )
    switch ($Operation) {
        'Computer' { Show-SetupComputer }
        'BackupFiles' { Backup-UserFiles $Values.Source $Values.Destination }
        'ExportDrivers' {
            if (-not $Values.IsCurrent) { throw '另一台电脑的驱动必须在目标电脑导出，或从厂商官网下载。' }
            if (-not $script:DryRunEnabled -and -not (Test-Administrator)) { Invoke-ElevatedSetupTask $Operation $Values; return }
            Export-SetupDrivers $Values.Destination
        }
        'ImportDrivers' {
            if (-not $script:DryRunEnabled -and -not (Test-Administrator)) { Invoke-ElevatedSetupTask $Operation $Values; return }
            Import-SetupDrivers $Values.Source
        }
        'CopyDrivers' {
            $destination = Join-Path $Values.Folder 'Drivers'
            Backup-UserFiles $Values.Source $destination -ContentsOnly
        }
        'CopyIso' {
            if ([IO.Path]::GetExtension($Values.Source) -ine '.iso') { throw '请选择 ISO 系统镜像文件。' }
            $destination = Join-Path (Join-Path $Values.Folder 'Images') ([IO.Path]::GetFileName($Values.Source))
            if (-not $script:DryRunEnabled) { Copy-PreparationFile $Values.Source $destination }
            Write-Status "系统镜像：$destination"
            Write-Result '保存系统镜像' $true
        }
        'VerifyIso' { Test-IsoFile $Values.Source $Values.Hash }
        'BootRufus' { $script:SetupFolder = $Values.Folder; Start-BootTool 'Rufus' }
        'BootVentoy' { $script:SetupFolder = $Values.Folder; Start-BootTool 'Ventoy' }
        'CopyAssistant' { Copy-SetupLauncher $Values.Folder }
        'CopyKit' {
            Invoke-SetupTask 'CheckKit' @{ Folder = $Values.Folder }
            $before = $script:Succeeded
            Backup-UserFiles $Values.Folder $Values.Destination -PreparationKit
            if (-not $script:DryRunEnabled -and $script:Succeeded -eq $before) { return }
            Write-Status "资料保存到：$($Values.Destination)。请打开其中的 WindowsSetupHelper\Launch.cmd 验证可以启动。"
        }
        'CheckKit' {
            $checks = @(Get-PreparationChecks $Values.Folder)
            foreach ($check in $checks) {
                $state = if ($check.Ready) { '已找到' } elseif ($check.Required) { '缺少' } else { '未准备（可选）' }
                Write-Status "$state · $($check.Name)：$($check.Detail)"
            }
            if (@($checks | Where-Object { $_.Required -and -not $_.Ready }).Count -gt 0) { throw '准备资料不完整，请补齐上方标记为“缺少”的内容。' }
            Write-Status '资料文件已备齐。请在目标电脑上核对驱动兼容性，并实际检查 U 盘能否启动。Windows 首次设置的网络要求也需要提前确认。'
            Write-Result '资料检查' $true
        }
        'Install' {
            $catalog = @($script:AppCatalog) + @($script:PackageCatalog)
            Install-Packages @(Get-RequestedPackages $Values.Ids $catalog) -Location $Values.Location -Interactive:$Values.Interactive
        }
        'Download' {
            if ($Values.Architecture -notin @('x64', 'arm64')) { throw '请先设置目标电脑的处理器类型。' }
            $catalog = @($script:AppCatalog) + @($script:PackageCatalog)
            $items = @(Get-RequestedPackages $Values.Ids $catalog)
            if (-not $script:DryRunEnabled -and -not (Find-Tool 'winget')) { throw '当前电脑缺少 WinGet，请从 Microsoft Store 安装或更新“应用安装程序”，再重新打开助手。' }
            foreach ($item in $items) {
                $directory = Join-Path (Join-Path $Values.Folder 'Software') $item.id
                Write-Status "下载安装包：$($item.name)；目标处理器：$($Values.Architecture)"
                $result = Invoke-Tool 'winget' @('download', '--id', $item.id, '--exact', '--source', 'winget', '--architecture', $Values.Architecture, '--download-directory', $directory, '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
                Write-Result $item.name $result
            }
            Write-Status '安装包保存在 Software 中。下载成功不代表可以完全离线安装；请在目标电脑断网时验证安装包和依赖。联网下载器需要替换为厂商提供的完整安装包。'
        }
        'Optimize' { Invoke-SystemOptimization }
        'OptimizeMachine' { Invoke-SystemOptimization -Full:$Values.Full -MachineOnly }
        'ActivationStatus' { Show-ActivationStatus }
        'Activate' { Start-Activation }
        'Mirrors' {
            $names = @($Values.Managers)
            if ($names -contains 'winget') {
                Invoke-SetupTask 'WingetMirror' @{ Mirror = $Values.Mirror }
                $names = @($names | Where-Object { $_ -ne 'winget' })
            }
            if ($names.Count -gt 0) { Invoke-MirrorPlan @(New-MirrorPlan $names $Values.Mirror) }
        }
        'WingetMirror' {
            if (-not $script:DryRunEnabled -and -not (Test-Administrator)) { Invoke-ElevatedSetupTask $Operation $Values; return }
            Invoke-MirrorPlan @(New-MirrorPlan @('winget') $Values.Mirror)
        }
    }
}

function Start-SetupWorker {
    param([string]$Operation, [hashtable]$Values, [switch]$Preview)
    $worker = [PowerShell]::Create()
    [void]$worker.AddScript({
        param($root, $operation, $values, $preview)
        . (Join-Path $root 'Start-DevSetup.ps1') -Action List -DryRun -Yes 6>$null
        $script:DryRunEnabled = $preview
        try {
            Invoke-SetupTask $operation $values
            Show-Summary
            [pscustomobject]@{ Succeeded = $script:Succeeded; Skipped = $script:Skipped; Failed = $script:Failed }
        }
        finally { Save-Log }
    }).AddArgument($script:ProjectRoot).AddArgument($Operation).AddArgument($Values).AddArgument([bool]$Preview)
    $handle = $worker.BeginInvoke()
    return [pscustomobject]@{ PowerShell = $worker; Handle = $handle; ReadCount = 0 }
}
