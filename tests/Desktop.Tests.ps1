Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$entry = Join-Path $root 'Start-DevSetup.ps1'
$folder = Join-Path $root ('.work/desktop-tests-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $folder -Force)
$originalLocalAppData = $env:LOCALAPPDATA
$env:LOCALAPPDATA = Join-Path $folder 'appdata'

try {
    & {
        . $entry -Action List -DryRun -Yes 6>$null
        $guide = Get-Content (Join-Path $root 'data/guide.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($step in @($guide.prepare) + @($guide.system)) {
            if (-not $step.title -or -not $step.body -or $step.actions.Count -eq 0) { throw '引导步骤缺少标题、说明或操作入口。' }
        }
        if ((Get-WindowsDownloadUrl 'arm64') -notmatch 'windows11arm64$' -or (Get-WindowsDownloadUrl 'x64') -notmatch 'windows11$') { throw '镜像下载页没有按目标架构选择。' }
        $target = @{ IsCurrent = $false; Model = '另一台 Arm 电脑'; Architecture = 'arm64'; Offline = $true }
        Save-PreparationTarget $folder $target
        $checks = @(Get-PreparationChecks $folder)
        if (@($checks | Where-Object { $_.Required -and -not $_.Ready }).Count -ne 3) { throw '没有检查离线准备所需的镜像、助手和驱动。' }
        $refused = $false
        try { Save-PreparationTarget $folder @{ IsCurrent = $true; Model = ''; Architecture = 'x64'; Offline = $false } }
        catch { if ($_.Exception.Message -notmatch '其他目标电脑') { throw }; $refused = $true }
        if (-not $refused) { throw '不同目标电脑混用了同一个准备目录。' }
        $refused = $false
        try { Invoke-SetupTask 'ExportDrivers' @{ IsCurrent = $false; Destination = $folder } }
        catch { if ($_.Exception.Message -notmatch '目标电脑导出') { throw }; $refused = $true }
        if (-not $refused) { throw '给另一台电脑准备时仍导出了本机驱动。' }
        $script:DryRunEnabled = $false
        $source = Join-Path $folder 'sample.iso'
        [IO.File]::WriteAllText($source, 'test-file-for-copy-only')
        Invoke-SetupTask 'CopyIso' @{ Folder = $folder; Source = $source }
        if ((Get-FileHash $source).Hash -ne (Get-FileHash (Join-Path $folder 'Images/sample.iso')).Hash) { throw '镜像复制内容不一致。' }
        $script:ProjectRoot = Join-Path $folder 'source'
        [void](New-Item -ItemType Directory -Path $script:ProjectRoot)
        foreach ($name in @('Launch.cmd', 'Launch-Online.cmd', 'Start-DevSetup.ps1', 'README.md', 'LICENSE', 'data', 'scripts', 'docs')) {
            Copy-Item -LiteralPath (Join-Path $root $name) -Destination $script:ProjectRoot -Recurse
        }
        Invoke-SetupTask 'CopyAssistant' @{ Folder = $folder }
        if (-not (Test-Path (Join-Path $folder 'WindowsSetupHelper/data/guide.json'))) { throw '离线助手缺少引导文件。' }
        if ((Get-FileHash (Join-Path $folder 'WindowsSetupHelper/docs/advanced.md')).Hash -ne (Get-FileHash (Join-Path $root 'docs/advanced.md')).Hash) { throw '离线助手中的技术说明与源文件不一致。' }
        if (@(Get-PreparationChecks $folder | Where-Object { $_.Required -and -not $_.Ready }).Count -ne 1) { throw '缺少网卡驱动时错误报告资料齐全。' }
        Remove-Item -LiteralPath (Join-Path $folder 'WindowsSetupHelper/data/guide.json')
        if (@(Get-PreparationChecks $folder | Where-Object { $_.Required -and -not $_.Ready }).Count -ne 2) { throw '助手缺少必要文件时仍显示完整。' }
        Invoke-SetupTask 'CopyAssistant' @{ Folder = $folder }
        $script:BackupRequested = $false
        function Backup-UserFiles { $script:BackupRequested = $true }
        $refused = $false
        try { Invoke-SetupTask 'CopyKit' @{ Folder = $folder; Destination = (Join-Path $folder 'not-created') } }
        catch { if ($_.Exception.Message -notmatch '准备资料不完整') { throw }; $refused = $true }
        if (-not $refused -or $script:BackupRequested) { throw '资料缺少必要驱动时仍复制了离线资料包。' }
    }

    & {
        . $entry -Action List -DryRun -Yes 6>$null
        $script:Calls = New-Object 'System.Collections.Generic.List[object]'
        function Invoke-Tool {
            param([string]$Name, [string[]]$Arguments)
            $script:Calls.Add([pscustomobject]@{ Name = $Name; Arguments = $Arguments })
            return $true
        }
        Invoke-SetupTask 'Download' @{ Ids = @('Git.Git'); Folder = $folder; Architecture = 'arm64' }
        $arguments = $script:Calls[0].Arguments
        if ($arguments[0] -ne 'download' -or $arguments[([Array]::IndexOf($arguments, '--architecture') + 1)] -ne 'arm64') { throw '下载误用了准备电脑的架构，或执行了安装。' }
        $location = Join-Path $folder 'Apps with spaces'
        Invoke-SetupTask 'Install' @{ Ids = @('Git.Git', 'Microsoft.VisualStudioCode'); Location = $location; Interactive = $true }
        foreach ($call in $script:Calls.ToArray()[1..2]) {
            $arguments = $call.Arguments
            $id = $arguments[([Array]::IndexOf($arguments, '--id') + 1)]
            if ($arguments -notcontains '--interactive' -or $arguments[([Array]::IndexOf($arguments, '--location') + 1)] -ne (Join-Path $location $id)) { throw '安装目录、独立子目录或交互安装参数错误。' }
        }
        $script:Calls.Clear()
        Invoke-SetupTask 'Install' @{ Ids = @('Git.Git'); Location = ''; Interactive = $false }
        if ($script:Calls[0].Arguments -contains '--location' -or $script:Calls[0].Arguments -contains '--interactive') { throw '默认安装夹带了自定义选项。' }
    }

    & {
        . $entry -Action List -DryRun -Yes 6>$null
        $script:DryRunEnabled = $false
        $script:RequestedElevation = $null
        $script:ElevatedSuccesses = 1
        $script:ElevatedSkips = 0
        function Start-Process {
            param([string]$FilePath, [string[]]$ArgumentList, [string]$Verb, [switch]$Wait, [switch]$PassThru)
            if ($Verb -ne 'RunAs' -or -not $Wait -or $ArgumentList -notcontains '-EncodedCommand' -or $ArgumentList -notcontains '-ExecutionPolicy' -or $ArgumentList -notcontains 'Bypass') { throw '驱动操作没有请求管理员授权或配置脚本执行方式。' }
            $command = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($ArgumentList[-1]))
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($command, [ref]$tokens, [ref]$errors)
            if ($errors.Count -gt 0) { throw '管理员脚本无法解析。' }
            $encoded = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $node.Value -match '^[A-Za-z0-9+/=]{80,}$' }, $true)[0].Value
            $script:RequestedElevation = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded)) | ConvertFrom-Json
            @{ Succeeded = $script:ElevatedSuccesses; Skipped = $script:ElevatedSkips } | ConvertTo-Json | Set-Content -LiteralPath $script:RequestedElevation.ResultFile -Encoding UTF8
            return [pscustomobject]@{ ExitCode = 0 }
        }
        function Test-Administrator { return $false }
        $destination = Join-Path $folder "driver's files"
        Invoke-SetupTask 'ExportDrivers' @{ IsCurrent = $true; Destination = $destination }
        if ($script:RequestedElevation.Operation -ne 'ExportDrivers' -or $script:RequestedElevation.Values.Destination -ne $destination) { throw '管理员操作丢失了含空格和引号的路径。' }
        Invoke-SetupTask 'ImportDrivers' @{ Source = $destination }
        if ($script:RequestedElevation.Operation -ne 'ImportDrivers' -or $script:RequestedElevation.Values.Source -ne $destination) { throw '驱动安装未传递用户选择的目录。' }
        $script:ElevatedSuccesses = 0
        $script:ElevatedSkips = 1
        $before = $script:Succeeded
        Invoke-SetupTask 'ImportDrivers' @{ Source = $destination }
        if ($script:Succeeded -ne $before -or $script:Skipped -ne 1) { throw '管理员进程跳过操作时被统计为成功。' }
    }

    & {
        . $entry -Action List -DryRun -Yes 6>$null
        $row = [pscustomobject]@{ Tag = $script:PackageCatalog[2] }
        $script:Desktop = @{
            Worker = $null
            Packages = @{ developer = @{ List = [pscustomobject]@{ CheckedItems = @($row) }; Location = [pscustomobject]@{ Text = (Join-Path $folder 'Applications') }; Interactive = [pscustomobject]@{ Checked = $true } } }
        }
        $script:Accepted = $false
        $script:StartedOperation = $null
        function Confirm-DesktopAction { param([string]$Text) return $script:Accepted }
        function Start-DesktopOperation { param($Operation, $Values, $Context) $script:StartedOperation = @{ Operation = $Operation; Values = $Values } }
        Invoke-DesktopClick @{ Action = 'InstallSelected'; Context = 'developer' }
        if ($null -ne $script:StartedOperation) { throw '图形界面取消后仍启动了任务。' }
        $script:Accepted = $true
        Invoke-DesktopClick @{ Action = 'InstallSelected'; Context = 'developer' }
        if ($script:StartedOperation.Operation -ne 'Install' -or $script:StartedOperation.Values.Location -ne (Join-Path $folder 'Applications')) { throw '图形界面没有传入安装目录。' }
        function Get-DesktopPreparation { return @{ Folder = $folder; Target = @{ Architecture = 'arm64'; IsCurrent = $false } } }
        Invoke-DesktopClick @{ Action = 'DownloadSelected'; Context = 'developer' }
        if ($script:StartedOperation.Operation -ne 'Download' -or $script:StartedOperation.Values.Architecture -ne 'arm64') { throw '图形界面把离线下载当作本机安装。' }
    }

    & {
        . $entry -Action List -DryRun -Yes 6>$null
        $worker = Start-SetupWorker 'Download' @{ Ids = @('Git.Git'); Folder = $folder; Architecture = 'arm64' } -Preview
        try {
            $deadline = (Get-Date).AddSeconds(30)
            while (-not $worker.Handle.IsCompleted -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 25 }
            if (-not $worker.Handle.IsCompleted) { throw '后台操作没有结束。' }
            $output = @($worker.PowerShell.EndInvoke($worker.Handle))
            $messages = $worker.PowerShell.Streams.Information | Out-String
            if ($worker.PowerShell.HadErrors -or $messages -notmatch 'winget download' -or $output[-1].Failed -ne 0) { throw '后台任务没有传回操作记录和结果。' }
        }
        finally { $worker.PowerShell.Dispose() }
        $worker = Start-SetupWorker 'CopyIso' @{ Folder = $folder; Source = 'wrong.txt' }
        try {
            $deadline = (Get-Date).AddSeconds(30)
            while (-not $worker.Handle.IsCompleted -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 25 }
            if (-not $worker.Handle.IsCompleted -or $worker.PowerShell.InvocationStateInfo.State -ne 'Failed' -or $worker.PowerShell.InvocationStateInfo.Reason.Message -notmatch 'ISO') { throw '后台异常没有保留错误状态和原因。' }
            $logs = Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'WindowsSetupHelper/logs') -Filter '*.log'
            if (($logs | Get-Content -Raw -Encoding UTF8 | Out-String) -notmatch '\[Error\].*ISO') { throw '后台异常原因没有写入日志。' }
        }
        finally { $worker.PowerShell.Dispose() }
    }

    if ($env:OS -eq 'Windows_NT') {
        & {
            . $entry -Action List -DryRun -Yes 6>$null
            $state = New-SetupDesktop
            try {
                $state.Form.Show()
                [Windows.Forms.Application]::DoEvents()
                if ($state.Tabs.TabPages.Count -ne 7 -or $state.Log.Visible -or $state.TargetChoice.Visible) { throw '首页没有分离任务入口、目标信息和详细记录。' }
                Invoke-DesktopClick @{ Action = 'TargetSetup'; Context = $null }
                [Windows.Forms.Application]::DoEvents()
                if ($state.Tabs.SelectedIndex -ne 6 -or -not $state.TargetChoice.Visible) { throw '准备重装入口没有打开目标信息。' }
                $state.TargetChoice.SelectedIndex = 1
                if ($state.Architecture.SelectedIndex -ne -1) { throw '另一台电脑继承了本机架构。' }
                $state.Model.Text = '另一台 Arm 电脑'
                $state.Architecture.SelectedIndex = 1
                $state.Folder.Text = $folder
                $prepared = Get-DesktopPreparation
                if ($prepared.Target.Architecture -ne 'arm64' -or $prepared.Target.IsCurrent) { throw '图形界面没有保存目标电脑信息。' }
                $state.Tabs.SelectedIndex = 4
                [Windows.Forms.Application]::DoEvents()
                if (-not $state.Packages.developer.List.IsHandleCreated -or -not $state.Packages.developer.List.Visible) { throw '开发软件页面没有显示。' }
                $rows = @($state.Packages.developer.List.Items)
                $node = $rows | Where-Object { $_.Tag.id -eq 'OpenJS.NodeJS.LTS' }
                $nvm = $rows | Where-Object { $_.Tag.id -eq 'CoreyButler.NVMforWindows' }
                $node.Checked = $true
                $nvm.Checked = $true
                if ($node.Checked -or -not $nvm.Checked) { throw '冲突软件可以同时勾选。' }
                $node.Checked = $true
                if (-not $node.Checked -or $nvm.Checked) { throw '冲突软件反向切换失败。' }
                $state.Tabs.SelectedIndex = 1
                [Windows.Forms.Application]::DoEvents()
                $state.Guides.prepare.Done.PerformClick()
                if ($state.Guides.prepare.List.SelectedIndex -ne 1) { throw '下一步按钮没有切换步骤。' }
                $state.Guides.prepare.Previous.PerformClick()
                if ($state.Guides.prepare.States[0] -ne '已核对' -or $state.Guides.prepare.Title.Text -notmatch '已核对') { throw '切换步骤后丢失了完成状态。' }
                foreach ($key in @('prepare', 'system')) {
                    $state.Tabs.SelectedIndex = if ($key -eq 'prepare') { 1 } else { 2 }
                    for ($i = 0; $i -lt $state.Guides[$key].Steps.Count; $i++) {
                        $state.Guides[$key].List.SelectedIndex = $i
                        [Windows.Forms.Application]::DoEvents()
                        if ($state.Guides[$key].Actions.Controls.Count -ne $state.Guides[$key].Steps[$i].actions.Count -or $state.Guides[$key].Body.Text -notmatch [regex]::Escape($state.Guides[$key].Steps[$i].body.Split("`n")[0])) { throw '步骤切换后缺少说明或操作按钮。' }
                    }
                }
                $state.Tabs.SelectedIndex = 1
                $state.Guides.prepare.List.SelectedIndex = 2
                $workerFolder = Join-Path $folder 'window-copy'
                [void](New-Item -ItemType Directory -Path (Join-Path $workerFolder 'Images') -Force)
                Start-DesktopOperation 'CopyIso' @{ Source = (Join-Path $folder 'sample.iso'); Folder = $workerFolder } @{ Guide = 'prepare'; Index = 2 }
                if ($state.Tabs.Enabled -or $state.Navigation.Enabled) { throw '后台任务执行时仍允许重复提交。' }
                $deadline = (Get-Date).AddSeconds(30)
                while ($null -ne $state.Worker -and (Get-Date) -lt $deadline) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 25 }
                if ($null -ne $state.Worker -or -not $state.Tabs.Enabled -or $state.Guides.prepare.States[2] -ne '待核对' -or $state.Log.Text -notmatch '成功：保存系统镜像') { throw '窗口没有显示实际复制结果或恢复操作按钮。' }
                if ((Get-FileHash (Join-Path $folder 'sample.iso')).Hash -ne (Get-FileHash (Join-Path $workerFolder 'Images/sample.iso')).Hash) { throw '窗口后台复制内容不一致。' }
                Start-DesktopOperation 'CopyIso' @{ Source = 'wrong.txt'; Folder = $workerFolder } @{ Guide = 'prepare'; Index = 2 }
                $deadline = (Get-Date).AddSeconds(30)
                while ($null -ne $state.Worker -and (Get-Date) -lt $deadline) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 25 }
                if ($null -ne $state.Worker -or -not $state.Tabs.Enabled -or -not $state.Navigation.Enabled -or $state.Guides.prepare.States[2] -ne '未完成' -or $state.Log.Text -notmatch 'ISO' -or -not $state.Log.Visible) { throw '窗口没有展开后台错误或恢复操作按钮。' }
                Invoke-DesktopClick @{ Action = 'ToggleDetails'; Context = $null }
                if ($state.Log.Visible) { throw '详细记录不能收起。' }
                function Confirm-DesktopAction { return $false }
                function Start-SetupWorker { throw '取消确认后仍然开始安装。' }
                Invoke-DesktopClick @{ Action = 'InstallSelected'; Context = 'developer' }
                if ($null -ne $state.Worker) { throw '取消后仍创建了后台任务。' }
                $state.Form.Size = New-Object Drawing.Size(980, 680)
                [Windows.Forms.Application]::DoEvents()
                if ($state.Tabs.Width -le 0 -or $state.Guides.prepare.Body.Height -lt 150) { throw '最小窗口尺寸下引导不可用。' }
                foreach ($key in @('prepare', 'system')) {
                    $state.Tabs.SelectedIndex = if ($key -eq 'prepare') { 1 } else { 2 }
                    for ($i = 0; $i -lt $state.Guides[$key].Steps.Count; $i++) {
                        $view = $state.Guides[$key]
                        $view.List.SelectedIndex = $i
                        [Windows.Forms.Application]::DoEvents()
                        if ($view.Steps[$i].manual -and ($view.Next.Visible -or -not $view.Done.Visible)) { throw '手动核对步骤同时显示了两个继续按钮。' }
                        foreach ($button in @($view.Actions.Controls) + @($view.Previous, $view.Done, $view.Next)) {
                            if (-not $button.Visible) { continue }
                            $position = $state.Tabs.PointToClient($button.PointToScreen([Drawing.Point]::Empty))
                            if ($position.Y -lt 0 -or $position.Y + $button.Height -gt $state.Tabs.ClientSize.Height -or $position.X + $button.Width -gt $state.Tabs.ClientSize.Width) { throw "最小窗口中按钮超出页面：$($button.Text)" }
                        }
                    }
                }
            }
            finally { $state.Timer.Dispose(); $state.Form.Dispose() }
        }
        Write-Host 'Windows 窗口测试通过：控件创建、目标选择、软件互斥、按钮点击、全部引导步骤、后台实际复制、错误恢复和取消操作。'
    }
    else { Write-Host '当前系统不支持 Windows Forms，窗口测试未执行。' }
    Write-Host '桌面功能测试通过：离线检查、目标隔离、文件复制、安装目录、目标架构下载、后台结果及错误传播。'
}
finally {
    $env:LOCALAPPDATA = $originalLocalAppData
    Remove-Item -LiteralPath $folder -Recurse -Force
}
