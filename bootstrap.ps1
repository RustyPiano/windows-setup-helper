& {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $BaseUrl = 'https://raw.githubusercontent.com/RustyPiano/win-dev-picker/main'

    if ($env:OS -ne 'Windows_NT') { throw '在线安装助手仅支持 Windows。' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $folder = Join-Path $env:LOCALAPPDATA ('WinDevPicker/downloads/' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path (Join-Path $folder 'data') -Force)
    try {
        foreach ($file in @('Start-DevSetup.ps1', 'data/packages.json', 'data/mirrors.json')) {
            Write-Host "正在下载：$file"
            Invoke-WebRequest -Uri ($BaseUrl.TrimEnd('/') + '/' + $file) -OutFile (Join-Path $folder $file) -UseBasicParsing -TimeoutSec 60
        }
        $shell = (Get-Process -Id $PID).Path
        & $shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $folder 'Start-DevSetup.ps1')
        if ($LASTEXITCODE -ne 0) { throw "安装助手已退出，退出代码：$LASTEXITCODE" }
    }
    finally {
        Remove-Item -LiteralPath $folder -Recurse -Force
    }
}
