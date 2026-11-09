@echo off
REM Uruchamia kreator graficzny konfigurator-win (PowerShell STA).
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0gui\Start-Kreator.ps1"
