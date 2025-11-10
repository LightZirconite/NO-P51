Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot "scripts\no-p51.ps1")

Describe "Convert-Nop51HotKey" {
  It "parses ctrl+alt+h" {
    $result = Convert-Nop51HotKey -HotKeyString "Ctrl+Alt+H"
    $result.Modifiers | Should Be ([uint32]0x0003)
    $result.Key | Should Be ([System.Windows.Forms.Keys]::H)
    $result.Display | Should Be "CTRL+ALT+H"
  }
}

  It "parses digit keys" {
    $result = Convert-Nop51HotKey -HotKeyString "Win+2"
    $result.Modifiers | Should Be ([uint32]0x0008)
    $result.Key | Should Be ([System.Windows.Forms.Keys]::D2)
  }

  It "parses equals key" {
    $result = Convert-Nop51HotKey -HotKeyString "="
    $result.Modifiers | Should Be ([uint32]0)
    $result.Key | Should Be ([System.Windows.Forms.Keys]::Oemplus)
    $result.Display | Should Be "="
  }

  It "throws on unknown modifier" {
    { Convert-Nop51HotKey -HotKeyString "Foo+Bar" } | Should Throw
  }
}

Describe "Assert-Nop51Config" {
  It "accepts a valid configuration" {
    $config = [pscustomobject]@{
      targetProcessName = "notepad.exe"
      hideStrategy = "hide"
      hideHotkey = "Ctrl+Alt+H"
      restoreHotkey = "Ctrl+Alt+R"
      fallback = [pscustomobject]@{
        mode = "url"
        value = "https://example.com"
        autoClose = $false
      }
    }

  { Assert-Nop51Config -Config $config } | Should Not Throw
    $config.hideStrategy | Should Be "hide"
  }

  It "defaults hideStrategy when missing" {
    $config = [pscustomobject]@{
      targetProcessName = "notepad.exe"
      hideHotkey = "Ctrl+Alt+H"
      restoreHotkey = "Ctrl+Alt+R"
    }

    { Assert-Nop51Config -Config $config } | Should Not Throw
    $config.hideStrategy | Should Be "hide"
  }

  It "accepts fallback fullscreen flag" {
    $config = [pscustomobject]@{
      targetProcessName = "notepad.exe"
      hideHotkey = "Ctrl+Alt+H"
      restoreHotkey = "Ctrl+Alt+R"
      fallback = [pscustomobject]@{
        mode = "app"
        value = "notepad.exe"
        autoClose = $true
        fullscreen = 1
      }
    }

    { Assert-Nop51Config -Config $config } | Should Not Throw
    $config.fallback.fullscreen | Should Be $true
  }

  It "rejects identical hotkeys" {
    $config = [pscustomobject]@{
      targetProcessName = "calc.exe"
      hideHotkey = "Ctrl+Alt+H"
      restoreHotkey = "Ctrl+Alt+H"
    }

  { Assert-Nop51Config -Config $config } | Should Throw
  }

  It "rejects invalid fallback url" {
    $config = [pscustomobject]@{
      targetProcessName = "calc.exe"
      hideHotkey = "Ctrl+Alt+H"
      restoreHotkey = "Ctrl+Alt+R"
      fallback = [pscustomobject]@{
        mode = "url"
        value = "invalid url"
      }
    }

  { Assert-Nop51Config -Config $config } | Should Throw
  }

  It "rejects an unknown hideStrategy" {
    $config = [pscustomobject]@{
      targetProcessName = "calc.exe"
      hideHotkey = "Ctrl+Alt+H"
      restoreHotkey = "Ctrl+Alt+R"
      hideStrategy = "minimize"
    }

    { Assert-Nop51Config -Config $config } | Should Throw
  }
}
