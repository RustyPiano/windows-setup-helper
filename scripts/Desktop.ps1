function New-DesktopButton {
    param([string]$Text, [string]$Action, [object]$Context = $null)
    $button = New-Object Windows.Forms.Button
    $button.Text = $Text
    $button.AutoSize = $true
    $button.MinimumSize = New-Object Drawing.Size(100, 36)
    $button.Padding = New-Object Windows.Forms.Padding(8, 3, 8, 3)
    $button.Margin = New-Object Windows.Forms.Padding(0, 4, 10, 4)
    $button.Tag = @{ Action = $Action; Context = $Context }
    $button.Add_Click({ Invoke-DesktopClick $this.Tag })
    return ,$button
}

function New-DesktopLabel {
    param([string]$Text)
    $label = New-Object Windows.Forms.Label
    $label.Text = $Text
    $label.AutoSize = $true
    $label.Dock = 'Top'
    $label.MaximumSize = New-Object Drawing.Size(740, 0)
    $label.Margin = New-Object Windows.Forms.Padding(0, 6, 0, 6)
    return ,$label
}

function New-DesktopFlow {
    $panel = New-Object Windows.Forms.FlowLayoutPanel
    $panel.Dock = 'Top'
    $panel.AutoSize = $true
    $panel.WrapContents = $true
    return ,$panel
}

function New-DesktopColumn {
    $panel = New-Object Windows.Forms.TableLayoutPanel
    $panel.Dock = 'Fill'
    $panel.ColumnCount = 1
    $panel.AutoScroll = $true
    $panel.Padding = New-Object Windows.Forms.Padding(16)
    return ,$panel
}

function Show-DesktopMessage {
    param([string]$Text)
    [void][Windows.Forms.MessageBox]::Show($script:Desktop.Form, $Text, 'Windows 装机助手', 'OK', 'Information')
}

function Confirm-DesktopAction {
    param([string]$Text)
    return [Windows.Forms.MessageBox]::Show($script:Desktop.Form, $Text, '确认操作', 'YesNo', 'Question', 'Button2') -eq 'Yes'
}

function Get-DesktopTarget {
    $state = $script:Desktop
    $current = $state.TargetChoice.SelectedIndex -eq 0
    if ($state.Architecture.SelectedIndex -lt 0) { Show-DesktopMessage '请先确认目标电脑的处理器类型。'; return $null }
    if (-not $current -and [string]::IsNullOrWhiteSpace($state.Model.Text)) { Show-DesktopMessage '请填写另一台电脑的品牌和完整型号。'; return $null }
    return @{
        IsCurrent = $current
        Model = $state.Model.Text.Trim()
        Architecture = @('x64', 'arm64')[$state.Architecture.SelectedIndex]
        Offline = $state.Network.SelectedIndex -eq 1
    }
}

function Get-DesktopPreparation {
    $target = Get-DesktopTarget
    if ($null -eq $target) { $script:Desktop.Tabs.SelectedIndex = 0; return $null }
    $folder = $script:Desktop.Folder.Text
    if (-not $folder -or -not (Test-Path -LiteralPath $folder -PathType Container)) {
        Show-DesktopMessage '请在“开始”页选择准备目录，再继续。'
        $script:Desktop.Tabs.SelectedIndex = 0
        return $null
    }
    $targetFile = Join-Path $folder 'target.json'
    if (Test-Path -LiteralPath $targetFile) {
        $existing = Get-Content -LiteralPath $targetFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($existing.Architecture -ne $target.Architecture -or $existing.Model -ne $target.Model -or $existing.IsCurrent -ne $target.IsCurrent) {
            Show-DesktopMessage '这个目录已有其他目标电脑的资料。请为新的目标电脑选择另一个目录，避免混用镜像和驱动。'
            $state = $script:Desktop
            $state.Tabs.SelectedIndex = 0
            return $null
        }
    }
    Save-PreparationTarget $folder $target
    return @{ Folder = $folder; Target = $target }
}

function Open-DesktopPreparation {
    param([string]$Folder)
    $state = $script:Desktop
    $state.Folder.Text = $Folder
    $targetFile = Join-Path $Folder 'target.json'
    if (Test-Path -LiteralPath $targetFile) {
        $target = Get-Content -LiteralPath $targetFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $state.TargetChoice.SelectedIndex = if ($target.IsCurrent) { 0 } else { 1 }
        $state.Model.Text = $target.Model
        $state.Architecture.SelectedIndex = switch ($target.Architecture) { 'arm64' { 1 }; 'x64' { 0 }; default { -1 } }
        $state.Network.SelectedIndex = if ($target.Offline) { 1 } else { 0 }
    }
    foreach ($key in $state.Guides.Keys) {
        for ($i = 0; $i -lt $state.Guides[$key].Steps.Count; $i++) { Set-DesktopStepState @{ Guide = $key; Index = $i } '未完成' }
    }
}

