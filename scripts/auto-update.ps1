# auto-update.ps1
# Automatic update system using GitHub API
# Checks for new releases and updates the local installation
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:repoOwner = "LightZirconite"
$script:repoName = "NO-P51"
$script:currentVersionFile = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath ".version"
$script:projectRoot = Split-Path -Parent $PSScriptRoot
$script:logDir = Join-Path -Path $script:projectRoot -ChildPath "logs"
$script:logFile = Join-Path -Path $script:logDir -ChildPath "auto-update-$(Get-Date -Format 'yyyy-MM-dd').log"

function Get-ShortCommit {
  param([string]$CommitHash)
  if ([string]::IsNullOrEmpty($CommitHash)) { return 'none' }
  if ($CommitHash.Length -ge 7) { return $CommitHash.Substring(0, 7) }
  return $CommitHash
}

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

function Get-CurrentVersion {
  if (Test-Path $script:currentVersionFile) {
    try {
      return Get-Content -Path $script:currentVersionFile -Raw -ErrorAction Stop | ForEach-Object { $_.Trim() }
    } catch {}
  }
  return $null
}

function Set-CurrentVersion {
  param([string]$Version)
  
  try {
    $Version | Out-File -FilePath $script:currentVersionFile -Encoding UTF8 -NoNewline -Force
  } catch {}
}

function Get-LatestReleaseFromAPI {
  try {
    Write-Host "Checking for updates via GitHub API..." -ForegroundColor Cyan
    Write-Log "Checking for updates via GitHub API"
    
    $apiUrl = "https://api.github.com/repos/$script:repoOwner/$script:repoName/releases/latest"
    $headers = @{
      "User-Agent" = "NO-P51-Updater"
      "Accept" = "application/vnd.github.v3+json"
    }
    
    $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -TimeoutSec 10
    Write-Log "Latest release found: $($response.tag_name)"
    return $response
    
  } catch {
    Write-Host "Unable to check for updates" -ForegroundColor Yellow
    Write-Log "Failed to check for updates: $($_.Exception.Message)" -Level WARN
    return $null
  }
}

function Get-LatestCommitSHA {
  try {
    $apiUrl = "https://api.github.com/repos/$script:repoOwner/$script:repoName/commits/main"
    $headers = @{
      "User-Agent" = "NO-P51-Updater"
      "Accept" = "application/vnd.github.v3+json"
    }
    
    $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -TimeoutSec 10
    return $response.sha
    
  } catch {
    return $null
  }
}

function Download-AndExtract {
  param(
    [string]$ZipUrl,
    [string]$DestinationPath
  )
  
  try {
    Write-Host "Downloading update..." -ForegroundColor Cyan
    Write-Log "Starting download from: $ZipUrl"
    
    $tempZip = Join-Path -Path $env:TEMP -ChildPath "NO-P51-update-$(Get-Random).zip"
    $tempExtract = Join-Path -Path $env:TEMP -ChildPath "NO-P51-extract-$(Get-Random)"
    
    # Download with progress
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $webClient = New-Object System.Net.WebClient
    $webClient.Headers.Add("User-Agent", "NO-P51-Updater")
    $webClient.Headers.Add("Accept", "application/vnd.github.v3+json")
    
    try {
      $webClient.DownloadFile($ZipUrl, $tempZip)
      Write-Log "Download completed: $tempZip"
    } catch {
      Write-Host "Download failed: $($_.Exception.Message)" -ForegroundColor Red
      Write-Log "Download failed: $($_.Exception.Message)" -Level ERROR
      return $false
    }
    
    if (-not (Test-Path $tempZip)) {
      Write-Host "Download failed" -ForegroundColor Red
      Write-Log "Download verification failed: file not found" -Level ERROR
      return $false
    }
    
    Write-Host "Installing update..." -ForegroundColor Cyan
    Write-Log "Extracting archive to: $tempExtract"
    
    # Extract
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($tempZip, $tempExtract)
    
    # Find extracted folder
    $extractedFolder = Get-ChildItem -Path $tempExtract -Directory | Select-Object -First 1
    if (-not $extractedFolder) {
      Write-Host "Extraction failed" -ForegroundColor Red
      return $false
    }
    
    # Backup config.json if exists
    $configBackup = $null
    $configPath = Join-Path -Path $DestinationPath -ChildPath "config.json"
    if (Test-Path $configPath) {
      $configBackup = Get-Content -Path $configPath -Raw -Encoding UTF8
    }
    
    # Copy files (except config.json)
    Get-ChildItem -Path $extractedFolder.FullName -Recurse | ForEach-Object {
      $relativePath = $_.FullName.Substring($extractedFolder.FullName.Length + 1)
      $targetPath = Join-Path -Path $DestinationPath -ChildPath $relativePath
      
      # Skip config.json
      if ($relativePath -eq "config.json") {
        return
      }
      
      if ($_.PSIsContainer) {
        if (-not (Test-Path $targetPath)) {
          New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
        }
      } else {
        $targetDir = Split-Path -Path $targetPath -Parent
        if (-not (Test-Path $targetDir)) {
          New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
        }
        Copy-Item -Path $_.FullName -Destination $targetPath -Force
      }
    }
    
    # Restore config.json
    if ($configBackup) {
      $configBackup | Out-File -FilePath $configPath -Encoding UTF8 -Force
    }
    
    # Cleanup
    Remove-Item -Path $tempZip -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
    
    Write-Host "Update installed successfully" -ForegroundColor Green
    Write-Log "Update installed successfully to: $DestinationPath"
    return $true
    
  } catch {
    Write-Host "Update failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Log "Update installation failed: $($_.Exception.Message)" -Level ERROR
    return $false
  }
}

