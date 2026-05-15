#Requires -Version 5.1

BeforeAll {
    Import-Module "$PSScriptRoot/../src/core/config.psm1" -Force
}

Describe 'config: defaults' {
    It 'Get-DefaultConfig liefert ein Hashtable mit Pflicht-Keys' {
        $d = Get-DefaultConfig
        $d              | Should -BeOfType [hashtable]
        $d.SchemaVersion | Should -BeGreaterOrEqual 1
        $d.OutputDir    | Should -Not -BeNullOrEmpty
        $d.DelaySeconds | Should -BeOfType [int]
        $d.FileNameFormat | Should -Match '\{mode\}'
        $d.Hotkeys      | Should -BeOfType [hashtable]
        $d.Hotkeys.Keys | Should -Contain 'Region'
        $d.Hotkeys.Keys | Should -Contain 'ActiveWindow'
        $d.Hotkeys.Keys | Should -Contain 'Monitor'
        $d.Hotkeys.Keys | Should -Contain 'AllMonitors'
        $d.Hotkeys.Keys | Should -Contain 'TrayMenu'
    }

    It 'Default-Hotkey "Region" ist Ctrl+Shift+D1' {
        $d = Get-DefaultConfig
        $d.Hotkeys.Region.Modifiers | Should -Contain 'Control'
        $d.Hotkeys.Region.Modifiers | Should -Contain 'Shift'
        $d.Hotkeys.Region.Key       | Should -Be 'D1'
    }

    It 'Get-ConfigPath liegt unter %APPDATA%/LucentScreen' {
        $p = Get-ConfigPath
        $p | Should -Match 'LucentScreen[\\\/]config\.json$'
    }
}

Describe 'config: load' {
    BeforeEach {
        $script:CfgFile = Join-Path $TestDrive ("cfg_" + [guid]::NewGuid().ToString('N') + '.json')
    }

    AfterEach {
        Get-ChildItem $TestDrive -File -EA SilentlyContinue | Remove-Item -Force -EA SilentlyContinue
    }

    It 'liefert Defaults wenn Datei fehlt' {
        $cfg = Read-Config -Path (Join-Path $TestDrive 'fehlt.json')
        $cfg.SchemaVersion | Should -Be (Get-DefaultConfig).SchemaVersion
        $cfg.OutputDir     | Should -Be (Get-DefaultConfig).OutputDir
    }

    It 'liefert Defaults bei kaputtem JSON (mit Warning)' {
        Set-Content -LiteralPath $script:CfgFile -Value 'das ist kein JSON {' -Encoding UTF8
        $cfg = Read-Config -Path $script:CfgFile -WarningAction SilentlyContinue
        $cfg.SchemaVersion | Should -Be (Get-DefaultConfig).SchemaVersion
    }

    It 'liefert Defaults bei leerer Datei' {
        Set-Content -LiteralPath $script:CfgFile -Value '' -Encoding UTF8
        $cfg = Read-Config -Path $script:CfgFile
        $cfg.OutputDir | Should -Be (Get-DefaultConfig).OutputDir
    }

    It 'merged geladene Werte mit Defaults (User-Wert hat Vorrang)' {
        $payload = @{
            SchemaVersion = 1
            OutputDir     = 'C:/Custom/Path'
            DelaySeconds  = 5
        } | ConvertTo-Json -Depth 4
        Set-Content -LiteralPath $script:CfgFile -Value $payload -Encoding UTF8

        $cfg = Read-Config -Path $script:CfgFile
        $cfg.OutputDir     | Should -Be 'C:/Custom/Path'
        $cfg.DelaySeconds  | Should -Be 5
        # Nicht-geliefertes FileNameFormat kommt aus Defaults
        $cfg.FileNameFormat | Should -Be (Get-DefaultConfig).FileNameFormat
        # Nicht-gelieferte Hotkey-Map kommt komplett aus Defaults
        $cfg.Hotkeys.Region.Key | Should -Be 'D1'
    }

    It 'ueberzaehlige Keys werden erhalten (Forward-Kompat)' {
        $payload = @{
            SchemaVersion = 1
            CustomExtraField = 'erhalten'
        } | ConvertTo-Json -Depth 4
        Set-Content -LiteralPath $script:CfgFile -Value $payload -Encoding UTF8

        $cfg = Read-Config -Path $script:CfgFile
        $cfg.CustomExtraField | Should -Be 'erhalten'
    }

    It 'fehlende SchemaVersion wird auf die aktuelle gehoben (Migration)' {
        $payload = @{ OutputDir = 'C:/X' } | ConvertTo-Json
        Set-Content -LiteralPath $script:CfgFile -Value $payload -Encoding UTF8
        $cfg = Read-Config -Path $script:CfgFile
        $cfg.SchemaVersion | Should -Be (Get-DefaultConfig).SchemaVersion
    }
}

