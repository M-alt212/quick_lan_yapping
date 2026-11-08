@echo off
chcp 65001 >nul
set "SH=powershell"
where pwsh >nul 2>&1
if not errorlevel 1 set "SH=pwsh"
%SH% -NoProfile -ExecutionPolicy Bypass -File "%~dp0chat.ps1"
pause