function Update-DesktopGuide {
    param([string]$Key)
    $view = $script:Desktop.Guides[$Key]
    $index = $view.List.SelectedIndex
    if ($index -lt 0) { return }
    $step = $view.Steps[$index]
    $view.Title.Text = '第 {0}/{1} 步 · {2}　{3}' -f ($index + 1), $view.Steps.Count, $step.title, $view.States[$index]
    $view.Body.Text = $step.body.Replace("`n", "`r`n")
    foreach ($button in @($view.Actions.Controls)) { $button.Dispose() }
    $view.Actions.Controls.Clear()
    foreach ($action in $step.actions) {
        $view.Actions.Controls.Add((New-DesktopButton $action.label $action.operation @{ Guide = $Key; Index = $index }))
    }
    $view.Hash.Visible = @($step.actions.operation) -contains 'VerifyIso'
    $view.HashLabel.Visible = $view.Hash.Visible
    $view.Previous.Enabled = $index -gt 0
    $view.Next.Text = if ($index -eq $view.Steps.Count - 1) { '查看完成情况' } else { '下一步' }
    $view.Done.Visible = [bool]$step.manual
}

function Set-DesktopStepState {
    param([object]$Context, [string]$Status)
    if ($null -eq $Context -or -not $Context.ContainsKey('Guide')) { return }
    $view = $script:Desktop.Guides[$Context.Guide]
    $view.States[$Context.Index] = $Status
    $view.List.Items[$Context.Index] = '{0}. {1} · {2}' -f ($Context.Index + 1), $view.Steps[$Context.Index].title, $Status
    Update-DesktopGuide $Context.Guide
}

function Reset-DesktopPreparationSteps {
    if (-not $script:Desktop.Guides.ContainsKey('prepare')) { return }
    for ($i = 0; $i -lt $script:Desktop.Guides.prepare.Steps.Count; $i++) {
        Set-DesktopStepState @{ Guide = 'prepare'; Index = $i } '未完成'
    }
}

function Add-DesktopGuide {
    param([object]$Tab, [string]$Key, [object[]]$Steps)
    $layout = New-Object Windows.Forms.TableLayoutPanel
    $layout.Dock = 'Fill'
    $layout.ColumnCount = 2
    [void]$layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 32)))
    [void]$layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 68)))
    $list = New-Object Windows.Forms.ListBox
    $list.Dock = 'Fill'
    $list.IntegralHeight = $false
    $list.HorizontalScrollbar = $true
    $list.Tag = $Key
    $list.Add_SelectedIndexChanged({ Update-DesktopGuide $this.Tag })
    $content = New-DesktopColumn
    $content.RowCount = 6
    foreach ($height in @('AutoSize', 'Percent', 'AutoSize', 'AutoSize', 'AutoSize', 'AutoSize')) {
        [void]$content.RowStyles.Add((New-Object Windows.Forms.RowStyle($height, 100)))
    }
    $title = New-DesktopLabel ''
    $body = New-Object Windows.Forms.RichTextBox
    $body.Dock = 'Fill'
    $body.ReadOnly = $true
    $body.BorderStyle = 'None'
    $body.BackColor = [Drawing.Color]::White
    $body.DetectUrls = $false
    $body.MinimumSize = New-Object Drawing.Size(200, 150)
    $hashLabel = New-DesktopLabel '校验值（仅校验 ISO 时填写，从微软下载页完整复制）'
    $hash = New-Object Windows.Forms.TextBox
    $hash.Dock = 'Top'
    $hash.AccessibleName = '微软公布的 ISO 校验值'
    $actions = New-DesktopFlow
    $navigation = New-DesktopFlow
    $previous = New-DesktopButton '上一步' 'Previous' $Key
    $done = New-DesktopButton '我已核对本步骤' 'Done' $Key
    $skip = New-DesktopButton '暂时跳过' 'Skip' $Key
    $next = New-DesktopButton '下一步' 'Next' $Key
    foreach ($control in @($previous, $done, $skip, $next)) { $navigation.Controls.Add($control) }
    foreach ($control in @($title, $body, $hashLabel, $hash, $actions, $navigation)) { $content.Controls.Add($control) }
    $layout.Controls.Add($list, 0, 0)
    $layout.Controls.Add($content, 1, 0)
    $Tab.Controls.Add($layout)
    $script:Desktop.Guides[$Key] = @{ List = $list; Title = $title; Body = $body; Hash = $hash; HashLabel = $hashLabel; Actions = $actions; Previous = $previous; Next = $next; Done = $done; Steps = $Steps; States = @($Steps | ForEach-Object { '未完成' }) }
    for ($i = 0; $i -lt $Steps.Count; $i++) { [void]$list.Items.Add(('{0}. {1} · 未完成' -f ($i + 1), $Steps[$i].title)) }
    $list.SelectedIndex = 0
}

