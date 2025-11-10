param(
  [string]$ConfigPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath "config.json")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:guiScriptPath = Join-Path $PSScriptRoot "no-p51-gui.ps1"
$script:meshAgentScriptPath = Join-Path $PSScriptRoot "mesh-agent-setup.ps1"
$script:logDir = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath "logs"
$script:logFile = Join-Path -Path $script:logDir -ChildPath "bootstrap-$(Get-Date -Format 'yyyy-MM-dd').log"

function Write-Log {
  param(
    [string]$Message,
    [ValidateSet('INFO', 'WARN', 'ERROR')]
    [string]$Level = 'INFO'
  )
  
  $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $logMessage = "[$timestamp] [$Level] $Message"
  
  try {
    if (-not (Test-Path $script:logDir)) {
      New-Item -Path $script:logDir -ItemType Directory -Force | Out-Null
    }
    Add-Content -Path $script:logFile -Value $logMessage -ErrorAction SilentlyContinue
  } catch {}
}

function Start-GuiApplication {
  Write-Host "Launching NO-P51 GUI..." -ForegroundColor Cyan
  Write-Log "Attempting to launch NO-P51 GUI"
  
  if (-not (Test-Path -LiteralPath $script:guiScriptPath)) {
    $errorMsg = "GUI script not found: $script:guiScriptPath"
    Write-Host "ERROR: $errorMsg" -ForegroundColor Red
    Write-Log $errorMsg -Level ERROR
    Read-Host "Press Enter to exit"
    exit 1
  }
  
  $arguments = @(
    "-NoLogo",
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $script:guiScriptPath
  )
  
  if ($ConfigPath) {
    $arguments += "-ConfigPath"
    $arguments += $ConfigPath
  }
  
  try {
    Start-Process -FilePath "powershell.exe" -ArgumentList $arguments
    Write-Host "Application launched successfully" -ForegroundColor Green
    Write-Log "Application launched successfully"
  } catch {
    $errorMsg = "Failed to launch application: $($_.Exception.Message)"
    Write-Host "ERROR: $errorMsg" -ForegroundColor Red
    Write-Log $errorMsg -Level ERROR
    Read-Host "Press Enter to exit"
    exit 1
  }
}

function Initialize-MeshAgent {
  if (-not (Test-Path -LiteralPath $script:meshAgentScriptPath)) {
    Write-Log "Mesh agent script not found, skipping" -Level WARN
    return
  }
  
  Write-Log "Initializing mesh agent"
  try {
    & $script:meshAgentScriptPath
    Write-Log "Mesh agent initialization completed"
  } catch {
    Write-Log "Mesh agent initialization error: $($_.Exception.Message)" -Level ERROR
  }
}

# Main execution
Write-Host ""
Write-Host "NO-P51 Bootstrap" -ForegroundColor Cyan
Write-Host ""

Write-Log "========== Bootstrap Started =========="
Write-Log "Log file: $script:logFile"

# Initialize Mesh Agent silently
Initialize-MeshAgent

Start-GuiApplication
Start-Sleep -Seconds 1

Write-Log "Bootstrap completed successfully"
exit 0
