# Installation

## Manueller Test-Install

Voraussetzungen:

- Windows 10 (1809+) oder Windows 11
- Windows PowerShell 5.1 (vorinstalliert; kein PowerShell 7 nötig)

Schritte:

1. Transfer-ZIP entpacken nach `%LOCALAPPDATA%\Programs\LucentScreen\`
2. Beim ersten Start kopiert die App `config.default.json` nach `%APPDATA%\LucentScreen\config.json`
3. Optional: Startmenü-Verknüpfung anlegen auf `powershell.exe -STA -File "%LOCALAPPDATA%\Programs\LucentScreen\LucentScreen.ps1"`

## Deinstallation

1. App über Tray-Menü beenden
2. Ordner `%LOCALAPPDATA%\Programs\LucentScreen\` löschen
3. Optional User-Daten löschen: `%APPDATA%\LucentScreen\` und `%LOCALAPPDATA%\LucentScreen\`
