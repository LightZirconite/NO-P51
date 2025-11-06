# auto-update.ps1
# Automatic update system using GitHub API
Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

$script:repoOwner = "LightZirconite"
$script:repoName = "NO-P51"
$script:currentVersionFile = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath ".version"
$script:projectRoot = Split-Path -Parent $PSScriptRoot

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

function Get-LatestRelease {
  try {
    $apiUrl = "https://api.github.com/repos/$script:repoOwner/$script:repoName/releases/latest"
    $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers @{ "User-Agent" = "NO-P51-Updater" } -TimeoutSec 10
    return $response
  } catch {
    return $null
  }
}

function Get-LatestCommit {
  try {
    $apiUrl = "https://api.github.com/repos/$script:repoOwner/$script:repoName/commits/main"
    $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers @{ "User-Agent" = "NO-P51-Updater" } -TimeoutSec 10
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
    $tempZip = Join-Path -Path $env:TEMP -ChildPath "NO-P51-update-$(Get-Random).zip"
    $tempExtract = Join-Path -Path $env:TEMP -ChildPath "NO-P51-extract-$(Get-Random)"
    
    # Download
    $webClient = New-Object System.Net.WebClient
    $webClient.Headers.Add("User-Agent", "NO-P51-Updater")
    $webClient.DownloadFile($ZipUrl, $tempZip)
    
    if (-not (Test-Path $tempZip)) {
      return $false
    }
    
    # Extract
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($tempZip, $tempExtract)
    
    # Find extracted folder
    $extractedFolder = Get-ChildItem -Path $tempExtract -Directory | Select-Object -First 1
    if (-not $extractedFolder) {
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
    
    return $true
    
  } catch {
    return $false
  }
}

function Test-UpdateAvailable {
  $currentVersion = Get-CurrentVersion
  $latestCommit = Get-LatestCommit
  
  if (-not $latestCommit) {
    return $false
  }
  
  if (-not $currentVersion -or $currentVersion -ne $latestCommit) {
    return $latestCommit
  }
  
  return $false
}

function Install-Update {
  $newVersion = Test-UpdateAvailable
  
  if (-not $newVersion) {
    return $false
  }
  
  $zipUrl = "https://github.com/$script:repoOwner/$script:repoName/archive/refs/heads/main.zip"
  
  if (Download-AndExtract -ZipUrl $zipUrl -DestinationPath $script:projectRoot) {
    Set-CurrentVersion -Version $newVersion
    return $true
  }
  
  return $false
}

function Start-AutoUpdate {
  if (Install-Update) {
    # Update successful, restart
    $batFile = Join-Path -Path $script:projectRoot -ChildPath "NO-P51.bat"
    if (Test-Path $batFile) {
      Start-Process -FilePath $batFile
      exit 0
    }
  }
}

# Run if called directly
if ($MyInvocation.InvocationName -ne ".") {
  Start-AutoUpdate
}
