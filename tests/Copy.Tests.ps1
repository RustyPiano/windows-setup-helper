Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$entry = Join-Path $root 'Start-DevSetup.ps1'
$folder = Join-Path $root ('.work/copy-tests-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $folder -Force)

try {
    & {
        . $entry -Action List -DryRun -Yes 6>$null
        $script:DryRunEnabled = $false
        $script:Copies = New-Object 'System.Collections.Generic.List[object]'
        $script:InterruptCopy = $false
        function Invoke-Tool {
            param([string]$Name, [string[]]$Arguments, [int[]]$SuccessExitCodes)
            if ($Name -ne 'robocopy' -or $Arguments -contains '/MIR' -or $Arguments -contains '/PURGE') { throw '复制不能清除目标中的其他文件。' }
            $script:Copies.Add([pscustomobject]@{ Source = $Arguments[0]; Destination = $Arguments[1]; Restartable = $Arguments -contains '/Z' })
            if ($script:DryRunEnabled) { return $true }
            [void](New-Item -ItemType Directory -Path $Arguments[1] -Force)
            if ($script:InterruptCopy) {
                if (-not (Test-Path (Join-Path $Arguments[1] 'target.json'))) { throw '开始复制前没有保存目标电脑信息。' }
                [IO.File]::WriteAllText((Join-Path $Arguments[1] 'partial.txt'), 'partial-copy-fixture')
                return $false
            }
            # 此处测试目标目录决策和文件隔离；真实 Robocopy 单独在 Windows 分支执行。
            foreach ($item in Get-ChildItem -LiteralPath $Arguments[0] -Force) {
                Copy-Item -LiteralPath $item.FullName -Destination $Arguments[1] -Recurse -Force
            }
            return $true
        }
        $destination = Join-Path $folder 'backups'
        [void](New-Item -ItemType Directory -Path $destination)
        [IO.File]::WriteAllText((Join-Path $destination 'keep.txt'), 'keep')
        $sources = @('Desktop', 'alice/Documents', 'bob/Documents')
        for ($i = 0; $i -lt $sources.Count; $i++) {
            $source = Join-Path $folder $sources[$i]
            [void](New-Item -ItemType Directory -Path $source -Force)
            [IO.File]::WriteAllText((Join-Path $source 'same.txt'), "source-$i")
            Invoke-SetupTask 'BackupFiles' @{ Source = $source; Destination = $destination }
        }
        $source = Join-Path $folder 'alice/Documents'
        [IO.File]::WriteAllText((Join-Path $source 'same.txt'), 'new-version')
        Backup-UserFiles $source $destination
        $expected = @{ Desktop = 'source-0'; Documents = 'source-1'; 'Documents (2)' = 'source-2'; 'Documents (3)' = 'new-version' }
        foreach ($name in $expected.Keys) {
            if ([IO.File]::ReadAllText((Join-Path (Join-Path $destination $name) 'same.txt')) -ne $expected[$name]) { throw '不同来源或多次备份覆盖了已有内容。' }
        }
        if ([IO.File]::ReadAllText((Join-Path $destination 'keep.txt')) -ne 'keep') { throw '备份修改了已有的其他文件。' }

        $kit = Join-Path $folder 'kit'
        [void](New-Item -ItemType Directory -Path $kit)
        Save-PreparationTarget $kit @{ IsCurrent = $false; Model = 'Target A'; Architecture = 'arm64'; Offline = $true }
        [IO.File]::WriteAllText((Join-Path $kit 'partial.txt'), 'complete-content')
        function Get-PreparationChecks { return [pscustomobject]@{ Name = '复制测试资料'; Ready = $true; Required = $true; Detail = '文件存在检查由桌面测试覆盖。' } }
        $copiedKit = Join-Path $folder 'usb/WindowsSetupKit'
        $script:InterruptCopy = $true
        Invoke-SetupTask 'CopyKit' @{ Folder = $kit; Destination = $copiedKit }
        if ($script:Failed -ne 1 -or -not (Test-Path (Join-Path $copiedKit 'target.json'))) { throw '中断后没有保留失败状态和目标信息。' }
        $script:InterruptCopy = $false
        Invoke-SetupTask 'CopyKit' @{ Folder = $kit; Destination = $copiedKit }
        if ([IO.File]::ReadAllText((Join-Path $copiedKit 'partial.txt')) -ne 'complete-content' -or -not $script:Copies[$script:Copies.Count - 1].Restartable) { throw '同一准备目录无法重试，或缺少可恢复复制参数。' }
        [IO.File]::WriteAllText((Join-Path $copiedKit 'keep.txt'), 'user-file')
        [IO.File]::WriteAllText((Join-Path $kit 'Drivers/new.inf'), 'new-driver')
        Invoke-SetupTask 'CopyKit' @{ Folder = $kit; Destination = $copiedKit }
        if (-not (Test-Path (Join-Path $copiedKit 'Drivers/new.inf')) -or [IO.File]::ReadAllText((Join-Path $copiedKit 'keep.txt')) -ne 'user-file') { throw '更新没有复制新增文件，或删除了已有文件。' }
        $empty = Join-Path $folder 'empty-kit'
        [void](New-Item -ItemType Directory -Path $empty)
        Invoke-SetupTask 'CopyKit' @{ Folder = $kit; Destination = $empty }
        if (-not (Test-Path (Join-Path $empty 'target.json'))) { throw '无法使用已有空目录。' }

        $foreign = Join-Path $folder 'foreign-kit'
        [void](New-Item -ItemType Directory -Path $foreign)
        Save-PreparationTarget $foreign @{ IsCurrent = $false; Model = 'Target B'; Architecture = 'x64'; Offline = $true }
        $foreignHash = (Get-FileHash (Join-Path $foreign 'target.json')).Hash
        $unknown = Join-Path $folder 'unknown-kit'
        [void](New-Item -ItemType Directory -Path $unknown)
        [IO.File]::WriteAllText((Join-Path $unknown 'keep.txt'), 'unknown-owner')
        foreach ($path in @($foreign, $unknown, (Join-Path $kit 'nested'))) {
            $count = $script:Copies.Count
            $refused = $false
            try { Invoke-SetupTask 'CopyKit' @{ Folder = $kit; Destination = $path } }
            catch {
                if ($_.Exception.Message -notmatch '其他目标电脑|没有目标电脑信息|不能互相包含') { throw }
                $refused = $true
            }
            if (-not $refused -or $script:Copies.Count -ne $count) { throw '无法确认目标归属或目录包含时仍执行了复制。' }
        }
        if ((Get-FileHash (Join-Path $foreign 'target.json')).Hash -ne $foreignHash -or (Test-Path (Join-Path $kit 'nested'))) { throw '拒绝复制后仍修改了文件。' }

        $script:DryRunEnabled = $true
        $preview = Join-Path $folder 'preview'
        Backup-UserFiles $source $preview
        Invoke-SetupTask 'CopyKit' @{ Folder = $kit; Destination = $preview }
        if (Test-Path $preview) { throw '预演创建了目标目录。' }
        $script:DryRunEnabled = $false
        function Confirm-Selection { return $false }
        $count = $script:Copies.Count
        Backup-UserFiles $source $preview
        Invoke-SetupTask 'CopyKit' @{ Folder = $kit; Destination = $preview }
        if ((Test-Path $preview) -or $script:Copies.Count -ne $count) { throw '取消确认后仍创建目录或执行复制。' }
        function Confirm-Selection { return $true }
        Invoke-SetupTask 'CopyDrivers' @{ Source = (Join-Path $kit 'Drivers'); Folder = $empty }
        if ($script:Copies[$script:Copies.Count - 1].Destination -ne (Join-Path $empty 'Drivers')) { throw '驱动复制错误地增加了个人备份子目录。' }
        $script:Failed = 0
    }

    if ($env:OS -eq 'Windows_NT') {
        & {
            . $entry -Action List -DryRun -Yes 6>$null
            $script:DryRunEnabled = $false
            $destination = Join-Path $folder 'native-backups'
            Backup-UserFiles (Join-Path $folder 'Desktop') $destination
            Backup-UserFiles (Join-Path $folder 'alice/Documents') $destination
            if ([IO.File]::ReadAllText((Join-Path $destination 'Desktop/same.txt')) -ne 'source-0' -or [IO.File]::ReadAllText((Join-Path $destination 'Documents/same.txt')) -ne 'new-version') { throw '真实 Robocopy 没有隔离不同来源的同名文件。' }
            $kit = Join-Path $folder 'kit'
            $copiedKit = Join-Path $folder 'native-kit'
            Backup-UserFiles $kit $copiedKit -PreparationKit
            [IO.File]::WriteAllText((Join-Path $copiedKit 'partial.txt'), 'partial')
            [IO.File]::WriteAllText((Join-Path $copiedKit 'keep.txt'), 'preserve')
            [IO.File]::WriteAllText((Join-Path $kit 'Software/added.txt'), 'added')
            Backup-UserFiles $kit $copiedKit -PreparationKit
            if ([IO.File]::ReadAllText((Join-Path $copiedKit 'partial.txt')) -ne 'complete-content' -or [IO.File]::ReadAllText((Join-Path $copiedKit 'keep.txt')) -ne 'preserve' -or -not (Test-Path (Join-Path $copiedKit 'Software/added.txt')) -or $script:Failed -ne 0) { throw '真实 Robocopy 没有补齐资料或保留用户文件。' }
            Write-Host 'Windows Robocopy 验证通过。'
        }
    }
    else { Write-Host '当前系统不支持 Robocopy，Windows 实际复制测试未执行。' }
    Write-Host '复制测试通过：来源隔离、同名文件夹、重复备份、失败重试、资料更新、目标归属、取消与预演。'
}
finally { Remove-Item -LiteralPath $folder -Recurse -Force }
