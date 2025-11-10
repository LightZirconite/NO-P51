@echo off
setlocal ENABLEDELAYEDEXPANSION
title NO-P51 Setup

REM ========================================
REM    NO-P51 Setup Manager
REM ========================================

:MENU
cls
echo.
echo ========================================
echo    NO-P51 Setup Manager
echo ========================================
echo.
echo 1. Install NO-P51
echo 2. Uninstall NO-P51
echo 3. Repair/Reinstall NO-P51
echo 4. Exit
echo.
set /p CHOICE="Enter your choice (1-4): "

if "%CHOICE%"=="1" goto INSTALL
if "%CHOICE%"=="2" goto UNINSTALL
if "%CHOICE%"=="3" goto REPAIR
if "%CHOICE%"=="4" goto EXIT
goto MENU

REM ========================================
REM    INSTALLATION
REM ========================================
:INSTALL
cls
echo.
echo ========================================
echo    NO-P51 Installation
echo ========================================
echo.

REM Check if already installed
call :CHECK_INSTALLATION
if "%INSTALLED%"=="1" (
    echo NO-P51 is already installed at: %INSTALL_DIR%
    echo.
    set /p UPGRADE="Do you want to upgrade/reinstall? (Y/N): "
    if /i not "!UPGRADE!"=="Y" goto MENU
)

REM Check for administrator privileges
net session >nul 2>&1
if %errorLevel% == 0 (
    set "INSTALL_DIR=%ProgramFiles%\NO-P51"
    set "IS_ADMIN=1"
    echo [OK] Running with administrator privileges
    echo [OK] Installation directory: %ProgramFiles%\NO-P51
) else (
    set "INSTALL_DIR=%LOCALAPPDATA%\NO-P51"
    set "IS_ADMIN=0"
    echo [INFO] Running without administrator privileges
    echo [INFO] Installation directory: %LOCALAPPDATA%\NO-P51
)

echo.
echo ========================================
echo    Downloading from GitHub
echo ========================================
echo.

set "TEMP_DIR=%TEMP%\NO-P51-Install-%RANDOM%"
set "ZIP_FILE=%TEMP_DIR%\NO-P51.zip"
set "EXTRACT_DIR=%TEMP_DIR%\extract"
set "GITHUB_URL=https://github.com/LightZirconite/NO-P51/archive/refs/heads/main.zip"

REM Create temporary directory
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%"
if not exist "%EXTRACT_DIR%" mkdir "%EXTRACT_DIR%"

echo Downloading from: %GITHUB_URL%
echo.

REM Download using PowerShell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference = 'SilentlyContinue'; try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $webClient = New-Object System.Net.WebClient; $webClient.Headers.Add('User-Agent', 'NO-P51-Installer'); $webClient.DownloadFile('%GITHUB_URL%', '%ZIP_FILE%'); Write-Host '[OK] Download completed successfully' -ForegroundColor Green; } catch { Write-Host '[ERROR] Download failed:' $_.Exception.Message -ForegroundColor Red; exit 1; }"

if %errorLevel% neq 0 goto INSTALL_FAILED
if not exist "%ZIP_FILE%" goto INSTALL_FAILED

echo.
echo ========================================
echo    Extracting files
echo ========================================
echo.

REM Extract using PowerShell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::ExtractToDirectory('%ZIP_FILE%', '%EXTRACT_DIR%'); Write-Host '[OK] Extraction completed' -ForegroundColor Green"

if %errorLevel% neq 0 goto INSTALL_FAILED

REM Find the extracted folder (GitHub adds repo name prefix)
for /d %%i in ("%EXTRACT_DIR%\*") do set "SOURCE_DIR=%%i"

if not exist "%SOURCE_DIR%" goto INSTALL_FAILED

echo.
echo ========================================
echo    Installing to system
echo ========================================
echo.

REM Backup config if exists
set "CONFIG_BACKUP="
if exist "%INSTALL_DIR%\config.json" (
    echo [INFO] Backing up existing configuration...
    set "CONFIG_BACKUP=%TEMP%\NO-P51-config-backup-%RANDOM%.json"
    copy /Y "%INSTALL_DIR%\config.json" "!CONFIG_BACKUP!" >nul 2>&1
)

REM Create installation directory
if exist "%INSTALL_DIR%" (
    echo [INFO] Removing old installation...
    rmdir /s /q "%INSTALL_DIR%" 2>nul
    timeout /t 1 /nobreak >nul
)

mkdir "%INSTALL_DIR%" 2>nul

