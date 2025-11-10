# Quick Start Guide

Get NO-P51 up and running in minutes!

## First-Time Setup

### 1. Prerequisites Check
```powershell
# Check PowerShell version (need 5.1+)
$PSVersionTable.PSVersion

# Check if you're on Windows 10+
[System.Environment]::OSVersion.Version
```

### 2. Audio Files Setup (REQUIRED)

The project currently has MP3 files that need to be converted to WAV format:

**Option A: Automatic (with FFmpeg)**
```powershell
.\scripts\setup-dev.ps1 -ConvertAudio
```

**Option B: Manual Conversion**
1. Download FFmpeg: https://ffmpeg.org/download.html
2. Run in `songs/` folder:
   ```powershell
   ffmpeg -i click.mp3 -acodec pcm_s16le -ar 44100 click.wav
   ffmpeg -i notif.mp3 -acodec pcm_s16le -ar 44100 notif.wav
   ```

**Option C: Online Converter**
1. Visit: https://cloudconvert.com/mp3-to-wav
2. Convert `click.mp3` and `notif.mp3`
3. Save as `click.wav` and `notif.wav` in `songs/` folder

### 3. Configuration

Edit `config.json` to set your target application:

```json
{
  "targetProcessName": "notepad.exe",
  "hideStrategy": "hide",
  "hideHotkey": "=",
  "restoreHotkey": "Ctrl+Alt+R",
  "fallback": null
}
```

**Tips:**
- Use executable name (e.g., `notepad.exe`) instead of PID
- `hideStrategy`: `"hide"` to hide window, `"terminate"` to kill process
- Leave `fallback` as `null` if you don't need a decoy action

### 4. Launch

Simply double-click:
```
NO-P51.bat
```

Or run from PowerShell:
```powershell
.\NO-P51.bat
```

## Usage

### From GUI
1. Launch `NO-P51.bat`
2. Select a process from the list (or type in target field)
3. Set your hotkeys
4. Click "Start service"
5. Minimize to tray (click arrow button) or close window

### Hotkeys
- **Default Hide**: `=` key
- **Default Restore**: `Ctrl+Alt+R`
- Customize in the GUI or `config.json`

### System Tray
- Right-click tray icon → "Open interface" or "Exit NO-P51"
- Double-click tray icon to restore window

## Common Tasks

### Change Target Application
1. Open control panel
2. Find process in list
3. Double-click to select
4. Configuration auto-saves

### Add Fallback Action
1. Open control panel
2. Go to "Fallback action" section
3. Choose "Launch app" or "Open URL"
4. Enter path or URL
5. Optional: Check "Close fallback app on restore" or "Toggle fullscreen (F11)"

### Stop Everything Quickly
- Click "Exit" button in control panel
- Or right-click tray → "Exit NO-P51"

## Verification

Run health check to ensure everything is set up correctly:
```powershell
.\scripts\health-check.ps1 -Verbose
```

## Troubleshooting

### "Audio files not found"
- Convert MP3 to WAV (see Audio Files Setup above)

### "Process not found"
- Make sure the target application is running
- Use executable name, not display name
- Check spelling (e.g., `notepad.exe` not `notepad`)

### "Hotkey doesn't work"
- Check if hotkey is already used by another application
- Try a different combination
- Avoid system hotkeys (Win+L, Ctrl+Alt+Del, etc.)

### "Permission denied" when terminating
- Use "Hide window" strategy instead of "Terminate process"
- Or run with administrator privileges (not recommended)

### "Script execution is disabled"
- Use `NO-P51.bat` launcher (bypasses ExecutionPolicy)
- Or manually: `powershell -ExecutionPolicy Bypass -File .\scripts\no-p51-gui.ps1`

## Development

### Run Tests
```powershell
# Install Pester if needed
Install-Module -Name Pester -Force

# Run tests
Invoke-Pester -Path "tests"
```

### Setup Dev Environment
```powershell
.\scripts\setup-dev.ps1 -InstallPester -ConvertAudio
```

## Need Help?

1. Check `README.md` for detailed documentation
2. Review `CONTRIBUTING.md` for development guidelines
3. Check `CHANGELOG.md` for recent changes
4. Open an issue on GitHub

## Quick Reference

| Action | Command |
|--------|---------|
| Start application | `.\NO-P51.bat` |
| Health check | `.\scripts\health-check.ps1` |
| Setup dev env | `.\scripts\setup-dev.ps1` |
| Run tests | `Invoke-Pester -Path "tests"` |
| Convert audio | `.\scripts\setup-dev.ps1 -ConvertAudio` |

---

**Ready to go!** Launch `NO-P51.bat` and start hiding applications! 🚀