function Add-DesktopPackages {
    param([object]$Tab, [string]$Key, [object[]]$Catalog)
    $layout = New-DesktopColumn
    $layout.RowCount = 4
    foreach ($height in @('AutoSize', 'Percent', 'AutoSize', 'AutoSize')) { [void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle($height, 100))) }
    $layout.Controls.Add((New-DesktopLabel '勾选需要的软件。安装会修改当前电脑；下载只保存安装包，供目标电脑使用。'))
    $list = New-Object Windows.Forms.ListView
    $list.Dock = 'Fill'
    $list.View = 'Details'
    $list.CheckBoxes = $true
    $list.FullRowSelect = $true
    $list.HideSelection = $false
    $list.AccessibleName = '选择需要的软件'
    [void]$list.Columns.Add('软件', 210)
    [void]$list.Columns.Add('用途', 470)
    $groups = @{}
    foreach ($item in $Catalog) {
        if (-not $groups.ContainsKey($item.category)) {
            $group = New-Object Windows.Forms.ListViewGroup($item.category)
            $groups[$item.category] = $group
            [void]$list.Groups.Add($group)
        }
        $row = New-Object Windows.Forms.ListViewItem($item.name)
        [void]$row.SubItems.Add($item.description)
        $row.Tag = $item
        $row.Group = $groups[$item.category]
        [void]$list.Items.Add($row)
    }
    $list.Tag = $Key
    $list.Add_ItemCheck({
        param($sender, $eventArgs)
        if ($eventArgs.NewValue -ne [Windows.Forms.CheckState]::Checked) { return }
        $id = $sender.Items[$eventArgs.Index].Tag.id
        if ($id -in @('OpenJS.NodeJS.LTS', 'CoreyButler.NVMforWindows')) {
            foreach ($row in $sender.Items) {
                if ($row.Tag.id -ne $id -and $row.Tag.id -in @('OpenJS.NodeJS.LTS', 'CoreyButler.NVMforWindows')) { $row.Checked = $false }
            }
        }
    })
    $layout.Controls.Add($list)
    $options = New-DesktopColumn
    $options.Dock = 'Top'
    $options.AutoSize = $true
    $options.Padding = New-Object Windows.Forms.Padding(0)
    $options.Controls.Add((New-DesktopLabel '安装目录：留空使用软件默认位置。自选目录下按软件分别建立子目录；实际支持情况由安装程序决定。'))
    $pathRow = New-DesktopFlow
    $path = New-Object Windows.Forms.TextBox
    $path.ReadOnly = $true
    $path.Width = 380
    $path.AccessibleName = '软件安装目录'
    $pathRow.Controls.Add($path)
    $pathRow.Controls.Add((New-DesktopButton '选择安装目录' 'InstallFolder' $Key))
    $pathRow.Controls.Add((New-DesktopButton '使用默认目录' 'DefaultFolder' $Key))
    $options.Controls.Add($pathRow)
    $interactive = New-Object Windows.Forms.CheckBox
    $interactive.Text = '打开软件安装向导，逐个确认安装位置和选项'
    $interactive.AutoSize = $true
    $interactive.Checked = $true
    $options.Controls.Add($interactive)
    if ($Key -eq 'developer') { $options.Controls.Add((New-DesktopLabel 'Node.js 与 nvm 二选一，勾选其中一个会取消另一个。没有多版本需求时选择 Node.js LTS。')) }
    $layout.Controls.Add($options)
    $buttons = New-DesktopFlow
    $buttons.Controls.Add((New-DesktopButton '安装到当前电脑' 'InstallSelected' $Key))
    $buttons.Controls.Add((New-DesktopButton '下载到准备目录' 'DownloadSelected' $Key))
    $buttons.Controls.Add((New-DesktopButton '清空选择' 'ClearSelection' $Key))
    $layout.Controls.Add($buttons)
    $Tab.Controls.Add($layout)
    $script:Desktop.Packages[$Key] = @{ List = $list; Location = $path; Interactive = $interactive }
}

