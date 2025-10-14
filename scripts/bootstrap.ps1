param(
  [string]$ConfigPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath "config.json"),
  [switch]$SkipUpdateCheck,
  [switch]$ForceUpdate,
  [switch]$Verbose
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:repoRoot = Split-Path -Parent $PSScriptRoot
$script:guiScriptPath = Join-Path $PSScriptRoot "no-p51-gui.ps1"

function Start-GuiApplication {
  Write-Host "Launching NO-P51 GUI..." -ForegroundColor Cyan
  
  if (-not (Test-Path -LiteralPath $script:guiScriptPath)) {
    Write-Host "ERROR: GUI script not found: $script:guiScriptPath" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
  }
  
  $arguments = @(
    "-NoLogo",
    "-NoProfile",
    "-WindowStyle", "Hidden",
    "-ExecutionPolicy", "Bypass",
    "-File", $script:guiScriptPath
  )
  
  if ($ConfigPath) {
    $arguments += "-ConfigPath"
    $arguments += $ConfigPath
  }
  
  try {
    Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -WindowStyle Hidden
    Write-Host "Application launched successfully" -ForegroundColor Green
  } catch {
    Write-Host "ERROR: Failed to launch application: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
  }
}

# Main execution
Write-Host ""
Write-Host "NO-P51 Bootstrap" -ForegroundColor Cyan
Write-Host ""

Start-GuiApplication
Start-Sleep -Seconds 1

exit 0
