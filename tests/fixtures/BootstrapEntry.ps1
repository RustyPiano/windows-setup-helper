$ErrorActionPreference = 'Stop'
$packages = Get-Content (Join-Path $PSScriptRoot 'data/packages.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$mirrors = Get-Content (Join-Path $PSScriptRoot 'data/mirrors.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$tweaks = Get-Content (Join-Path $PSScriptRoot 'data/tweaks.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($packages.Count -ne 19 -or -not $mirrors.winget -or $tweaks.Count -ne 23) { throw '下载清单不完整。' }
[IO.File]::WriteAllText($env:WINDEVPICKER_TEST_BOOTSTRAP_MARKER, 'bootstrap-started')
if ($env:WINDEVPICKER_TEST_BOOTSTRAP_FAIL -eq '1') { exit 9 }
