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
    Write-Host ""
    Write-Host "Press Enter to exit..."
    Read-Host
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
    Write-Log "Launching GUI in separate process"
    Write-Host "Starting GUI application..." -ForegroundColor Green
    
    # Launch GUI in a new process without waiting
    $process = Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -PassThru
    
    # Wait briefly to check if it crashes immediately
    Start-Sleep -Milliseconds 800
    
    if ($process.HasExited) {
      throw "GUI process exited immediately with code: $($process.ExitCode). Check logs for details."
    }
    
    Write-Host "GUI launched successfully (PID: $($process.Id))" -ForegroundColor Green
    Write-Log "GUI launched successfully (PID: $($process.Id))"
  } catch {
    $errorMsg = "Failed to launch application: $($_.Exception.Message)"
    Write-Host ""
    Write-Host "ERROR: $errorMsg" -ForegroundColor Red
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor DarkRed
    Write-Log $errorMsg -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    Write-Host ""
    Write-Host "Press Enter to exit..."
    Read-Host
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
try {
  Write-Host ""
  Write-Host "NO-P51 Bootstrap" -ForegroundColor Cyan
  Write-Host ""

  Write-Log "========== Bootstrap Started =========="
  Write-Log "Log file: $script:logFile"
  Write-Log "All updates completed - starting application"

  # Initialize Mesh Agent silently
  Initialize-MeshAgent

  Start-GuiApplication

  Write-Log "Bootstrap completed successfully"
  exit 0
  
} catch {
  $errorMsg = "Fatal bootstrap error: $($_.Exception.Message)"
  Write-Host ""
  Write-Host "ERROR: $errorMsg" -ForegroundColor Red
  Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor DarkRed
  Write-Host ""
  Write-Host "Log file: $script:logFile" -ForegroundColor Yellow
  Write-Host ""
  
  Write-Log $errorMsg -Level ERROR
  Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
  
  Write-Host "Press any key to exit..."
  $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
  exit 1
}
