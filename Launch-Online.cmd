@echo off
chcp 65001 >nul
powershell.exe -NoProfile -Command "irm https://raw.githubusercontent.com/RustyPiano/windows-setup-helper/main/bootstrap.ps1 | iex"
pause