function Test-UpdateAvailable {
  $currentVersion = Get-CurrentVersion
  
  # Try to get latest release first
  $latestRelease = Get-LatestReleaseFromAPI
  if ($latestRelease -and $latestRelease.tag_name) {
    $latestVersion = $latestRelease.tag_name
    
    if (-not $currentVersion) {
      Write-Host "First run detected, setting version: $latestVersion" -ForegroundColor Cyan
      Write-Log "First run detected, setting initial version: $latestVersion"
      Set-CurrentVersion -Version $latestVersion
      return $null
    }
    
    if ($currentVersion -ne $latestVersion) {
      Write-Host "New release available: $latestVersion (current: $currentVersion)" -ForegroundColor Yellow
      Write-Log "New release available: $latestVersion (current: $currentVersion)"
      return @{
        Version = $latestVersion
        ZipUrl = $latestRelease.zipball_url
        Type = "release"
      }
    } else {
      Write-Host "Already up to date ($latestVersion)" -ForegroundColor Green
      Write-Log "Already up to date: $latestVersion"
      return $null
    }
  }
  
  # Fallback to commit SHA if no releases
  $latestCommit = Get-LatestCommitSHA
  if ($latestCommit) {
    $shortCommit = Get-ShortCommit -CommitHash $latestCommit
    
    if (-not $currentVersion) {
      Write-Host "First run detected, setting commit: $shortCommit" -ForegroundColor Cyan
      Set-CurrentVersion -Version $latestCommit
      return $null
    }
    
    if ($currentVersion -ne $latestCommit) {
      Write-Host "New commit available: $shortCommit" -ForegroundColor Yellow
      $currentShort = Get-ShortCommit -CommitHash $currentVersion
      Write-Log "New commit available: $shortCommit (current: $currentShort)"
      return @{
        Version = $latestCommit
        ZipUrl = "https://github.com/$script:repoOwner/$script:repoName/archive/refs/heads/main.zip"
        Type = "commit"
      }
    } else {
      Write-Host "Already up to date ($shortCommit)" -ForegroundColor Green
      Write-Log "Already up to date: $shortCommit"
      return $null
    }
  }
  
  Write-Host "Unable to check for updates" -ForegroundColor Yellow
  return $null
}

function Install-Update {
  $updateInfo = Test-UpdateAvailable
  
  if (-not $updateInfo) {
    Write-Log "No update available"
    return $false
  }
  
  Write-Host "Installing update..." -ForegroundColor Yellow
  Write-Log "========== Installing Update =========="
  
  if ($updateInfo.Type -eq "release") {
    Write-Host "Release: $($updateInfo.Version)" -ForegroundColor Cyan
    Write-Log "Update type: Release $($updateInfo.Version)"
  } else {
    $shortCommit = Get-ShortCommit -CommitHash $updateInfo.Version
    Write-Host "Commit: $shortCommit" -ForegroundColor Cyan
    Write-Log "Update type: Commit $shortCommit"
  }
  
  Write-Log "Download URL: $($updateInfo.ZipUrl)"
  
  if (Download-AndExtract -ZipUrl $updateInfo.ZipUrl -DestinationPath $script:projectRoot) {
    Set-CurrentVersion -Version $updateInfo.Version
    Write-Log "Version updated to: $($updateInfo.Version)"
    return $true
  }
  
  Write-Log "Update installation failed" -Level ERROR
  return $false
}

function Start-AutoUpdate {
  Write-Host ""
  Write-Host "Checking for updates..." -ForegroundColor Cyan
  Write-Log "========== Auto-Update Started =========="
  Write-Log "Current version file: $script:currentVersionFile"
  
  $currentVer = Get-CurrentVersion
  if ($currentVer) {
    Write-Log "Current local version: $currentVer"
  } else {
    Write-Log "No local version found (first run)"
  }
  
  $updateInstalled = Install-Update
  
  if ($updateInstalled) {
    Write-Log "========== UPDATE INSTALLED - RESTART REQUIRED =========="
    Write-Host ""
    Write-Host "Update installed successfully! Restarting..." -ForegroundColor Green
  } else {
    Write-Log "No update installed - proceeding with launch"
  }
  
  Write-Host ""
  return $updateInstalled
}

# Run if called directly
if ($MyInvocation.InvocationName -ne ".") {
  try {
    $result = Start-AutoUpdate
    if ($result) {
      exit 1
    }
    exit 0
  } catch {
    $errorMsg = "Fatal auto-update error: $($_.Exception.Message)"
    Write-Host ""
    Write-Host "ERROR: $errorMsg" -ForegroundColor Red
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor DarkRed
    Write-Host ""
    Write-Log $errorMsg -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    Write-Host "Press any key to continue..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 2
  }
}
