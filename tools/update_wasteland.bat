@echo off
REM Wasteland Core: update to the newest version (stop the server first).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update_wasteland.ps1" %*
pause
