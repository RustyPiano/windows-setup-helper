Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$entry = Join-Path $root 'Start-DevSetup.ps1'
$testFolder = Join-Path $root ('.work/setup-tests-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $testFolder -Force)
$originalLocalAppData = $env:LOCALAPPDATA
$originalArchitecture = $env:PROCESSOR_ARCHITECTURE
$originalWowArchitecture = $env:PROCESSOR_ARCHITEW6432
$env:LOCALAPPDATA = Join-Path $testFolder 'appdata'

try {
    & {
        . $entry -Action List -DryRun 6>$null
        $script:DryRunEnabled = $false
        $iso = Join-Path $testFolder 'hash-test.iso'
        [IO.File]::WriteAllText($iso, 'checksum-test')
        $hash = (Get-FileHash $iso -Algorithm SHA256).Hash
        Test-IsoFile $iso $hash
        $failed = $false
        try { Test-IsoFile $iso ('0' * 64) }
        catch { if ($_.Exception.Message -notmatch '镜像校验失败') { throw }; $failed = $true }
        if (-not $failed -or $script:Succeeded -ne 1) { throw 'ISO 校验没有识别不匹配。' }
    }

    & {
        . $entry -Action List -DryRun 6>$null
        $script:DryRunEnabled = $false
        $script:SetupFolder = Join-Path $testFolder 'downloads'
        $fixture = Join-Path $testFolder 'download-fixture.bin'
        [IO.File]::WriteAllText($fixture, 'download-test')
        function Invoke-WebRequest {
            param([string]$Uri, [string]$OutFile, [switch]$UseBasicParsing, [int]$TimeoutSec)
            Copy-Item -LiteralPath $fixture -Destination $OutFile
        }
        $hash = (Get-FileHash $fixture -Algorithm SHA256).Hash
        $file = Receive-SetupFile 'https://download-test.invalid/tool.exe' 'tool.exe' $hash
        $failed = $false
        try { [void](Receive-SetupFile 'https://download-test.invalid/tool.exe' 'tool.exe' ('0' * 64)) }
        catch { if ($_.Exception.Message -notmatch '文件校验失败') { throw }; $failed = $true }
        if (-not $failed -or (Get-FileHash $file -Algorithm SHA256).Hash -ne $hash) { throw '下载校验失败后替换了已有文件。' }
    }

    & {
        . $entry -Action List -DryRun 6>$null
        $script:DryRunEnabled = $false
        $Yes = $true
        $env:PROCESSOR_ARCHITECTURE = 'AMD64'
        Remove-Item Env:PROCESSOR_ARCHITEW6432 -ErrorAction SilentlyContinue
        $script:SetupFolder = Join-Path $testFolder 'boot-tools'
        [void](New-Item -ItemType Directory -Path $script:SetupFolder)
        $zipContent = Join-Path $testFolder 'zip/ventoy-test'
        [void](New-Item -ItemType Directory -Path (Join-Path $zipContent 'altexe') -Force)
        [IO.File]::WriteAllText((Join-Path $zipContent 'Ventoy2Disk.exe'), 'x86-fixture')
        [IO.File]::WriteAllText((Join-Path $zipContent 'altexe/Ventoy2Disk_ARM64.exe'), 'arm64-fixture')
        $zip = Join-Path $testFolder 'ventoy-test.zip'
        Compress-Archive -Path $zipContent -DestinationPath $zip
        function Invoke-RestMethod {
            param([string]$Uri, [switch]$UseBasicParsing, [int]$TimeoutSec)
            return [pscustomobject]@{ tag_name = 'v1.0'; assets = @(
                [pscustomobject]@{ name = 'rufus-1.0.exe'; browser_download_url = 'https://tool-test.invalid/rufus.exe'; digest = ('sha256:' + ('1' * 64)) },
                [pscustomobject]@{ name = 'rufus-1.0_arm64.exe'; browser_download_url = 'https://tool-test.invalid/rufus-arm64.exe'; digest = ('sha256:' + ('2' * 64)) },
                [pscustomobject]@{ name = 'ventoy-1.0-windows.zip'; browser_download_url = 'https://tool-test.invalid/ventoy.zip'; digest = ('sha256:' + ('3' * 64)) }
            ) }
        }
        function Receive-SetupFile {
            param([string]$Uri, [string]$Name, [string]$SHA256)
            $script:ReceivedFile = $Name
            if ($Name.EndsWith('.zip')) { return $zip }
            return (Join-Path $script:SetupFolder $Name)
        }
        function Start-SetupProgram {
            param([string]$Name, [string]$FilePath, [string[]]$Arguments)
            $script:StartedFile = $FilePath
        }
        Start-BootTool 'Rufus'
        if ($script:ReceivedFile -ne 'rufus-1.0.exe') { throw 'Rufus x64 文件选择错误。' }
        $env:PROCESSOR_ARCHITECTURE = 'ARM64'
        Start-BootTool 'Rufus'
        if ($script:ReceivedFile -ne 'rufus-1.0_arm64.exe') { throw 'Rufus Arm64 文件选择错误。' }
        Start-BootTool 'Ventoy'
        if ([IO.File]::ReadAllText($script:StartedFile) -ne 'arm64-fixture') { throw 'Ventoy Arm64 程序未放在工具目录。' }
    }
    $env:PROCESSOR_ARCHITECTURE = $originalArchitecture
    $env:PROCESSOR_ARCHITEW6432 = $originalWowArchitecture

    & {
        . $entry -Action List -DryRun 6>$null
        $script:DryRunEnabled = $false
        $Yes = $true
        $source = Join-Path $testFolder 'source'
        [void](New-Item -ItemType Directory -Path $source)
        function Invoke-Tool { throw '目录包含检查没有阻止备份。' }
        foreach ($destination in @($source, (Join-Path $source 'child'), $testFolder)) {
            $failed = $false
            try { Backup-UserFiles $source $destination }
            catch { if ($_.Exception.Message -notmatch '不能互相包含') { throw }; $failed = $true }
            if (-not $failed) { throw '备份目录包含检查失败。' }
        }
    }

    if ($env:OS -eq 'Windows_NT') {
        & {
            . $entry -Action List -DryRun 6>$null
            $script:DryRunEnabled = $false
            $Yes = $true
            $source = Join-Path $testFolder 'source with spaces'
            $destination = Join-Path $testFolder 'backup with spaces'
            [void](New-Item -ItemType Directory -Path $source)
            [void](New-Item -ItemType Directory -Path $destination)
            [IO.File]::WriteAllText((Join-Path $source 'document.txt'), 'backup-test')
            [IO.File]::WriteAllText((Join-Path $destination 'keep.txt'), 'keep-test')
            Backup-UserFiles $source $destination
            if ([IO.File]::ReadAllText((Join-Path $destination 'source with spaces/document.txt')) -ne 'backup-test' -or -not (Test-Path (Join-Path $destination 'keep.txt'))) { throw '文件备份不完整或删除了目标文件。' }
            if ($script:Succeeded -ne 1 -or $script:Failed -ne 0) { throw 'Robocopy 正常复制被误判为失败。' }
            Show-SetupComputer
            Show-ActivationStatus
        }
    }

    & {
        . $entry -Action List -DryRun 6>$null
        $script:DryRunEnabled = $false
        function Find-Tool { return (Join-Path $PSScriptRoot 'fixtures/NativeCommand.ps1') }
        $result = Invoke-Tool 'driver-return-test' @('259') -SkipExitCodes @(259)
        Write-Result '无需安装的驱动' $result
        if ($null -ne $result -or $script:Skipped -ne 1 -or $script:Failed -ne 0) { throw '无需安装的驱动被误判为失败。' }
    }

    & {
        . $entry -Action List -DryRun 6>$null
        $script:DryRunEnabled = $false
        $Yes = $true
        function Test-Administrator { return $true }
        function Invoke-Tool {
            param([string]$Name, [string[]]$Arguments, [int[]]$SuccessExitCodes, [int[]]$SkipExitCodes)
            $script:DriverTool = $Name
            $script:DriverArguments = $Arguments
            $script:DriverSkipCodes = $SkipExitCodes
            return $true
        }
        $drivers = Join-Path $testFolder 'drivers'
        Export-SetupDrivers $drivers
        if ($script:DriverTool -ne 'dism' -or $script:DriverArguments -notcontains '/Export-Driver') { throw '驱动备份命令错误。' }
        [IO.File]::WriteAllText((Join-Path $drivers 'test.inf'), 'driver-fixture')
        Import-SetupDrivers $drivers
        if ($script:DriverTool -ne 'pnputil' -or $script:DriverArguments -notcontains '/subdirs' -or $script:DriverArguments -contains '/reboot' -or $script:DriverSkipCodes -notcontains 259) { throw '驱动安装命令错误。' }
        $script:ProjectRoot = Join-Path $testFolder 'assistant-source'
        [void](New-Item -ItemType Directory -Path $script:ProjectRoot)
        foreach ($name in @('Launch.cmd', 'Launch-Online.cmd', 'Start-DevSetup.ps1', 'README.md', 'data', 'scripts', 'docs')) {
            Copy-Item -LiteralPath (Join-Path $root $name) -Destination $script:ProjectRoot -Recurse
        }
        Copy-SetupLauncher $testFolder
        $launcher = Join-Path $testFolder 'WindowsSetupHelper/Launch-Online.cmd'
        if ((Get-FileHash $launcher).Hash -ne (Get-FileHash (Join-Path $root 'Launch-Online.cmd')).Hash) { throw '复制的在线启动入口不一致。' }
        $guide = Join-Path $testFolder 'WindowsSetupHelper/docs/advanced.md'
        if ((Get-FileHash $guide).Hash -ne (Get-FileHash (Join-Path $root 'docs/advanced.md')).Hash) { throw '离线助手中的技术说明与源文件不一致。' }
        $shell = (Get-Process -Id $PID).Path
        $output = & $shell -NoProfile -File (Join-Path $testFolder 'WindowsSetupHelper/Start-DevSetup.ps1') -Action AppList -DryRun
        if ($LASTEXITCODE -ne 0 -or ($output -join "`n") -notmatch 'Tencent.WeChat') { throw '复制的助手无法独立启动。' }
    }

    & {
        . $entry -Action List -DryRun 6>$null
        $script:DryRunEnabled = $false
        function Confirm-Selection { return $false }
        function Start-SetupProgram { throw '取消后仍启动了激活工具。' }
        Start-Activation
        function Confirm-Selection { return $true }
        function Start-SetupProgram {
            param([string]$Name, [string]$FilePath, [string[]]$Arguments)
            if ($Arguments[-1] -ne 'irm https://get.activated.win | iex') { throw '激活命令与用户指定的不一致。' }
            $script:ActivationRequested = $true
        }
        function Show-ActivationStatus { $script:ActivationStatusRead = $true }
        Start-Activation
        if (-not $script:ActivationRequested -or -not $script:ActivationStatusRead) { throw '激活入口没有执行完整流程。' }
    }

    & {
        . $entry -Action List -DryRun 6>$null
        $script:DryRunEnabled = $false
        $Yes = $true
        function Set-SystemTweak {
            param([object]$Setting)
            if ($Setting.id -ne 'ShowFileExtensions' -or $Setting.type -ne 'DWord') { throw '文件扩展名操作修改了其他设置。' }
            $script:ExtensionValue = $Setting.value
        }
        Set-FileExtensionDisplay $true
        if ($script:ExtensionValue -ne 0) { throw '显示文件扩展名的设置错误。' }
        Set-FileExtensionDisplay $false
        if ($script:ExtensionValue -ne 1) { throw '隐藏文件扩展名的设置错误。' }
    }

    Write-Host '装机功能测试通过：文件校验、工具选择、备份目录检查、驱动命令、启动入口、激活确认和系统设置。' -ForegroundColor Green
}
finally {
    $env:LOCALAPPDATA = $originalLocalAppData
    $env:PROCESSOR_ARCHITECTURE = $originalArchitecture
    $env:PROCESSOR_ARCHITEW6432 = $originalWowArchitecture
    Remove-Item -LiteralPath $testFolder -Recurse -Force
}
exit 0