Describe 'config: save' {
    BeforeEach {
        $script:CfgFile = Join-Path $TestDrive ("cfg_" + [guid]::NewGuid().ToString('N') + '.json')
    }

    AfterEach {
        Get-ChildItem $TestDrive -File -EA SilentlyContinue | Remove-Item -Force -EA SilentlyContinue
    }

    It 'speichert eine Config und liefert Success' {
        $cfg = Get-DefaultConfig
        $cfg.OutputDir = 'C:/Bilder/Tests'
        $r = Save-Config -Config $cfg -Path $script:CfgFile

        $r.Success | Should -BeTrue
        $r.Status  | Should -Be 'OK'
        Test-Path -LiteralPath $script:CfgFile | Should -BeTrue
    }

    It 'Save -> Read liefert dieselben Werte zurueck (Roundtrip)' {
        $cfg = Get-DefaultConfig
        $cfg.OutputDir = 'C:/Roundtrip'
        $cfg.DelaySeconds = 7
        $cfg.Hotkeys.Region.Key = 'D5'
        [void](Save-Config -Config $cfg -Path $script:CfgFile)

        $loaded = Read-Config -Path $script:CfgFile
        $loaded.OutputDir    | Should -Be 'C:/Roundtrip'
        $loaded.DelaySeconds | Should -Be 7
        $loaded.Hotkeys.Region.Key | Should -Be 'D5'
    }

    It 'legt fehlendes Verzeichnis an' {
        $deep = Join-Path $TestDrive 'a/b/c/cfg.json'
        $cfg = Get-DefaultConfig
        $r = Save-Config -Config $cfg -Path $deep
        $r.Success | Should -BeTrue
        Test-Path -LiteralPath $deep | Should -BeTrue
    }

    It 'setzt SchemaVersion wenn sie fehlt' {
        $cfg = @{ OutputDir = 'C:/x' }
        [void](Save-Config -Config $cfg -Path $script:CfgFile)
        $loaded = Read-Config -Path $script:CfgFile
        $loaded.SchemaVersion | Should -Be (Get-DefaultConfig).SchemaVersion
    }
}

Describe 'config: Format-Hotkey' {
    It 'formatiert Ctrl+Shift+D1 als Ctrl+Shift+1' {
        Format-Hotkey @{ Modifiers = @('Control', 'Shift'); Key = 'D1' } | Should -Be 'Control+Shift+1'
    }
    It 'formatiert Alt+F4' {
        Format-Hotkey @{ Modifiers = @('Alt'); Key = 'F4' } | Should -Be 'Alt+F4'
    }
    It 'akzeptiert leere Modifier-Liste' {
        Format-Hotkey @{ Modifiers = @(); Key = 'A' } | Should -Be 'A'
    }
}

Describe 'config: ConvertFrom-HotkeyString' {
    It 'parst "Ctrl+Shift+1" zu Control/Shift/D1' {
        $hk = ConvertFrom-HotkeyString 'Ctrl+Shift+1'
        $hk.Modifiers | Should -Contain 'Control'
        $hk.Modifiers | Should -Contain 'Shift'
        $hk.Key       | Should -Be 'D1'
    }
    It 'parst "Alt+F4"' {
        $hk = ConvertFrom-HotkeyString 'Alt+F4'
        $hk.Modifiers | Should -Be @('Alt')
        $hk.Key       | Should -Be 'F4'
    }
    It 'liefert $null bei leerem Input' {
        ConvertFrom-HotkeyString '   ' | Should -BeNullOrEmpty
    }
}

Describe 'config: Test-HotkeyConflict' {
    It 'meldet keinen Konflikt bei Default-Config' {
        $r = Test-HotkeyConflict -Hotkeys (Get-DefaultConfig).Hotkeys
        $r.IsValid | Should -BeTrue
        $r.Conflicts.Count | Should -Be 0
    }
    It 'erkennt zwei identische Hotkeys' {
        $map = @{
            A = @{ Modifiers = @('Control', 'Shift'); Key = 'D1' }
            B = @{ Modifiers = @('Shift', 'Control'); Key = 'D1' }  # gleiche Modifier in anderer Reihenfolge
        }
        $r = Test-HotkeyConflict -Hotkeys $map
        $r.IsValid          | Should -BeFalse
        $r.Conflicts.Count  | Should -Be 1
    }
    It 'unterscheidet unterschiedliche Modifier' {
        $map = @{
            A = @{ Modifiers = @('Control', 'Shift'); Key = 'D1' }
            B = @{ Modifiers = @('Alt'); Key = 'D1' }
        }
        (Test-HotkeyConflict -Hotkeys $map).IsValid | Should -BeTrue
    }
}

Describe 'config: Test-ConfigValid' {
    It 'akzeptiert Default-Config' {
        $r = Test-ConfigValid -Config (Get-DefaultConfig)
        $r.IsValid     | Should -BeTrue
        $r.Errors.Count | Should -Be 0
    }
    It 'fehlerhafte Delay (>30) wird gefangen' {
        $c = Get-DefaultConfig
        $c.DelaySeconds = 99
        $r = Test-ConfigValid -Config $c
        $r.IsValid | Should -BeFalse
        ($r.Errors -join ' ') | Should -Match 'Verzoegerung'
    }
    It 'leerer Zielordner wird gefangen' {
        $c = Get-DefaultConfig
        $c.OutputDir = ''
        $r = Test-ConfigValid -Config $c
        $r.IsValid | Should -BeFalse
        ($r.Errors -join ' ') | Should -Match 'Zielordner'
    }
    It 'Dateinamen-Schema ohne {mode} wird gefangen' {
        $c = Get-DefaultConfig
        $c.FileNameFormat = 'screenshot_yyyy.png'
        $r = Test-ConfigValid -Config $c
        $r.IsValid | Should -BeFalse
        ($r.Errors -join ' ') | Should -Match '\{mode\}'
    }
    It 'Hotkey-Konflikt schlaegt durch' {
        $c = Get-DefaultConfig
        $c.Hotkeys.ActiveWindow.Key = 'D1'  # collides mit Region
        $r = Test-ConfigValid -Config $c
        $r.IsValid | Should -BeFalse
        ($r.Errors -join ' ') | Should -Match 'Konflikt'
    }
}
