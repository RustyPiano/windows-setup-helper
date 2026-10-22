param([switch]$Fail)

Write-Output 'native-stdout'
[Console]::Error.WriteLine('native-stderr')
if ($Fail) { exit 7 }
