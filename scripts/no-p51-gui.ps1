param(
  [string]$ConfigPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath "config.json")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @"
  [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError=true)]
  public static extern bool DestroyIcon(System.IntPtr hIcon);
"@

. (Join-Path $PSScriptRoot "no-p51.ps1")

class Nop51ProcessItem {
  [string]$ProcessName
  [int]$Id

  Nop51ProcessItem([string]$name, [int]$id) {
    $this.ProcessName = $name
    $this.Id = $id
  }

  [string] ToString() {
    $displayName = $this.ProcessName
    if (-not $displayName.EndsWith(".exe", [System.StringComparison]::OrdinalIgnoreCase)) {
      $displayName = "$displayName.exe"
    }
    return "{0} (PID {1})" -f $displayName, $this.Id
  }
}

$script:serviceState = [pscustomobject]@{
  Runspace = $null
  PowerShell = $null
  Cancellation = $null
  Handle = $null
  Status = "Stopped"
  Error = $null
}

$script:allowFormClose = $false
$script:trayBalloonShown = $false
$script:serviceScriptPath = Join-Path $PSScriptRoot "no-p51.ps1"
$script:isLoadingConfig = $false
$script:configDirty = $false
$script:lastAutoSaveError = $null
$script:isElevatedSession = Test-Nop51IsElevated
$script:customIcon = $null
$script:customIconHandle = [IntPtr]::Zero
$script:pendingServiceRestart = $false
$script:serviceRestartCountdown = 0
$script:userStopRequested = $false
$script:repoRoot = Split-Path -Parent $PSScriptRoot
$script:preferredIconPath = $null
$script:resolvedIconPath = $null
$script:logoPreviewImage = $null
$script:autoSaveTimer = $null
$script:uiControls = $null

function New-Nop51DefaultConfig {
  return [pscustomobject]@{
    targetProcessName = ""
    hideStrategy = "hide"
    hideHotkey = "="
    restoreHotkey = "Ctrl+Alt+R"
  iconPath = "logo.png"
    fallback = $null
  }
}

function Get-Nop51AppIcon {
  if ($script:customIcon) {
    return $script:customIcon
  }

  $size = 32
  $createIconFromBitmap = {
    param([System.Drawing.Bitmap]$bmp)
    $iconHandle = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($iconHandle)
    $script:customIconHandle = $iconHandle
    return $icon
  }

  $resolvedPath = Resolve-Nop51IconPath -RequestedPath $script:preferredIconPath
  $script:resolvedIconPath = $resolvedPath

  if ($resolvedPath -and (Test-Path -LiteralPath $resolvedPath)) {
    $logo = $null
    $bitmap = $null
    $graphics = $null
    try {
      $logo = [System.Drawing.Image]::FromFile($resolvedPath)
      $bitmap = New-Object System.Drawing.Bitmap $size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
      $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
      $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
      $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
      $graphics.Clear([System.Drawing.Color]::Transparent)
      $graphics.DrawImage($logo, [System.Drawing.Rectangle]::new(0, 0, $size, $size))

      $script:customIcon = & $createIconFromBitmap $bitmap
      return $script:customIcon
    } catch {
      # fall back below
    } finally {
      if ($graphics) { $graphics.Dispose() }
      if ($bitmap) { $bitmap.Dispose() }
      if ($logo) { $logo.Dispose() }
    }
  }

  $bitmapFallback = New-Nop51FallbackBitmap -Size $size
  $script:customIcon = & $createIconFromBitmap $bitmapFallback
  $bitmapFallback.Dispose()
  return $script:customIcon
}

function Resolve-Nop51IconPath {
  param(
    [string]$RequestedPath
  )

  $candidates = @()
  if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
    $candidate = $RequestedPath.Trim()
    if (-not [System.IO.Path]::IsPathRooted($candidate) -and $script:repoRoot) {
      $candidate = Join-Path -Path $script:repoRoot -ChildPath $candidate
    }
    try {
      $candidate = [System.IO.Path]::GetFullPath($candidate)
    } catch {
      $candidate = $null
    }
    if ($candidate) {
      $candidates += $candidate
    }
  }

  if ($script:repoRoot) {
    $defaultNames = @("logo.png", "logo.ico")
    foreach ($name in $defaultNames) {
      $defaultPath = Join-Path -Path $script:repoRoot -ChildPath $name
      if (-not ($candidates -contains $defaultPath)) {
        $candidates += $defaultPath
      }
    }
  }

  foreach ($candidatePath in $candidates) {
    if ($candidatePath -and (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
      return $candidatePath
    }
  }

  return $null
}

function Convert-Nop51PathToConfigValue {
  param(
    [string]$FullPath
  )

  if ([string]::IsNullOrWhiteSpace($FullPath)) {
    return $null
  }

  $normalized = $FullPath
  try {
    $normalized = [System.IO.Path]::GetFullPath($FullPath)
  } catch {
    return $FullPath
  }

  if ($script:repoRoot) {
    try {
      $base = New-Object System.Uri(($script:repoRoot.TrimEnd([char]'\', [char]'/' ) + [System.IO.Path]::DirectorySeparatorChar))
      $target = New-Object System.Uri($normalized)
      if ($base.IsBaseOf($target)) {
        $relative = $base.MakeRelativeUri($target).ToString()
        if ($relative) {
          return $relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        }
      }
    } catch {
      # fall back to absolute path
    }
  }

  return $normalized
}

function New-Nop51FallbackBitmap {
  param(
    [int]$Size = 64
  )

  $bitmapFallback = New-Object System.Drawing.Bitmap $Size, $Size
  $graphicsFallback = [System.Drawing.Graphics]::FromImage($bitmapFallback)
  $gradientBrush = $null
  $textBrush = $null
  $shadowBrush = $null
  $font = $null
  $stringFormat = $null
  try {
    $graphicsFallback.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphicsFallback.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphicsFallback.Clear([System.Drawing.Color]::Transparent)

    $rect = [System.Drawing.Rectangle]::new(2, 2, $Size - 4, $Size - 4)
    $gradientBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
      $rect,
      [System.Drawing.Color]::FromArgb(255, 58, 134, 255),
      [System.Drawing.Color]::FromArgb(255, 138, 43, 226),
      45
    )
    $graphicsFallback.FillEllipse($gradientBrush, $rect)

    $glowBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(60, 255, 255, 255))
    $glowRect = [System.Drawing.Rectangle]::new(6, 4, $Size - 12, ($Size / 2) - 4)
    $graphicsFallback.FillEllipse($glowBrush, $glowRect)
    $glowBrush.Dispose()

    $shadowBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(80, 0, 0, 0))
    $font = [System.Drawing.Font]::new("Segoe UI", [double](0.48 * $Size), [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $stringFormat = New-Object System.Drawing.StringFormat
    $stringFormat.Alignment = [System.Drawing.StringAlignment]::Center
    $stringFormat.LineAlignment = [System.Drawing.StringAlignment]::Center
    $graphicsFallback.DrawString("N", $font, $shadowBrush, [System.Drawing.RectangleF]::new(2, 2, $Size, $Size), $stringFormat)

    $textBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 255, 255, 255))
    $graphicsFallback.DrawString("N", $font, $textBrush, [System.Drawing.RectangleF]::new(0, 0, $Size, $Size), $stringFormat)
  } finally {
    if ($stringFormat) { $stringFormat.Dispose() }
    if ($font) { $font.Dispose() }
    if ($textBrush) { $textBrush.Dispose() }
    if ($shadowBrush) { $shadowBrush.Dispose() }
    if ($gradientBrush) { $gradientBrush.Dispose() }
    if ($graphicsFallback) { $graphicsFallback.Dispose() }
  }

  return $bitmapFallback
}

function Reset-Nop51AppIcon {
  if ($script:customIcon) {
    try { $script:customIcon.Dispose() } catch { }
    $script:customIcon = $null
  }
  if ($script:customIconHandle -ne [IntPtr]::Zero) {
    [Win32.NativeMethods]::DestroyIcon($script:customIconHandle) | Out-Null
    $script:customIconHandle = [IntPtr]::Zero
  }
  $script:resolvedIconPath = $null
}

function Update-Nop51LogoPreview {
  param(
    [string]$ResolvedPath
  )

  if (-not $script:uiControls -or -not $script:uiControls.LogoPicture) {
    return
  }

  $pictureBox = $script:uiControls.LogoPicture

  if ($script:logoPreviewImage) {
    try { $script:logoPreviewImage.Dispose() } catch { }
    $script:logoPreviewImage = $null
  }

  $imageToDisplay = $null
  if ($ResolvedPath -and (Test-Path -LiteralPath $ResolvedPath -PathType Leaf)) {
    try {
      $imageToDisplay = [System.Drawing.Image]::FromFile($ResolvedPath)
    } catch {
      $imageToDisplay = $null
    }
  }

  if (-not $imageToDisplay) {
    $imageToDisplay = New-Nop51FallbackBitmap -Size 96
  }

  $script:logoPreviewImage = $imageToDisplay
  $pictureBox.Image = $script:logoPreviewImage
}

function Apply-Nop51IconToUi {
  $icon = Get-Nop51AppIcon
  if ($icon -and $form) {
    $form.Icon = $icon
  }
  if ($icon -and $script:uiControls -and $script:uiControls.TrayIcon) {
    $script:uiControls.TrayIcon.Icon = $icon
  }
  Update-Nop51LogoPreview -ResolvedPath $script:resolvedIconPath
}

function Use-Nop51IconFromConfig {
  param(
    [psobject]$Config
  )

  $newValue = $null
  if ($Config -and $Config.PSObject.Properties.Name -contains "iconPath") {
    $candidate = $Config.iconPath
    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
      $newValue = $candidate.ToString()
    }
  }

  $script:preferredIconPath = $newValue
  Reset-Nop51AppIcon
  Apply-Nop51IconToUi
}

