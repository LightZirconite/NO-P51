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
$script:cacheFile = Join-Path $script:repoRoot ".update-cache"
$script:logFile = Join-Path $script:repoRoot "bootstrap.log"
$script:updateCheckInterval = 900 # 15 minutes in seconds

function Write-BootstrapLog {
  param([string]$Message, [string]$Type = "Info")
  
  $timestamp = Get-Date -Format "HH:mm:ss"
  $prefix = switch ($Type) {
    "Error" { "[ERROR]" }
    "Warning" { "[WARN]" }
    "Success" { "[OK]" }
    default { "[INFO]" }
  }
  
  $logMessage = "$timestamp $prefix $Message"
  
  # Write to console
  if ($Verbose -or $Type -in @("Error", "Warning", "Success")) {
    Write-Host $logMessage -ForegroundColor $(
      switch ($Type) {
        "Error" { "Red" }
        "Warning" { "Yellow" }
        "Success" { "Green" }
        default { "Cyan" }
      }
    )
  }
  
  # Write to log file (append)
  try {
    Add-Content -Path $script:logFile -Value $logMessage -ErrorAction SilentlyContinue
  } catch {
    # Ignore log file errors
  }
}

function Get-UpdateCache {
  if (-not (Test-Path $script:cacheFile)) {
    return $null
  }
  
  try {
    $content = Get-Content $script:cacheFile -Raw | ConvertFrom-Json
    return $content
  } catch {
    return $null
  }
}

function Set-UpdateCache {
  param(
    [string]$LastCheck,
    [string]$LastCommit,
    [bool]$UpdateAvailable
  )
  
  $cache = @{
    lastCheck = $LastCheck
    lastCommit = $LastCommit
    updateAvailable = $UpdateAvailable
  }
  
  try {
    $cache | ConvertTo-Json | Set-Content -Path $script:cacheFile -ErrorAction SilentlyContinue
  } catch {
    # Ignore cache errors
  }
}

function Test-ShouldCheckUpdate {
  if ($ForceUpdate) {
    return $true
  }
  
  if ($SkipUpdateCheck) {
    return $false
  }
  
  $cache = Get-UpdateCache
  if (-not $cache) {
    return $true
  }
  
  try {
    $lastCheck = [DateTime]::Parse($cache.lastCheck)
    $elapsed = (Get-Date) - $lastCheck
    
    if ($elapsed.TotalSeconds -lt $script:updateCheckInterval) {
      Write-BootstrapLog "Last check was $([int]$elapsed.TotalMinutes) minute(s) ago, skipping..." "Info"
      return $false
    }
  } catch {
    return $true
  }
  
  return $true
}

