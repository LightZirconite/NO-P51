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
for /f "delims=" %%i in ('git pull 2^>^&1') do set GIT_OUTPUT=%%i
echo %GIT_OUTPUT% | find "Already up to date" >nul
if %ERRORLEVEL% NEQ 0 (
  echo Updates downloaded. Restarting...
  timeout /t 2 >nul
  call "%~f0"
  exit /b 0
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "& '%BOOTSTRAP_SCRIPT%'"
endlocal
