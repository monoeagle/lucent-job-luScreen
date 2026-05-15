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
- PSSA: 0 Findings (10 Dateien gescannt).
- Pester: 10/10 grün.
- Smoke-Test: App startet -STA, durchläuft alle Bootstrap-Schritte und blockiert im `Application.Run()`-Message-Loop.
