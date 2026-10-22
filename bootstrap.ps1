& {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $archiveUrl = 'https://setup.rustypiano.com/windows-setup-helper.zip'

    if ($env:OS -ne 'Windows_NT') { throw 'Windows 装机助手仅支持 Windows。' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $folder = Join-Path $env:LOCALAPPDATA ('WindowsSetupHelper/downloads/' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $folder -Force)
    try {
        Write-Host '正在下载 Windows 装机助手……'
        $archive = Join-Path $folder 'windows-setup-helper.zip'
        Invoke-WebRequest -Uri $archiveUrl -OutFile $archive -UseBasicParsing -TimeoutSec 60
        Expand-Archive -LiteralPath $archive -DestinationPath $folder -Force
        $shell = (Get-Process -Id $PID).Path
        $entry = Join-Path $folder 'windows-setup-helper-main/Start-DevSetup.ps1'
        if ([Console]::IsInputRedirected) { & $shell -NoProfile -ExecutionPolicy Bypass -File $entry -Action Menu }
        else { & $shell -NoProfile -ExecutionPolicy Bypass -File $entry }
        if ($LASTEXITCODE -ne 0) { throw "Windows 装机助手已退出，退出代码：$LASTEXITCODE" }
    }
    finally {
        Remove-Item -LiteralPath $folder -Recurse -Force
    }
}
