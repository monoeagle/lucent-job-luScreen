# Erledigt

Chronologisches Logbuch über bereits abgeschlossene Arbeitspakete und alle Commits/Pushes.

> **Workflow:** Sobald ein Punkt in `todo.md` vollständig erledigt ist, wird er **hier** einsortiert (im AP-Block) und in `todo.md` gelöscht. So bleibt die Todo-Liste schlank.
>
> **Datumsformat:** Immer `YYYYMMDD-HHMM` (z.B. `20260515-1412`) — sortierbar, eindeutig, ohne Trennzeichen-Mehrdeutigkeit.

---

## Arbeitspakete

### AP 0 — Projekt-Setup & Grundgerüst — abgeschlossen `20260515-1349`

- [x] Ordnerstruktur anlegen (`src/`, `src/views/` für XAML, `assets/` für Icons, `config/`, `docs/`, `packaging/`)
- [x] Einstiegsskript `LucentScreen.ps1` mit STA-Apartment-Check (`-STA` ist Pflicht für WPF und Clipboard)
- [x] Single-Instance-Mutex (verhindert Mehrfachstart)
- [x] Assemblies laden: `PresentationCore`, `PresentationFramework`, `WindowsBase`, `System.Xaml`, `System.Drawing`, `System.Windows.Forms` (nur für NotifyIcon)
- [x] XAML-Loader-Helper (`Load-Xaml` Funktion, Named-Elements per `FindName` extrahieren)
- [x] Zentrales Logging (Datei in `%LOCALAPPDATA%\LucentScreen\logs\` + optional Debug-Konsole)
- [x] Globale Fehlerbehandlung (`DispatcherUnhandledException`, `AppDomain.UnhandledException`)
- [x] App-Lifecycle: `[System.Windows.Application]::new()` + `Run()` als Message-Loop-Anker, `ShutdownMode = OnExplicitShutdown` (sonst beendet sich App beim Schließen jedes Fensters)

**Artefakte:** `src/LucentScreen.ps1`, `src/core/native.psm1` (DPI P/Invoke), `src/core/logging.psm1`, `src/core/xaml-loader.psm1`, `tests/core.logging.Tests.ps1`, `tests/core.xaml-loader.Tests.ps1`.

**Quality-Stand:** Parse 19/19 clean · PSSA 0 Findings · Pester 10/10 grün auf PS 7 und PS 5.1.

### AP 1 (Teil 2) — Konfig-Dialog (WPF) — abgeschlossen `20260515-1458`

- [x] Konfig-Dialog als WPF-Fenster (XAML)
- [x] Zielordner wählen (`FolderBrowserDialog`)
- [x] 5 Hotkey-Felder mit KeyDown-Capture und Konflikterkennung (Region, ActiveWindow, Monitor, AllMonitors, TrayMenu)
- [x] Verzögerung 0–30 s (Slider + Textbox, synchronisiert)
- [x] Dateinamen-Schema, Edit-Postfix
- [x] Speichern/Abbrechen, Live-Validierung mit Inline-Warn-Box
- [ ] Re-Apply zur Laufzeit (Hotkeys/FileWatcher) — folgt nach AP 2/AP 3

**Artefakte:**
- `src/views/config-dialog.xaml` — XAML-Window (640×640, FixedDialog, ResourceDictionary-Style)
- `src/ui/config-dialog.psm1` — `Show-ConfigDialog` (STA-Check, FolderBrowser, Hotkey-Capture via `PreviewKeyDown`, Slider/Textbox-Bindung, Validation-Box)
- `src/core/config.psm1` (erweitert) — `Format-Hotkey`, `ConvertFrom-HotkeyString`, `Test-ConfigValid`, `Test-HotkeyConflict`
- `tools/Show-ConfigDialog.ps1` — STA-Launcher für interaktiven Smoke-Test
- `run.ps1` — neue Taste `cfg` (Action-ConfigDialog)
- 14 zusätzliche Pester-Tests (Format-Hotkey, ConvertFrom, Test-HotkeyConflict, Test-ConfigValid)

**Bugfixes während der Tests:**
- `ConvertFrom-HotkeyString` mit Whitespace-Input crashte unter StrictMode (`$null.Count`). Fix: `@(…)`-Wrap.
- `Test-ConfigValid` warf `Index out of range` weil Methoden-Komma die `-f`-Argumente fraß. Fix: Extra-Klammer um das Format-Statement, dann `Add()` mit nur einem Argument.

**Quality-Stand:** Parse 29/29 clean · PSSA 0 Findings · Pester 37/37 grün auf PS 7 und PS 5.1. Headless-Smoke des XAML: lädt sauber, alle 15 Named-Controls erreichbar.

### AP 1 (Teil 1) — Konfigurations-Backend — abgeschlossen `20260515-1446`

- [x] Default-Konfig im Code (Hotkeys, Zielordner, Verzögerung, Dateinamensschema)
- [x] Konfig-Datei `config.json` in `%APPDATA%\LucentScreen\` (User-scope, NICHT im Programmordner)
- [x] Laden/Speichern der Konfig (mit Migrations-/Default-Fallback, Schema-Version)
- [ ] Konfig-Dialog als WPF-Fenster — folgt nach AP 2 (Tray-Menü)
- [ ] Konfig-Änderungen wirken zur Laufzeit — folgt mit dem Dialog

**Artefakte:**
- `src/core/config.psm1` — `Get-DefaultConfig`, `Get-ConfigPath`, `Read-Config` (Merge + Migration), `Save-Config` (atomar via `.tmp`-File)
- `tests/core.config.Tests.ps1` — 13 Pester-Tests
- `src/LucentScreen.ps1` — Config wird nach Logging geladen, in `$script:Config` abgelegt

**Schema v1:**
- `OutputDir` — Standard `~/Pictures/LucentScreen`
- `DelaySeconds` — Default 0 (0–30 möglich, validiert beim Speichern aus dem Dialog)
- `FileNameFormat` — `LucentScreen_yyyy-MM-dd_HH-mm-ss_{mode}.png`
- `EditPostfix` — `_edited`
- `Hotkeys` — fünf Einträge (`Region`, `ActiveWindow`, `Monitor`, `AllMonitors`, `TrayMenu`), jeweils `{Modifiers, Key}`

**Robustheits-Eigenschaften:**
- Datei fehlt → Defaults
- Datei kaputt → Defaults + `Write-Warning`
- Schema-Version niedriger → durchläuft `_Migrate-Config` (Framework für künftige Versionen, V1 ist erste)
- Geladene Werte mergen rekursiv mit Defaults; überzählige User-Keys bleiben erhalten (Forward-Kompat)
- `Save-Config` schreibt erst `.tmp`, dann Rename — kein halb-geschriebenes File bei Abbruch

**Quality-Stand:** Parse 25/25 clean · PSSA 0 Findings · Pester 23/23 grün auf PS 7 und PS 5.1.

---

## Zusätzliche Setup-Arbeiten (außerhalb der nummerierten APs)

### Scaffolding — `20260515-1331`
Initiales Projekt-Gerüst: Ordnerstruktur, PSSA-Setup, Agent-Definitionen, Doku-Gerüst, `run.ps1`-Menü, Reports-Layout, Zensical-Doc-Site, Single-Page-HTML-Doku-Bootstrap, Hooks, `docs/ecosystem-playbook.md` (Bootstrap-Rezept für künftige `lucent-job-*`-Projekte).

### PS-5.1-Kompatibilität + No-NuGet-Runtime — `20260515-1412`
- `#Requires -Version 5.1` in allen `.ps1`/`.psm1`
- Ternary durch `if`/`else` ersetzt
- Shell-Detection (`pwsh` bevorzugt, Fallback `powershell.exe`) in `run.ps1` und `LucentScreen.ps1` Self-Relaunch
- Pester-Offline-Bundle in `_deps/Pester/<ver>/` mit `tools/Install-Pester-Offline.ps1` (drei Modi: `Save-Module` / `-Source` / `-Url`)
- `run.ps1`: `Import-PesterBundled`-Helper, Menü-Eintrag `ip`
- Doku-Updates in CLAUDE.md, `docs/Entwicklung.md`, `docs/ecosystem-playbook.md`, `luscreen-docs/docs/grundlagen/plattformen.md`, `README.md`, `.claude/agents/powershell-specialist.md`

---

## Commits & Pushes

Tabelle pro Commit/Push. Eintrag VOR `git commit` ergänzen, Hash nach erfolgreichem Commit nachtragen, `Push ✓` nach `git push`.

| # | Datum | Hash | Push | Scope | Beschreibung |
|---|---|---|---|---|---|
| 1 | `20260515-1302` | `a23a0fa` | ✓ | meta | Initial todo |
| 2 | `20260515-1331` | `3704a64` | ✓ | scaffold | Bootstrap LucentScreen scaffolding (Ordner, Agenten, PSSA, Reports, Doku, HTML-Single-Page, Hooks, Ecosystem-Playbook) |
| 3 | `20260515-1349` | `5e69a08` | ✓ | AP 0 | Projekt-Setup und Grundgerüst — `src/LucentScreen.ps1`, `src/core/{native,logging,xaml-loader}.psm1`, Pester-Tests (10/10), PSSA 0 Findings |
| 4 | `20260515-1412` | `9c375a7` | ✓ | compat | PS 5.1-Kompatibilität, Shell-Detection, Pester-Offline-Bundle (`tools/Install-Pester-Offline.ps1`), No-NuGet-Runtime-Doku |
| 5 | `20260515-1412` | `28313f5` | ✓ | chore | Commit-Log-Eintrag 4 mit finalem Hash nachgetragen |
| 6 | `20260515-1412` | `9055065` | ✓ | chore | Commit-Log-Eintrag 5 ergänzt |
| 7 | `20260515-1418` | `2cccf5a` | ✓ | docs | `erledigt.md` angelegt, AP 0 + Commit-Log aus `todo.md` hierher verschoben, Datumsformat `YYYYMMDD-HHMM` etabliert, `zensical.toml`-Nav um „Erledigt" erweitert, `ecosystem-playbook` um Workflow-Abschnitt 11 ergänzt |
| 8 | `20260515-1418` | `bc8dd3e` | ✓ | chore | Commit-Log-Eintrag 7 mit finalem Hash nachgetragen |
| 9 | `20260515-1421` | `1914bfd` | ✓ | fix | `run.ps1 d` öffnet `site/index.html` nach erfolgreichem Build im Standard-Browser, Exit-Code-Check zwischengeschaltet, Menü-Text aktualisiert |
| 10 | `20260515-1421` | `9171d9b` | ✓ | chore | Commit-Log-Eintrag 9 mit finalem Hash nachgetragen |
| 11 | `20260515-1421` | `1c3d67c` | ✓ | chore | Commit-Log-Eintrag 10 mit finalem Hash nachgetragen |
| 12 | `20260515-1435` | `_pending_` | — | fix | `build_docs.py` UTF-8-safe Output + Python-Mindestversion-Check (3.10); `luscreen-docs/run.ps1` PS-Wrapper mit `.venv-docs`-Management, Python-Detection, Build/Serve/Clean/Menu; Haupt-`run.ps1` `Action-DocsBuild` ruft Wrapper, neue Taste `D` für Live-Server; `run_luscreen_docs.sh` (bash) gelöscht; Playbook-Abschnitt 11 um Option-2-Regel (Hash nicht backfillen) ergänzt |
| 13 | `20260515-1440` | `_pending_` | — | fix | `zensical.toml: use_directory_urls = false` damit Doku-Site aus `file://` direkt klickbar ist (statt Verzeichnis-Listing) |
| 14 | `20260515-1446` | `_pending_` | — | AP 1 | Config-Backend: `src/core/config.psm1` (Get-DefaultConfig, Get-ConfigPath, Read-Config mit Defaults-Merge und Migration, Save-Config atomar). 13 Pester-Tests. Bootstrap in `src/LucentScreen.ps1` laedt Config nach Logging. Pflicht-Path: `%APPDATA%/LucentScreen/config.json`. WPF-Konfig-Dialog folgt nach AP 2. |
| 15 | `20260515-1458` | `_pending_` | — | AP 1 | Konfig-Dialog (WPF): `src/views/config-dialog.xaml`, `src/ui/config-dialog.psm1` mit `Show-ConfigDialog` (Hotkey-Capture via PreviewKeyDown, FolderBrowserDialog, Slider/Textbox-Sync, Live-Validation). `core/config.psm1` um `Format-Hotkey`/`ConvertFrom-HotkeyString`/`Test-ConfigValid`/`Test-HotkeyConflict` ergänzt + 14 neue Tests (jetzt 37/37 grün). `tools/Show-ConfigDialog.ps1` STA-Launcher und `run.ps1 cfg`-Task. |

**Regeln:**
- **Datumsformat ist `YYYYMMDD-HHMM`** (z.B. `20260515-1412`).
- Scope-Tag: `meta`, `scaffold`, `AP <n>`, `compat`, `fix`, `docs`, `chore`.
- Bei Force-Push oder Revert: zusätzliche Zeile mit Vermerk anhängen, **nicht** alte Zeile editieren.
- Bei mehreren Commits derselben Minute: weiter zählen — die `#` ist Wahrheits-Reihenfolge, nicht das Datum.
- **Hash bleibt `_pending_`, Push-Spalte `—`.** Hashes nicht nachtragen — `git log` ist die Wahrheit, Backfill-Commits erzeugen nur Rauschen (siehe `docs/ecosystem-playbook.md` Abschnitt 11).
