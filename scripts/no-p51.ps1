param(
  [string]$ConfigPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath "config.json" )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms

$script:ConvertFromJsonSupportsDepth = $null
$script:ConvertToJsonSupportsDepth = $null
$script:soundPlayer = $null
$script:songsPath = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath "songs"

function Play-Nop51Sound {
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("click", "notif", "error")]
    [string]$SoundType
  )

  if (-not $script:soundPlayer) {
    $script:soundPlayer = New-Object System.Media.SoundPlayer
  }

  $soundFile = switch ($SoundType) {
    "click" { "click.mp3" }
    "notif" { "notif.mp3" }
    "error" { "notif.mp3" }
    default { $null }
  }

  if (-not $soundFile) {
    return
  }

  $soundPath = Join-Path -Path $script:songsPath -ChildPath $soundFile
  if (-not (Test-Path -LiteralPath $soundPath)) {
    return
  }

  try {
    $script:soundPlayer.SoundLocation = $soundPath
    $script:soundPlayer.Play()
  } catch {
    # Silently ignore audio playback errors
  }
}

function Convert-Nop51FromJson {
  param(
    [Parameter(Mandatory = $true)][string]$Json,
    [int]$Depth = 10
  )

  if ($null -eq $script:ConvertFromJsonSupportsDepth) {
    $script:ConvertFromJsonSupportsDepth = (Get-Command ConvertFrom-Json -ErrorAction Stop).Parameters.ContainsKey('Depth')
  }

  if ($script:ConvertFromJsonSupportsDepth) {
    return $Json | ConvertFrom-Json -Depth $Depth
  }

  return $Json | ConvertFrom-Json
}

function Convert-Nop51ToJson {
  param(
    [Parameter(Mandatory = $true)]$InputObject,
    [int]$Depth = 10
  )

  if ($null -eq $script:ConvertToJsonSupportsDepth) {
    $script:ConvertToJsonSupportsDepth = (Get-Command ConvertTo-Json -ErrorAction Stop).Parameters.ContainsKey('Depth')
  }

  if ($script:ConvertToJsonSupportsDepth) {
    return $InputObject | ConvertTo-Json -Depth $Depth
  }

  return $InputObject | ConvertTo-Json
}

function Write-Nop51Log {
  param(
    [string]$Message,
    [string]$Level = "INFO"
  )

  $timestamp = (Get-Date).ToString("HH:mm:ss")
  $label = $Level.ToUpperInvariant()
  Write-Host "[$timestamp] [$label] $Message"
}

function Test-Nop51IsElevated {
  try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $identity) {
      return $false
    }
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
  } catch {
    return $false
  }
}

function Read-Nop51Config {
  param(
    [Parameter(Mandatory = $true)][string]$Path
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Configuration file not found at '$Path'."
  }

  $rawContent = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
  if ([string]::IsNullOrWhiteSpace($rawContent)) {
    throw "Configuration file at '$Path' is empty."
  }

  try {
    return Convert-Nop51FromJson -Json $rawContent -Depth 10
  } catch {
    throw "Configuration file at '$Path' is not valid JSON: $($_.Exception.Message)"
  }
}

