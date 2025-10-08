@echo off
setlocal ENABLEDELAYEDEXPANSION
set SCRIPT_DIR=%~dp0
if "%SCRIPT_DIR:~-1%"=="\" set SCRIPT_DIR=%SCRIPT_DIR:~0,-1%
set PS_SCRIPT=%SCRIPT_DIR%\scripts\no-p51-gui.ps1

if not exist "%PS_SCRIPT%" (
  echo Missing GUI script: %PS_SCRIPT%
  exit /b 1
)

start "" powershell.exe -NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
endlocal