REM Copy files
echo [INFO] Copying files to %INSTALL_DIR%...
xcopy /E /I /H /Y "%SOURCE_DIR%\*" "%INSTALL_DIR%" >nul 2>&1

if %errorLevel% neq 0 goto INSTALL_FAILED
if not exist "%INSTALL_DIR%\NO-P51.bat" goto INSTALL_FAILED

REM Restore config if backed up
if defined CONFIG_BACKUP (
    if exist "!CONFIG_BACKUP!" (
        echo [INFO] Restoring configuration...
        copy /Y "!CONFIG_BACKUP!" "%INSTALL_DIR%\config.json" >nul 2>&1
        del /f /q "!CONFIG_BACKUP!" 2>nul
    )
)

echo [OK] Installation completed successfully!

echo.
echo ========================================
echo    Creating shortcuts
echo ========================================
echo.

call :CREATE_SHORTCUTS
if %errorLevel% neq 0 (
    echo [WARN] Failed to create some shortcuts
) else (
    echo [OK] Shortcuts created successfully
)

echo.
echo ========================================
echo    Cleaning up
echo ========================================
echo.

echo [INFO] Removing temporary files...
rmdir /s /q "%TEMP_DIR%" 2>nul

echo.
echo ========================================
echo    Installation Complete!
echo ========================================
echo.
echo [OK] NO-P51 has been successfully installed!
echo.
echo Installation directory: %INSTALL_DIR%
echo Desktop shortcut: %USERPROFILE%\Desktop\NO-P51.lnk
echo.
echo You can uninstall anytime by running setup.bat again (option 2)
echo.
echo.
set /p LAUNCH="Launch NO-P51 now? (Y/N): "
if /i "%LAUNCH%"=="Y" start "" "%INSTALL_DIR%\NO-P51.bat"

echo.
pause
goto MENU

:INSTALL_FAILED
echo.
echo [ERROR] Installation failed!
echo.
echo Please check:
echo - Internet connection
echo - Write permissions
echo - Disk space
echo.
if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%" 2>nul
pause
goto MENU

REM ========================================
REM    UNINSTALLATION
REM ========================================
:UNINSTALL
cls
echo.
echo ========================================
echo    NO-P51 Uninstallation
echo ========================================
echo.

call :CHECK_INSTALLATION
if "%INSTALLED%"=="0" (
    echo [INFO] NO-P51 is not installed on this system.
    echo.
    pause
    goto MENU
)

echo Found installation: %INSTALL_DIR%
echo.
echo This will completely remove NO-P51 from your system.
echo.
set /p CONFIRM="Are you sure you want to uninstall? (Y/N): "

if /i not "%CONFIRM%"=="Y" (
    echo [INFO] Uninstallation cancelled.
    pause
    goto MENU
)

echo.
echo ========================================
echo    Removing NO-P51
echo ========================================
echo.

REM Stop any running instances
echo [INFO] Stopping NO-P51 processes...
taskkill /F /IM powershell.exe /FI "WINDOWTITLE eq NO-P51*" >nul 2>&1
timeout /t 1 /nobreak >nul

REM Remove shortcuts
call :REMOVE_SHORTCUTS

REM Remove installation directory
echo [INFO] Removing installation directory...
timeout /t 2 /nobreak >nul
rmdir /s /q "%INSTALL_DIR%" 2>nul

if exist "%INSTALL_DIR%" (
    echo.
    echo [WARN] Some files could not be removed.
    echo Please close all NO-P51 windows and try again.
    echo.
    pause
    goto MENU
)

echo [OK] Installation directory removed

echo.
echo ========================================
echo    Uninstallation Complete!
echo ========================================
echo.
echo [OK] NO-P51 has been successfully removed from your system.
echo.
pause
goto MENU

REM ========================================
REM    REPAIR/REINSTALL
REM ========================================
:REPAIR
cls
echo.
echo ========================================
echo    NO-P51 Repair/Reinstall
echo ========================================
echo.

call :CHECK_INSTALLATION
if "%INSTALLED%"=="0" (
    echo [INFO] NO-P51 is not installed. Redirecting to installation...
    timeout /t 2 /nobreak >nul
    goto INSTALL
)

echo Current installation: %INSTALL_DIR%
echo.
echo This will reinstall NO-P51 while preserving your configuration.
echo.
set /p CONFIRM="Continue with repair? (Y/N): "

if /i not "%CONFIRM%"=="Y" (
    echo [INFO] Repair cancelled.
    pause
    goto MENU
)