function Assert-Nop51Config {
  param(
    [Parameter(Mandatory = $true)][psobject]$Config
  )

  if (-not $Config.targetProcessName -or [string]::IsNullOrWhiteSpace($Config.targetProcessName)) {
    throw "The 'targetProcessName' property is required."
  }

  if (-not $Config.hideHotkey -or [string]::IsNullOrWhiteSpace($Config.hideHotkey)) {
    throw "The 'hideHotkey' property is required."
  }

  if (-not $Config.restoreHotkey -or [string]::IsNullOrWhiteSpace($Config.restoreHotkey)) {
    throw "The 'restoreHotkey' property is required."
  }

  if ($Config.hideHotkey -eq $Config.restoreHotkey) {
    throw "Hide and restore hotkeys must be different."
  }

  $hideStrategy = "hide"
  if ($Config.PSObject.Properties.Name -contains "hideStrategy" -and $Config.hideStrategy) {
    $hideStrategy = $Config.hideStrategy.ToString().ToLowerInvariant()
  }

  $validStrategies = @("hide", "terminate")
  if (-not ($validStrategies -contains $hideStrategy)) {
    throw "Unsupported hideStrategy '$hideStrategy'. Use 'hide' or 'terminate'."
  }

  if ($Config.PSObject.Properties.Name -contains "hideStrategy") {
    $Config.hideStrategy = $hideStrategy
  } else {
    $Config | Add-Member -NotePropertyName "hideStrategy" -NotePropertyValue $hideStrategy
  }

  $hasFallbackProperty = $Config.PSObject.Properties.Name -contains "fallback"
  if ($hasFallbackProperty -and $Config.fallback) {
    if (-not $Config.fallback.mode -or [string]::IsNullOrWhiteSpace($Config.fallback.mode)) {
      throw "The fallback 'mode' property is required when fallback is defined."
    }

    if (-not $Config.fallback.value -or [string]::IsNullOrWhiteSpace($Config.fallback.value)) {
      throw "The fallback 'value' property is required when fallback is defined."
    }

    $validModes = @("app", "url")
    $modeValue = $Config.fallback.mode.ToString().ToLowerInvariant()
    if (-not ($validModes -contains $modeValue)) {
      throw "Unsupported fallback mode '$($Config.fallback.mode)'. Use 'app' or 'url'."
    }

    if ($modeValue -eq "url") {
      try {
        $null = [Uri]::new($Config.fallback.value)
      } catch {
        throw "Fallback value '$($Config.fallback.value)' is not a valid URL."
      }
    }

    if ($Config.fallback.PSObject.Properties.Name -contains "fullscreen") {
      $Config.fallback.fullscreen = [bool]$Config.fallback.fullscreen
    }
  }
}

