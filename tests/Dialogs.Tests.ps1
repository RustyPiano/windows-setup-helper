Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$entry = Join-Path $root 'Start-DevSetup.ps1'

& {
    . $entry -Action List -DryRun 6>$null
    $script:DryRunEnabled = $false
    $script:DialogResult = 'OK'
    $script:DialogDisposed = $false
    $dialog = [pscustomobject]@{
        Title = ''; Filter = ''; CheckFileExists = $false; RestoreDirectory = $false
        FileName = 'C:\Downloads\Windows.iso'; Description = ''; RootFolder = $null
        ShowNewFolderButton = $false; SelectedPath = 'E:\Backup'
    }
    $dialog | Add-Member -MemberType ScriptMethod -Name ShowDialog -Value { return $script:DialogResult }
    $dialog | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $script:DialogDisposed = $true }
    function Add-Type { param([string]$AssemblyName) }
    function New-Object { param([string]$TypeName) return $dialog }

    $path = Select-SetupPath '选择系统镜像' -File
    if ($path -ne 'C:\Downloads\Windows.iso' -or $dialog.Filter -notmatch '\*\.iso' -or -not $dialog.CheckFileExists -or -not $script:DialogDisposed) { throw '文件选择或窗口释放错误。' }
    $path = Select-SetupPath '选择备份文件夹'
    if ($path -ne 'E:\Backup' -or $dialog.Description -ne '选择备份文件夹' -or -not $dialog.ShowNewFolderButton) { throw '文件夹选择错误。' }
    $script:DialogResult = 'Cancel'
    $script:DialogDisposed = $false
    if ($null -ne (Select-SetupPath '取消选择') -or -not $script:DialogDisposed) { throw '取消选择没有正常返回。' }
    $script:SetupFolder = ''
    if ($null -ne (Get-SetupFolder)) { throw '取消后仍然设置了保存位置。' }
}

& {
    . $entry -Action List -DryRun 6>$null
    $script:DryRunEnabled = $false
    $script:Selections = New-Object 'System.Collections.Generic.Queue[string]'
    foreach ($choice in @('4', '7', '8', '9', '10', '0')) { $script:Selections.Enqueue($choice) }
    function Read-Host { param([string]$Prompt) return $script:Selections.Dequeue() }
    function Select-SetupPath { return $null }
    function Test-IsoFile { throw '取消后仍然校验了系统镜像。' }
    function Backup-UserFiles { throw '取消后仍然执行了备份。' }
    function Export-SetupDrivers { throw '取消后仍然导出了驱动。' }
    function Copy-SetupLauncher { throw '取消后仍然复制了助手。' }
    $output = Show-PreparationMenu 6>&1 | Out-String
    if ($output -match '操作结果：') { throw '查询或取消操作显示了任务统计。' }

    foreach ($choice in @('2', '0')) { $script:Selections.Enqueue($choice) }
    function Import-SetupDrivers { throw '取消后仍然安装了驱动。' }
    $output = Show-SystemMenu 6>&1 | Out-String
    if ($output -match '操作结果：') { throw '取消驱动选择后显示了任务统计。' }
}

if ($env:OS -eq 'Windows_NT') {
    Add-Type -AssemblyName System.Windows.Forms
    $fileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    try {
        if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { throw '文件选择窗口需要 STA 模式。' }
        $fileDialog.Filter = '系统镜像文件（*.iso）|*.iso'
        $folderDialog.RootFolder = [Environment+SpecialFolder]::MyComputer
        $folderDialog.ShowNewFolderButton = $true
    }
    finally { $fileDialog.Dispose(); $folderDialog.Dispose() }
}

Write-Host '选择窗口测试通过：文件与文件夹选择、取消操作、只读查询和窗口资源释放。' -ForegroundColor Green
