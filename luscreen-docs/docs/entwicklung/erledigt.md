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

### AP 7 — Zwischenablage — abgeschlossen `20260515-1624`

- [x] Helper „Bitmap → Clipboard" via `Clipboard.SetImage(BitmapSource)` mit STA-Guard
- [x] Nach jedem Capture: aktuelles Bild in die Zwischenablage
- [x] Robust gegen Clipboard-Locks (Retry mit exponentiellem Backoff: 50/100/200/400/800ms, max. 5 Versuche)
- [ ] „STRG+C im Verlaufsfenster" — verschoben zu AP 8 (Verlauf existiert noch nicht)

**Artefakte:**
- `src/core/clipboard.psm1` — `Convert-BitmapToBitmapSource` (PNG-Roundtrip via MemoryStream, liefert Frozen-Source), `Set-ClipboardImage` mit STA-Check + Retry-Backoff
- `tests/core.clipboard.Tests.ps1` — 3 Tests (BitmapSource-Dimensionen, Frozen-Flag, MTA-NotSta-Guard)
- `src/LucentScreen.ps1` — `$invokeCapture` ruft `Set-ClipboardImage` nach `Save-Capture`, Result wird geloggt

**Implementierungs-Detail:**
- BitmapSource-Konvertierung über `MemoryStream` + `BitmapImage.CacheOption=OnLoad` + `Freeze()` — vermeidet HBITMAP-Leak und macht das Bild Cross-Thread-fähig
- Pester läuft in MTA → STA-Test wird übersprungen (`Set-ItResult -Skipped`)

**Interaktiver Smoke-Test:**
- `Ctrl+Shift+3` → PNG gespeichert + Bild in Clipboard → `Strg+V` in Bildbetrachter zeigt Screenshot

**Quality-Stand:** Parse 49/49 clean · PSSA 0 Findings · Pester 76/76 grün, 1 skipped (STA-Guard).

### AP 6 — Dateinamen-Schema — abgeschlossen `20260515-1616`

- [x] `FileNameFormat` aus Config respektieren mit Tokens `{mode}`, `{postfix}`, `yyyy`, `yy`, `MM`, `dd`, `HH`, `mm`, `ss`
- [x] Edit-Variante: `{postfix}`-Token + `Postfix`-Parameter in `Save-Capture` (für AP 9 Editor vorbereitet)
- [x] Kollisionsschutz: `Resolve-UniqueFilename` hängt `-2`, `-3`, … vor der Endung an
- [x] Berechtigungsprüfung: Probe-File-Write vor `Bitmap.Save`, klare `PermissionDenied`-Meldung statt Stack-Trace

**Artefakte:**
- `src/core/capture.psm1`: `Format-CaptureFilename` (case-sensitive `-creplace`, Reihenfolge yyyy→yy→MM→dd→HH→mm→ss), `Resolve-UniqueFilename`, `_Test-DirectoryWritable`, erweitertes `Save-Capture` mit `-Template`/`-Postfix`
- `tests/core.capture.Tests.ps1`: 10 neue Tests (Format-CaptureFilename: 5, Resolve-UniqueFilename: 3, Save-Capture-Kollisionen+Postfix: 2)
- `src/LucentScreen.ps1`: `$invokeCapture` liest `$script:Config.FileNameFormat` und reicht es als `-Template` durch

**Implementierungs-Detail:**
- Frühere Version nutzte `DateTime.ToString($template)` — scheiterte daran, dass `g` (Era) in `.png` zu `n. Chr.` expandiert wurde. Lösung: explizite `-creplace`-Substitution unserer fixen Token-Liste, kein `ToString` über das ganze Template.
- `-creplace` (case-sensitive) damit `MM` (Monat) und `mm` (Minute) unterscheidbar bleiben.

**Interaktiver Smoke-Test:**
- 5 Captures innerhalb 2 Sekunden → `…_16-16-08_Monitor.png` + `-2`-Suffix; `…_16-16-09_Monitor.png` + `-2` + `-3`-Suffix
- Alle Dateien valide PNG

**Quality-Stand:** Parse 45/45 clean · PSSA 0 Findings · Pester 74/74 grün unter PS 5.1.

### Vorgezogen aus AP 5 / AP 6 — `20260515-1602`

Im Zuge von AP 4 mit-erledigt, aus den dortigen AP-Blöcken in `todo.md` entfernt:

**Aus AP 5:**
- [x] Verzögerung aus Konfig lesen (0 = sofort) — `Invoke-Capture -DelaySeconds` aus `$script:Config.DelaySeconds`

**Aus AP 6:**
- [x] Zielordner anlegen, falls fehlt — `Save-Capture` macht `New-Item -ItemType Directory -Force`
- [x] Schreiben mit `Bitmap.Save(..., ImageFormat.Png)`
- [x] OutputDir-Änderungen wirken zur Laufzeit — `$script:Config.OutputDir` wird beim nächsten Capture lazy aufgelöst, kein extra Refresh nötig

