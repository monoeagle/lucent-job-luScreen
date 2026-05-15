# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/de/1.1.0/) · Versionierung: [SemVer](https://semver.org/lang/de/).

## [Unreleased]

### Added
- **AP 0 — Projekt-Setup & Grundgerüst**
  - `src/LucentScreen.ps1` — Bootstrap mit STA-Self-Relaunch, Single-Instance-Mutex, DPI-Awareness (PER_MONITOR_AWARE_V2), WPF/Drawing/Forms-Assemblies, globale Fehlerhandler (Dispatcher + AppDomain), `Application.Run()` mit `ShutdownMode=OnExplicitShutdown`.
  - `src/core/native.psm1` — P/Invoke-Block `LucentScreen.Native` mit `SetProcessDpiAwarenessContext`, `RECT`-Struct; `Set-DpiAwareness`-Wrapper mit Result-Hashtable.
  - `src/core/logging.psm1` — `Initialize-Logging` (Default-Pfad `%LOCALAPPDATA%/LucentScreen/logs/app.log`), `Write-LsLog` mit Level-Filter (Debug/Info/Warn/Error), Mutex-geschütztes Append, 7-Tage-Rotation.
  - `src/core/xaml-loader.psm1` — `Load-Xaml` (entfernt `x:Class`-Attribut vor `XamlReader::Load`), `Get-XamlControls` (Named-Element-Map via `FindName`).
  - Pester-Tests: `tests/core.logging.Tests.ps1` (5 Tests), `tests/core.xaml-loader.Tests.ps1` (5 Tests).
- Projekt-Scaffolding: Ordnerstruktur, PSSA-Setup, Agent-Definitionen, Doku-Gerüst, `run.ps1`-Menü, Reports-Layout, Zensical-Doc-Site, Single-Page-HTML-Doku-Bootstrap.
- `todo.md` mit Arbeitspaket-Plan (AP 0 – AP n).

### Quality
- PSSA: 0 Findings.
- Pester: 23/23 grün (10 aus AP 0 + 13 aus AP 1 Teil 1).
- Smoke-Test: App startet -STA, durchläuft alle Bootstrap-Schritte (inkl. Config-Load) und blockiert im `Application.Run()`-Message-Loop.

### Added (AP 1 Teil 1 — Konfigurations-Backend)
- `src/core/config.psm1` — Default-Schema v1, `Read-Config` mit Defaults-Merge und Schema-Migration, atomares `Save-Config` (via `.tmp`-Rename).
- 13 Pester-Tests in `tests/core.config.Tests.ps1`.
- `src/LucentScreen.ps1` lädt die Config nach Logging und legt sie in `$script:Config` ab. Ort: `%APPDATA%\LucentScreen\config.json`.
- Default-Hotkeys: `Ctrl+Shift+1..4` für Capture-Modi, `Ctrl+Shift+0` für Tray-Menü.