function Start-DesktopOperation {
    param([string]$Operation, [hashtable]$Values, [object]$Context)
    $state = $script:Desktop
    if ($null -ne $state.Worker) { return }
    $state.Log.AppendText("`r`n----- $Operation -----`r`n")
    $state.Status.Text = '正在操作，请等待；需要授权或安装选择时，请在弹出的窗口中完成。'
    $state.Progress.Style = 'Marquee'
    $state.Tabs.Enabled = $false
    $state.Context = $Context
    $state.Operation = $Operation
    $state.Worker = Start-SetupWorker $Operation $Values
    $state.Timer.Start()
}

function Update-DesktopWorker {
    $state = $script:Desktop
    $job = $state.Worker
    if ($null -eq $job) { return }
    $completed = $job.Handle.IsCompleted
    $stream = $job.PowerShell.Streams.Information
    while ($job.ReadCount -lt $stream.Count) {
        $message = [string]$stream[$job.ReadCount].MessageData
        $state.Log.AppendText($message + "`r`n")
        $job.ReadCount++
    }
    if (-not $completed) { return }
    $state.Timer.Stop()
    $failed = $job.PowerShell.InvocationStateInfo.State -eq 'Failed'
    if ($failed) {
        $reason = $job.PowerShell.InvocationStateInfo.Reason.Message
        $state.Log.AppendText("操作未完成：$reason`r`n")
        $state.Status.Text = "操作未完成：$reason"
        Set-DesktopStepState $state.Context '未完成'
    }
    else {
        $output = @($job.PowerShell.EndInvoke($job.Handle))
        $result = $output[-1]
        $failed = $result.Failed -gt 0 -or $job.PowerShell.HadErrors
        if ($failed) {
            $state.Status.Text = '有操作未完成，请查看下方记录。原来的选择仍然保留，可以处理原因后重试。'
            Set-DesktopStepState $state.Context '未完成'
        }
        else {
            $state.Status.Text = '操作结束。请查看下方结果；步骤说明仍保留，可继续核对或进入下一步。'
            if ($null -ne $state.Context -and $state.Context.ContainsKey('Guide')) {
                $view = $state.Guides[$state.Context.Guide]
                if ($view.Steps[$state.Context.Index].manual) { Set-DesktopStepState $state.Context '待核对' }
                elseif ($result.Succeeded -gt 0) { Set-DesktopStepState $state.Context '已完成' }
            }
        }
    }
    $job.PowerShell.Dispose()
    $state.Worker = $null
    $state.Progress.Style = 'Blocks'
    $state.Tabs.Enabled = $true
}