### AP 4 — Capture-Engine — abgeschlossen `20260515-1602`

- [x] DPI-Awareness (war schon AP 0)
- [x] Multi-Monitor-Erkennung über `Screen.AllScreens`
- [x] Capture-Helfer: `System.Drawing.Bitmap` + `Graphics.CopyFromScreen` (`Capture-Rect`)
- [x] Modus „Alle Monitore" über `SystemInformation.VirtualScreen`
- [x] Modus „Monitor unter Maus" über `Screen.FromPoint(GetCursorPos())`
- [x] Modus „Aktives Fenster" via `GetForegroundWindow` + `DwmGetWindowAttribute(DWMWA_EXTENDED_FRAME_BOUNDS=9)`, Fallback `GetWindowRect`
- [x] Modus „Bereich" mit Vollbild-Overlay (`src/views/region-overlay.xaml`), Maus-Drag-Auswahl + Live-Größe + ESC-Cancel
- [x] PNG speichern mit `Bitmap.Save(...,ImageFormat.Png)` in `Save-Capture` (volles Dateinamen-Schema folgt mit AP 6)
- [ ] BitmapSource-Konvertierung für WPF-Vorschau — verschoben nach AP 9 (Editor braucht es)

**Artefakte:**
- `src/core/native.psm1` erweitert: `GetForegroundWindow`, `GetWindowRect`, `DwmGetWindowAttribute`, `GetCursorPos`, `POINT`-Struct, `DWMWA_EXTENDED_FRAME_BOUNDS`-Konstante
- `src/core/capture.psm1`: `Get-AllScreens`, `Get-VirtualScreenBounds`, `Get-ScreenUnderCursor`, `Get-ForegroundWindowRect` (mit DWM-bevorzugt + Fallback), `Capture-Rect`, `Save-Capture` (minimal-Schema, AP 6 erweitert), `Invoke-Capture` (orchestriert)
- `src/views/region-overlay.xaml` — WPF-Fenster über VirtualScreen, `AllowsTransparency=True`, `Background=#33000000`, `Cursor=Cross`
- `src/ui/region-overlay.psm1` — `Show-RegionOverlay` mit Drag-State, ESC-Cancel, MouseUp-Confirm, Live-Größe-Anzeige
- `tests/core.capture.Tests.ps1` — 11 Pester-Tests (Screen-Enumeration, Capture-Rect, Save-Capture, Invoke-Capture für alle Modi)
- `src/LucentScreen.ps1` — `$invokeCapture`-ScriptBlock ersetzt die MessageBox-Stubs: Region → Overlay → Capture, andere Modi direkt; `Save-Capture` zum konfigurierten `OutputDir`

**Interaktiver Smoke-Test:**
- `Ctrl+Shift+3` (Monitor) → `LucentScreen_20260515-160132_Monitor.png` (1600×900, 137 KB)
- `Ctrl+Shift+2` (ActiveWindow) → `LucentScreen_20260515-160206_ActiveWindow.png` (861×602, 34 KB)
- Beide Dateien valide PNG unter `%USERPROFILE%/Pictures/LucentScreen/`

**Quality-Stand:** Parse 45/45 clean · PSSA 0 Findings · Pester 64/64 grün unter PS 5.1.

### AP 3 — Globale Hotkeys — abgeschlossen `20260515-1551`

- [x] P/Invoke für `RegisterHotKey` / `UnregisterHotKey` via `Add-Type` (`LucentScreen.HotKey`)
- [x] Hidden-Window mit `WindowInteropHelper.EnsureHandle()` + `HwndSource.AddHook` für `WM_HOTKEY` (0x312)
- [x] Hotkey-Registry-Dictionary (`$script:HotkeyState.Registered` — ID → Name/Callback/Display/Hwnd)
- [x] Re-Registrierung nach Konfig-Speichern (Tray-Callback `Config` ruft `Register-AllHotkeys` neu auf `$script:Config.Hotkeys`)
- [x] Konflikt-Behandlung mit `Marshal.GetLastWin32Error()` + MessageBox-Warnung beim Start
- [x] Cleanup im `Application.Exit`-Handler (`Unregister-AllHotkeys` vor Tray-Dispose)

