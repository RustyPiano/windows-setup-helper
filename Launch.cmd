@echo off
chcp 65001 >nul
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-DevSetup.ps1"
if errorlevel 1 (
  echo.
  echo Windows 装机助手执行失败，请查看上方的错误提示。
)
pause
