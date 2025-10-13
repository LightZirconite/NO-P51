@echo off
setlocal ENABLEDELAYEDEXPANSION
set SCRIPT_DIR=%~dp0
if "%SCRIPT_DIR:~-1%"=="\" set SCRIPT_DIR=%SCRIPT_DIR:~0,-1%
set BOOTSTRAP_SCRIPT=%SCRIPT_DIR%\scripts\bootstrap.ps1

if not exist "%BOOTSTRAP_SCRIPT%" (
  echo Missing bootstrap script: %BOOTSTRAP_SCRIPT%
  exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%BOOTSTRAP_SCRIPT%"
endlocal
