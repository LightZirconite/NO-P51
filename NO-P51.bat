@echo off
setlocal ENABLEDELAYEDEXPANSION
set SCRIPT_DIR=%~dp0
if "%SCRIPT_DIR:~-1%"=="\" set SCRIPT_DIR=%SCRIPT_DIR:~0,-1%
set BOOTSTRAP_SCRIPT=%SCRIPT_DIR%\scripts\bootstrap.ps1

if not exist "%BOOTSTRAP_SCRIPT%" (
  echo Missing bootstrap script: %BOOTSTRAP_SCRIPT%
  exit /b 1
)

REM Auto-update: git pull
echo Checking for updates...
cd /d "%SCRIPT_DIR%"
git pull >nul 2>&1
if %ERRORLEVEL% EQU 0 (
  echo Updates checked successfully.
) else (
  echo Warning: Could not check for updates.
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "& '%BOOTSTRAP_SCRIPT%'"
endlocal
