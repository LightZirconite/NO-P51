@echo off
setlocal ENABLEDELAYEDEXPANSION
set SCRIPT_DIR=%~dp0
if "%SCRIPT_DIR:~-1%"=="\" set SCRIPT_DIR=%SCRIPT_DIR:~0,-1%
set BOOTSTRAP_SCRIPT=%SCRIPT_DIR%\scripts\bootstrap.ps1

if not exist "%BOOTSTRAP_SCRIPT%" (
  echo Missing bootstrap script: %BOOTSTRAP_SCRIPT%
  exit /b 1
)

REM Check for command line arguments
set SKIP_UPDATE=
set FORCE_UPDATE=
set VERBOSE=

:parse_args
if "%~1"=="" goto end_parse
if /i "%~1"=="--skip-update" set SKIP_UPDATE=-SkipUpdateCheck
if /i "%~1"=="--force-update" set FORCE_UPDATE=-ForceUpdate
if /i "%~1"=="--verbose" set VERBOSE=-Verbose
if /i "%~1"=="-v" set VERBOSE=-Verbose
shift
goto parse_args

:end_parse

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "& '%BOOTSTRAP_SCRIPT%' %SKIP_UPDATE% %FORCE_UPDATE% %VERBOSE%"
endlocal
