# Architektur

> Interne Sicht für Entwickler. Anwender-Architektur in `luscreen-docs/docs/referenz/architektur.md`.

## Layer-Übersicht

```
┌─────────────────────────────────────────────────┐
│  src/LucentScreen.ps1                           │
│  Bootstrap: STA-Check, Mutex, DPI, App-Loop     │
└──────────┬────────────────────────┬─────────────┘
           │                        │
┌──────────▼───────────┐  ┌─────────▼─────────────┐
│  src/ui/             │  │  src/core/            │
│  WPF: Tray, Fenster, │◄─┤  Logik, GDI+, P/Invoke│
│  XAML, HwndSource    │  │  Logging, Config      │
└──────────────────────┘  └───────────────────────┘
```

## Modulübersicht (Plan — wird mit AP-Fortschritt gefüllt)

| Modul | Layer | Zweck |
|---|---|---|
| `src/LucentScreen.ps1` | entry | Bootstrap, STA, Mutex, DPI, Application-Loop |
| `src/core/logging.psm1` | core | Datei-Log nach `%LOCALAPPDATA%/LucentScreen/logs/`, Rotation |
| `src/core/config.psm1` | core | Load/Save `config.json`, Schema-Migration, Defaults |
| `src/core/native.psm1` | core | `Add-Type`-Block: P/Invoke (RegisterHotKey, DwmGetWindowAttribute, …) |
| `src/core/hotkeys.psm1` | core | RegisterHotKey-IDs, WM_HOTKEY-Dispatch |
| `src/core/capture.psm1` | core | GDI+ Capture aller vier Modi |
| `src/core/files.psm1` | core | Dateinamen-Schema, Speichern, Clipboard |
| `src/core/history.psm1` | core | Verlauf laden/speichern |
| `src/ui/tray.psm1` | ui | NotifyIcon + Kontextmenü |
| `src/ui/config-dialog.psm1` | ui | XAML-Konfigurationsfenster |
| `src/ui/region-overlay.psm1` | ui | Vollbild-Overlay für Bereichsauswahl |
| `src/ui/editor.psm1` | ui | Annotations-Fenster |
| `src/ui/history-window.psm1` | ui | Verlaufsfenster |
| `src/ui/about.psm1` | ui | About-Dialog |

## Datenfluss: Bereichs-Screenshot

```
Hotkey  WM_HOTKEY
─────►  ┌─────────────────┐    ┌──────────────────┐    ┌──────────────┐
        │ HwndSource Hook │───►│ ui/region-overlay│───►│ core/capture │
        │ (Hidden Window) │    │  (Rect-Drag)     │    │  CopyFromScrn│
        └─────────────────┘    └──────────────────┘    └──────┬───────┘
                                                              │ Bitmap
                                                              ▼
                                                   ┌──────────────────┐
                                                   │ core/files       │
                                                   │  Save+Clipboard  │
                                                   └──────────────────┘
```

## Threads & Apartments

- **Main-Thread:** STA, läuft die WPF-Message-Loop via `Application.Run()`.
- **Capture-Worker:** kein eigener Thread — Capture läuft synchron auf Main-STA (GDI+ ist threadsafe, aber WPF braucht STA-Dispatcher für `BitmapSource`).
- **Logging:** Background-Datei-Append, lock-frei via `Mutex` pro Log-Datei.

## Datei-Ablagen

| Pfad | Zweck |
|---|---|
| `%APPDATA%\LucentScreen\config.json` | User-Konfig (mit Migration) |
| `%LOCALAPPDATA%\LucentScreen\logs\*.log` | Rolling-Logs (7 Tage) |
| `%LOCALAPPDATA%\LucentScreen\run\app.pid` | aktive Instanz (für `run.ps1 S`) |
| `<config:OutputDir>` | Screenshots — User-konfigurierbar |

## Externe Abhängigkeiten

- PowerShell 7+ (`pwsh.exe`)
- .NET 6+ (kommt mit PS7)
- WPF-Assemblies (im OS enthalten)
- `_deps/PSScriptAnalyzer/<ver>/` für PSSA (offline)

Keine NuGet/PSGallery-Abhängigkeiten zur Laufzeit.