**Artefakte:**
- `src/core/hotkeys.psm1`: `LucentScreen.HotKey` (P/Invoke), `Convert-ModifiersToFlags`, `Convert-KeyNameToVirtualKey` (via `KeyInterop.VirtualKeyFromKey`), `Register-AllHotkeys`, `Unregister-AllHotkeys`, `Invoke-HotkeyById`, `Get-RegisteredHotkeys`
- `tests/core.hotkeys.Tests.ps1`: 16 Pester-Tests (Modifier-Flags, VK-Codes, Register/Unregister mit Thread-HWND, Conflict-Erkennung bei unbekannter Taste, NextId-Eindeutigkeit)
- `src/LucentScreen.ps1`: Hidden-WPF-Window mit `EnsureHandle`, `HwndSource.AddHook` dispatcht `WM_HOTKEY` an `Invoke-HotkeyById`, Re-Register im Config-Callback, Unregister im Exit-Handler

**Interaktiver Smoke-Test:**
- Start: Log meldet `[hotkey] Registriert: 5, Konflikte: 0`
- `Ctrl+Shift+1` (Region) → MessageBox „Capture-Engine kommt mit AP 4"
- Beenden über Tray oder Hotkey-Konflikt-MessageBox → `Unregister-AllHotkeys` läuft sauber, kein dangling Hotkey

**Quality-Stand:** Parse 39/39 clean · PSSA 0 Findings · Pester 53/53 grün unter PS 5.1.

### AP 2 — Tray-Icon & Kontextmenü — abgeschlossen `20260515-1529`

- [x] `System.Windows.Forms.NotifyIcon` mit Programm-Icon (`assets/luscreen.ico`, multi-res 16/32/48/64)
- [x] Tooltip (Programmname + Version)
- [x] Kontextmenü (`ContextMenuStrip`): Bereich, Aktives Fenster, Monitor, Alle Monitore, Verlauf, Konfiguration…, Über…, Beenden
- [x] „Über"-Dialog als WPF-Fenster (`src/views/about-dialog.xaml`, `src/ui/about-dialog.psm1`)
- [x] Sauberes `Dispose` beim `Application.Exit` (verhindert Hänge-Icon)

**Artefakte:**
- `assets/luscreen.ico` (3.2 KB, 4 Auflösungen) + `tools/Make-Icon.ps1` (Generator)
- `src/ui/tray.psm1` — `Initialize-Tray` mit Callbacks-Hashtable, Doppelklick-Hook auf „Region", Dispose-Closure-Result
- `src/views/about-dialog.xaml`, `src/ui/about-dialog.psm1` — `Show-AboutDialog -Version -IconPath -Owner`
- `src/LucentScreen.ps1` — Tray nach Config-Load initialisieren, Capture-Aktionen als Placeholder (MessageBox + Log) bis AP 4

**Capture-Stubs:** Region/ActiveWindow/Monitor/AllMonitors zeigen aktuell eine MessageBox „Capture-Engine kommt mit AP 4". Verlauf-Stub analog für AP 8. Konfiguration… öffnet den AP 1-Dialog und persistiert per `Save-Config`.

**Interaktiver Smoke-Test:**
- Tray-Icon sichtbar, Tooltip „LucentScreen 0.1.0"
- Rechtsklick → vollständiges Menü
- „Konfiguration…" öffnet den Dialog, Speichern → `Save-Config` ok
- „Beenden" → `Application.Shutdown()` → `Application.Exit`-Handler → Tray-Dispose → kein Ghost-Icon