function Refresh-Nop51IconPreviewFromTextBox {
  if (-not $script:uiControls -or -not $script:uiControls.LogoPathText) {
    return
  }

  $rawValue = $script:uiControls.LogoPathText.Text
  $trimmedValue = if ($rawValue) { $rawValue.Trim() } else { "" }
  $previewConfig = [pscustomobject]@{ iconPath = if ([string]::IsNullOrWhiteSpace($trimmedValue)) { $null } else { $trimmedValue } }
  Use-Nop51IconFromConfig -Config $previewConfig
}

function Get-Nop51RunningProcessItems {
  $items = @()
  $processes = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 } | Sort-Object -Property ProcessName
  foreach ($process in $processes) {
    try {
      $items += [Nop51ProcessItem]::new($process.ProcessName, $process.Id)
    } catch {
      continue
    }
  }
  return $items
}

function Convert-KeysToHotKeyString {
  param(
    [System.Windows.Forms.KeyEventArgs]$EventArgs
  )

  $parts = New-Object System.Collections.Generic.List[string]
  if (($EventArgs.Modifiers -band [System.Windows.Forms.Keys]::Control) -ne 0) {
    $parts.Add("Ctrl") | Out-Null
  }
  if (($EventArgs.Modifiers -band [System.Windows.Forms.Keys]::Alt) -ne 0) {
    $parts.Add("Alt") | Out-Null
  }
  if (($EventArgs.Modifiers -band [System.Windows.Forms.Keys]::Shift) -ne 0) {
    $parts.Add("Shift") | Out-Null
  }
  if (($EventArgs.Modifiers -band [System.Windows.Forms.Keys]::LWin) -ne 0 -or ($EventArgs.Modifiers -band [System.Windows.Forms.Keys]::RWin) -ne 0) {
    $parts.Add("Win") | Out-Null
  }

  $keyCode = $EventArgs.KeyCode
  if ($keyCode -in @([System.Windows.Forms.Keys]::Menu, [System.Windows.Forms.Keys]::ShiftKey, [System.Windows.Forms.Keys]::ControlKey, [System.Windows.Forms.Keys]::LWin, [System.Windows.Forms.Keys]::RWin)) {
    if ($parts.Count -gt 0) {
      return $parts -join "+"
    }
    return $null
  }

  $keyString = $null
  $keyValue = [int]$keyCode
  $d0 = [int][System.Windows.Forms.Keys]::D0
  $d9 = [int][System.Windows.Forms.Keys]::D9
  if ($keyValue -ge $d0 -and $keyValue -le $d9) {
    $keyString = [char](48 + ($keyValue - $d0))
  } else {
    $numPad0 = [int][System.Windows.Forms.Keys]::NumPad0
    $numPad9 = [int][System.Windows.Forms.Keys]::NumPad9
    if ($keyValue -ge $numPad0 -and $keyValue -le $numPad9) {
      $keyString = "Num" + [char](48 + ($keyValue - $numPad0))
    } else {
      $displayMap = @{
        [System.Windows.Forms.Keys]::Oemplus = "="
        [System.Windows.Forms.Keys]::OemMinus = "-"
        [System.Windows.Forms.Keys]::Oemcomma = ","
        [System.Windows.Forms.Keys]::OemPeriod = "."
        [System.Windows.Forms.Keys]::OemSemicolon = ";"
        [System.Windows.Forms.Keys]::OemQuestion = "/"
      }

      if ($displayMap.ContainsKey($keyCode)) {
        $keyString = $displayMap[$keyCode]
      } else {
        $keyString = $keyCode.ToString().ToUpperInvariant()
      }
    }
  }

  if (-not $keyString) {
    return $null
  }

  $parts.Add($keyString) | Out-Null
  return $parts -join "+"
}

function Show-Nop51Error {
  param(
    [string]$Message
  )

  [System.Windows.Forms.MessageBox]::Show($Message, "NO-P51", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
}

function Show-Nop51Info {
  param(
    [string]$Message
  )

  [System.Windows.Forms.MessageBox]::Show($Message, "NO-P51", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}

function Restart-Nop51Application {
  $arguments = @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)
  if ($PSBoundParameters.ContainsKey("ConfigPath") -and $PSBoundParameters["ConfigPath"]) {
    $arguments += "-ConfigPath"
    $arguments += $ConfigPath
  }

  Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -ArgumentList $arguments | Out-Null
  exit
}

function Save-Nop51ConfigFromForm {
  param(
    [System.Windows.Forms.TextBox]$TargetTextBox,
    [System.Windows.Forms.TextBox]$HideHotKeyTextBox,
    [System.Windows.Forms.TextBox]$RestoreHotKeyTextBox,
    [System.Windows.Forms.TextBox]$LogoPathTextBox,
    [System.Windows.Forms.CheckBox]$UsePidCheckbox,
    [System.Windows.Forms.ComboBox]$HideStrategyCombo,
    [System.Windows.Forms.RadioButton]$FallbackNone,
    [System.Windows.Forms.RadioButton]$FallbackApp,
    [System.Windows.Forms.RadioButton]$FallbackUrl,
    [System.Windows.Forms.TextBox]$FallbackValueTextBox,
    [System.Windows.Forms.CheckBox]$FallbackAutoClose,
    [System.Windows.Forms.CheckBox]$FallbackFullscreen
  )

  $targetProcess = $TargetTextBox.Text.Trim()
  if ([string]::IsNullOrWhiteSpace($targetProcess)) {
    throw "Select a target process from the list or enter its executable name or PID."
  }

  $usePidMode = $UsePidCheckbox.Checked
  if ($usePidMode) {
    $pidValue = 0
    if (-not [int]::TryParse($targetProcess, [ref]$pidValue) -or $pidValue -le 0) {
      throw "Enter a numeric PID when PID selection is enabled."
    }
    $targetProcess = $pidValue.ToString()
  }

  $hideHotKey = $HideHotKeyTextBox.Text.Trim()
  $restoreHotKey = $RestoreHotKeyTextBox.Text.Trim()

  if ([string]::IsNullOrWhiteSpace($hideHotKey) -or [string]::IsNullOrWhiteSpace($restoreHotKey)) {
    throw "Define both hide and restore hotkeys."
  }

  $null = Convert-Nop51HotKey -HotKeyString $hideHotKey
  $null = Convert-Nop51HotKey -HotKeyString $restoreHotKey

  $hideStrategy = "hide"
  if ($HideStrategyCombo.SelectedItem) {
    $hideStrategy = $HideStrategyCombo.SelectedItem.Value
  }
  if (-not $hideStrategy) {
    $hideStrategy = "hide"
  }

  $iconPathValue = $null
  if ($LogoPathTextBox) {
    $iconPathInput = $LogoPathTextBox.Text.Trim()
    if (-not [string]::IsNullOrWhiteSpace($iconPathInput)) {
      $candidate = $iconPathInput
      if (-not [System.IO.Path]::IsPathRooted($candidate) -and $script:repoRoot) {
        $candidate = Join-Path -Path $script:repoRoot -ChildPath $candidate
      }
      try {
        $resolved = (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).ProviderPath
      } catch {
        throw "Logo file not found at '$iconPathInput'."
      }

      $extension = [System.IO.Path]::GetExtension($resolved)
      if ($extension) {
        $extension = $extension.ToLowerInvariant()
      }
      if ($extension -notin @('.png', '.ico')) {
        throw "Logo file must be a .png or .ico image."
      }

      $iconPathValue = Convert-Nop51PathToConfigValue -FullPath $resolved
    }
  }

  $fallback = $null
  if ($FallbackApp.Checked -or $FallbackUrl.Checked) {
    $value = $FallbackValueTextBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
      throw "Provide a value for the fallback action."
    }
    $mode = if ($FallbackApp.Checked) { "app" } else { "url" }
    $fallback = [pscustomobject]@{
      mode = $mode
      value = $value
      autoClose = $FallbackAutoClose.Checked
      fullscreen = $FallbackFullscreen.Checked
    }
  }

  $configObject = [pscustomobject]@{
    targetProcessName = $targetProcess
    hideStrategy = $hideStrategy
    hideHotkey = $hideHotKey
    restoreHotkey = $restoreHotKey
    iconPath = $iconPathValue
    fallback = $fallback
  }

  Assert-Nop51Config -Config $configObject

  $json = Convert-Nop51ToJson -InputObject $configObject -Depth 6
  Set-Content -LiteralPath $ConfigPath -Value $json -Encoding UTF8

  Use-Nop51IconFromConfig -Config $configObject

  return $configObject
}

function Invoke-Nop51SaveConfigFromUi {
  param(
    [switch]$Silent
  )

  if (-not $script:uiControls) {
    return $null
  }

  $config = Save-Nop51ConfigFromForm -TargetTextBox $script:uiControls.TargetText -HideHotKeyTextBox $script:uiControls.HideHotkeyText -RestoreHotKeyTextBox $script:uiControls.RestoreHotkeyText -LogoPathTextBox $script:uiControls.LogoPathText -UsePidCheckbox $script:uiControls.UsePidCheckbox -HideStrategyCombo $script:uiControls.HideStrategyCombo -FallbackNone $script:uiControls.FallbackNone -FallbackApp $script:uiControls.FallbackApp -FallbackUrl $script:uiControls.FallbackUrl -FallbackValueTextBox $script:uiControls.FallbackValueText -FallbackAutoClose $script:uiControls.FallbackAutoClose -FallbackFullscreen $script:uiControls.FallbackFullscreen

  if (-not $Silent) {
    Update-Nop51ConfigStatus "Configuration saved"
  }

  return $config
}

