@echo off
rem Double-click launcher for the LidKeeper tray app.
rem The script asks for administrator rights itself, because changing the lid
rem close action goes through powercfg.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0src\LidKeeper.ps1" %*