function Convert-Nop51HotKey {
  param(
    [Parameter(Mandatory = $true)][string]$HotKeyString
  )

  if ([string]::IsNullOrWhiteSpace($HotKeyString)) {
    throw "Hotkey string cannot be empty."
  }

  $parts = @($HotKeyString.Split("+") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  if ($parts.Count -lt 1) {
    throw "Hotkey string '$HotKeyString' is invalid."
  }

  $rawKeyToken = $parts[-1]
  $keyToken = $rawKeyToken.ToUpperInvariant()
  $modifierTokens = if ($parts.Count -gt 1) { $parts[0..($parts.Count - 2)] } else { @() }

  $modifierMap = @{
    "CTRL" = 0x0002
    "CONTROL" = 0x0002
    "ALT" = 0x0001
    "SHIFT" = 0x0004
    "WIN" = 0x0008
    "WINDOWS" = 0x0008
    "LWIN" = 0x0008
    "RWIN" = 0x0008
  }

  $modifiersValue = [uint32]0
  foreach ($modifier in $modifierTokens) {
    if ([string]::IsNullOrWhiteSpace($modifier)) {
      continue
    }

    $token = $modifier.ToUpperInvariant()
    if (-not $modifierMap.ContainsKey($token)) {
      throw "Unsupported modifier '$modifier' in hotkey '$HotKeyString'."
    }

    $modifiersValue = $modifiersValue -bor [uint32]$modifierMap[$token]
  }

  $specialKeyMap = @{
    "=" = "Oemplus"
    "+" = "Oemplus"
    "-" = "OemMinus"
    "_" = "OemMinus"
    "," = "Oemcomma"
    "." = "OemPeriod"
    ";" = "OemSemicolon"
    ":" = "Oem1"
    "/" = "OemQuestion"
    "?" = "OemQuestion"
  }

  $keyValue = $null
  $displayKeyToken = $rawKeyToken
  $parseToken = $keyToken

  if ($specialKeyMap.ContainsKey($rawKeyToken)) {
    $parseToken = $specialKeyMap[$rawKeyToken]
  } elseif ($specialKeyMap.ContainsKey($keyToken)) {
    $parseToken = $specialKeyMap[$keyToken]
  }

  if ($parseToken.Length -eq 1 -and [char]::IsDigit($parseToken, 0)) {
    $keyAlias = "D" + $parseToken
    $keyValue = [System.Enum]::Parse([System.Windows.Forms.Keys], $keyAlias, $true)
  } else {
    try {
      $keyValue = [System.Enum]::Parse([System.Windows.Forms.Keys], $parseToken, $true)
    } catch {
      if ($parseToken.Length -eq 1) {
        $keyValue = [System.Enum]::Parse([System.Windows.Forms.Keys], $parseToken, $true)
      } else {
        throw "Unsupported key '$rawKeyToken' in hotkey '$HotKeyString'."
      }
    }
  }

  if (-not [Enum]::IsDefined([System.Windows.Forms.Keys], $keyValue)) {
    throw "Unsupported key '$rawKeyToken' in hotkey '$HotKeyString'."
  }

  $normalizedTokens = @()
  foreach ($modifier in $modifierTokens) {
    if (-not [string]::IsNullOrWhiteSpace($modifier)) {
      $normalizedTokens += $modifier.ToUpperInvariant()
    }
  }
  if ([string]::IsNullOrWhiteSpace($displayKeyToken)) {
    $displayKeyToken = $rawKeyToken
  }

  if ($displayKeyToken.Length -eq 1 -and [char]::IsLetter($displayKeyToken, 0)) {
    $displayKeyToken = $displayKeyToken.ToUpperInvariant()
  } elseif ($displayKeyToken.Length -gt 1 -and $displayKeyToken -ne "=") {
    $displayKeyToken = $displayKeyToken.ToUpperInvariant()
  }

  $normalizedTokens += $displayKeyToken

  [pscustomobject]@{
    Modifiers = [uint32]$modifiersValue
    Key = [System.Windows.Forms.Keys]$keyValue
    Display = ($normalizedTokens -join "+")
  }
}

function Resolve-Nop51Target {
  param(
    [Parameter(Mandatory = $true)][string]$ProcessIdentifier,
    [switch]$IsPid
  )

  if ($IsPid) {
    $pidValue = 0
    if (-not [int]::TryParse($ProcessIdentifier, [ref]$pidValue)) {
      return $null
    }

    try {
      $process = Get-Process -Id $pidValue -ErrorAction Stop
    } catch {
      return $null
    }

    $handle = [Nop51.Interop.WindowInterop]::FindMainWindow($process.Id)
    if ($handle -eq [IntPtr]::Zero) {
      return $null
    }

    return [pscustomobject]@{
      Process = $process
      Handle = $handle
    }
  }

  $nameWithoutExtension = [System.IO.Path]::GetFileNameWithoutExtension($ProcessIdentifier)
  $candidateProcesses = Get-Process -Name $nameWithoutExtension -ErrorAction SilentlyContinue | Sort-Object -Property StartTime -Descending

  foreach ($process in $candidateProcesses) {
    $handle = [Nop51.Interop.WindowInterop]::FindMainWindow($process.Id)
    if ($handle -ne [IntPtr]::Zero) {
      return [pscustomobject]@{
        Process = $process
        Handle = $handle
      }
    }
  }

  return $null
}

function Get-Nop51TargetDisplay {
  param(
    [Parameter(Mandatory = $true)][pscustomobject]$State
  )

  if ($State.TargetDisplayName) {
    return $State.TargetDisplayName
  }

  if ($State.TargetIsPid) {
    return "PID $($State.TargetProcessName)"
  }

  return "'$($State.TargetProcessName)'"
}

function Hide-Nop51Target {
  param(
    [Parameter(Mandatory = $true)][System.IntPtr]$Handle
  )

  return [Nop51.Interop.WindowInterop]::HideWindow($Handle)
}

function Restore-Nop51Target {
  param(
    [Parameter(Mandatory = $true)][System.IntPtr]$Handle
  )

  return [Nop51.Interop.WindowInterop]::RestoreWindow($Handle)
}

function Invoke-Nop51FallbackAction {
  param(
    [Parameter(Mandatory = $true)][pscustomobject]$State
  )

  if (-not $State.Fallback) {
    return $null
  }

  $mode = $State.Fallback.mode.ToString().ToLowerInvariant()
  $value = $State.Fallback.value.ToString()
  $fullscreen = $false
  if ($State.Fallback.PSObject.Properties.Name -contains "fullscreen") {
    $fullscreen = [bool]$State.Fallback.fullscreen
  }

  switch ($mode) {
    "app" {
      try {
        Write-Nop51Log "Launching fallback application '$value'."
        $process = Start-Process -FilePath $value -PassThru
        if ($fullscreen -and $process) {
          Invoke-Nop51FallbackFullscreen -Process $process
        }
        return $process
      } catch {
        Write-Nop51Log "Failed to launch fallback application '$value': $($_.Exception.Message)" "WARN"
        return $null
      }
    }
    "url" {
      try {
        Write-Nop51Log "Opening fallback URL '$value'."
        $browserProcess = Start-Process -FilePath $value -PassThru
        if ($fullscreen -and $browserProcess) {
          Invoke-Nop51FallbackFullscreen -Process $browserProcess
        }
      } catch {
        Write-Nop51Log "Failed to open fallback URL '$value': $($_.Exception.Message)" "WARN"
      }
      return $null
    }
    default {
      Write-Nop51Log "Unknown fallback mode '$mode'." "WARN"
      return $null
    }
  }
}

function Invoke-Nop51FallbackFullscreen {
  param(
    [Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process,
    [int]$TimeoutMilliseconds = 4000
  )

  if (-not $Process -or $Process.HasExited) {
    return
  }

  try {
    try {
      $null = $Process.WaitForInputIdle(1000)
    } catch {
      # Some processes do not support WaitForInputIdle; ignore
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $handle = [IntPtr]::Zero

    while ($stopwatch.ElapsedMilliseconds -lt $TimeoutMilliseconds) {
      if ($Process.HasExited) {
        return
      }

      $handle = [Nop51.Interop.WindowInterop]::FindMainWindow($Process.Id)
      if ($handle -ne [IntPtr]::Zero) {
        break
      }

      Start-Sleep -Milliseconds 120
    }

    if ($handle -eq [IntPtr]::Zero) {
      return
    }

    [Nop51.Interop.WindowInterop]::SendF11ToWindow($handle)
  } catch {
    Write-Nop51Log "Failed to toggle fullscreen for fallback (PID $($Process.Id)): $($_.Exception.Message)" "WARN"
  }
}

function Stop-Nop51Fallback {
  param(
    [Parameter(Mandatory = $true)][pscustomobject]$State
  )

  if (-not $State.FallbackProcess) {
    return
  }

  if ($State.FallbackProcess.HasExited) {
    $State.FallbackProcess = $null
    return
  }

  Write-Nop51Log "Closing fallback process (PID $($State.FallbackProcess.Id))."
  try {
    $null = $State.FallbackProcess.CloseMainWindow()
    Start-Sleep -Milliseconds 400
    if (-not $State.FallbackProcess.HasExited) {
      $State.FallbackProcess.Kill()
    }
  } catch {
    Write-Nop51Log "Failed to close fallback process: $($_.Exception.Message)" "WARN"
  }
  $State.FallbackProcess = $null
}

function Test-Nop51TypeExists {
  param(
    [Parameter(Mandatory = $true)][string]$TypeName
  )

  foreach ($assembly in [AppDomain]::CurrentDomain.GetAssemblies()) {
    if ($assembly.GetType($TypeName, $false)) {
      return $true
    }
  }

  return $false
}

function Ensure-Nop51InteropTypes {
  if (-not (Test-Nop51TypeExists -TypeName "Nop51.Interop.HotKeyWindow")) {
    $hotKeyManagerCode = @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Nop51.Interop
{
  public class HotKeyEventArgs : EventArgs
  {
    public int Id { get; private set; }

    public HotKeyEventArgs(int id)
    {
      Id = id;
    }
  }

  public class HotKeyWindow : Form
  {
    private const int WM_HOTKEY = 0x0312;
    private readonly HashSet<int> _registeredIds = new HashSet<int>();

    public event EventHandler<HotKeyEventArgs> HotKeyPressed;

    public HotKeyWindow()
    {
      ShowInTaskbar = false;
      FormBorderStyle = FormBorderStyle.FixedToolWindow;
      WindowState = FormWindowState.Minimized;
      Load += (sender, args) =>
      {
        Visible = false;
        Opacity = 0;
      };
    }

    protected override void SetVisibleCore(bool value)
    {
      base.SetVisibleCore(false);
    }

    public bool RegisterHotKey(int id, uint modifiers, Keys key)
    {
      if (_registeredIds.Contains(id))
      {
        UnregisterHotKey(Handle, id);
        _registeredIds.Remove(id);
      }

      bool result = RegisterHotKey(Handle, id, modifiers, (uint)key);
      if (result)
      {
        _registeredIds.Add(id);
      }
      return result;
    }

    public void UnregisterAllHotKeys()
    {
      foreach (var id in _registeredIds)
      {
        UnregisterHotKey(Handle, id);
      }
      _registeredIds.Clear();
    }

    protected override void OnHandleDestroyed(EventArgs e)
    {
      UnregisterAllHotKeys();
      base.OnHandleDestroyed(e);
    }

    protected override void WndProc(ref Message m)
    {
      if (m.Msg == WM_HOTKEY)
      {
        int id = m.WParam.ToInt32();
        var handler = HotKeyPressed;
        if (handler != null)
        {
          handler(this, new HotKeyEventArgs(id));
        }
      }
      base.WndProc(ref m);
    }

    [DllImport("user32.dll")]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);
  }
}
"@

    Add-Type -TypeDefinition $hotKeyManagerCode -Language CSharp -ReferencedAssemblies System.Windows.Forms
  }

  if (-not (Test-Nop51TypeExists -TypeName "Nop51.Interop.WindowInterop")) {
    $windowInteropCode = @"
using System;
using System.Runtime.InteropServices;

namespace Nop51.Interop
{
  public static class WindowInterop
  {
    private const uint GW_OWNER = 4;
    private const int SW_HIDE = 0;
    private const int SW_RESTORE = 9;
    private const byte VK_F11 = 0x7A;
    private const uint KEYEVENTF_KEYUP = 0x0002;

    public static IntPtr FindMainWindow(int processId)
    {
      IntPtr result = IntPtr.Zero;
      EnumWindows((hWnd, lParam) =>
      {
        if (!IsWindow(hWnd))
        {
          return true;
        }

        int windowProcessId = 0;
        GetWindowThreadProcessId(hWnd, out windowProcessId);
        if (windowProcessId != processId)
        {
          return true;
        }

        if (GetWindow(hWnd, GW_OWNER) != IntPtr.Zero)
        {
          return true;
        }

        result = hWnd;
        return false;
      }, IntPtr.Zero);

      return result;
    }

    public static bool HideWindow(IntPtr hWnd)
    {
      return ShowWindow(hWnd, SW_HIDE);
    }

    public static bool RestoreWindow(IntPtr hWnd)
    {
      ShowWindow(hWnd, SW_RESTORE);
      return SetForegroundWindow(hWnd);
    }

    public static bool IsValidHandle(IntPtr hWnd)
    {
      return IsWindow(hWnd);
    }

    public static void SendKeyToWindow(IntPtr hWnd, byte virtualKey)
    {
      if (hWnd == IntPtr.Zero)
      {
        return;
      }

      SetForegroundWindow(hWnd);
      keybd_event(virtualKey, 0, 0, UIntPtr.Zero);
      keybd_event(virtualKey, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    }

    public static void SendF11ToWindow(IntPtr hWnd)
    {
      SendKeyToWindow(hWnd, VK_F11);
    }

    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out int processId);

    [DllImport("user32.dll")]
    private static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
  }
}
"@

    Add-Type -TypeDefinition $windowInteropCode -Language CSharp
  }
}

function Invoke-Nop51Hide {
  param(
    [Parameter(Mandatory = $true)][pscustomobject]$State
  )

  $resolved = Resolve-Nop51Target -ProcessIdentifier $State.TargetProcessName -IsPid:$State.TargetIsPid
  if (-not $resolved) {
    Write-Nop51Log "No visible window found for $(Get-Nop51TargetDisplay -State $State)." "WARN"
    return
  }

  $fallbackProcess = Invoke-Nop51FallbackAction -State $State
  if ($fallbackProcess) {
    $State.FallbackProcess = $fallbackProcess
  }

  $State.LastHandle = $resolved.Handle
  $State.LastProcessId = $resolved.Process.Id
  if ($State.TargetIsPid -and -not $State.TargetPid) {
    $State.TargetPid = $resolved.Process.Id
  }

  switch ($State.HideStrategy) {
    "terminate" {
      try {
        Write-Nop51Log "Terminating '$($resolved.Process.ProcessName)' (PID $($resolved.Process.Id))."
        Stop-Process -Id $resolved.Process.Id -Force -ErrorAction Stop
        $State.LastHandle = [IntPtr]::Zero
        Play-Nop51Sound -SoundType "click"
      } catch {
        Write-Nop51Log "Failed to terminate process '$($resolved.Process.ProcessName)': $($_.Exception.Message)" "WARN"
        Play-Nop51Sound -SoundType "error"
      }
    }
    default {
      if (Hide-Nop51Target -Handle $resolved.Handle) {
        Write-Nop51Log "Hidden '$($resolved.Process.ProcessName)' (PID $($resolved.Process.Id))."
        Play-Nop51Sound -SoundType "click"
      } else {
        Write-Nop51Log "Failed to hide window for '$($resolved.Process.ProcessName)'." "WARN"
        Play-Nop51Sound -SoundType "error"
      }
    }
  }
}

function Invoke-Nop51Restore {
  param(
    [Parameter(Mandatory = $true)][pscustomobject]$State
  )

  $handle = $State.LastHandle
  if ($State.HideStrategy -eq "terminate") {
    Write-Nop51Log "Restore ignored: terminate strategy cannot re-open the target." "WARN"
    if ($State.Fallback -and $State.Fallback.autoClose -and $State.FallbackProcess) {
      Stop-Nop51Fallback -State $State
    }
    return
  }

  if (-not $handle -or -not [Nop51.Interop.WindowInterop]::IsValidHandle($handle)) {
    $resolved = Resolve-Nop51Target -ProcessIdentifier $State.TargetProcessName -IsPid:$State.TargetIsPid
    if (-not $resolved) {
      Write-Nop51Log "Unable to locate the target window to restore for $(Get-Nop51TargetDisplay -State $State)." "WARN"
      return
    }
    $handle = $resolved.Handle
    $State.LastHandle = $handle
    $State.LastProcessId = $resolved.Process.Id
    if ($State.TargetIsPid -and -not $State.TargetPid) {
      $State.TargetPid = $resolved.Process.Id
    }
  }

  if (Restore-Nop51Target -Handle $handle) {
    Write-Nop51Log "Restored target window."
    Play-Nop51Sound -SoundType "notif"
  } else {
    Write-Nop51Log "Failed to restore target window." "WARN"
    Play-Nop51Sound -SoundType "error"
  }

  if ($State.Fallback -and $State.Fallback.autoClose -and $State.FallbackProcess) {
    Stop-Nop51Fallback -State $State
  }
}

function Start-NOP51 {
  param(
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [System.Threading.CancellationToken]$CancellationToken = $null
  )

  Write-Nop51Log "Loading configuration from '$ConfigPath'."
  $config = Read-Nop51Config -Path $ConfigPath
  Assert-Nop51Config -Config $config

  Ensure-Nop51InteropTypes

  $hideHotKey = Convert-Nop51HotKey -HotKeyString $config.hideHotkey
  $restoreHotKey = Convert-Nop51HotKey -HotKeyString $config.restoreHotkey

  $targetPidValue = 0
  $targetIsPid = [int]::TryParse($config.targetProcessName, [ref]$targetPidValue)
  $hideStrategy = if ($config.hideStrategy) { $config.hideStrategy.ToString().ToLowerInvariant() } else { "hide" }

  $state = [pscustomobject]@{
    TargetProcessName = $config.targetProcessName
    TargetIsPid = $targetIsPid
    TargetPid = if ($targetIsPid) { $targetPidValue } else { $null }
    HideStrategy = $hideStrategy
  TargetDisplayName = if ($targetIsPid) { "PID $targetPidValue" } else { "'$($config.targetProcessName)'" }
    Fallback = if ($config.fallback) { $config.fallback } else { $null }
    FallbackProcess = $null
    LastHandle = [IntPtr]::Zero
    LastProcessId = $null
  }

  $hotKeyWindow = [Nop51.Interop.HotKeyWindow]::new()
  $cancellationRegistration = $null
  if ($CancellationToken -and $CancellationToken.CanBeCanceled) {
    $exitAction = [System.Action]{
      try {
        if ($hotKeyWindow -and -not $hotKeyWindow.IsDisposed) {
          $null = $hotKeyWindow.BeginInvoke([System.Action]{ [System.Windows.Forms.Application]::ExitThread() })
        } else {
          [System.Windows.Forms.Application]::ExitThread()
        }
      } catch {
        # Swallow cancellation errors
      }
    }
    $cancellationRegistration = $CancellationToken.Register($exitAction)
  } elseif ($CancellationToken) {
    throw "Provided cancellation token cannot be canceled."
  }

  if (-not $hotKeyWindow.RegisterHotKey(1, $hideHotKey.Modifiers, $hideHotKey.Key)) {
    throw "Failed to register hide hotkey '$($hideHotKey.Display)'."
  }
  if (-not $hotKeyWindow.RegisterHotKey(2, $restoreHotKey.Modifiers, $restoreHotKey.Key)) {
    throw "Failed to register restore hotkey '$($restoreHotKey.Display)'."
  }

  Write-Nop51Log "Hide hotkey: $($hideHotKey.Display)."
  Write-Nop51Log "Restore hotkey: $($restoreHotKey.Display)."
  Write-Nop51Log "Press Ctrl+C in this window to exit."

  $hotKeyWindow.add_HotKeyPressed({
    param($sender, $eventArgs)
    switch ($eventArgs.Id) {
      1 { Invoke-Nop51Hide -State $state }
      2 { Invoke-Nop51Restore -State $state }
      default { Write-Nop51Log "Received unexpected hotkey id $($eventArgs.Id)." "WARN" }
    }
  })

  try {
    [System.Windows.Forms.Application]::Run($hotKeyWindow)
  } finally {
    if ($cancellationRegistration) {
      $cancellationRegistration.Dispose()
    }
    if ($state.FallbackProcess) {
      Stop-Nop51Fallback -State $state
    }
    $hotKeyWindow.UnregisterAllHotKeys()
    $hotKeyWindow.Dispose()
    Write-Nop51Log "NO-P51 stopped."
  }
}

if ($MyInvocation.InvocationName -eq ".") {
  return
}

Start-NOP51 -ConfigPath $ConfigPath