function Update-Nop51ConfigStatus {
  param(
    [string]$Message,
    [switch]$IsError
  )

  if (-not $script:uiControls -or -not $script:uiControls.ConfigStatusLabel) {
    return
  }

  $label = $script:uiControls.ConfigStatusLabel
  $label.Text = $Message

  if ($IsError) {
    $label.ForeColor = [System.Drawing.Color]::FromArgb(192, 0, 0)
  } else {
    $label.ForeColor = [System.Drawing.SystemColors]::ControlText
  }
}

function Test-Nop51FormReady {
  if (-not $script:uiControls) {
    return $false
  }

  $targetValue = $script:uiControls.TargetText.Text.Trim()
  if ([string]::IsNullOrWhiteSpace($targetValue)) {
    return $false
  }

  if ($script:uiControls.UsePidCheckbox.Checked) {
    $pidValue = 0
    if (-not [int]::TryParse($targetValue, [ref]$pidValue) -or $pidValue -le 0) {
      return $false
    }
  }

  $hideHotkey = $script:uiControls.HideHotkeyText.Text.Trim()
  $restoreHotkey = $script:uiControls.RestoreHotkeyText.Text.Trim()
  if ([string]::IsNullOrWhiteSpace($hideHotkey) -or [string]::IsNullOrWhiteSpace($restoreHotkey)) {
    return $false
  }

  if ($script:uiControls.FallbackApp.Checked -or $script:uiControls.FallbackUrl.Checked) {
    $fallbackValue = $script:uiControls.FallbackValueText.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($fallbackValue)) {
      return $false
    }
  }

  if ($script:uiControls.LogoPathText) {
    $iconValue = $script:uiControls.LogoPathText.Text.Trim()
    if ($iconValue) {
      try {
        $resolved = $iconValue
        if (-not [System.IO.Path]::IsPathRooted($resolved) -and $script:repoRoot) {
          $resolved = Join-Path -Path $script:repoRoot -ChildPath $resolved
        }
        [void](Resolve-Path -LiteralPath $resolved -ErrorAction Stop)
      } catch {
        return $false
      }
    }
  }

  return $true
}

function Start-Nop51AutoSaveTimer {
  param(
    [int]$DelayMs = 1200
  )

  if (-not $script:autoSaveTimer) {
    return
  }

  $script:autoSaveTimer.Stop()
  $script:autoSaveTimer.Interval = [Math]::Max(100, $DelayMs)
  $script:autoSaveTimer.Start()
}

function Try-Nop51AutoSave {
  if ($script:isLoadingConfig) {
    return
  }

  if (-not $script:configDirty) {
    return
  }

  if (-not $script:uiControls) {
    return
  }

  if (-not (Test-Nop51FormReady)) {
    Update-Nop51ConfigStatus "Configuration pending: complete required fields"
    return
  }

  if ($script:autoSaveTimer) {
    $script:autoSaveTimer.Stop()
  }

  try {
    Invoke-Nop51SaveConfigFromUi -Silent | Out-Null
    $script:configDirty = $false
    $script:lastAutoSaveError = $null
    Update-Nop51ConfigStatus "Configuration saved"
  } catch {
    $script:lastAutoSaveError = $_.Exception.Message
    $translated = $script:lastAutoSaveError
    switch -Wildcard ($translated) {
      "Select a target process*" { $translated = "Select a target process or enter a PID." }
      "Define both hide*" { $translated = "Define both hide and restore shortcuts." }
      "Provide a value for the fallback action." { $translated = "Provide a value for the fallback action." }
      "Enter a numeric PID when PID selection is enabled." { $translated = "Enter a numeric PID when PID selection is enabled." }
      default { }
    }
    Update-Nop51ConfigStatus "Configuration not saved: $translated" -IsError
  }
}

function Set-Nop51ConfigDirty {
  param(
    [bool]$Dirty = $true,
    [switch]$SyncNow
  )

  if ($script:isLoadingConfig) {
    return
  }

  $script:configDirty = $Dirty

  if (-not $Dirty) {
    $script:lastAutoSaveError = $null
    if ($script:autoSaveTimer) {
      $script:autoSaveTimer.Stop()
    }
    return
  }

  if ($SyncNow) {
    Start-Nop51AutoSaveTimer -DelayMs 300
  } else {
    Start-Nop51AutoSaveTimer
  }
  Update-Nop51ConfigStatus "Configuration changed"
}

function Read-Nop51ConfigOrDefault {
  if (-not (Test-Path -LiteralPath $ConfigPath)) {
    return New-Nop51DefaultConfig
  }

  try {
    return Read-Nop51Config -Path $ConfigPath
  } catch {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = "$ConfigPath.bak-$timestamp"
    try {
      Copy-Item -LiteralPath $ConfigPath -Destination $backupPath -ErrorAction Stop
    } catch {
      $backupPath = $null
    }

    $defaultConfig = New-Nop51DefaultConfig
    try {
      $json = Convert-Nop51ToJson -InputObject $defaultConfig -Depth 6
      Set-Content -LiteralPath $ConfigPath -Value $json -Encoding UTF8
    } catch {
      # If even writing defaults fails, surface the original error
    }

    $details = $_.Exception.Message
    if ($backupPath) {
      Show-Nop51Error "Configuration file is corrupted: $details`nA backup was created at: $backupPath`nA default configuration has been restored."
    } else {
      Show-Nop51Error "Configuration file is corrupted: $details`nA backup could not be created. A default configuration has been restored."
    }

    return $defaultConfig
  }
}

function Start-Nop51BackgroundService {
  param(
    [string]$Path
  )

  if ($script:serviceState.Status -eq "Running") {
    return
  }

  $script:userStopRequested = $false
  $script:pendingServiceRestart = $false
  $script:serviceRestartCountdown = 0

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Configuration file not found at '$Path'."
  }

  $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
  $runspace.ApartmentState = [System.Threading.ApartmentState]::STA
  $runspace.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
  $runspace.Open()

  $powerShell = [PowerShell]::Create()
  $powerShell.Runspace = $runspace

  $cts = [System.Threading.CancellationTokenSource]::new()
  $coreScriptPath = $script:serviceScriptPath
  $coreScriptPathLiteral = $coreScriptPath -replace "'", "''"

  $serviceScript = @"
param(
  [string]`$cfgPath,
  [System.Threading.CancellationToken]`$token
)

Set-StrictMode -Version Latest
`$ErrorActionPreference = "Stop"
. '$coreScriptPathLiteral'
Start-NOP51 -ConfigPath `$cfgPath -CancellationToken `$token
"@

  $powerShell.AddScript($serviceScript).AddArgument($Path).AddArgument($cts.Token) | Out-Null

  $handle = $powerShell.BeginInvoke()

  $script:serviceState = [pscustomobject]@{
    Runspace = $runspace
    PowerShell = $powerShell
    Cancellation = $cts
    Handle = $handle
    Status = "Running"
    Error = $null
  }
}

function Stop-Nop51BackgroundService {
  param(
    [switch]$SuppressAutoRestart
  )

  if ($script:serviceState.Status -ne "Running") {
    return
  }

  if ($SuppressAutoRestart) {
    $script:userStopRequested = $true
    $script:pendingServiceRestart = $false
    $script:serviceRestartCountdown = 0
  }

  $cts = $script:serviceState.Cancellation
  if ($cts) {
    $cts.Cancel()
  }

  try {
    if ($script:serviceState.PowerShell -and $script:serviceState.Handle) {
      $script:serviceState.PowerShell.EndInvoke($script:serviceState.Handle)
    }
  } catch {
    $script:serviceState.Error = $_.Exception.Message
  }

  if ($script:serviceState.PowerShell) {
    $script:serviceState.PowerShell.Dispose()
  }
  if ($script:serviceState.Runspace) {
    $script:serviceState.Runspace.Dispose()
  }
  if ($cts) {
    $cts.Dispose()
  }

  $script:serviceState = [pscustomobject]@{
    Runspace = $null
    PowerShell = $null
    Cancellation = $null
    Handle = $null
    Status = "Stopped"
    Error = $script:serviceState.Error
  }
}

function Update-Nop51ServiceUi {
  param(
    [System.Windows.Forms.Button]$StartButton,
    [System.Windows.Forms.Label]$StatusLabel,
    [string]$StatusOverride = $null
  )

  if ($script:serviceState.Status -eq "Running") {
    $StartButton.Text = "Stop service"
    $StatusLabel.Text = if ($StatusOverride) { $StatusOverride } else { "Service running" }
  } else {
    $StartButton.Text = "Start service"
    $StatusLabel.Text = if ($StatusOverride) { $StatusOverride } else { "Service stopped" }
  }
}

function Hide-Nop51ControlPanel {
  param(
    [System.Windows.Forms.Form]$Form
  )

  if ($null -eq $Form) {
    return
  }

  Try-Nop51AutoSave
  $Form.Hide()
  if ($script:uiControls -and $script:uiControls.TrayIcon) {
    $script:uiControls.TrayIcon.Visible = $true
    if (-not $script:trayBalloonShown) {
  $script:uiControls.TrayIcon.ShowBalloonTip(1500, "NO-P51", "The control panel stays active in the taskbar.", [System.Windows.Forms.ToolTipIcon]::Info)
      $script:trayBalloonShown = $true
    }
  }
}

function Invoke-Nop51KillTarget {
  param(
    [Parameter(Mandatory = $true)][string]$TargetValue,
    [Parameter(Mandatory = $true)][bool]$UsePid
  )

  $trimmed = $TargetValue.Trim()
  if ([string]::IsNullOrWhiteSpace($trimmed)) {
    throw "Select a target process before attempting to stop it."
  }

  if ($UsePid) {
    $pid = 0
    if (-not [int]::TryParse($trimmed, [ref]$pid) -or $pid -le 0) {
      throw "The target PID is not a valid positive integer."
    }

    $process = Get-Process -Id $pid -ErrorAction SilentlyContinue
    if (-not $process) {
      throw "Unable to find a process with PID $pid. The process may have already stopped."
    }
    $process | Stop-Process -Force -ErrorAction Stop
    return 1
  }

  $nameToken = $trimmed
  if ($nameToken.EndsWith(".exe", [System.StringComparison]::OrdinalIgnoreCase)) {
    $nameToken = $nameToken.Substring(0, $nameToken.Length - 4)
  }

  if ([string]::IsNullOrWhiteSpace($nameToken)) {
    throw "The target process name is empty after removing the .exe suffix."
  }

  $processes = Get-Process -Name $nameToken -ErrorAction SilentlyContinue
  if (-not $processes -or $processes.Count -eq 0) {
    throw "Unable to find a process named `"$nameToken`". Verify the process name and try calling the command again."
  }
  
  $count = 0
  foreach ($proc in $processes) {
    $proc | Stop-Process -Force -ErrorAction Stop
    $count++
  }
  return $count
}

