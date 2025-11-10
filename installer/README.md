# NO-P51 Installer

Professional installer for NO-P51 that downloads and installs the latest version from GitHub.

## Quick Start

Download and run **`setup.bat`** - One file for everything!

```batch
setup.bat
```

**Features:**
- ✅ Interactive menu (Install / Uninstall / Repair)
- ✅ Automatic download from GitHub
- ✅ Preserves configuration during upgrades
- ✅ Creates shortcuts with custom icon (`logo.ico`)
- ✅ Clean uninstallation
- ✅ Single file - easy to distribute

## Usage

Simply run `setup.bat` and choose from the menu:

```
1. Install NO-P51      - Download and install from GitHub
2. Uninstall NO-P51    - Complete removal
3. Repair/Reinstall    - Update or fix installation
4. Exit                - Close the installer
```

## Features

- ✅ Downloads latest version from GitHub automatically
- ✅ Installs to proper system directories
- ✅ Creates desktop shortcut with custom icon (`logo.ico`)
- ✅ Creates Start Menu shortcut
- ✅ Supports both admin and non-admin installations
- ✅ Preserves configuration during upgrades
- ✅ Clean uninstallation
- ✅ Repair/Reinstall option

### With Administrator Privileges
- Installation: `C:\Program Files\NO-P51\`
- Shortcuts: Desktop + Start Menu (All Users)

### Without Administrator Privileges
- Installation: `%LOCALAPPDATA%\NO-P51\`
- Shortcuts: Desktop + Start Menu (Current User)

## What Gets Installed

```
NO-P51/
├── NO-P51.bat           # Main launcher
├── config.json          # Configuration file
├── logo.ico             # Application icon
├── scripts/             # PowerShell scripts
├── songs/               # Audio files
├── tests/               # Unit tests
└── ...                  # Documentation files
```

## Shortcuts Created

### Desktop Shortcut
- Name: `NO-P51.lnk`
- Icon: Custom NO-P51 icon (`logo.ico`)
- Description: "Hide applications with global hotkeys"

### Start Menu Shortcut
- Location: Programs folder
- Same properties as desktop shortcut

## Uninstallation

### Method 1: Using Uninstaller

```batch
# Navigate to installation directory and run
uninstall.bat
```

### Method 2: Manual Removal

1. Delete installation directory:
   - `C:\Program Files\NO-P51\` (admin install)
   - `%LOCALAPPDATA%\NO-P51\` (user install)

2. Delete shortcuts:
   - `%USERPROFILE%\Desktop\NO-P51.lnk`
   - Start Menu shortcuts

## Upgrading

To upgrade to a new version:

1. Run `install.bat` again
2. The installer will automatically remove the old version
3. Fresh installation of the latest version

Or use the built-in auto-update feature in NO-P51.

## Troubleshooting

### Download Fails
- Check internet connection
- Verify GitHub is accessible
- Try running as administrator

### Installation Fails
- Close any running NO-P51 instances
- Check disk space
- Verify write permissions

### Shortcut Missing Icon
- Ensure `logo.ico` exists in installation directory
- Recreate shortcut manually if needed

## Advanced Options

### Silent Installation (Future)
```batch
install.bat /S
```

### Custom Installation Directory (Future)
```batch
install.bat /D=C:\CustomPath\NO-P51
```

## For Developers

### Building Installer Package

To prepare installer for release:

1. Ensure `logo.ico` exists in project root
2. Copy `install.bat` to release artifacts
3. Users download and run `install.bat` directly

### Installer Process

1. **Download**: Fetches latest code from GitHub main branch
2. **Extract**: Unzips to temporary directory
3. **Install**: Copies files to installation directory
4. **Configure**: Creates shortcuts with custom icon
5. **Cleanup**: Removes temporary files
6. **Launch**: Optionally starts NO-P51

### Technical Details

- Uses PowerShell for downloads (TLS 1.2 support)
- ZIP extraction via .NET Framework
- COM automation for shortcut creation
- Graceful handling of permissions
- Proper cleanup on failure

## Security Notes

- Installer downloads from official GitHub repository only
- No external dependencies or downloads
- Source code fully visible in `.bat` files
- Can be reviewed before running

## License

Same as NO-P51 project - MIT License
