# Installation

> Stub — wird mit AP 9 (Packaging) gefüllt.

## Per Softwareverteilung (Standardweg)

Der MSI-Installer wird vom Softwareverteilteam paketiert und ausgerollt.

## Manueller Test-Install

Voraussetzungen:
- Windows 10 (1809+) oder Windows 11
- PowerShell 7+ installiert (`pwsh.exe` im PATH)

Schritte:
1. Transfer-ZIP entpacken nach `%LOCALAPPDATA%\Programs\LucentScreen\`
2. Beim ersten Start kopiert die App `config.default.json` nach `%APPDATA%\LucentScreen\config.json`
3. Optional: Startmenu-Verknüpfung anlegen auf `pwsh.exe -STA -File "%LOCALAPPDATA%\Programs\LucentScreen\LucentScreen.ps1"`

## Deinstallation

1. App über Tray-Menü beenden
2. Ordner `%LOCALAPPDATA%\Programs\LucentScreen\` löschen
3. Optional User-Daten löschen: `%APPDATA%\LucentScreen\` und `%LOCALAPPDATA%\LucentScreen\`
