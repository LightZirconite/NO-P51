param(
  [string]$ConfigPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath "config.json")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:repoRoot = Split-Path -Parent $PSScriptRoot
$script:guiScriptPath = Join-Path $PSScriptRoot "no-p51-gui.ps1"

function Write-BootstrapLog {
  param([string]$Message, [string]$Type = "Info")
  
  $timestamp = Get-Date -Format "HH:mm:ss"
  $prefix = switch ($Type) {
    "Error" { "[ERROR]" }
    "Warning" { "[WARN]" }
    "Success" { "[OK]" }
    default { "[INFO]" }
  }
  
  Write-Host "$timestamp $prefix $Message" -ForegroundColor $(
    switch ($Type) {
      "Error" { "Red" }
      "Warning" { "Yellow" }
      "Success" { "Green" }
      default { "Cyan" }
    }
  )
}

function Test-GitInstalled {
  try {
    $gitCommand = Get-Command -Name git -ErrorAction Stop
    return $gitCommand
  } catch {
    Write-BootstrapLog "Git is not installed or not in PATH" "Error"
    Write-BootstrapLog "Please install Git from: https://git-scm.com/download/win" "Warning"
    return $null
  }
}

function Test-GitRepository {
  $gitFolder = Join-Path -Path $script:repoRoot -ChildPath ".git"
  if (-not (Test-Path -LiteralPath $gitFolder)) {
    Write-BootstrapLog "Not a Git repository. Skipping update check." "Warning"
    return $false
  }
  return $true
}

function Get-GitStatus {
  param([object]$GitCommand)
  
  try {
    $statusOutput = & $GitCommand.Path -C $script:repoRoot status --porcelain 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-BootstrapLog "Failed to get Git status (code: $LASTEXITCODE)" "Warning"
      return $null
    }
    
    $statusLines = @()
    if ($statusOutput -is [System.Array]) {
      foreach ($line in $statusOutput) {
        if ($null -ne $line) {
          $statusLines += $line.ToString().Trim()
        }
      }
    } elseif ($statusOutput) {
      $statusLines = @($statusOutput.ToString().Trim())
    }
    
    return $statusLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  } catch {
    Write-BootstrapLog "Exception getting Git status: $($_.Exception.Message)" "Warning"
    return $null
  }
}

