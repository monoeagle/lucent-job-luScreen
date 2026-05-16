# Packaging & Verteilung

> Dieser Bereich entwickelt sich noch — siehe [todo.md](https://github.com/monoeagle/lucent-job-luScreen/blob/main/todo.md) AP 11.

## Ziel

Versioniertes, signiertes ZIP, das das Softwareverteilteam in ein MSI wickelt. Reihenfolge: erst lokal lauffähiges Bundle → dann Signatur → dann Übergabe.

## Soll-Layout (für MSI-Mapping)

| Pfad | Inhalt | Dauerhaftigkeit |
|---|---|---|
| `%ProgramFiles%\LucentScreen\` | Skripte, Assets, Launcher-EXE | read-only, vom MSI verwaltet |
| `%APPDATA%\LucentScreen\config.json` | User-Konfig | wird vom MSI **NICHT** überschrieben |
| `%LOCALAPPDATA%\LucentScreen\logs\` | Logs (mit 7-Tage-Rotation) | wird vom MSI bei Uninstall **NICHT** entfernt |
| `%USERPROFILE%\Pictures\LucentScreen\` | Default-Zielordner für Screenshots | bleibt nach Uninstall |

## Launcher-EXE (geplant, noch nicht implementiert)

Mini-C#-Projekt `LucentScreen.Launcher` (Single-File-EXE, .NET Framework 4.8 — auf jedem Win10/11 vorhanden, kein Runtime-Install nötig):

- Startet `powershell.exe -STA -ExecutionPolicy AllSigned -File "<Pfad>\LucentScreen.ps1"` ohne Konsolenfenster
- Eigenes App-Icon, Versionsinformationen, Manifest mit `dpiAwareness = PerMonitorV2`
- Build-Skript erzeugt reproducible `LucentScreen.exe`

## Code-Signing (geplant)

- Zertifikat-Quelle: interne CA (vermutlich) oder Drittanbieter (Sectigo/DigiCert) — noch zu klären
- Build-Skript signiert ALLE `.ps1`-Skripte (`Set-AuthenticodeSignature`) und die Launcher-EXE (`signtool sign /tr <timestamp> /fd SHA256 /td SHA256`)
- Timestamp-Server pflichtmäßig (sonst läuft Signatur mit Zertifikat-Ablauf aus)
- Verifikationsschritt im Build (`Get-AuthenticodeSignature` muss `Valid` zurückgeben)

## Übergabe-Bundle (geplant)

```
release/LucentScreen-<version>/
├── LucentScreen.exe          (Launcher, signiert)
├── src/                      (alle .ps1/.psm1, signiert)
├── assets/
│   ├── icon.png              (App-Icon)
│   └── luscreen.ico          (Tray + Window-Titel)
└── _deps/                    (PSScriptAnalyzer, Pester — gebundelt)
LucentScreen-<version>.zip
SHA256SUMS.txt
```

## Mindest-Zielsystem

- **Windows 10 1809+** (DPI-Awareness PER_MONITOR_AWARE_V2 ist hier verfügbar)
- **PowerShell 5.1** (vorinstalliert auf jedem Win10/11)
- **kein** PowerShell 7 / .NET-6+-Install nötig

## Fallback-Verteilung (Pilotphase, vor MSI)

„Portable"-Modus: ZIP entpacken, `LucentScreen.exe` starten — keine Installation. Konfig liegt dann neben der EXE statt in `%APPDATA%`.

## Status

| Stück | Status |
|---|---|
| Bundle-Layout dokumentiert | Skizze vorhanden, Festschreibung in `packaging/LAYOUT.md` offen |
| Launcher-EXE | offen |
| Signing-Pipeline | offen |
| Release-Build-Skript | offen |
| HANDOVER.md ans Verteilteam | offen |

→ Detaillierte Aufgabenliste in [todo.md AP 11](https://github.com/monoeagle/lucent-job-luScreen/blob/main/todo.md).