function Invoke-DesktopClick {
    param([hashtable]$Command)
    $state = $script:Desktop
    $action = $Command.Action
    $context = $Command.Context
    if ($null -ne $state.Worker) { return }
    switch ($action) {
        'ChooseFolder' {
            $folder = Select-SetupPath '选择准备目录（不要放在即将清除的启动 U 盘上）'
            if ($folder) { Open-DesktopPreparation $folder }
            return
        }
        'Prepare' {
            if ($null -eq (Get-DesktopPreparation)) { return }
            $state.Tabs.SelectedIndex = 1
            return
        }
        'GoSystem' { $state.Tabs.SelectedIndex = 2; return }
        'GoApps' { $state.Tabs.SelectedIndex = 3; return }
        'InstallFolder' {
            $folder = Select-SetupPath '选择软件安装目录（例如 D:\Applications）'
            if ($folder) { $state.Packages[$context].Location.Text = $folder }
            return
        }
        'DefaultFolder' { $state.Packages[$context].Location.Text = ''; return }
        'ClearSelection' { foreach ($row in $state.Packages[$context].List.Items) { $row.Checked = $false }; return }
        { $_ -in @('Previous', 'Next', 'Done', 'Skip') } {
            $view = $state.Guides[$context]
            $index = $view.List.SelectedIndex
            if ($action -eq 'Previous') { $view.List.SelectedIndex = [Math]::Max(0, $index - 1); return }
            if ($action -eq 'Done') { Set-DesktopStepState @{ Guide = $context; Index = $index } '已核对' }
            if ($action -eq 'Skip') { Set-DesktopStepState @{ Guide = $context; Index = $index } '暂时跳过' }
            if ($index -lt $view.Steps.Count - 1) { $view.List.SelectedIndex = $index + 1 }
            else {
                $pending = @(for ($i = 0; $i -lt $view.Steps.Count; $i++) { if ($view.States[$i] -notin @('已完成', '已核对')) { $view.Steps[$i].title } })
                $message = if ($pending.Count -gt 0) { '尚未完成或已跳过：' + ($pending -join '、') } else { '本次引导中的步骤已核对。需要重新检查时，可以点击左侧的步骤。' }
                Show-DesktopMessage $message
            }
            return
        }
        { $_ -in @('InstallSelected', 'DownloadSelected') } {
            $view = $state.Packages[$context]
            $items = @($view.List.CheckedItems | ForEach-Object { $_.Tag })
            if ($items.Count -eq 0) { Show-DesktopMessage '请先勾选需要的软件。'; return }
            $values = @{ Ids = @($items.id); Location = $view.Location.Text; Interactive = $view.Interactive.Checked }
            if ($action -eq 'DownloadSelected') {
                $preparation = Get-DesktopPreparation
                if ($null -eq $preparation) { return }
                $values.Folder = $preparation.Folder
                $values.Architecture = $preparation.Target.Architecture
                $operation = 'Download'
                $message = "为目标电脑下载：$($items.name -join '、')`n处理器：$($values.Architecture)`n保存位置：$($values.Folder)\Software`n`n下载成功后仍需确认安装包可以离线运行。"
            }
            else {
                $operation = 'Install'
                $location = if ($values.Location) { $values.Location + '（每个软件单独建立子目录）' } else { '各软件的默认位置' }
                $message = "安装到正在运行助手的这台电脑：$($items.name -join '、')`n安装位置：$location`n已安装的软件保留原位置。自选目录是否生效取决于安装程序，请在安装向导中确认。"
            }
            if (Confirm-DesktopAction $message) { Start-DesktopOperation $operation $values $null }
            return
        }
        { $_ -in @('MirrorAuto', 'MirrorOfficial') } {
            $names = @($state.Managers.CheckedItems | ForEach-Object { $_.Tag })
            if ($names.Count -eq 0) { Show-DesktopMessage '请选择需要设置的工具。'; return }
            $mirror = if ($action -eq 'MirrorAuto') { 'Auto' } else { 'Official' }
            if (Confirm-DesktopAction "修改当前电脑的软件下载源：$($names -join '、')`n缺少的工具会显示原因并跳过。") {
                Start-DesktopOperation 'Mirrors' @{ Managers = $names; Mirror = $mirror } $null
            }
            return
        }
    }
    $urls = @{
        OpenNetwork = 'ms-settings:network'; OpenUpdate = 'ms-settings:windowsupdate'; OpenActivation = 'ms-settings:activation'
        OpenTaskbar = 'ms-settings:taskbar'; OpenPower = 'ms-settings:powersleep'; OpenDefaults = 'ms-settings:defaultapps'; OpenStartup = 'ms-settings:startupapps'
        OpenInstallHelp = 'https://www.microsoft.com/zh-cn/software-download/windows11'
    }
    if ($urls.ContainsKey($action)) { Start-Process $urls[$action]; $state.Status.Text = '已打开相应页面。完成页面中的操作后，请回到助手核对本步骤。'; return }
    $values = @{}
    if ($action -in @('ExportDrivers', 'CopyDrivers', 'CopyIso', 'OpenWindows', 'BootRufus', 'BootVentoy', 'CopyAssistant', 'CopyKit', 'CheckKit', 'OpenFolder', 'OpenDrivers')) {
        $preparation = Get-DesktopPreparation
        if ($null -eq $preparation) { return }
        $values.Folder = $preparation.Folder
        if ($action -eq 'OpenWindows') { Start-Process (Get-WindowsDownloadUrl $preparation.Target.Architecture); return }
        if ($action -eq 'OpenFolder') { Start-Process explorer.exe -ArgumentList ('"{0}"' -f $values.Folder); return }
        if ($action -eq 'OpenDrivers') { Start-Process explorer.exe -ArgumentList ('"{0}"' -f (Join-Path $values.Folder 'Drivers')); return }
        if ($action -eq 'ExportDrivers') {
            if (-not $preparation.Target.IsCurrent) { Show-DesktopMessage '你正在给另一台电脑准备资料。请在目标电脑导出驱动，或按目标型号从厂商官网下载，然后点击“加入已准备的驱动”。'; return }
            $values.IsCurrent = $true
            $values.Destination = Join-Path $values.Folder 'Drivers'
        }
        if ($action -eq 'CopyKit') {
            $destination = Select-SetupPath '选择制作完成的 U 盘或另一个移动存储设备，将建立 WindowsSetupKit 文件夹'
            if (-not $destination) { return }
            $values.Destination = Join-Path $destination 'WindowsSetupKit'
        }
    }
    if ($action -in @('BrowseDrivers', 'BrowseSoftware')) {
        $folder = Select-SetupPath '选择 U 盘中的驱动或软件安装包文件夹'
        if ($folder) { Start-Process explorer.exe -ArgumentList ('"{0}"' -f $folder) }
        return
    }
    if ($action -in @('CopyIso', 'VerifyIso')) {
        $values.Source = Select-SetupPath '选择目标电脑的 ISO 系统镜像' -File
        if (-not $values.Source) { return }
        if ($action -eq 'VerifyIso') {
            $values.Hash = $state.Guides[$context.Guide].Hash.Text.Trim()
            if ($values.Hash -notmatch '^[a-fA-F0-9]{64}$') { Show-DesktopMessage '请先粘贴微软公布的完整校验值（64 个字符）。'; return }
        }
    }
    if ($action -in @('BackupFiles', 'CopyDrivers', 'ImportDrivers')) {
        $prompt = switch ($action) { 'BackupFiles' { '选择需要备份的文件夹' }; 'CopyDrivers' { '选择按目标电脑型号准备的驱动文件夹' }; 'ImportDrivers' { '选择含有 INF 文件的驱动备份目录' } }
        $values.Source = Select-SetupPath $prompt
        if (-not $values.Source) { return }
        if ($action -eq 'BackupFiles') {
            $values.Destination = Select-SetupPath '选择备份保存位置（重装时保留的磁盘，不要选择即将清除的 U 盘）'
            if (-not $values.Destination) { return }
        }
    }
    if ($action -in @('BootRufus', 'BootVentoy')) {
        if (-not (Confirm-DesktopAction "即将打开启动盘制作工具。写入会清除所选 U 盘的数据。`n请确保准备目录、系统镜像和唯一一份备份均不在即将清除的 U 盘上，并在工具中核对目标设备。")) { return }
    }
    elseif ($action -notin @('Computer', 'ActivationStatus', 'CheckKit', 'VerifyIso')) {
        $details = @($values.GetEnumerator() | Where-Object { $_.Key -in @('Source', 'Destination', 'Folder') } | ForEach-Object {
            $label = switch ($_.Key) { 'Source' { '来源' }; 'Destination' { '保存位置' }; 'Folder' { '准备目录' } }
            "$label：$($_.Value)"
        })
        $message = "执行当前选中的操作？`n" + ($details -join "`n")
        if ($action -eq 'Optimize') { $message = '应用本步骤中列出的全部推荐设置？部分设置需要重新登录或重启后生效。' }
        if ($action -eq 'Activate') { $message = '打开第三方 Microsoft Activation Scripts？需要网络连接，并在其窗口中选择操作。' }
        if (-not (Confirm-DesktopAction $message)) { return }
    }
    Start-DesktopOperation $action $values $context
}