function Test-AllowedGitPath {
  param([string]$Path)
  
  if ([string]::IsNullOrWhiteSpace($Path)) {
    return $false
  }
  
  $normalized = $Path.Replace('\', '/')
  $normalized = $normalized.TrimStart('.', '/')
  
  $allowedPaths = @(
    "config.json"
  )
  
  foreach ($allowed in $allowedPaths) {
    if ($normalized -eq $allowed -or $normalized -eq "./$allowed" -or $normalized -eq $allowed) {
      return $true
    }
  }
  
  return $false
}

function Invoke-GitPull {
  param(
    [object]$GitCommand,
    [bool]$UseAutoStash = $false
  )
  
  $pullArgs = @("-C", $script:repoRoot, "pull", "--ff-only")
  if ($UseAutoStash) {
    $pullArgs += "--autostash"
  }
  
  Write-BootstrapLog "Running: git pull $(if ($UseAutoStash) { '--autostash' })" "Info"
  
  try {
    $output = & $GitCommand.Path @pullArgs 2>&1
    $exitCode = $LASTEXITCODE
    
    $outputLines = @()
    if ($output -is [System.Array]) {
      foreach ($line in $output) {
        if ($null -ne $line) {
          $outputLines += $line.ToString().TrimEnd("`r", "`n")
        }
      }
    } elseif ($output) {
      $outputLines = @($output.ToString().TrimEnd("`r", "`n"))
    }
    
    return [pscustomobject]@{
      ExitCode = $exitCode
      Output = $outputLines
      Success = ($exitCode -eq 0)
    }
  } catch {
    Write-BootstrapLog "Exception during git pull: $($_.Exception.Message)" "Error"
    return [pscustomobject]@{
      ExitCode = 1
      Output = @($_.Exception.Message)
      Success = $false
    }
  }
}

function Invoke-GitUpdate {
  param([object]$GitCommand)
  
  Write-BootstrapLog "Checking for updates..." "Info"
  
  # Get current HEAD
  $currentHead = $null
  try {
    $currentHead = (& $GitCommand.Path -C $script:repoRoot rev-parse HEAD 2>$null).Trim()
  } catch {
    Write-BootstrapLog "Could not get current HEAD" "Warning"
  }
  
  # Check for local changes
  $statusLines = Get-GitStatus -GitCommand $GitCommand
  $hasBlockingChanges = $false
  $useAutoStash = $false
  
  if ($statusLines -and $statusLines.Count -gt 0) {
    Write-BootstrapLog "Found $($statusLines.Count) local change(s)" "Info"
    
    $blockedChanges = @()
    foreach ($line in $statusLines) {
      if ($line.Length -lt 3) { continue }
      
      $status = $line.Substring(0, 2)
      $path = $line.Substring(3).Trim()
      
      if ($path -match "\s->\s") {
        $parts = $path -split "\s->\s"
        if ($parts.Count -gt 0) {
          $path = $parts[-1].Trim()
        }
      }
      
      if (-not (Test-AllowedGitPath -Path $path)) {
        $blockedChanges += "$status $path"
      }
    }
    
    if ($blockedChanges.Count -gt 0) {
      Write-BootstrapLog "Local changes detected (excluding config.json):" "Warning"
      foreach ($change in $blockedChanges) {
        Write-Host "  $change" -ForegroundColor Yellow
      }
      Write-BootstrapLog "Skipping update. Commit or stash changes first." "Warning"
      return $false
    }
    
    $useAutoStash = $true
  }
  
  # Fetch remote changes first
  Write-BootstrapLog "Fetching remote changes..." "Info"
  try {
    & $GitCommand.Path -C $script:repoRoot fetch 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
      Write-BootstrapLog "Git fetch failed (code: $LASTEXITCODE)" "Warning"
    }
  } catch {
    Write-BootstrapLog "Exception during fetch: $($_.Exception.Message)" "Warning"
  }
  
  # Try pull with --ff-only first
  $pullResult = Invoke-GitPull -GitCommand $GitCommand -UseAutoStash $useAutoStash
  
  if (-not $pullResult.Success) {
    # Check if it's a non-fast-forward issue
    $nonFastForward = $false
    foreach ($line in $pullResult.Output) {
      if ($line -match "not possible to fast-forward|need to specify how to reconcile|refusing to merge") {
        $nonFastForward = $true
        break
      }
    }
    
    if ($nonFastForward) {
      Write-BootstrapLog "Fast-forward not possible, trying normal pull..." "Warning"
      $fallbackArgs = @("-C", $script:repoRoot, "pull")
      if ($useAutoStash) {
        $fallbackArgs += "--autostash"
      }
      
      try {
        $output = & $GitCommand.Path @fallbackArgs 2>&1
        $exitCode = $LASTEXITCODE
        
        if ($exitCode -eq 0) {
          Write-BootstrapLog "Update successful (with merge)" "Success"
          $pullResult = [pscustomobject]@{
            ExitCode = 0
            Output = $output
            Success = $true
          }
        } else {
          Write-BootstrapLog "Fallback pull also failed" "Error"
          foreach ($line in $output) {
            Write-Host "  $line" -ForegroundColor Red
          }
          return $false
        }
      } catch {
        Write-BootstrapLog "Exception during fallback pull: $($_.Exception.Message)" "Error"
        return $false
      }
    } else {
      Write-BootstrapLog "Git pull failed:" "Error"
      foreach ($line in $pullResult.Output) {
        Write-Host "  $line" -ForegroundColor Red
      }
      
      # Check if credentials are needed
      $needsAuth = $false
      foreach ($line in $pullResult.Output) {
        if ($line -match "could not read Username|authentication failed") {
          $needsAuth = $true
          break
        }
      }
      
      if ($needsAuth) {
        Write-BootstrapLog "Authentication required. Please run 'git pull' manually." "Warning"
      }
      
      return $false
    }
  } else {
    Write-BootstrapLog "Git pull completed successfully" "Success"
  }
  
  # Check if HEAD changed
  $newHead = $null
  try {
    $newHead = (& $GitCommand.Path -C $script:repoRoot rev-parse HEAD 2>$null).Trim()
  } catch {
    Write-BootstrapLog "Could not get new HEAD" "Warning"
  }
  
  if ($currentHead -and $newHead -and $currentHead -ne $newHead) {
    Write-BootstrapLog "Repository updated: $($currentHead.Substring(0, 7)) -> $($newHead.Substring(0, 7))" "Success"
    return $true
  } else {
    Write-BootstrapLog "Already up to date" "Success"
    return $false
  }
}

function Start-GuiApplication {
  Write-BootstrapLog "Launching NO-P51 GUI..." "Info"
  
  if (-not (Test-Path -LiteralPath $script:guiScriptPath)) {
    Write-BootstrapLog "GUI script not found: $script:guiScriptPath" "Error"
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
    Write-BootstrapLog "Application launched successfully" "Success"
  } catch {
    Write-BootstrapLog "Failed to launch application: $($_.Exception.Message)" "Error"
    Read-Host "Press Enter to exit"
    exit 1
  }
}

# Main execution
Write-Host ""
Write-BootstrapLog "NO-P51 Bootstrap" "Info"
Write-Host ""

$gitCommand = Test-GitInstalled
if (-not $gitCommand) {
  Write-BootstrapLog "Launching without update check..." "Warning"
  Start-Sleep -Seconds 2
  Start-GuiApplication
  exit 0
}

if (-not (Test-GitRepository)) {
  Write-BootstrapLog "Launching without update check..." "Warning"
  Start-Sleep -Seconds 2
  Start-GuiApplication
  exit 0
}

try {
  $wasUpdated = Invoke-GitUpdate -GitCommand $gitCommand
  Write-Host ""
  
  if ($wasUpdated) {
    Write-BootstrapLog "Restarting with updated version..." "Info"
    Start-Sleep -Seconds 2
  }
  
  Start-GuiApplication
  Start-Sleep -Seconds 1
  
} catch {
  Write-BootstrapLog "Unexpected error: $($_.Exception.Message)" "Error"
  Write-BootstrapLog "Launching application anyway..." "Warning"
  Start-Sleep -Seconds 2
  Start-GuiApplication
}

exit 0
