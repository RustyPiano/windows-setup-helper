@echo off
chcp 65001 >nul
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-DevSetup.ps1"
if errorlevel 1 (
  echo.
  echo Script finished with an error.
)
pause