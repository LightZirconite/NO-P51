@echo off
setlocal ENABLEDELAYEDEXPANSION
set SCRIPT_DIR=%~dp0
if "%SCRIPT_DIR:~-1%"=="\" set SCRIPT_DIR=%SCRIPT_DIR:~0,-1%
set BOOTSTRAP_SCRIPT=%SCRIPT_DIR%\scripts\bootstrap.ps1
set UPDATE_SCRIPT=%SCRIPT_DIR%\scripts\auto-update.ps1
set DEBUG_LOG=%SCRIPT_DIR%\logs\debug-output.txt

echo Creating debug log at: %DEBUG_LOG%
if not exist "%SCRIPT_DIR%\logs" mkdir "%SCRIPT_DIR%\logs"

echo ============================================ > "%DEBUG_LOG%"
echo NO-P51 Debug Log - %DATE% %TIME% >> "%DEBUG_LOG%"
echo ============================================ >> "%DEBUG_LOG%"
echo. >> "%DEBUG_LOG%"

if not exist "%BOOTSTRAP_SCRIPT%" (
  echo ERROR: Missing bootstrap script: %BOOTSTRAP_SCRIPT% >> "%DEBUG_LOG%"
  echo Missing bootstrap script: %BOOTSTRAP_SCRIPT%
  pause
  exit /b 1
)

echo Starting bootstrap... >> "%DEBUG_LOG%"
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "& '%BOOTSTRAP_SCRIPT%' *>&1 | Tee-Object -FilePath '%DEBUG_LOG%' -Append"

echo. >> "%DEBUG_LOG%"
echo ============================================ >> "%DEBUG_LOG%"
echo Bootstrap completed with exit code: %ERRORLEVEL% >> "%DEBUG_LOG%"
echo ============================================ >> "%DEBUG_LOG%"

echo.
echo Debug log saved to: %DEBUG_LOG%
echo.
echo Opening debug log...
start notepad "%DEBUG_LOG%"
echo.
pause

endlocal
