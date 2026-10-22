param([switch]$Fail, [int]$ExitCode = 0)

Write-Output 'native-stdout'
[Console]::Error.WriteLine('native-stderr')
if ($Fail) { exit 7 }
$global:LASTEXITCODE = $ExitCode