goto INSTALL

REM ========================================
REM    HELPER FUNCTIONS
REM ========================================

:CHECK_INSTALLATION
set "INSTALLED=0"
set "INSTALL_DIR="

if exist "%ProgramFiles%\NO-P51\NO-P51.bat" (
    set "INSTALL_DIR=%ProgramFiles%\NO-P51"
    set "INSTALLED=1"
    goto :EOF
)

if exist "%LOCALAPPDATA%\NO-P51\NO-P51.bat" (
    set "INSTALL_DIR=%LOCALAPPDATA%\NO-P51"
    set "INSTALLED=1"
    goto :EOF
)

goto :EOF

:CREATE_SHORTCUTS
set "DESKTOP=%USERPROFILE%\Desktop"
set "SHORTCUT=%DESKTOP%\NO-P51.lnk"
set "TARGET=%INSTALL_DIR%\NO-P51.bat"
set "ICON=%INSTALL_DIR%\logo.ico"
set "WORKDIR=%INSTALL_DIR%"

echo [INFO] Creating desktop shortcut...

powershell -NoProfile -ExecutionPolicy Bypass -Command "$WScriptShell = New-Object -ComObject WScript.Shell; $Shortcut = $WScriptShell.CreateShortcut('%SHORTCUT%'); $Shortcut.TargetPath = '%TARGET%'; $Shortcut.WorkingDirectory = '%WORKDIR%'; $Shortcut.IconLocation = '%ICON%'; $Shortcut.Description = 'NO-P51 - Hide applications with global hotkeys'; $Shortcut.WindowStyle = 7; $Shortcut.Save()" 2>nul

if exist "%SHORTCUT%" (
    echo [OK] Desktop shortcut created
) else (
    echo [WARN] Desktop shortcut creation failed
)

REM Create Start Menu shortcut
if "%IS_ADMIN%"=="1" (
    set "STARTMENU=%ProgramData%\Microsoft\Windows\Start Menu\Programs"
) else (
    set "STARTMENU=%APPDATA%\Microsoft\Windows\Start Menu\Programs"
)

set "STARTMENU_SHORTCUT=%STARTMENU%\NO-P51.lnk"

echo [INFO] Creating Start Menu shortcut...

powershell -NoProfile -ExecutionPolicy Bypass -Command "$WScriptShell = New-Object -ComObject WScript.Shell; $Shortcut = $WScriptShell.CreateShortcut('%STARTMENU_SHORTCUT%'); $Shortcut.TargetPath = '%TARGET%'; $Shortcut.WorkingDirectory = '%WORKDIR%'; $Shortcut.IconLocation = '%ICON%'; $Shortcut.Description = 'NO-P51 - Hide applications with global hotkeys'; $Shortcut.WindowStyle = 7; $Shortcut.Save()" 2>nul

if exist "%STARTMENU_SHORTCUT%" (
    echo [OK] Start Menu shortcut created
) else (
    echo [WARN] Start Menu shortcut creation failed
)

goto :EOF

:REMOVE_SHORTCUTS
set "DESKTOP=%USERPROFILE%\Desktop"

if exist "%DESKTOP%\NO-P51.lnk" (
    echo [INFO] Removing desktop shortcut...
    del /f /q "%DESKTOP%\NO-P51.lnk" 2>nul
    if not exist "%DESKTOP%\NO-P51.lnk" echo [OK] Desktop shortcut removed
)

if exist "%ProgramData%\Microsoft\Windows\Start Menu\Programs\NO-P51.lnk" (
    echo [INFO] Removing Start Menu shortcut...
    del /f /q "%ProgramData%\Microsoft\Windows\Start Menu\Programs\NO-P51.lnk" 2>nul
    if not exist "%ProgramData%\Microsoft\Windows\Start Menu\Programs\NO-P51.lnk" echo [OK] Start Menu shortcut removed
)

if exist "%APPDATA%\Microsoft\Windows\Start Menu\Programs\NO-P51.lnk" (
    echo [INFO] Removing Start Menu shortcut...
    del /f /q "%APPDATA%\Microsoft\Windows\Start Menu\Programs\NO-P51.lnk" 2>nul
    if not exist "%APPDATA%\Microsoft\Windows\Start Menu\Programs\NO-P51.lnk" echo [OK] Start Menu shortcut removed
)

goto :EOF

:EXIT
cls
echo.
echo Thank you for using NO-P51 Setup Manager!
echo.
timeout /t 2 /nobreak >nul
endlocal
exit /b 0