function Test-GitInstalled {
  try {
    $gitCommand = Get-Command -Name git -ErrorAction Stop
    
    # Check Git version (minimum 2.20.0 recommended)
    try {
      $versionOutput = & git --version 2>$null
      if ($versionOutput -match "(\d+)\.(\d+)\.(\d+)") {
        $major = [int]$matches[1]
        $minor = [int]$matches[2]
        
        if ($major -lt 2 -or ($major -eq 2 -and $minor -lt 20)) {
          Write-BootstrapLog "Git version $major.$minor is old. Consider updating to 2.20+" "Warning"
        }
      }
    } catch {
      # Version check is optional
    }
    
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
    
  return @($statusLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
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
  
  $previousErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = "Continue"
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
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
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
      
      # Update cache to skip frequent checks
      Set-UpdateCache -LastCheck (Get-Date -Format "o") -LastCommit $currentHead -UpdateAvailable $false
      return $false
    }
    
    $useAutoStash = $true
  }
  
  # Fetch and check if update is available BEFORE pulling
  Write-BootstrapLog "Fetching remote changes..." "Info"
  $previousErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = "Continue"
    $fetchOutput = & $GitCommand.Path -C $script:repoRoot fetch 2>&1
    $fetchExitCode = $LASTEXITCODE

    if ($fetchExitCode -ne 0) {
      Write-BootstrapLog "Git fetch failed (code: $fetchExitCode)" "Warning"
      if ($fetchOutput) {
        foreach ($line in $fetchOutput) {
          if (-not [string]::IsNullOrWhiteSpace($line)) {
            Write-Host "  $line" -ForegroundColor Yellow
          }
        }
      }
      Set-UpdateCache -LastCheck (Get-Date -Format "o") -LastCommit $currentHead -UpdateAvailable $false
      return $false
    }

    if ($Verbose -and $fetchOutput) {
      foreach ($line in $fetchOutput) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
          Write-Host "  $line" -ForegroundColor Cyan
        }
      }
    }
  } catch {
    Write-BootstrapLog "Exception during fetch: $($_.Exception.Message)" "Warning"
    if ($_.Exception.InnerException) {
      Write-BootstrapLog "Inner exception: $($_.Exception.InnerException.Message)" "Warning"
    }
    Write-BootstrapLog "Run 'git -C $script:repoRoot fetch' manually for details." "Warning"
    Set-UpdateCache -LastCheck (Get-Date -Format "o") -LastCommit $currentHead -UpdateAvailable $false
    return $false
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  
  # Check if we're behind remote
  $remoteBranch = $null
  try {
    $currentBranch = (& $GitCommand.Path -C $script:repoRoot branch --show-current 2>$null).Trim()
    if ($currentBranch) {
      $remoteBranch = "origin/$currentBranch"
      
      # Check if remote branch exists
      $remoteExists = & $GitCommand.Path -C $script:repoRoot rev-parse --verify "$remoteBranch" 2>$null
      if ($LASTEXITCODE -eq 0 -and $remoteExists) {
        # Compare local and remote
        $behind = & $GitCommand.Path -C $script:repoRoot rev-list --count HEAD..$remoteBranch 2>$null
        $ahead = & $GitCommand.Path -C $script:repoRoot rev-list --count $remoteBranch..HEAD 2>$null
        
        if ($behind -and $behind -gt 0) {
          Write-BootstrapLog "Remote has $behind new commit(s)" "Info"
        } elseif ($ahead -and $ahead -gt 0) {
          Write-BootstrapLog "Local is $ahead commit(s) ahead of remote" "Info"
        } else {
          Write-BootstrapLog "Already up to date (no remote changes)" "Success"
          Set-UpdateCache -LastCheck (Get-Date -Format "o") -LastCommit $currentHead -UpdateAvailable $false
          return $false
        }
      }
    }
  } catch {
    # Continue with pull if comparison fails
    Write-BootstrapLog "Could not compare with remote, proceeding with pull..." "Info"
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
      
      $previousErrorActionPreference = $ErrorActionPreference
      try {
        $ErrorActionPreference = "Continue"
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
          Set-UpdateCache -LastCheck (Get-Date -Format "o") -LastCommit $currentHead -UpdateAvailable $false
          return $false
        }
      } catch {
        Write-BootstrapLog "Exception during fallback pull: $($_.Exception.Message)" "Error"
        Set-UpdateCache -LastCheck (Get-Date -Format "o") -LastCommit $currentHead -UpdateAvailable $false
        return $false
      } finally {
        $ErrorActionPreference = $previousErrorActionPreference
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
      
      Set-UpdateCache -LastCheck (Get-Date -Format "o") -LastCommit $currentHead -UpdateAvailable $false
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
    Set-UpdateCache -LastCheck (Get-Date -Format "o") -LastCommit $newHead -UpdateAvailable $false
    
    # Show what changed
    try {
      $changedFiles = & $GitCommand.Path -C $script:repoRoot diff --name-only "$currentHead..$newHead" 2>$null
      if ($changedFiles) {
        $fileCount = ($changedFiles | Measure-Object).Count
        Write-BootstrapLog "Updated $fileCount file(s)" "Info"
        if ($Verbose) {
          foreach ($file in $changedFiles) {
            Write-Host "  - $file" -ForegroundColor Cyan
          }
        }
      }
    } catch {
      # Ignore diff errors
    }
    
    return $true
  } else {
    Write-BootstrapLog "Already up to date" "Success"
    Set-UpdateCache -LastCheck (Get-Date -Format "o") -LastCommit $currentHead -UpdateAvailable $false
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

# Clean old log files (keep last 10)
try {
  [array]$logFiles = Get-ChildItem -Path (Join-Path $script:repoRoot "bootstrap*.log") -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
  if ($logFiles.Count -gt 10) {
    $logFiles | Select-Object -Skip 10 | Remove-Item -Force -ErrorAction SilentlyContinue
  }
} catch {
  # Ignore cleanup errors
}

if ($SkipUpdateCheck) {
  Write-BootstrapLog "Update check skipped (--SkipUpdateCheck)" "Warning"
  Start-GuiApplication
  exit 0
}

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

# Check if we should skip update check based on cache
if (-not (Test-ShouldCheckUpdate)) {
  Write-BootstrapLog "Skipping update check (checked recently)" "Info"
  Write-BootstrapLog "Use -ForceUpdate to check anyway" "Info"
  Write-Host ""
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
