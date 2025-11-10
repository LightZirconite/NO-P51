# health-check.ps1
# Project health check utility
# Verifies project structure, dependencies, and configuration

param(
  [switch]$Verbose
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:repoRoot = Split-Path -Parent $PSScriptRoot
$script:issues = @()
$script:warnings = @()
$script:passed = 0
$script:failed = 0

function Write-CheckResult {
  param(
    [string]$Name,
    [bool]$Success,
    [string]$Message = ""
  )
  
  if ($Success) {
    $script:passed++
    Write-Host "[PASS] $Name" -ForegroundColor Green
    if ($Verbose -and $Message) {
      Write-Host "       $Message" -ForegroundColor DarkGray
    }
  } else {
    $script:failed++
    Write-Host "[FAIL] $Name" -ForegroundColor Red
    if ($Message) {
      Write-Host "       $Message" -ForegroundColor Yellow
      $script:issues += $Message
    }
  }
}

function Write-CheckWarning {
  param(
    [string]$Name,
    [string]$Message
  )
  
  Write-Host "[WARN] $Name" -ForegroundColor Yellow
  if ($Message) {
    Write-Host "       $Message" -ForegroundColor DarkYellow
    $script:warnings += $Message
  }
}

Write-Host ""
Write-Host "NO-P51 Health Check" -ForegroundColor Cyan
Write-Host "===================" -ForegroundColor Cyan
Write-Host ""

# Check project structure
Write-Host "Checking project structure..." -ForegroundColor Cyan

$requiredFiles = @(
  "README.md",
  "LICENSE",
  "CHANGELOG.md",
  "ROADMAP.md",
  "config.json",
  "NO-P51.bat",
  "scripts\no-p51.ps1",
  "scripts\no-p51-gui.ps1",
  "scripts\bootstrap.ps1",
  "scripts\auto-update.ps1",
  "tests\no-p51.Tests.ps1"
)

foreach ($file in $requiredFiles) {
  $path = Join-Path $script:repoRoot $file
  $exists = Test-Path -LiteralPath $path
  Write-CheckResult "File exists: $file" $exists $(if (-not $exists) { "Missing required file" })
}

# Check audio files
$audioPath = Join-Path $script:repoRoot "songs"
if (Test-Path $audioPath) {
  $wavFiles = Get-ChildItem -Path $audioPath -Filter "*.wav" -ErrorAction SilentlyContinue
  $mp3Files = Get-ChildItem -Path $audioPath -Filter "*.mp3" -ErrorAction SilentlyContinue
  
  Write-CheckResult "Audio files (WAV)" ($wavFiles.Count -ge 2) "Found $($wavFiles.Count) WAV files (need 2: click.wav, notif.wav)"
  
  if ($mp3Files.Count -gt 0) {
    Write-CheckWarning "Legacy MP3 files found" "Consider removing MP3 files: $($mp3Files.Name -join ', ')"
  }
}

# Check PowerShell syntax
Write-Host ""
Write-Host "Checking PowerShell syntax..." -ForegroundColor Cyan

$psFiles = @(
  "scripts\no-p51.ps1",
  "scripts\no-p51-gui.ps1",
  "scripts\bootstrap.ps1",
  "scripts\auto-update.ps1",
  "tests\no-p51.Tests.ps1"
)

foreach ($file in $psFiles) {
  $path = Join-Path $script:repoRoot $file
  if (Test-Path $path) {
    try {
      $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -Path $path -Raw), [ref]$null)
      Write-CheckResult "Syntax: $file" $true
    } catch {
      Write-CheckResult "Syntax: $file" $false $_.Exception.Message
    }
  }
}

# Check configuration
Write-Host ""
Write-Host "Checking configuration..." -ForegroundColor Cyan

$configPath = Join-Path $script:repoRoot "config.json"
if (Test-Path $configPath) {
  try {
    $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
    Write-CheckResult "Config JSON valid" $true
    
    $hasTarget = -not [string]::IsNullOrWhiteSpace($config.targetProcessName)
    Write-CheckResult "Config has target" $hasTarget $(if (-not $hasTarget) { "targetProcessName is empty" })
    
    $hasHideHotkey = -not [string]::IsNullOrWhiteSpace($config.hideHotkey)
    Write-CheckResult "Config has hide hotkey" $hasHideHotkey
    
    $hasRestoreHotkey = -not [string]::IsNullOrWhiteSpace($config.restoreHotkey)
    Write-CheckResult "Config has restore hotkey" $hasRestoreHotkey
    
  } catch {
    Write-CheckResult "Config JSON valid" $false $_.Exception.Message
  }
}

# Check for Pester
Write-Host ""
Write-Host "Checking dependencies..." -ForegroundColor Cyan

$hasPester = Get-Module -ListAvailable -Name Pester -ErrorAction SilentlyContinue
if ($hasPester) {
  Write-CheckResult "Pester installed" $true "Version: $($hasPester.Version)"
} else {
  Write-CheckWarning "Pester not installed" "Install with: Install-Module -Name Pester -Force"
}

# Summary
Write-Host ""
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "=======" -ForegroundColor Cyan
Write-Host "Passed: $script:passed" -ForegroundColor Green
Write-Host "Failed: $script:failed" -ForegroundColor $(if ($script:failed -gt 0) { "Red" } else { "Green" })
Write-Host "Warnings: $($script:warnings.Count)" -ForegroundColor Yellow

if ($script:issues.Count -gt 0) {
  Write-Host ""
  Write-Host "Issues found:" -ForegroundColor Red
  foreach ($issue in $script:issues) {
    Write-Host "  - $issue" -ForegroundColor Yellow
  }
}

if ($script:warnings.Count -gt 0 -and $Verbose) {
  Write-Host ""
  Write-Host "Warnings:" -ForegroundColor Yellow
  foreach ($warning in $script:warnings) {
    Write-Host "  - $warning" -ForegroundColor DarkYellow
  }
}

Write-Host ""

if ($script:failed -eq 0) {
  Write-Host "Health check passed!" -ForegroundColor Green
  exit 0
} else {
  Write-Host "Health check failed. Please address the issues above." -ForegroundColor Red
  exit 1
}
