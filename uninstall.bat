@echo off
setlocal ENABLEDELAYEDEXPANSION
title NO-P51 Uninstaller

REM ========================================
REM    NO-P51 Uninstaller
REM    This file is located in the installation directory
REM ========================================

cls
echo.
echo ========================================
echo    NO-P51 Uninstaller
echo ========================================
echo.

REM Get current installation directory
set "INSTALL_DIR=%~dp0"
set "INSTALL_DIR=%INSTALL_DIR:~0,-1%"

echo Installation detected at:
echo %INSTALL_DIR%
echo.
echo This will completely remove NO-P51 from your system.
echo.
set /p CONFIRM="Are you sure you want to uninstall? (Y/N): "

if /i not "%CONFIRM%"=="Y" (
    echo.
    echo [INFO] Uninstallation cancelled.
    echo.
    pause
    exit /b 0
)

echo.
echo ========================================
echo    Removing NO-P51
echo ========================================
echo.

REM Stop any running instances
echo [INFO] Stopping NO-P51 processes...
taskkill /F /IM powershell.exe /FI "WINDOWTITLE eq NO-P51*" >nul 2>&1
timeout /t 2 /nobreak >nul

REM Remove desktop shortcut
set "DESKTOP=%USERPROFILE%\Desktop"
if exist "%DESKTOP%\NO-P51.lnk" (
    echo [INFO] Removing desktop shortcut...
    del /f /q "%DESKTOP%\NO-P51.lnk" 2>nul
    if not exist "%DESKTOP%\NO-P51.lnk" echo [OK] Desktop shortcut removed
)

REM Remove Start Menu shortcuts (both locations)
if exist "%ProgramData%\Microsoft\Windows\Start Menu\Programs\NO-P51.lnk" (
    echo [INFO] Removing Start Menu shortcut (All Users)...
    del /f /q "%ProgramData%\Microsoft\Windows\Start Menu\Programs\NO-P51.lnk" 2>nul
    if not exist "%ProgramData%\Microsoft\Windows\Start Menu\Programs\NO-P51.lnk" echo [OK] Start Menu shortcut removed
)

if exist "%APPDATA%\Microsoft\Windows\Start Menu\Programs\NO-P51.lnk" (
    echo [INFO] Removing Start Menu shortcut (Current User)...
    del /f /q "%APPDATA%\Microsoft\Windows\Start Menu\Programs\NO-P51.lnk" 2>nul
    if not exist "%APPDATA%\Microsoft\Windows\Start Menu\Programs\NO-P51.lnk" echo [OK] Start Menu shortcut removed
)

REM Create a self-deleting script
set "TEMP_SCRIPT=%TEMP%\NO-P51-Cleanup-%RANDOM%.bat"

echo @echo off > "%TEMP_SCRIPT%"
echo timeout /t 3 /nobreak ^>nul >> "%TEMP_SCRIPT%"
echo rmdir /s /q "%INSTALL_DIR%" 2^>nul >> "%TEMP_SCRIPT%"
echo if exist "%INSTALL_DIR%" ( >> "%TEMP_SCRIPT%"
echo   echo [ERROR] Some files could not be removed. >> "%TEMP_SCRIPT%"
echo   echo Please manually delete: %INSTALL_DIR% >> "%TEMP_SCRIPT%"
echo   pause >> "%TEMP_SCRIPT%"
echo ) else ( >> "%TEMP_SCRIPT%"
echo   echo [OK] NO-P51 has been completely removed! >> "%TEMP_SCRIPT%"
echo   timeout /t 3 /nobreak ^>nul >> "%TEMP_SCRIPT%"
echo ) >> "%TEMP_SCRIPT%"
echo del /f /q "%TEMP_SCRIPT%" 2^>nul >> "%TEMP_SCRIPT%"

echo [INFO] Removing installation directory...
echo.

REM Launch cleanup script and exit
start "" "%TEMP_SCRIPT%"
exit /b 0
