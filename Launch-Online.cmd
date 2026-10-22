@echo off
chcp 65001 >nul
powershell.exe -NoProfile -Command "irm https://setup.rustypiano.com | iex"
pause
