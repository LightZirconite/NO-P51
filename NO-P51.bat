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

:CHECK_UPDATE
REM Auto-update check
set UPDATE_INSTALLED=0
if exist "%UPDATE_SCRIPT%" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$result = & '%UPDATE_SCRIPT%'; if ($result) { exit 1 } else { exit 0 }"
  if errorlevel 1 (
    echo Update installed, restarting...
    timeout /t 2 /nobreak >nul
    goto CHECK_UPDATE
  )
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "& '%BOOTSTRAP_SCRIPT%' *>&1"

echo.
echo Application closed.
echo.
pause >nul
endlocal