function Stop-Nop51LauncherProcess {
  try {
    $current = [System.Diagnostics.Process]::GetCurrentProcess()
    $currentInfo = Get-CimInstance Win32_Process -Filter "ProcessId=$($current.Id)"
    if (-not $currentInfo) { return }

    $parentId = $currentInfo.ParentProcessId
    if (-not $parentId -or $parentId -eq 0) { return }

    $parent = [System.Diagnostics.Process]::GetProcessById($parentId)
    $parentInfo = Get-CimInstance Win32_Process -Filter "ProcessId=$parentId"

    if ($parent -and $parentInfo) {
      $commandLine = $parentInfo.CommandLine
      if ($commandLine -and $commandLine.ToLowerInvariant().Contains("no-p51.bat")) {
        $parent.Kill()
      }
    }
  } catch {
    return
  }
}

function Stop-Nop51Application {
  param(
    [System.Windows.Forms.Form]$Form
  )

  Try-Nop51AutoSave
  if ($script:serviceState.Status -eq "Running") {
    Stop-Nop51BackgroundService -SuppressAutoRestart
  }
  $script:pendingServiceRestart = $false
  $script:serviceRestartCountdown = 0
  $script:userStopRequested = $true

  if ($script:uiControls -and $script:uiControls.ServiceMonitor) {
    $script:uiControls.ServiceMonitor.Stop()
  }

  if ($Form) {
    $script:allowFormClose = $true
    $Form.Close()
  }

  if ($script:uiControls -and $script:uiControls.TrayIcon) {
    $script:uiControls.TrayIcon.Visible = $false
    $script:uiControls.TrayIcon.Dispose()
  }

  Stop-Nop51LauncherProcess
  [System.Windows.Forms.Application]::Exit()
}

# UI Construction
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
$form = New-Object System.Windows.Forms.Form
$form.Text = "NO-P51 Control Panel"
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false
$form.StartPosition = "CenterScreen"
$form.ClientSize = New-Object System.Drawing.Size 860, 620
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)
$form.Icon = Get-Nop51AppIcon

$quickHideButton = New-Object System.Windows.Forms.Button
$quickHideButton.Text = "▲"
$quickHideButton.Font = [System.Drawing.Font]::new("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$quickHideButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$quickHideButton.FlatAppearance.BorderSize = 1
$quickHideButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
$quickHideButton.BackColor = [System.Drawing.Color]::FromArgb(59, 130, 246)
$quickHideButton.ForeColor = [System.Drawing.Color]::White
$quickHideButton.UseVisualStyleBackColor = $false
$quickHideButton.Location = New-Object System.Drawing.Point 812, 8
$quickHideButton.Size = New-Object System.Drawing.Size 32, 32
$quickHideButton.TabStop = $false
$quickHideButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($quickHideButton)

$targetGroup = New-Object System.Windows.Forms.GroupBox
$targetGroup.Text = "Target"
$targetGroup.Font = [System.Drawing.Font]::new("Segoe UI Semibold", 10, [System.Drawing.FontStyle]::Bold)
$targetGroup.Location = New-Object System.Drawing.Point 10, 45
$targetGroup.Size = New-Object System.Drawing.Size 420, 340
$targetGroup.BackColor = [System.Drawing.Color]::White
$targetGroup.ForeColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
$form.Controls.Add($targetGroup)

$processLabel = New-Object System.Windows.Forms.Label
$processLabel.Text = "Running processes"
$processLabel.Font = [System.Drawing.Font]::new("Segoe UI", 9)
$processLabel.Location = New-Object System.Drawing.Point 15, 25
$processLabel.AutoSize = $true
$targetGroup.Controls.Add($processLabel)

$processFilterLabel = New-Object System.Windows.Forms.Label
$processFilterLabel.Text = "Filter"
$processFilterLabel.Font = [System.Drawing.Font]::new("Segoe UI", 9)
$processFilterLabel.Location = New-Object System.Drawing.Point 15, 50
$processFilterLabel.AutoSize = $true
$targetGroup.Controls.Add($processFilterLabel)

$processFilterText = New-Object System.Windows.Forms.TextBox
$processFilterText.Font = [System.Drawing.Font]::new("Segoe UI", 9)
$processFilterText.Location = New-Object System.Drawing.Point 70, 47
$processFilterText.Size = New-Object System.Drawing.Size 190, 26
$processFilterText.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$targetGroup.Controls.Add($processFilterText)

$processList = New-Object System.Windows.Forms.ListBox
$processList.Location = New-Object System.Drawing.Point 15, 85
$processList.Size = New-Object System.Drawing.Size 240, 220
$processList.SelectionMode = [System.Windows.Forms.SelectionMode]::One
$targetGroup.Controls.Add($processList)

$processHintLabel = New-Object System.Windows.Forms.Label
$processHintLabel.Text = "Double-click a process to copy it below"
$processHintLabel.Location = New-Object System.Drawing.Point 15, 315
$processHintLabel.AutoSize = $true
$targetGroup.Controls.Add($processHintLabel)

$refreshProcessesButton = New-Object System.Windows.Forms.Button
$refreshProcessesButton.Text = "Refresh"
$refreshProcessesButton.Font = [System.Drawing.Font]::new("Segoe UI", 9)
$refreshProcessesButton.Location = New-Object System.Drawing.Point 270, 45
$refreshProcessesButton.Size = New-Object System.Drawing.Size 120, 32
$refreshProcessesButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$refreshProcessesButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(203, 213, 225)
$refreshProcessesButton.BackColor = [System.Drawing.Color]::FromArgb(241, 245, 249)
$refreshProcessesButton.ForeColor = [System.Drawing.Color]::FromArgb(51, 65, 85)
$refreshProcessesButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$targetGroup.Controls.Add($refreshProcessesButton)

$privilegeStatusLabel = New-Object System.Windows.Forms.Label
$privilegeStatusLabel.Location = New-Object System.Drawing.Point 270, 85
$privilegeStatusLabel.AutoSize = $true
if ($script:isElevatedSession) {
  $privilegeStatusLabel.Text = "Privilege: Administrator"
  $privilegeStatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 128, 64)
} else {
  $privilegeStatusLabel.Text = "Privilege: Standard user"
  $privilegeStatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(160, 80, 0)
}
$targetGroup.Controls.Add($privilegeStatusLabel)

$targetLabel = New-Object System.Windows.Forms.Label
$targetLabel.Text = "Selected process"
$targetLabel.Location = New-Object System.Drawing.Point 270, 110
$targetLabel.AutoSize = $true
$targetGroup.Controls.Add($targetLabel)

$targetText = New-Object System.Windows.Forms.TextBox
$targetText.Location = New-Object System.Drawing.Point 270, 130
$targetText.Size = New-Object System.Drawing.Size 150, 26
$targetGroup.Controls.Add($targetText)

$usePidCheckbox = New-Object System.Windows.Forms.CheckBox
$usePidCheckbox.Text = "Use PID when selecting"
$usePidCheckbox.Location = New-Object System.Drawing.Point 270, 165
$usePidCheckbox.AutoSize = $true
$targetGroup.Controls.Add($usePidCheckbox)

$targetHintLabel = New-Object System.Windows.Forms.Label
$targetHintLabel.Location = New-Object System.Drawing.Point 270, 190
$targetHintLabel.MaximumSize = New-Object System.Drawing.Size 150, 0
$targetHintLabel.AutoSize = $true
$targetHintLabel.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
$targetHintLabel.Text = "Tip: prefer the executable name (.exe) for stability. Process IDs change every launch."
$targetGroup.Controls.Add($targetHintLabel)

$hideStrategyLabel = New-Object System.Windows.Forms.Label
$hideStrategyLabel.Text = "Hide strategy"
$hideStrategyLabel.Location = New-Object System.Drawing.Point 270, 220
$hideStrategyLabel.AutoSize = $true
$targetGroup.Controls.Add($hideStrategyLabel)

$hideStrategyCombo = New-Object System.Windows.Forms.ComboBox
$hideStrategyCombo.Location = New-Object System.Drawing.Point 270, 240
$hideStrategyCombo.Size = New-Object System.Drawing.Size 140, 26
$hideStrategyCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$hideStrategyCombo.DisplayMember = "Text"
$hideStrategyCombo.ValueMember = "Value"
$hideStrategyCombo.Items.Add([pscustomobject]@{ Text = "Hide window (no admin)"; Value = "hide" }) | Out-Null
$hideStrategyCombo.Items.Add([pscustomobject]@{ Text = "Terminate process (admin)"; Value = "terminate" }) | Out-Null
$targetGroup.Controls.Add($hideStrategyCombo)

