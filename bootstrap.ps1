& {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $archiveUrl = 'https://github.com/RustyPiano/win-dev-picker/archive/refs/heads/main.zip'

    if ($env:OS -ne 'Windows_NT') { throw '在线安装助手仅支持 Windows。' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $folder = Join-Path $env:LOCALAPPDATA ('WinDevPicker/downloads/' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $folder -Force)
    try {
        Write-Host '正在下载安装助手……'
        $archive = Join-Path $folder 'win-dev-picker.zip'
        Invoke-WebRequest -Uri $archiveUrl -OutFile $archive -UseBasicParsing -TimeoutSec 60
        Expand-Archive -LiteralPath $archive -DestinationPath $folder -Force
        $shell = (Get-Process -Id $PID).Path
        & $shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $folder 'win-dev-picker-main/Start-DevSetup.ps1')
        if ($LASTEXITCODE -ne 0) { throw "安装助手已退出，退出代码：$LASTEXITCODE" }
    }
    finally {
        Remove-Item -LiteralPath $folder -Recurse -Force
    }
}
