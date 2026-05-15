#Requires -Version 5.1

BeforeAll {
    Import-Module "$PSScriptRoot/../src/core/config.psm1"  -Force
    Import-Module "$PSScriptRoot/../src/core/hotkeys.psm1" -Force
}

Describe 'hotkeys: Convert-ModifiersToFlags' {
    It 'Control+Shift = MOD_CONTROL|MOD_SHIFT = 6' {
        Convert-ModifiersToFlags -Modifiers @('Control', 'Shift') | Should -Be 6
    }
    It 'Alt+Win = MOD_ALT|MOD_WIN = 9' {
        Convert-ModifiersToFlags -Modifiers @('Alt', 'Win') | Should -Be 9
    }
    It 'akzeptiert Aliase (Ctrl=Control, Windows=Win)' {
        Convert-ModifiersToFlags -Modifiers @('Ctrl', 'Windows') | Should -Be 10
    }
    It 'leere Liste = 0' {
        Convert-ModifiersToFlags -Modifiers @() | Should -Be 0
    }
    It 'unbekannte Modifier werden ignoriert' {
        Convert-ModifiersToFlags -Modifiers @('Hyper', 'Shift') | Should -Be 4
    }
}

Describe 'hotkeys: Convert-KeyNameToVirtualKey' {
    It 'D1 = 49 (0x31)' {
        Convert-KeyNameToVirtualKey 'D1' | Should -Be 49
    }
    It 'D0 = 48 (0x30)' {
        Convert-KeyNameToVirtualKey 'D0' | Should -Be 48
    }
    It 'F4 = 115 (0x73)' {
        Convert-KeyNameToVirtualKey 'F4' | Should -Be 115
    }
    It 'A = 65 (0x41)' {
        Convert-KeyNameToVirtualKey 'A' | Should -Be 65
    }
    It 'unbekannte Taste = 0' {
        Convert-KeyNameToVirtualKey 'NotARealKey' | Should -Be 0
    }
    It 'gross-/kleinschreibung egal' {
        Convert-KeyNameToVirtualKey 'd1' | Should -Be 49
    }
}

Describe 'hotkeys: Register/Unregister' {
    # Hinweis: RegisterHotKey mit hWnd=NULL ist KEIN Fehlerfall -- Windows
    # registriert dann einen Thread-Hotkey, der ueber die Message-Queue des
    # aktuellen Threads ankommt. Wir nutzen das hier als billige Test-Bindung
    # und raeumen am Ende immer auf.

    BeforeEach {
        Unregister-AllHotkeys -Hwnd ([IntPtr]::Zero)
    }
    AfterEach {
        Unregister-AllHotkeys -Hwnd ([IntPtr]::Zero)
    }

    It 'meldet Conflict bei unbekannter Taste' {
        $map = @{ X = @{ Modifiers = @('Control'); Key = 'NotARealKey' } }
        $r = Register-AllHotkeys -Hwnd ([IntPtr]::Zero) -HotkeyMap $map -Callbacks @{}
        $r.Registered.Count | Should -Be 0
        $r.Conflicts.Count  | Should -Be 1
        $r.Conflicts[0].Reason | Should -Match 'Unbekannt'
    }

    It 'ueberspringt Hotkeys ohne Key' {
        $map = @{ Empty = @{ Modifiers = @('Control'); Key = '' } }
        $r = Register-AllHotkeys -Hwnd ([IntPtr]::Zero) -HotkeyMap $map -Callbacks @{}
        $r.Registered.Count | Should -Be 0
        $r.Conflicts.Count  | Should -Be 0
    }

    It 'registriert eine vollstaendige Default-Map mit Thread-HWND' {
        $defaults = (Get-DefaultConfig).Hotkeys
        $r = Register-AllHotkeys -Hwnd ([IntPtr]::Zero) -HotkeyMap $defaults -Callbacks @{}
        $r.Registered.Count | Should -Be $defaults.Count
        # IDs sind eindeutig
        @($r.Registered | ForEach-Object { $_.Id } | Sort-Object -Unique).Count | Should -Be $defaults.Count
    }

    It 'Unregister-AllHotkeys leert die Registry' {
        $r = Register-AllHotkeys -Hwnd ([IntPtr]::Zero) -HotkeyMap (Get-DefaultConfig).Hotkeys -Callbacks @{}
        $r.Registered.Count | Should -BeGreaterThan 0
        Unregister-AllHotkeys -Hwnd ([IntPtr]::Zero)
        (Get-RegisteredHotkeys).Count | Should -Be 0
    }
}

Describe 'hotkeys: Invoke-HotkeyById' {
    BeforeEach {
        Unregister-AllHotkeys -Hwnd ([IntPtr]::Zero)
    }

    It 'unbekannte ID -> kein Fehler, kein Callback' {
        { Invoke-HotkeyById -Id 9999 } | Should -Not -Throw
    }
}