$hideStrategyWarningLabel = New-Object System.Windows.Forms.Label
$hideStrategyWarningLabel.Location = New-Object System.Drawing.Point 270, 270
$hideStrategyWarningLabel.MaximumSize = New-Object System.Drawing.Size 150, 0
$hideStrategyWarningLabel.AutoSize = $true
$targetGroup.Controls.Add($hideStrategyWarningLabel)

$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.SetToolTip($quickHideButton, "Hide the control panel immediately (runs in the tray).")
$toolTip.SetToolTip($processList, "Double-click a process to copy its name into the target field.")
$toolTip.SetToolTip($processHintLabel, "Double-click a process to copy its name into the target field.")
$toolTip.SetToolTip($processFilterText, "Filter the list in real time by typing part of the process name.")
$toolTip.SetToolTip($targetText, "Enter the process executable name (extension optional). Process IDs change after each restart.")
$toolTip.SetToolTip($usePidCheckbox, "Use this only when you must target a specific PID; it will change next time the app starts.")
$toolTip.SetToolTip($hideStrategyCombo, "Choose whether the hide hotkey only conceals the window or attempts to terminate the process.")
$toolTip.SetToolTip($privilegeStatusLabel, "Exposure of current privileges: administrator mode unlocks stronger fallback strategies.")

$hotkeyGroup = New-Object System.Windows.Forms.GroupBox
$hotkeyGroup.Text = "Hotkeys"
$hotkeyGroup.Font = [System.Drawing.Font]::new("Segoe UI Semibold", 10, [System.Drawing.FontStyle]::Bold)
$hotkeyGroup.Location = New-Object System.Drawing.Point 440, 45
$hotkeyGroup.Size = New-Object System.Drawing.Size 410, 150
$hotkeyGroup.BackColor = [System.Drawing.Color]::White
$hotkeyGroup.ForeColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
$form.Controls.Add($hotkeyGroup)

$hideHotkeyLabel = New-Object System.Windows.Forms.Label
$hideHotkeyLabel.Text = "Hide"
$hideHotkeyLabel.Location = New-Object System.Drawing.Point 15, 35
$hideHotkeyLabel.AutoSize = $true
$hotkeyGroup.Controls.Add($hideHotkeyLabel)

$hideHotkeyText = New-Object System.Windows.Forms.TextBox
$hideHotkeyText.Location = New-Object System.Drawing.Point 70, 30
$hideHotkeyText.Size = New-Object System.Drawing.Size 200, 26
$hideHotkeyText.ReadOnly = $true
$hideHotkeyText.TabStop = $true
$hotkeyGroup.Controls.Add($hideHotkeyText)

$restoreHotkeyLabel = New-Object System.Windows.Forms.Label
$restoreHotkeyLabel.Text = "Restore"
$restoreHotkeyLabel.Location = New-Object System.Drawing.Point 15, 75
$restoreHotkeyLabel.AutoSize = $true
$hotkeyGroup.Controls.Add($restoreHotkeyLabel)

$restoreHotkeyText = New-Object System.Windows.Forms.TextBox
$restoreHotkeyText.Location = New-Object System.Drawing.Point 70, 70
$restoreHotkeyText.Size = New-Object System.Drawing.Size 200, 26
$restoreHotkeyText.ReadOnly = $true
$restoreHotkeyText.TabStop = $true
$hotkeyGroup.Controls.Add($restoreHotkeyText)

$hotkeyHint = New-Object System.Windows.Forms.Label
$hotkeyHint.Text = "Click a box, then press the key combination"
$hotkeyHint.Location = New-Object System.Drawing.Point 280, 35
$hotkeyHint.AutoSize = $true
$hotkeyGroup.Controls.Add($hotkeyHint)

$brandingGroup = New-Object System.Windows.Forms.GroupBox
$brandingGroup.Text = "Branding"
$brandingGroup.Font = [System.Drawing.Font]::new("Segoe UI Semibold", 10, [System.Drawing.FontStyle]::Bold)
$brandingGroup.Location = New-Object System.Drawing.Point 440, 205
$brandingGroup.Size = New-Object System.Drawing.Size 410, 200
$brandingGroup.BackColor = [System.Drawing.Color]::White
$brandingGroup.ForeColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
$form.Controls.Add($brandingGroup)

$logoPathLabel = New-Object System.Windows.Forms.Label
$logoPathLabel.Text = "Logo path (.png / .ico, default: logo.png)"
$logoPathLabel.Location = New-Object System.Drawing.Point 15, 30
$logoPathLabel.AutoSize = $true
$brandingGroup.Controls.Add($logoPathLabel)

$logoPathText = New-Object System.Windows.Forms.TextBox
$logoPathText.Location = New-Object System.Drawing.Point 15, 55
$logoPathText.Size = New-Object System.Drawing.Size 250, 26
$brandingGroup.Controls.Add($logoPathText)

$logoBrowseButton = New-Object System.Windows.Forms.Button
$logoBrowseButton.Text = "Browse..."
$logoBrowseButton.Location = New-Object System.Drawing.Point 275, 53
$logoBrowseButton.Size = New-Object System.Drawing.Size 90, 30
$logoBrowseButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$logoBrowseButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(203, 213, 225)
$logoBrowseButton.BackColor = [System.Drawing.Color]::FromArgb(241, 245, 249)
$logoBrowseButton.ForeColor = [System.Drawing.Color]::FromArgb(51, 65, 85)
$logoBrowseButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$brandingGroup.Controls.Add($logoBrowseButton)

$logoClearButton = New-Object System.Windows.Forms.Button
$logoClearButton.Text = "Clear"
$logoClearButton.Location = New-Object System.Drawing.Point 275, 90
$logoClearButton.Size = New-Object System.Drawing.Size 90, 30
$logoClearButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$logoClearButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(203, 213, 225)
$logoClearButton.BackColor = [System.Drawing.Color]::FromArgb(249, 250, 251)
$logoClearButton.ForeColor = [System.Drawing.Color]::FromArgb(75, 85, 99)
$logoClearButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$brandingGroup.Controls.Add($logoClearButton)

$logoPreviewLabel = New-Object System.Windows.Forms.Label
$logoPreviewLabel.Text = "Preview"
$logoPreviewLabel.Location = New-Object System.Drawing.Point 315, 80
$logoPreviewLabel.AutoSize = $true
$brandingGroup.Controls.Add($logoPreviewLabel)

$logoPicture = New-Object System.Windows.Forms.PictureBox
$logoPicture.Location = New-Object System.Drawing.Point 315, 100
$logoPicture.Size = New-Object System.Drawing.Size 72, 72
$logoPicture.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$logoPicture.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$brandingGroup.Controls.Add($logoPicture)

$fallbackGroup = New-Object System.Windows.Forms.GroupBox
$fallbackGroup.Text = "Fallback action"
$fallbackGroup.Font = [System.Drawing.Font]::new("Segoe UI Semibold", 10, [System.Drawing.FontStyle]::Bold)
$fallbackGroup.Location = New-Object System.Drawing.Point 10, 400
$fallbackGroup.Size = New-Object System.Drawing.Size 840, 140
$fallbackGroup.BackColor = [System.Drawing.Color]::White
$fallbackGroup.ForeColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
$form.Controls.Add($fallbackGroup)

$fallbackNone = New-Object System.Windows.Forms.RadioButton
$fallbackNone.Text = "None"
$fallbackNone.Location = New-Object System.Drawing.Point 15, 30
$fallbackNone.AutoSize = $true
$fallbackNone.Checked = $true
$fallbackGroup.Controls.Add($fallbackNone)

$fallbackApp = New-Object System.Windows.Forms.RadioButton
$fallbackApp.Text = "Launch app"
$fallbackApp.Location = New-Object System.Drawing.Point 15, 55
$fallbackApp.AutoSize = $true
$fallbackGroup.Controls.Add($fallbackApp)

$fallbackUrl = New-Object System.Windows.Forms.RadioButton
$fallbackUrl.Text = "Open URL"
$fallbackUrl.Location = New-Object System.Drawing.Point 15, 80
$fallbackUrl.AutoSize = $true
$fallbackGroup.Controls.Add($fallbackUrl)

$fallbackValueLabel = New-Object System.Windows.Forms.Label
$fallbackValueLabel.Text = "Value"
$fallbackValueLabel.Location = New-Object System.Drawing.Point 150, 35
$fallbackValueLabel.AutoSize = $true
$fallbackGroup.Controls.Add($fallbackValueLabel)

$fallbackValueText = New-Object System.Windows.Forms.TextBox
$fallbackValueText.Location = New-Object System.Drawing.Point 150, 55
$fallbackValueText.Size = New-Object System.Drawing.Size 360, 26
$fallbackGroup.Controls.Add($fallbackValueText)

$fallbackAutoClose = New-Object System.Windows.Forms.CheckBox
$fallbackAutoClose.Text = "Close fallback app on restore"
$fallbackAutoClose.Location = New-Object System.Drawing.Point 520, 55
$fallbackAutoClose.AutoSize = $true
$fallbackGroup.Controls.Add($fallbackAutoClose)