**Quality-Stand:** Parse 35/35 clean · PSSA 0 Findings · Pester 37/37 grün unter PS 5.1.

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
| 16 | `20260515-1513` | `_pending_` | — | compat | PS 7-Support entfernt — PS 5.1 ist einziges Target. `$script:PSShell`-Detection raus aus `run.ps1`, Self-Relaunch in `LucentScreen.ps1` direkt mit `powershell.exe`, `$IsLinux`/`$IsMacOS` aus `luscreen-docs/run.ps1`. CLAUDE.md mit „Future"-Note (PS 7 später evtl. wieder). PSSA-Bundle `1.25.0` in `_deps/` via neuem `-Url`-Mode (Invoke-WebRequest, kein NuGet). `Install-{PSScriptAnalyzer,Pester}-Offline.ps1` speichern nupkg als `.zip` (PS-5.1-Expand-Archive akzeptiert nur `.zip`). |
| 17 | `20260515-1529` | `_pending_` | — | AP 2 | Tray-Icon mit Kontextmenü + About-Dialog. `assets/luscreen.ico` via `tools/Make-Icon.ps1` (multi-res, manuelles ICO-Binärformat statt BinaryWriter wegen PS-5.1-ctor-Mucken). `src/ui/tray.psm1` `Initialize-Tray` mit 8 Menü-Einträgen, Doppelklick-Hook, Dispose-Closure. `src/{views,ui}/about-dialog.*`. `LucentScreen.ps1` wired alles; Capture-Aktionen vorerst MessageBox-Stubs bis AP 4. Interaktiver Smoke-Test passed (User hat Tray-Menü inkl. Konfig-Dialog und Beenden geklickt, Tray sauber disposed). |
| 18 | `20260515-1521` | `_pending_` | — | chore | todo.md aufgeräumt: AP 1 (komplett erledigt) und leerer AP 2-Header entfernt, Restpunkt „Re-Apply zur Laufzeit" in AP 3 + AP 6 verschoben. |
| 19 | `20260515-1551` | `_pending_` | — | AP 3 | Globale Hotkeys: `src/core/hotkeys.psm1` mit P/Invoke (`LucentScreen.HotKey`: RegisterHotKey/UnregisterHotKey + MOD_*-Konstanten), `Convert-ModifiersToFlags`, `Convert-KeyNameToVirtualKey` via `KeyInterop`, `Register-AllHotkeys` mit Conflict-Erkennung (`Marshal.GetLastWin32Error`), `Unregister-AllHotkeys`, `Invoke-HotkeyById`. 16 Pester-Tests. `LucentScreen.ps1` legt Hidden-Window mit `EnsureHandle()` an, hookt `WM_HOTKEY` (0x312) via `HwndSource.AddHook`, registriert beim Start, re-registriert nach Config-Save, unregistriert im Exit-Handler. Interaktiver Smoke-Test: Ctrl+Shift+1 löst Region-Callback aus. |
| 20 | `20260515-1602` | `_pending_` | — | AP 4 | Capture-Engine: `src/core/capture.psm1` mit `Invoke-Capture` für vier Modi (Monitor/AllMonitors/ActiveWindow/Region), GDI+ `Graphics.CopyFromScreen`, DWM-Frame-Bounds für ActiveWindow mit `GetWindowRect`-Fallback. Region-Overlay (`src/views/region-overlay.xaml` + `src/ui/region-overlay.psm1`) mit Drag-Selection und ESC-Cancel. `native.psm1` erweitert (GetForegroundWindow, GetWindowRect, DwmGetWindowAttribute, GetCursorPos, POINT-Struct). 11 neue Tests. `LucentScreen.ps1`: $invokeCapture ersetzt die Placeholder-MessageBox; Screenshots landen in `$Config.OutputDir` mit `LucentScreen_YYYYMMDD-HHmmss_<Mode>.png` (volles Schema folgt mit AP 6). Interaktiver Test: Monitor- und ActiveWindow-Captures erzeugt valide PNGs. |
| 21 | `20260515-1608` | `_pending_` | — | chore | todo.md aufgeräumt: erledigte Sub-Items aus AP 5 (Delay aus Config) und AP 6 (Auto-Mkdir, Bitmap.Save, OutputDir-Lazy) entfernt, weil von AP 4 abgedeckt. AP-Beschreibungen oben jeweils mit Hinweis ergänzt was schon erledigt ist. |
| 22 | `20260515-1616` | `_pending_` | — | AP 6 | Dateinamen-Schema: `Format-CaptureFilename` mit Tokens `{mode}`, `{postfix}`, yyyy/yy/MM/dd/HH/mm/ss (case-sensitive `-creplace`, Reihenfolge: lange Tokens zuerst). `Resolve-UniqueFilename` hängt -2/-3/... an. `_Test-DirectoryWritable` macht Probe-Write vor `Bitmap.Save` (klare PermissionDenied-Meldung). `Save-Capture` nimmt jetzt `-Template`/`-Postfix`. `LucentScreen.ps1` reicht `$Config.FileNameFormat` durch. 10 neue Tests. Smoke-Test mit 5 Captures in 2 Sekunden zeigt -2/-3-Suffixe. |
| 23 | `20260515-1624` | `_pending_` | — | AP 7 | Zwischenablage: `src/core/clipboard.psm1` mit `Convert-BitmapToBitmapSource` (PNG-Roundtrip + Frozen) und `Set-ClipboardImage` (STA-Guard, Retry-Backoff 50→100→200→400→800ms, max 5 Versuche). 3 Tests (1 skipped wegen MTA). `LucentScreen.ps1` kopiert das Bild nach jedem Capture in die Zwischenablage. Verlaufsfenster-Hook bleibt als einziger Sub-Punkt offen und wandert zu AP 8. |

**Regeln:**
- **Datumsformat ist `YYYYMMDD-HHMM`** (z.B. `20260515-1412`).
- Scope-Tag: `meta`, `scaffold`, `AP <n>`, `compat`, `fix`, `docs`, `chore`.
- Bei Force-Push oder Revert: zusätzliche Zeile mit Vermerk anhängen, **nicht** alte Zeile editieren.
- Bei mehreren Commits derselben Minute: weiter zählen — die `#` ist Wahrheits-Reihenfolge, nicht das Datum.
- **Hash bleibt `_pending_`, Push-Spalte `—`.** Hashes nicht nachtragen — `git log` ist die Wahrheit, Backfill-Commits erzeugen nur Rauschen (siehe `docs/ecosystem-playbook.md` Abschnitt 11).
