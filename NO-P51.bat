@echo off
setlocal ENABLEDELAYEDEXPANSION
set SCRIPT_DIR=%~dp0
if "%SCRIPT_DIR:~-1%"=="\" set SCRIPT_DIR=%SCRIPT_DIR:~0,-1%
set BOOTSTRAP_SCRIPT=%SCRIPT_DIR%\scripts\bootstrap.ps1
set UPDATE_SCRIPT=%SCRIPT_DIR%\scripts\auto-update.ps1

if not exist "%BOOTSTRAP_SCRIPT%" (
  echo Missing bootstrap script: %BOOTSTRAP_SCRIPT%
  exit /b 1
)

REM Auto-update check
if exist "%UPDATE_SCRIPT%" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "& '%UPDATE_SCRIPT%'"
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "& '%BOOTSTRAP_SCRIPT%'"
endlocal