$fallbackFullscreen = New-Object System.Windows.Forms.CheckBox
$fallbackFullscreen.Text = "Toggle fullscreen (F11) after launch"
$fallbackFullscreen.Location = New-Object System.Drawing.Point 520, 85
$fallbackFullscreen.AutoSize = $true
$fallbackGroup.Controls.Add($fallbackFullscreen)
$toolTip.SetToolTip($fallbackFullscreen, "Send F11 when the fallback window appears to cover the screen quickly.")
$toolTip.SetToolTip($logoPathText, "Use a .png or .ico file. Relative paths are resolved from the NO-P51 folder.")
$toolTip.SetToolTip($logoBrowseButton, "Select an image to use for the tray icon and preview.")
$toolTip.SetToolTip($logoClearButton, "Reset to the bundled logo.")
$toolTip.SetToolTip($logoPicture, "Current icon preview.")

$saveButton = New-Object System.Windows.Forms.Button
$saveButton.Text = "Save configuration"
$saveButton.Font = [System.Drawing.Font]::new("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$saveButton.Location = New-Object System.Drawing.Point 10, 570
$saveButton.Size = New-Object System.Drawing.Size 160, 35
$saveButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$saveButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(34, 197, 94)
$saveButton.BackColor = [System.Drawing.Color]::FromArgb(34, 197, 94)
$saveButton.ForeColor = [System.Drawing.Color]::White
$saveButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($saveButton)

$startButton = New-Object System.Windows.Forms.Button
$startButton.Text = "▶ Start service"
$startButton.Font = [System.Drawing.Font]::new("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$startButton.Location = New-Object System.Drawing.Point 190, 570
$startButton.Size = New-Object System.Drawing.Size 140, 35
$startButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$startButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(59, 130, 246)
$startButton.BackColor = [System.Drawing.Color]::FromArgb(59, 130, 246)
$startButton.ForeColor = [System.Drawing.Color]::White
$startButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($startButton)

$killTargetButton = New-Object System.Windows.Forms.Button
$killTargetButton.Text = "Kill target"
$killTargetButton.Font = [System.Drawing.Font]::new("Segoe UI", 9)
$killTargetButton.Location = New-Object System.Drawing.Point 360, 570
$killTargetButton.Size = New-Object System.Drawing.Size 120, 35
$killTargetButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$killTargetButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(239, 68, 68)
$killTargetButton.BackColor = [System.Drawing.Color]::FromArgb(254, 242, 242)
$killTargetButton.ForeColor = [System.Drawing.Color]::FromArgb(220, 38, 38)
$killTargetButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($killTargetButton)

$exitAppButton = New-Object System.Windows.Forms.Button
$exitAppButton.Text = "Exit"
$exitAppButton.Font = [System.Drawing.Font]::new("Segoe UI", 9)
$exitAppButton.Location = New-Object System.Drawing.Point 700, 570
$exitAppButton.Size = New-Object System.Drawing.Size 100, 35
$exitAppButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$exitAppButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(156, 163, 175)
$exitAppButton.BackColor = [System.Drawing.Color]::FromArgb(249, 250, 251)
$exitAppButton.ForeColor = [System.Drawing.Color]::FromArgb(75, 85, 99)
$exitAppButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($exitAppButton)
$toolTip.SetToolTip($killTargetButton, "Force-stop the configured process immediately, similar to Task Manager's End Task.")
$toolTip.SetToolTip($exitAppButton, "Stop NO-P51 entirely and close the launcher.")

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Service stopped"
$statusLabel.Font = [System.Drawing.Font]::new("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
$statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
$statusLabel.Location = New-Object System.Drawing.Point 10, 540
$statusLabel.AutoSize = $true
$form.Controls.Add($statusLabel)

$configStatusLabel = New-Object System.Windows.Forms.Label
$configStatusLabel.Text = ""
$configStatusLabel.Font = [System.Drawing.Font]::new("Segoe UI", 8)
$configStatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(107, 114, 128)
$configStatusLabel.Location = New-Object System.Drawing.Point 10, 605
$configStatusLabel.AutoSize = $true
$form.Controls.Add($configStatusLabel)

$trayIcon = New-Object System.Windows.Forms.NotifyIcon
$trayIcon.Icon = Get-Nop51AppIcon
$trayIcon.Text = "NO-P51"
$trayIcon.Visible = $true

$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$menuOpen = $trayMenu.Items.Add("Open interface")
$menuExit = $trayMenu.Items.Add("Exit NO-P51")
$trayIcon.ContextMenuStrip = $trayMenu

$serviceMonitor = New-Object System.Windows.Forms.Timer
$serviceMonitor.Interval = 1000

$autoSaveTimer = New-Object System.Windows.Forms.Timer
$autoSaveTimer.Interval = 1200
$autoSaveTimer.add_Tick({
  if ($script:autoSaveTimer) {
    $script:autoSaveTimer.Stop()
  }
  Try-Nop51AutoSave
})
$script:autoSaveTimer = $autoSaveTimer

# Store controls in script scope for helper functions
$script:uiControls = [pscustomobject]@{
  ProcessFilterText = $processFilterText
  ProcessList = $processList
  TargetText = $targetText
  UsePidCheckbox = $usePidCheckbox
  QuickHideButton = $quickHideButton
  HideStrategyCombo = $hideStrategyCombo
  HideStrategyWarningLabel = $hideStrategyWarningLabel
  PrivilegeStatusLabel = $privilegeStatusLabel
  HideHotkeyText = $hideHotkeyText
  RestoreHotkeyText = $restoreHotkeyText
  LogoPathText = $logoPathText
  LogoBrowseButton = $logoBrowseButton
  LogoClearButton = $logoClearButton
  LogoPicture = $logoPicture
  FallbackNone = $fallbackNone
  FallbackApp = $fallbackApp
  FallbackUrl = $fallbackUrl
  FallbackValueText = $fallbackValueText
  FallbackValueLabel = $fallbackValueLabel
  FallbackAutoClose = $fallbackAutoClose
  FallbackFullscreen = $fallbackFullscreen
  StartButton = $startButton
  KillTargetButton = $killTargetButton
  ExitAppButton = $exitAppButton
  StatusLabel = $statusLabel
  ConfigStatusLabel = $configStatusLabel
  TrayIcon = $trayIcon
  ServiceMonitor = $serviceMonitor
  AutoSaveTimer = $autoSaveTimer
}

function Update-FallbackControls {
  if ($script:uiControls.FallbackApp.Checked) {
    $script:uiControls.FallbackValueLabel.Text = "Executable path"
    $script:uiControls.FallbackValueText.Enabled = $true
    $script:uiControls.FallbackAutoClose.Enabled = $true
    $script:uiControls.FallbackFullscreen.Enabled = $true
  } elseif ($script:uiControls.FallbackUrl.Checked) {
    $script:uiControls.FallbackValueLabel.Text = "URL"
    $script:uiControls.FallbackValueText.Enabled = $true
    $script:uiControls.FallbackAutoClose.Enabled = $false
    $script:uiControls.FallbackAutoClose.Checked = $false
    $script:uiControls.FallbackFullscreen.Enabled = $true
  } else {
    $script:uiControls.FallbackValueLabel.Text = "Value"
    $script:uiControls.FallbackValueText.Enabled = $false
    $script:uiControls.FallbackValueText.Text = ""
    $script:uiControls.FallbackAutoClose.Enabled = $false
    $script:uiControls.FallbackAutoClose.Checked = $false
    $script:uiControls.FallbackFullscreen.Enabled = $false
    $script:uiControls.FallbackFullscreen.Checked = $false
  }
}

function Update-HideStrategyWarning {
  if (-not $script:uiControls -or -not $script:uiControls.HideStrategyCombo -or -not $script:uiControls.HideStrategyWarningLabel) {
    return
  }

  $combo = $script:uiControls.HideStrategyCombo
  $label = $script:uiControls.HideStrategyWarningLabel
  $label.Text = ""
  $label.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)

  $selectedValue = "hide"
  if ($combo.SelectedItem) {
    $selectedValue = $combo.SelectedItem.Value
  }

  switch ($selectedValue) {
    "terminate" {
      if ($script:isElevatedSession) {
        $label.Text = "Kills the process instantly. The restore hotkey will not relaunch it automatically."
        $label.ForeColor = [System.Drawing.Color]::FromArgb(160, 32, 32)
      } else {
        $label.Text = "Attempts to kill the process. Windows may refuse if you lack permission."
        $label.ForeColor = [System.Drawing.Color]::FromArgb(192, 96, 0)
      }
    }
    default {
      $label.Text = "Hides the window and keeps the process running."
    }
  }
}

function Populate-FormFromConfig {
  param(
    [psobject]$Config
  )

  $script:isLoadingConfig = $true
  try {
    if (-not $Config) {
      $script:uiControls.TargetText.Text = ""
      $script:uiControls.UsePidCheckbox.Checked = $false
      $script:uiControls.HideHotkeyText.Text = "="
      $script:uiControls.RestoreHotkeyText.Text = "Ctrl+Alt+R"
      $script:uiControls.FallbackNone.Checked = $true
      if ($script:uiControls.HideStrategyCombo -and $script:uiControls.HideStrategyCombo.Items.Count -gt 0) {
        $script:uiControls.HideStrategyCombo.SelectedIndex = 0
      }
      Update-FallbackControls
      return
    }

    $targetValue = $Config.targetProcessName
    $script:uiControls.TargetText.Text = $targetValue
    $script:uiControls.UsePidCheckbox.Checked = if ($targetValue -and $targetValue -match '^[0-9]+$') { $true } else { $false }
    if ($Config.hideHotkey) {
      $script:uiControls.HideHotkeyText.Text = $Config.hideHotkey
    } else {
      $script:uiControls.HideHotkeyText.Text = "="
    }
    if ($Config.restoreHotkey) {
      $script:uiControls.RestoreHotkeyText.Text = $Config.restoreHotkey
    } else {
      $script:uiControls.RestoreHotkeyText.Text = "Ctrl+Alt+R"
    }

    if ($script:uiControls.LogoPathText) {
      if ($Config.PSObject.Properties.Name -contains "iconPath" -and $Config.iconPath) {
        $script:uiControls.LogoPathText.Text = $Config.iconPath.ToString()
      } else {
        $defaultLogo = Resolve-Nop51IconPath -RequestedPath "logo.png"
        if ($defaultLogo) {
          $script:uiControls.LogoPathText.Text = "logo.png"
        } else {
          $script:uiControls.LogoPathText.Text = ""
        }
      }
    }

    if ($Config.fallback) {
      $mode = $Config.fallback.mode.ToString().ToLowerInvariant()
      switch ($mode) {
        "app" {
          $script:uiControls.FallbackApp.Checked = $true
          $script:uiControls.FallbackValueText.Text = $Config.fallback.value
          $script:uiControls.FallbackAutoClose.Checked = [bool]$Config.fallback.autoClose
          $script:uiControls.FallbackFullscreen.Checked = [bool]$Config.fallback.fullscreen
        }
        "url" {
          $script:uiControls.FallbackUrl.Checked = $true
          $script:uiControls.FallbackValueText.Text = $Config.fallback.value
          $script:uiControls.FallbackFullscreen.Checked = [bool]$Config.fallback.fullscreen
        }
        default {
          $script:uiControls.FallbackNone.Checked = $true
          $script:uiControls.FallbackValueText.Text = ""
          $script:uiControls.FallbackAutoClose.Checked = $false
          $script:uiControls.FallbackFullscreen.Checked = $false
        }
      }
    } else {
      $script:uiControls.FallbackNone.Checked = $true
      $script:uiControls.FallbackValueText.Text = ""
      $script:uiControls.FallbackAutoClose.Checked = $false
      $script:uiControls.FallbackFullscreen.Checked = $false
    }

    $desiredStrategy = if ($Config.PSObject.Properties.Name -contains "hideStrategy" -and $Config.hideStrategy) { $Config.hideStrategy.ToString().ToLowerInvariant() } else { "hide" }
    $selected = $null
    if ($script:uiControls.HideStrategyCombo) {
      foreach ($item in $script:uiControls.HideStrategyCombo.Items) {
        if ($item.Value -eq $desiredStrategy) {
          $selected = $item
          break
        }
      }
      if ($selected) {
        $script:uiControls.HideStrategyCombo.SelectedItem = $selected
      } elseif ($script:uiControls.HideStrategyCombo.Items.Count -gt 0) {
        $script:uiControls.HideStrategyCombo.SelectedIndex = 0
      }
    }
  }
  finally {
    Refresh-Nop51IconPreviewFromTextBox
    Update-FallbackControls
    Update-HideStrategyWarning
    $script:isLoadingConfig = $false
    Set-Nop51ConfigDirty -Dirty:$false
  }
}

function Refresh-ProcessList {
  param(
    [switch]$PreserveSelection
  )

  $filterText = ""
  if ($script:uiControls -and $script:uiControls.ProcessFilterText) {
    $filterText = $script:uiControls.ProcessFilterText.Text.Trim()
  }

  $previousId = $null
  if ($PreserveSelection -and $script:uiControls.ProcessList.SelectedItem) {
    if ($script:autoSaveTimer) {
      $script:autoSaveTimer.Stop()
    }
    $previousId = $script:uiControls.ProcessList.SelectedItem.Id
  }

  $items = Get-Nop51RunningProcessItems
  if ($filterText) {
    $lower = $filterText.ToLowerInvariant()
    $items = $items | Where-Object {
      $_.ProcessName.ToLowerInvariant().Contains($lower) -or
      ("$($_.ProcessName).exe").ToLowerInvariant().Contains($lower)
    }
  }

  $script:uiControls.ProcessList.BeginUpdate()
  $script:uiControls.ProcessList.Items.Clear()
  foreach ($item in $items) {
    $null = $script:uiControls.ProcessList.Items.Add($item)
  }
  $script:uiControls.ProcessList.EndUpdate()

  if ($PreserveSelection -and $previousId) {
    foreach ($candidate in $script:uiControls.ProcessList.Items) {
      if ($candidate.Id -eq $previousId) {
        $script:uiControls.ProcessList.SelectedItem = $candidate
        break
      }
    }
  }
}

function Handle-HotkeyKeyDown {
  param(
    [System.Windows.Forms.TextBox]$TextBox,
    [System.Windows.Forms.KeyEventArgs]$EventArgs
  )

  $EventArgs.SuppressKeyPress = $true
  $EventArgs.Handled = $true
  $hotKeyString = Convert-KeysToHotKeyString -EventArgs $EventArgs
  if ($hotKeyString) {
    $TextBox.Text = $hotKeyString.ToUpperInvariant()
    Set-Nop51ConfigDirty -Dirty:$true -SyncNow
  }
}

$processList.add_DoubleClick({
  if ($script:uiControls.ProcessList.SelectedItem) {
    $selected = $script:uiControls.ProcessList.SelectedItem
    if ($script:uiControls.UsePidCheckbox.Checked) {
      $script:uiControls.TargetText.Text = $selected.Id.ToString()
    } else {
      $script:uiControls.TargetText.Text = "$($selected.ProcessName).exe"
    }
    Set-Nop51ConfigDirty -Dirty:$true -SyncNow
  }
})

$processFilterText.add_TextChanged({
  Refresh-ProcessList -PreserveSelection
})

$targetText.add_TextChanged({
  if ($script:isLoadingConfig) {
    return
  }
  Set-Nop51ConfigDirty
})

$targetText.add_Leave({
  if ($script:isLoadingConfig) {
    return
  }
  Set-Nop51ConfigDirty -SyncNow
})

$quickHideButton.add_Click({
  Hide-Nop51ControlPanel -Form $form
})

$usePidCheckbox.add_CheckedChanged({
  if ($script:isLoadingConfig) {
    return
  }
  Set-Nop51ConfigDirty -SyncNow
})

$hideStrategyCombo.add_SelectedIndexChanged({
  Update-HideStrategyWarning
  if ($script:isLoadingConfig) {
    return
  }
  Set-Nop51ConfigDirty -SyncNow
  $selectedItem = $script:uiControls.HideStrategyCombo.SelectedItem
  if ($selectedItem -and $selectedItem.Value -eq "terminate" -and -not $script:isElevatedSession) {
    Update-Nop51ConfigStatus "Terminate process mode will try to stop the process, but Windows may refuse."
  }
})

# Button hover effects
$saveButton.add_MouseEnter({
  $saveButton.BackColor = [System.Drawing.Color]::FromArgb(22, 163, 74)
})
$saveButton.add_MouseLeave({
  $saveButton.BackColor = [System.Drawing.Color]::FromArgb(34, 197, 94)
})

$startButton.add_MouseEnter({
  $startButton.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
})
$startButton.add_MouseLeave({
  $startButton.BackColor = [System.Drawing.Color]::FromArgb(59, 130, 246)
})

$killTargetButton.add_MouseEnter({
  $killTargetButton.BackColor = [System.Drawing.Color]::FromArgb(254, 226, 226)
})
$killTargetButton.add_MouseLeave({
  $killTargetButton.BackColor = [System.Drawing.Color]::FromArgb(254, 242, 242)
})

$exitAppButton.add_MouseEnter({
  $exitAppButton.BackColor = [System.Drawing.Color]::FromArgb(243, 244, 246)
})
$exitAppButton.add_MouseLeave({
  $exitAppButton.BackColor = [System.Drawing.Color]::FromArgb(249, 250, 251)
})

$quickHideButton.add_MouseEnter({
  $quickHideButton.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
})
$quickHideButton.add_MouseLeave({
  $quickHideButton.BackColor = [System.Drawing.Color]::FromArgb(59, 130, 246)
})

$refreshProcessesButton.add_MouseEnter({
  $refreshProcessesButton.BackColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
})
$refreshProcessesButton.add_MouseLeave({
  $refreshProcessesButton.BackColor = [System.Drawing.Color]::FromArgb(241, 245, 249)
})

$logoBrowseButton.add_MouseEnter({
  $logoBrowseButton.BackColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
})
$logoBrowseButton.add_MouseLeave({
  $logoBrowseButton.BackColor = [System.Drawing.Color]::FromArgb(241, 245, 249)
})

$logoClearButton.add_MouseEnter({
  $logoClearButton.BackColor = [System.Drawing.Color]::FromArgb(229, 231, 235)
})
$logoClearButton.add_MouseLeave({
  $logoClearButton.BackColor = [System.Drawing.Color]::FromArgb(249, 250, 251)
})

$refreshProcessesButton.add_Click({ Refresh-ProcessList -PreserveSelection })

$script:uiControls.FallbackNone.add_CheckedChanged({
  Update-FallbackControls
  if ($script:isLoadingConfig) { return }
  Set-Nop51ConfigDirty -SyncNow
})
$script:uiControls.FallbackApp.add_CheckedChanged({
  Update-FallbackControls
  if ($script:isLoadingConfig) { return }
  Set-Nop51ConfigDirty -SyncNow
})
$script:uiControls.FallbackUrl.add_CheckedChanged({
  Update-FallbackControls
  if ($script:isLoadingConfig) { return }
  Set-Nop51ConfigDirty -SyncNow
})

$fallbackValueText.add_TextChanged({
  if ($script:isLoadingConfig) {
    return
  }
  Set-Nop51ConfigDirty
})

$fallbackValueText.add_Leave({
  if ($script:isLoadingConfig) {
    return
  }
  Set-Nop51ConfigDirty -SyncNow
})

$fallbackAutoClose.add_CheckedChanged({
  if ($script:isLoadingConfig) {
    return
  }
  Set-Nop51ConfigDirty -SyncNow
})

$fallbackFullscreen.add_CheckedChanged({
  if ($script:isLoadingConfig) {
    return
  }
  Set-Nop51ConfigDirty -SyncNow
})

$logoPathText.add_TextChanged({
  if ($script:isLoadingConfig) {
    return
  }
  Refresh-Nop51IconPreviewFromTextBox
  Set-Nop51ConfigDirty
})

$logoPathText.add_Leave({
  if ($script:isLoadingConfig) {
    return
  }
  Refresh-Nop51IconPreviewFromTextBox
  Set-Nop51ConfigDirty -SyncNow
})

$logoBrowseButton.add_Click({
  $dialog = New-Object System.Windows.Forms.OpenFileDialog
  $dialog.Filter = "PNG or ICO|*.png;*.ico|All files|*.*"
  if ($script:resolvedIconPath -and (Test-Path -LiteralPath $script:resolvedIconPath)) {
    $dialog.InitialDirectory = [System.IO.Path]::GetDirectoryName($script:resolvedIconPath)
  } elseif ($script:repoRoot -and (Test-Path -LiteralPath $script:repoRoot)) {
    $dialog.InitialDirectory = $script:repoRoot
  }

  if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    $logoPathText.Text = $dialog.FileName
  }
})

$logoClearButton.add_Click({
  if ($logoPathText.Text.Length -eq 0) {
    return
  }
  $logoPathText.Text = ""
})

$hideHotkeyText.add_KeyDown({ Handle-HotkeyKeyDown -TextBox $script:uiControls.HideHotkeyText -EventArgs $_ })
$restoreHotkeyText.add_KeyDown({ Handle-HotkeyKeyDown -TextBox $script:uiControls.RestoreHotkeyText -EventArgs $_ })

$saveButton.add_Click({
  try {
    Invoke-Nop51SaveConfigFromUi -Silent | Out-Null
    Show-Nop51Info "Configuration saved."
    Set-Nop51ConfigDirty -Dirty:$false
    Update-Nop51ConfigStatus "Configuration saved manually"
  } catch {
    Show-Nop51Error $_.Exception.Message
  }
})

$startButton.add_Click({
  try {
    if ($script:serviceState.Status -eq "Running") {
      Stop-Nop51BackgroundService -SuppressAutoRestart
      Update-Nop51ServiceUi -StartButton $script:uiControls.StartButton -StatusLabel $script:uiControls.StatusLabel
      if ($script:serviceState.Error) {
        Show-Nop51Error "Service stopped with error: $($script:serviceState.Error)"
        $script:serviceState.Error = $null
      }
      return
    }

    Invoke-Nop51SaveConfigFromUi -Silent | Out-Null
    Set-Nop51ConfigDirty -Dirty:$false
    Update-Nop51ConfigStatus "Configuration saved"
    Start-Nop51BackgroundService -Path $ConfigPath
    Update-Nop51ServiceUi -StartButton $script:uiControls.StartButton -StatusLabel $script:uiControls.StatusLabel
  } catch {
    Show-Nop51Error $_.Exception.Message
  }
})

$killTargetButton.add_Click({
  try {
    $usePid = $script:uiControls.UsePidCheckbox.Checked
    $targetValue = $script:uiControls.TargetText.Text.Trim()
    Invoke-Nop51SaveConfigFromUi -Silent | Out-Null
    Set-Nop51ConfigDirty -Dirty:$false
    $stopped = Invoke-Nop51KillTarget -TargetValue $targetValue -UsePid $usePid
    Refresh-ProcessList
    $statusMessage = if ($stopped -eq 1) { "Stopped process (1 instance)" } else { "Stopped processes ($stopped instances)" }
    Update-Nop51ConfigStatus $statusMessage
    $modalMessage = if ($stopped -eq 1) { "One target process instance was stopped." } else { "$stopped target process instances were stopped." }
    Show-Nop51Info $modalMessage
  } catch {
    Show-Nop51Error $_.Exception.Message
  }
})

$exitAppButton.add_Click({
  Stop-Nop51Application -Form $form
})

$serviceMonitor.add_Tick({
  if ($script:serviceState.Status -ne "Running") {
    if ($script:pendingServiceRestart -and $script:serviceRestartCountdown -gt 0) {
      $script:serviceRestartCountdown--
      if ($script:serviceRestartCountdown -le 0) {
        try {
          Start-Nop51BackgroundService -Path $ConfigPath
          Update-Nop51ServiceUi -StartButton $script:uiControls.StartButton -StatusLabel $script:uiControls.StatusLabel
          $script:pendingServiceRestart = $false
          $script:uiControls.TrayIcon.ShowBalloonTip(1500, "NO-P51", "Service restarted after an interruption.", [System.Windows.Forms.ToolTipIcon]::Info)
        } catch {
          $script:pendingServiceRestart = $false
          $script:uiControls.TrayIcon.ShowBalloonTip(2000, "NO-P51", "Could not restart the service: $($_.Exception.Message)", [System.Windows.Forms.ToolTipIcon]::Error)
        }
      }
    }
    return
  }
  if (-not $script:serviceState.Handle) {
    return
  }
  if ($script:serviceState.Handle.IsCompleted) {
    try {
      if ($script:serviceState.PowerShell) {
        $script:serviceState.PowerShell.EndInvoke($script:serviceState.Handle)
      }
    } catch {
      $script:serviceState.Error = $_.Exception.Message
    }
    if ($script:serviceState.PowerShell) {
      $script:serviceState.PowerShell.Dispose()
    }
    if ($script:serviceState.Runspace) {
      $script:serviceState.Runspace.Dispose()
    }
    if ($script:serviceState.Cancellation) {
      $script:serviceState.Cancellation.Dispose()
    }
    $script:serviceState = [pscustomobject]@{
      Runspace = $null
      PowerShell = $null
      Cancellation = $null
      Handle = $null
      Status = "Stopped"
      Error = $script:serviceState.Error
    }
    Update-Nop51ServiceUi -StartButton $script:uiControls.StartButton -StatusLabel $script:uiControls.StatusLabel
    if ($script:serviceState.Error) {
      if (-not $script:userStopRequested) {
        $script:pendingServiceRestart = $true
        $script:serviceRestartCountdown = 3
        $script:uiControls.TrayIcon.Visible = $true
  $script:uiControls.TrayIcon.ShowBalloonTip(2000, "NO-P51", "Service stopped: $($script:serviceState.Error)`nAutomatic restart in 3 s.", [System.Windows.Forms.ToolTipIcon]::Warning)
      } else {
        Show-Nop51Error "Service stopped: $($script:serviceState.Error)"
      }
      $script:serviceState.Error = $null
    } elseif (-not $script:userStopRequested) {
      $script:pendingServiceRestart = $true
      $script:serviceRestartCountdown = 3
      $script:uiControls.TrayIcon.Visible = $true
  $script:uiControls.TrayIcon.ShowBalloonTip(1500, "NO-P51", "Service interrupted. Automatic restart in 3 s.", [System.Windows.Forms.ToolTipIcon]::Warning)
    }
  }
})

$menuOpen.add_Click({
  $form.Show()
  $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
  $form.Activate()
})

$menuExit.add_Click({
  Stop-Nop51Application -Form $form
})

$trayIcon.add_DoubleClick({
  $form.Show()
  $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
  $form.Activate()
})

$form.add_FormClosing({
  param($sender, $eventArgs)
  if (-not $script:allowFormClose -and $eventArgs.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
    Try-Nop51AutoSave
    $eventArgs.Cancel = $true
    $sender.Hide()
    $script:uiControls.TrayIcon.Visible = $true
    if (-not $script:trayBalloonShown) {
      $script:uiControls.TrayIcon.ShowBalloonTip(2000, "NO-P51", "The control panel is still running in the tray.", [System.Windows.Forms.ToolTipIcon]::Info)
      $script:trayBalloonShown = $true
    }
  } else {
    Try-Nop51AutoSave
    if ($script:serviceState.Status -eq "Running") {
  Stop-Nop51BackgroundService -SuppressAutoRestart
    }
    $script:uiControls.TrayIcon.Visible = $false
  }
})

$form.add_Shown({
  Refresh-ProcessList -PreserveSelection
  $config = Read-Nop51ConfigOrDefault
  Use-Nop51IconFromConfig -Config $config
  Populate-FormFromConfig -Config $config
  Update-Nop51ServiceUi -StartButton $script:uiControls.StartButton -StatusLabel $script:uiControls.StatusLabel
  Update-Nop51ConfigStatus "Configuration loaded"
  $script:uiControls.ServiceMonitor.Start()
})

$form.add_FormClosed({
  if ($script:uiControls -and $script:uiControls.ServiceMonitor) {
    $script:uiControls.ServiceMonitor.Stop()
  }
  if ($script:uiControls -and $script:uiControls.TrayIcon) {
    try { $script:uiControls.TrayIcon.Dispose() } catch { }
  }
  if ($script:autoSaveTimer) {
    try { $script:autoSaveTimer.Stop() } catch { }
    try { $script:autoSaveTimer.Dispose() } catch { }
    $script:autoSaveTimer = $null
  }
  if ($script:customIconHandle -ne [IntPtr]::Zero) {
    [Win32.NativeMethods]::DestroyIcon($script:customIconHandle) | Out-Null
    $script:customIconHandle = [IntPtr]::Zero
  }
  if ($script:customIcon) {
    try { $script:customIcon.Dispose() } catch { }
    $script:customIcon = $null
  }
})

if ($MyInvocation.InvocationName -eq ".") {
  return
}

[System.Windows.Forms.Application]::Run($form)
