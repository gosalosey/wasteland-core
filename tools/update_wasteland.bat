@echo off
REM Wasteland Core: update to the newest version (stop the server first).
REM Keep this file next to update_wasteland.ps1 (or update.ps1).
set "WLPS=%~dp0update_wasteland.ps1"
if not exist "%WLPS%" set "WLPS=%~dp0update.ps1"
if not exist "%WLPS%" (
  echo Could not find update_wasteland.ps1 next to this file:
  echo   %~dp0
  echo Download it from https://raw.githubusercontent.com/gosalosey/wasteland-core/main/tools/update.ps1
  echo and save it in this folder as update_wasteland.ps1
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%WLPS%" %*
pause
