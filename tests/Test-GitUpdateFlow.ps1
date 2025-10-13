# Test script for the new Git update flow

param(
  [switch]$DryRun
)

Write-Host ""
Write-Host "=== Testing NO-P51 Git Update Flow ===" -ForegroundColor Cyan
Write-Host ""

$scriptRoot = Split-Path -Parent $PSScriptRoot
$bootstrapPath = Join-Path $scriptRoot "scripts\bootstrap.ps1"
$batPath = Join-Path $scriptRoot "NO-P51.bat"
$guiPath = Join-Path $scriptRoot "scripts\no-p51-gui.ps1"

# Test 1: Check if files exist
Write-Host "Test 1: Checking required files..." -ForegroundColor Yellow
$allFilesExist = $true

if (Test-Path $bootstrapPath) {
  Write-Host "  OK bootstrap.ps1 exists" -ForegroundColor Green
} else {
  Write-Host "  ERROR bootstrap.ps1 NOT FOUND" -ForegroundColor Red
  $allFilesExist = $false
}

if (Test-Path $batPath) {
  Write-Host "  OK NO-P51.bat exists" -ForegroundColor Green
} else {
  Write-Host "  ERROR NO-P51.bat NOT FOUND" -ForegroundColor Red
  $allFilesExist = $false
}

if (Test-Path $guiPath) {
  Write-Host "  OK no-p51-gui.ps1 exists" -ForegroundColor Green
} else {
  Write-Host "  ERROR no-p51-gui.ps1 NOT FOUND" -ForegroundColor Red
  $allFilesExist = $false
}

if (-not $allFilesExist) {
  Write-Host ""
  Write-Host "Test FAILED: Missing required files" -ForegroundColor Red
  exit 1
}

# Test 2: Check if BAT file points to bootstrap
Write-Host ""
Write-Host "Test 2: Checking BAT file configuration..." -ForegroundColor Yellow
$batContent = Get-Content $batPath -Raw
if ($batContent -match "bootstrap\.ps1") {
  Write-Host "  OK BAT file correctly references bootstrap.ps1" -ForegroundColor Green
} else {
  Write-Host "  ERROR BAT file does NOT reference bootstrap.ps1" -ForegroundColor Red
  Write-Host "    Expected to find bootstrap.ps1 in NO-P51.bat" -ForegroundColor Yellow
  exit 1
}

# Test 3: Check if GUI has maintenance call commented
Write-Host ""
Write-Host "Test 3: Checking GUI script..." -ForegroundColor Yellow
$guiContent = Get-Content $guiPath -Raw
if ($guiContent -match "#\s*Invoke-Nop51GitMaintenance") {
  Write-Host "  OK Invoke-Nop51GitMaintenance is commented out" -ForegroundColor Green
} elseif ($guiContent -notmatch "Invoke-Nop51GitMaintenance") {
  Write-Host "  OK Invoke-Nop51GitMaintenance call not found (removed)" -ForegroundColor Green
} else {
  Write-Host "  WARNING Invoke-Nop51GitMaintenance is still active" -ForegroundColor Yellow
  Write-Host "    This will cause duplicate Git checks" -ForegroundColor Yellow
}

# Test 4: Check Git availability
Write-Host ""
Write-Host "Test 4: Checking Git installation..." -ForegroundColor Yellow
try {
  $gitCommand = Get-Command git -ErrorAction Stop
  $gitVersion = & git --version
  Write-Host "  OK Git is installed: $gitVersion" -ForegroundColor Green
} catch {
  Write-Host "  WARNING Git is not installed or not in PATH" -ForegroundColor Yellow
  Write-Host "    Bootstrap will skip update checks" -ForegroundColor Yellow
}

# Test 5: Check if in Git repository
Write-Host ""
Write-Host "Test 5: Checking Git repository..." -ForegroundColor Yellow
$gitFolder = Join-Path $scriptRoot ".git"
if (Test-Path $gitFolder) {
  Write-Host "  OK Running inside a Git repository" -ForegroundColor Green
  
  try {
    $remote = & git -C $scriptRoot remote get-url origin 2>$null
    if ($remote) {
      Write-Host "  OK Remote configured: $remote" -ForegroundColor Green
    } else {
      Write-Host "  WARNING No remote configured" -ForegroundColor Yellow
    }
  } catch {
    Write-Host "  WARNING Could not check remote" -ForegroundColor Yellow
  }
  
  try {
    $branch = & git -C $scriptRoot branch --show-current 2>$null
    if ($branch) {
      Write-Host "  OK Current branch: $branch" -ForegroundColor Green
    }
  } catch {
    Write-Host "  WARNING Could not check branch" -ForegroundColor Yellow
  }
  
} else {
  Write-Host "  WARNING Not a Git repository" -ForegroundColor Yellow
  Write-Host "    Bootstrap will skip update checks" -ForegroundColor Yellow
}

# Test 6: Check for local changes
Write-Host ""
Write-Host "Test 6: Checking for local changes..." -ForegroundColor Yellow
try {
  $status = & git -C $scriptRoot status --porcelain 2>$null
  if (-not $status) {
    Write-Host "  OK No local changes detected" -ForegroundColor Green
  } else {
    Write-Host "  WARNING Local changes detected:" -ForegroundColor Yellow
    $status | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
  }
} catch {
  Write-Host "  WARNING Could not check status" -ForegroundColor Yellow
}

# Test 7: Validate bootstrap.ps1 syntax
Write-Host ""
Write-Host "Test 7: Validating bootstrap.ps1 syntax..." -ForegroundColor Yellow
try {
  $errors = $null
  $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $bootstrapPath -Raw), [ref]$errors)
  if ($errors.Count -eq 0) {
    Write-Host "  OK bootstrap.ps1 has valid PowerShell syntax" -ForegroundColor Green
  } else {
    Write-Host "  ERROR Syntax errors in bootstrap.ps1:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
    exit 1
  }
} catch {
  Write-Host "  ERROR Could not validate syntax: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}

# Summary
Write-Host ""
Write-Host "=== Test Summary ===" -ForegroundColor Cyan
Write-Host "All tests passed!" -ForegroundColor Green
Write-Host ""
Write-Host "The new Git update flow is ready to use." -ForegroundColor Green
Write-Host "Run NO-P51.bat to test the complete flow." -ForegroundColor Cyan
Write-Host ""

if (-not $DryRun) {
  $response = Read-Host "Would you like to run NO-P51.bat now? (y/n)"
  if ($response -eq 'y' -or $response -eq 'Y') {
    Write-Host ""
    Write-Host "Launching NO-P51..." -ForegroundColor Cyan
    Start-Process -FilePath $batPath -WorkingDirectory $scriptRoot
  }
}