function New-SetupDesktop {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [Windows.Forms.Application]::EnableVisualStyles()
    $form = New-Object Windows.Forms.Form
    $form.Text = 'Windows 装机助手'
    $form.Font = New-Object Drawing.Font('Microsoft YaHei UI', 10)
    $form.Size = New-Object Drawing.Size(1120, 850)
    $form.MinimumSize = New-Object Drawing.Size(860, 650)
    $form.StartPosition = 'CenterScreen'
    $form.AutoScaleMode = 'Dpi'
    $root = New-Object Windows.Forms.TableLayoutPanel
    $root.Dock = 'Fill'
    $root.ColumnCount = 1
    $root.RowCount = 5
    [void]$root.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
    [void]$root.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent', 100)))
    [void]$root.RowStyles.Add((New-Object Windows.Forms.RowStyle('AutoSize')))
    [void]$root.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute', 8)))
    [void]$root.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute', 145)))
    $heading = New-DesktopLabel 'Windows 装机助手   /   准备资料 · 安装引导 · 软件安装'
    $heading.Padding = New-Object Windows.Forms.Padding(16, 8, 0, 8)
    $tabs = New-Object Windows.Forms.TabControl
    $tabs.Dock = 'Fill'
    foreach ($title in @('开始', '重装前准备', '安装后设置', '日常软件', '开发软件', '下载设置（可选）')) {
        $tab = New-Object Windows.Forms.TabPage
        $tab.Text = $title
        $tab.BackColor = [Drawing.Color]::White
        $tabs.TabPages.Add($tab)
    }
    $status = New-DesktopLabel '请选择要完成的事情。操作结果会保留在下方。'
    $status.Padding = New-Object Windows.Forms.Padding(12, 0, 12, 0)
    $progress = New-Object Windows.Forms.ProgressBar
    $progress.Dock = 'Fill'
    $log = New-Object Windows.Forms.TextBox
    $log.Multiline = $true
    $log.ReadOnly = $true
    $log.ScrollBars = 'Both'
    $log.WordWrap = $false
    $log.Dock = 'Fill'
    $log.AccessibleName = '操作记录与结果'
    $timer = New-Object Windows.Forms.Timer
    $timer.Interval = 150
    $timer.Add_Tick({ Update-DesktopWorker })
    $script:Desktop = @{ Form = $form; Tabs = $tabs; Status = $status; Log = $log; Progress = $progress; Timer = $timer; Worker = $null; Context = $null; Operation = ''; Guides = @{}; Packages = @{} }
    foreach ($control in @($heading, $tabs, $status, $progress, $log)) { $root.Controls.Add($control) }
    $form.Controls.Add($root)
    $home = New-DesktopColumn
    $home.Controls.Add((New-DesktopLabel '你想完成什么？'))
    $home.Controls.Add((New-DesktopLabel '准备重装：先填写目标电脑，再按步骤准备文件、驱动和启动盘。'))
    $target = New-Object Windows.Forms.ComboBox
    $target.DropDownStyle = 'DropDownList'
    $target.Width = 370
    $target.AccessibleName = '安装系统的目标电脑'
    $target.Items.AddRange(@('给正在使用的这台电脑重装', '给另一台电脑安装或重装'))
    $target.SelectedIndex = 0
    $home.Controls.Add($target)
    $home.Controls.Add((New-DesktopLabel '目标电脑品牌和完整型号（给另一台电脑准备时必填）'))
    $model = New-Object Windows.Forms.TextBox
    $model.Dock = 'Top'
    $model.AccessibleName = '目标电脑品牌和型号'
    $home.Controls.Add($model)
    $home.Controls.Add((New-DesktopLabel '目标电脑的处理器类型：请在目标电脑“设置 → 系统 → 系统信息”中核对。'))
    $architecture = New-Object Windows.Forms.ComboBox
    $architecture.DropDownStyle = 'DropDownList'
    $architecture.Width = 370
    $architecture.AccessibleName = '目标电脑处理器类型'
    $architecture.Items.AddRange(@('Intel / AMD 64 位（x64）', 'Arm 64 位（Arm64）'))
    $architecture.SelectedIndex = if ((Get-SetupArchitecture) -eq 'arm64') { 1 } else { 0 }
    $home.Controls.Add($architecture)
    $home.Controls.Add((New-DesktopLabel '目标电脑安装系统后的联网情况'))
    $network = New-Object Windows.Forms.ComboBox
    $network.DropDownStyle = 'DropDownList'
    $network.Width = 370
    $network.AccessibleName = '目标电脑联网情况'
    $network.Items.AddRange(@('能够联网', '无法联网或不确定，需要提前准备驱动和安装包'))
    $network.SelectedIndex = 1
    $home.Controls.Add($network)
    $home.Controls.Add((New-DesktopLabel '准备目录：保存镜像、驱动、安装包和离线助手。请放在制作启动盘时不会被清除的设备上。'))
    $folderRow = New-DesktopFlow
    $folder = New-Object Windows.Forms.TextBox
    $folder.Width = 500
    $folder.ReadOnly = $true
    $folder.AccessibleName = '准备资料的保存目录'
    $folderRow.Controls.Add($folder)
    $folderRow.Controls.Add((New-DesktopButton '选择准备目录' 'ChooseFolder'))
    $home.Controls.Add($folderRow)
    $home.Controls.Add((New-DesktopButton '开始准备重装' 'Prepare'))
    $home.Controls.Add((New-DesktopLabel '系统已经装好：在目标电脑运行助手，安装驱动、检查更新并调整设置。'))
    $home.Controls.Add((New-DesktopButton '配置当前电脑' 'GoSystem'))
    $home.Controls.Add((New-DesktopLabel '只需要软件：勾选软件，选择安装到当前电脑或下载供另一台电脑使用。'))
    $home.Controls.Add((New-DesktopButton '选择需要的软件' 'GoApps'))
    $tabs.TabPages[0].Controls.Add($home)
    $script:Desktop.TargetChoice = $target
    $script:Desktop.Model = $model
    $script:Desktop.Architecture = $architecture
    $script:Desktop.Network = $network
    $script:Desktop.Folder = $folder
    $target.Add_SelectedIndexChanged({
        $script:Desktop.Model.Text = ''
        $script:Desktop.Architecture.SelectedIndex = -1
        if ($this.SelectedIndex -eq 0) { $script:Desktop.Architecture.SelectedIndex = if ((Get-SetupArchitecture) -eq 'arm64') { 1 } else { 0 } }
    })
    $guide = Get-Content (Join-Path $script:ProjectRoot 'data/guide.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Add-DesktopGuide $tabs.TabPages[1] 'prepare' $guide.prepare
    Add-DesktopGuide $tabs.TabPages[2] 'system' $guide.system
    $model.Add_TextChanged({ Reset-DesktopPreparationSteps })
    $architecture.Add_SelectedIndexChanged({ Reset-DesktopPreparationSteps })
    $network.Add_SelectedIndexChanged({ Reset-DesktopPreparationSteps })
    Add-DesktopPackages $tabs.TabPages[3] 'apps' $script:AppCatalog
    Add-DesktopPackages $tabs.TabPages[4] 'developer' $script:PackageCatalog
    $advanced = New-DesktopColumn
    $advanced.Controls.Add((New-DesktopLabel '下载设置只影响当前电脑。安装日常软件通常无需进入此页；下载遇到问题或配置开发工具时再使用。'))
    $advanced.Controls.Add((New-DesktopLabel 'WinGet 下载源提供软件清单，不能保证所有安装包下载加速。这些设置不影响 Windows 系统镜像。'))
    $managers = New-Object Windows.Forms.ListView
    $managers.View = 'Details'
    $managers.CheckBoxes = $true
    $managers.Dock = 'Fill'
    $managers.MinimumSize = New-Object Drawing.Size(400, 220)
    [void]$managers.Columns.Add('工具', 140)
    [void]$managers.Columns.Add('什么时候需要', 500)
    $descriptions = @('助手安装软件时使用', '安装 Python 软件包', '使用 uv 管理 Python 项目', '安装 Node.js 软件包', '使用 pnpm 的项目', '使用 Yarn 的项目', '开发 Go 程序', '开发 Rust 程序')
    for ($i = 0; $i -lt $script:ManagerNames.Count; $i++) {
        $row = New-Object Windows.Forms.ListViewItem($script:ManagerNames[$i])
        $row.Tag = $script:ManagerNames[$i]
        [void]$row.SubItems.Add($descriptions[$i])
        [void]$managers.Items.Add($row)
    }
    $advanced.Controls.Add($managers)
    $mirrorButtons = New-DesktopFlow
    $mirrorButtons.Controls.Add((New-DesktopButton '使用推荐国内源' 'MirrorAuto'))
    $mirrorButtons.Controls.Add((New-DesktopButton '恢复官方源' 'MirrorOfficial'))
    $advanced.Controls.Add($mirrorButtons)
    $script:Desktop.Managers = $managers
    $tabs.TabPages[5].Controls.Add($advanced)
    $form.Add_FormClosing({
        param($sender, $eventArgs)
        if ($null -ne $script:Desktop.Worker) {
            $eventArgs.Cancel = $true
            Show-DesktopMessage '操作正在进行，请等待完成。若外部安装程序正在等待，请先在该窗口完成或取消安装。'
        }
    })
    $kitFolder = Split-Path -Parent $script:ProjectRoot
    if (Test-Path -LiteralPath (Join-Path $kitFolder 'target.json')) { Open-DesktopPreparation $kitFolder }
    return $script:Desktop
}

function Show-SetupDesktop {
    if ($script:DryRunEnabled) { Write-Status '[预演] 打开图形界面：目标电脑、逐步引导、软件勾选、安装目录和离线准备。'; return }
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        $shell = (Get-Process -Id $PID).Path
        & $shell -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $script:ProjectRoot 'Start-DevSetup.ps1') -Action Desktop
        if ($LASTEXITCODE -ne 0) { throw '图形界面未能启动。' }
        return
    }
    $state = New-SetupDesktop
    try { [void]$state.Form.ShowDialog() }
    finally { $state.Timer.Dispose(); $state.Form.Dispose() }
}
