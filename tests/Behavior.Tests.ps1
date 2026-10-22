Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$entry = Join-Path $root 'Start-DevSetup.ps1'
$testFolder = Join-Path $root ('.work/tests-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $testFolder -Force)
$originalLocalAppData = $env:LOCALAPPDATA
$originalCargoHome = $env:CARGO_HOME
$originalPath = $env:PATH
$originalOS = $env:OS
$env:LOCALAPPDATA = Join-Path $testFolder 'appdata'
$variableName = 'WINDEVPICKER_TEST_' + [guid]::NewGuid().ToString('N')

try {
    & {
        . $entry -Action List -DryRun 6>$null
        $script:DryRunEnabled = $false
        [void](Set-UserVariable $variableName 'https://pypi.tuna.tsinghua.edu.cn/simple')
        if ([Environment]::GetEnvironmentVariable($variableName, 'Process') -ne 'https://pypi.tuna.tsinghua.edu.cn/simple') { throw '环境变量设置失败。' }
        [void](Set-UserVariable $variableName $null)
        if ([Environment]::GetEnvironmentVariables('Process').Contains($variableName)) { throw '环境变量没有删除。' }
        if ($env:OS -eq 'Windows_NT' -and [Environment]::GetEnvironmentVariables('User').Contains($variableName)) { throw '用户环境变量没有删除。' }
    }

    & {
        . $entry -Action List -DryRun 6>$null
        $script:DryRunEnabled = $false
        $env:CARGO_HOME = Join-Path $testFolder 'cargo'
        [void](New-Item -ItemType Directory -Path $env:CARGO_HOME)
        $legacyFile = Join-Path $env:CARGO_HOME 'config'
        $configFile = Join-Path $env:CARGO_HOME 'config.toml'
        [IO.File]::WriteAllText($legacyFile, "[net]`noffline = true`n")
        $legacyContent = [IO.File]::ReadAllText($legacyFile)
        $plan = @(New-MirrorPlan @('cargo') 'TUNA')
        Invoke-MirrorPlan $plan
        if (Test-Path $configFile) { throw 'Cargo 旧配置存在时仍写入了新配置。' }
        if ($script:Skipped -ne 1 -or $script:Succeeded -ne 0) { throw 'Cargo 跳过计数错误。' }
        [void](Set-CargoMirror $null)
        if ([IO.File]::ReadAllText($legacyFile) -ne $legacyContent) { throw 'Cargo 旧配置被修改。' }
        Remove-Item -LiteralPath $legacyFile
        [void](Set-CargoMirror $script:MirrorCatalog.cargo.options[0].url)
        [void](Set-CargoMirror $script:MirrorCatalog.cargo.options[1].url)
        if ([IO.File]::ReadAllText($configFile) -notmatch 'mirrors.ustc.edu.cn') { throw 'Cargo 已管理配置更新失败。' }
        [void](Set-CargoMirror $null)
        if (Test-Path $configFile) { throw 'Cargo 官方源恢复失败。' }
        [IO.File]::WriteAllText($configFile, "[build]`njobs = 2`n")
        $customContent = [IO.File]::ReadAllText($configFile)
        [void](Set-CargoMirror $script:MirrorCatalog.cargo.options[0].url)
        [void](Set-CargoMirror $null)
        if ([IO.File]::ReadAllText($configFile) -ne $customContent) { throw 'Cargo 自定义配置被修改。' }
    }

    & {
        . $entry -Action List -DryRun 6>$null
        $items = @(Get-RequestedPackages @('OpenJS.NodeJS.LTS', 'CoreyButler.NVMforWindows'))
        function Confirm-Selection { throw '冲突检查晚于用户确认。' }
        function Invoke-Tool { throw '冲突软件仍然执行了安装。' }
        $output = Install-Packages $items 6>&1 | Out-String
        if ($output -notmatch '二选一') { throw '没有显示软件冲突说明。' }
        $script:DryRunEnabled = $false
        function Find-Tool { return 'winget' }
        function Test-Installed { param([string]$Id) return $Id -eq 'OpenJS.NodeJS.LTS' }
        $output = Install-Packages @(Get-RequestedPackages @('CoreyButler.NVMforWindows')) 6>&1 | Out-String
        if ($output -notmatch '已安装 OpenJS.NodeJS.LTS') { throw '没有检查已经安装的冲突软件。' }
    }

    & {
        . $entry -Action List -DryRun 6>$null
        $script:DryRunEnabled = $false
        $Yes = $true
        function Find-Tool { return 'winget' }
        function Test-Installed { return $false }
        function Invoke-Tool { return $true }
        $env:PATH = $originalPath + ';WinDevPickerTestPath'
        Install-Packages @(Get-RequestedPackages @('Git.Git'))
        if (($env:PATH -split ';') -notcontains 'WinDevPickerTestPath') { throw '刷新 PATH 丢失了当前进程的目录。' }
        foreach ($scope in @('Machine', 'User')) {
            foreach ($path in ([Environment]::GetEnvironmentVariable('Path', $scope) -split ';')) {
                if ($path -and ($env:PATH -split ';') -notcontains $path) { throw "刷新 PATH 缺少目录：$path" }
            }
        }
        if ($script:Succeeded -ne 1) { throw '软件结果没有按软件计数。' }
        $env:PATH = $originalPath
    }

    & {
        . $entry -Action List -DryRun 6>$null
        $script:DryRunEnabled = $false
        function Find-Tool { return (Get-Process -Id $PID).Path }
        $arguments = @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'fixtures/NativeCommand.ps1'), '-Fail')
        $result = Invoke-Tool 'native-test' $arguments
        if ($result -ne $false) { throw '没有识别命令失败。' }
        Write-Result 'native-test' $result
        Save-Log
        $log = Get-Content $script:LogFile -Raw -Encoding UTF8
        if ($log -notmatch 'native-stdout' -or $log -notmatch 'native-stderr' -or $log -notmatch '退出代码：7') { throw '命令日志不完整。' }
        if ($script:Failed -ne 1 -or $ErrorActionPreference -ne 'Stop') { throw '命令失败统计或错误处理设置异常。' }
    }

    & {
        . $entry -Action List -DryRun 6>$null
        $script:DryRunEnabled = $false
        function Find-Tool { return (Join-Path $PSScriptRoot 'fixtures/Winget.ps1') }
        function Test-Administrator { return $true }
        $plan = @(New-MirrorPlan @('winget') 'USTC')
        Invoke-MirrorPlan $plan
        if ($script:Succeeded -ne 1 -or $script:Failed -ne 0) { throw 'WinGet 修改源没有按包管理器计数。' }
        $env:WINDEVPICKER_TEST_SOURCE_FAIL = '1'
        Invoke-MirrorPlan $plan
        if ($script:Failed -ne 1 -or $script:Succeeded -ne 1) { throw 'WinGet 添加失败后的恢复计数错误。' }
        if (($script:LogLines -join "`n") -notmatch '恢复原有 WinGet 源') { throw 'WinGet 添加失败时没有恢复原源。' }
    }

    & {
        $env:OS = 'Windows_NT'
        $env:LOCALAPPDATA = Join-Path $testFolder 'fatal-appdata'
        $env:CARGO_HOME = Join-Path $testFolder 'cargo-home-file'
        [IO.File]::WriteAllText($env:CARGO_HOME, 'occupied')
        $shell = (Get-Process -Id $PID).Path
        $output = & {
            $ErrorActionPreference = 'Continue'
            & $shell -NoProfile -File $entry -Action Mirrors -Managers cargo -Mirror TUNA -Yes 2>&1
            if ($LASTEXITCODE -eq 0) { throw '文件写入异常没有使脚本失败。' }
        }
        $logs = @(Get-ChildItem (Join-Path $env:LOCALAPPDATA 'WinDevPicker/logs') -Filter '*.log')
        if ($logs.Count -ne 1 -or (Get-Content $logs[0].FullName -Raw -Encoding UTF8) -notmatch '处理：cargo') { throw '异常退出没有保存操作记录。' }
        if (($output -join "`n") -match '操作结果：成功 0，跳过 0，失败 0') { throw '异常退出显示了错误的完成统计。' }
    }

    Write-Host '行为测试通过：变量删除、Cargo 配置、软件冲突、PATH、命令日志、WinGet 结果统计、异常记录。' -ForegroundColor Green
}
finally {
    [Environment]::SetEnvironmentVariable($variableName, [System.Management.Automation.Language.NullString]::Value, 'User')
    [Environment]::SetEnvironmentVariable($variableName, [System.Management.Automation.Language.NullString]::Value, 'Process')
    $env:LOCALAPPDATA = $originalLocalAppData
    $env:CARGO_HOME = $originalCargoHome
    $env:PATH = $originalPath
    $env:OS = $originalOS
    Remove-Item Env:WINDEVPICKER_TEST_SOURCE_FAIL -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $testFolder -Recurse -Force
}
exit 0
