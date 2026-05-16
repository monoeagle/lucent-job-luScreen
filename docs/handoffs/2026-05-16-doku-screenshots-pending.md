# Handoff 2026-05-16 — Doku-Screenshots offen, sonst alles auf main + gepusht

## Stand

- **Branch:** `main` (clean bis auf `.claude/settings.local.json`)
- **Letzter Push:** `9684603` (Take-LuScreenshots.ps1 — halbautomatischer Screenshot-Generator)
- **Quality:** Parse 67/67 clean · PSSA 0 · Pester 110/110 grün (1 skipped)
- **App-Version:** `0.2.0`

## Was seit dem M3-Handoff (15.05.) erledigt wurde

Vier feat-Commits + ein docs-Commit + ein tools-Commit (alle gepusht):

- `4f12656` AP 9 Etappe 2a — Crop-Bugfixes + Crop-Undo + Save-UX
- `1ba7f6e` AP 9 Politur — Verlauf-Toolbar, Editor-Save-Fix, Konfig+About+Tray
- `b4c0b61` AP 9 Etappe 2b/3 — Radierer + Selection-Adorner + Move/Delete + ESC-Confirm
- `cb3e8e2` Politur — Umlaute + HistoryOpen-Hotkey + Tray-Hotkey-Anzeige
- `6fdc86d` Doku — Komplette Doku-Befüllung + Mermaid-Quellen + Single-Page-Refresh
- `9684603` Tools — Take-LuScreenshots.ps1 (halbautomatischer Generator)

**AP 9 ist abgeschlossen** — alle Etappen (1, 2a, 2b, 3) durch. todo.md zeigt nur noch AP 10 (Politur) + AP 11 (Packaging) als Restplan.

## Was als nächstes ansteht (in genau dieser Reihenfolge)

### 1. Doku-Screenshots — Phase 2 abschließen

Manifest: `luscreen-docs/docs/images/luscreen/0.2.0/manifest.json` listet 14 geplante Screenshots. Tobias macht sie manuell (mit LucentScreen selbst + PrintScreen für Popup-Captures).

**Ablauf wenn Tobias fertig ist:**

1. Liste was unter `%USERPROFILE%\Pictures\LucentScreen\` gegenüber dem 16.05.-Stand neu ist (waren beim Handoff: 1 Datei `20260516_0157_ActiveWindow.png` — der fehlerhafte 136×39-Capture, kann gelöscht werden)
2. Mit Tobias durchgehen: jede neue PNG einem Manifest-Eintrag zuordnen
3. Kopieren + umbenennen nach `luscreen-docs/docs/images/luscreen/0.2.0/<file>.png`
4. `manifest.json` `capturedAt` mit ISO-Timestamp aktualisieren
5. `./run.ps1 d` testen — Site bauen, prüfen ob alle Bilder eingebunden sind
6. Screenshot-Refs in der `LucentScreen.docs.html` (Single-Page) sind aktuell `<div class="imgph">[ Screenshot: … ]</div>`-Platzhalter — durch `<img>`-Tags ersetzen
7. Commit `docs(images): 14 Screenshots fuer v0.2.0`, push

**Tabelle der erwarteten Files** (aus manifest.json):

| # | Datei | Was |
|---|---|---|
| 1 | `tray-menu.png` | Tray-Kontextmenü |
| 2 | `config-dialog.png` | Konfig-Dialog |
| 3 | `history-window.png` | Verlaufsfenster |
| 4 | `history-context.png` | Verlauf-Kontextmenü |
| 5 | `editor-empty.png` | Editor frisch geöffnet |
| 6 | `editor-tools.png` | Editor mit Annotations |
| 7 | `editor-crop.png` | Editor Crop-Tool aktiv |
| 8 | `editor-selection.png` | Editor Selection-Adorner |
| 9 | `about-dialog.png` | Über-Dialog Tab Info |
| 10 | `about-changelog.png` | Über-Dialog Tab Changelog |
| 11 | `toast-saved.png` | Save-Toast |
| 12 | `toast-capture.png` | Capture-Toast |
| 13 | `region-overlay.png` | Region-Overlay |
| 14 | `countdown.png` | Countdown-Overlay |

### 2. Bekannter Bug — ActiveWindow-Capture mit DelaySeconds > 0

**Symptom:** `Strg+Shift+2` mit aktiver Verzögerung captured nur ein 136×39-Mini-Window statt des Vorder-Fensters.

**Diagnose:**

```text
01:56:56.612 [Info] [capture] Mode=ActiveWindow angefordert
01:57:05.939 [Info] [capture] OK: ActiveWindow (136x39) -> 20260516_0157_ActiveWindow.png
```

9 Sekunden Lücke zwischen Anforderung und Capture = aktiver Countdown. Der Countdown-Overlay (Topmost) verdrängt das User-Foreground; nach Countdown-Schließung liefert `GetForegroundWindow()` ein zufälliges OS-Mini-Window statt des ursprünglichen Ziel-Fensters.

**Fix-Plan:** in `LucentScreen.ps1::$invokeCapture` muss `Get-ForegroundWindowRect` (oder direkt `GetForegroundWindow()`) **vor** dem Countdown gemerkt werden — Stelle ist Zeile ~228 (`if ($delay -gt 0) { Show-CountdownOverlay … }`). Dann an `Invoke-Capture` als Pre-Captured-Hwnd weitergeben.

Workaround bis dahin: vor jedem ActiveWindow-Capture per `Strg+Shift+R` Verzögerung resetten.

**Niedrige Prio**, weil betroffen sind nur ActiveWindow-Captures + Doku-Screenshots, und der Workaround ist trivial.

### 3. Optionale Folge-Themen

- **AP 10 (Politur):** DPI-Tests Multi-Monitor, gesperrte-Datei-/voller-Datenträger-Behavior, README. Siehe `todo.md`.
- **AP 11 (Packaging):** Launcher-EXE + Signing + MSI-Übergabe. Siehe `todo.md`.
- **Mermaid-Render-Pipeline:** `./run.ps1 m` braucht `mmdc` (Node.js + `npm i -g @mermaid-js/mermaid-cli`). Aktuell sind die Mermaid-Diagramme nur als `.mmd`-Quellen + Codeblöcke in den Markdowns; Zensical hat keinen Default-Render-Plugin → die landen als Codeblöcke in der Site. In der `LucentScreen.docs.html` werden sie clientseitig via CDN gerendert. Wenn Tobias mmdc installiert: `./run.ps1 m` → SVG-Files → die Markdowns referenzieren die SVGs.

## Wiedereinstieg (Befehle)

```powershell
cd C:\_Projects\lucent-job-luScreen
git status
git log --oneline -5
.\run.ps1 p             # Parse-Check (sollte 67/67 clean)
.\run.ps1 l             # PSSA (sollte 0 Findings)
.\run.ps1 S             # App stoppen falls läuft (vor Pester pflicht)
.\run.ps1 t             # Pester (sollte 110/110 grün, 1 skipped)
.\run.ps1 s             # App starten
.\run.ps1 d             # Doku-Site bauen + im Standard-Browser öffnen
explorer LucentScreen.docs.html   # Single-Page-Doku
```

## Architektur-Snapshot

```
src/
  core/
    capture.psm1       Get-AllScreens, Capture-Rect, Save-Capture, Invoke-Capture
    clipboard.psm1     Convert-BitmapToBitmapSource, Set-ClipboardImage
    config.psm1        Read-Config, Save-Config (Schema 1-6 mit Migration)
    editor.psm1        Format-EditedFilename, Save-EditedImage, Get-ArrowGeometry
    history.psm1       Get-HistoryItems, Open-/Show-/Remove-/Copy-HistoryFile
    hotkeys.psm1       Register-AllHotkeys, Invoke-HotkeyById
    logging.psm1       Write-LsLog (Mutex, 7-Tage-Rotation)
    native.psm1        P/Invoke (DPI, Cursor, Window, Hotkey)
    xaml-loader.psm1   Load-Xaml, Get-XamlControls, Set-AppDefaultIcon, Set-AppWindowIcon
  ui/
    about-dialog.psm1     CSC-Stil mit Tabs Info+Changelog
    capture-toast.psm1    Glyph-konfigurierbar
    config-dialog.psm1    Hotkey-Slots inkl. HistoryOpen, IconSize-Slider
    countdown-overlay.psm1
    editor-window.psm1    Tools, Crop, Selection-Adorner, Eraser, Save-Auto-Close
    history-window.psm1   7 MDL2-Icon-Buttons + Multi-Copy
    region-overlay.psm1
    tray.psm1             Hotkey-Anzeige im Menü
  views/
    *.xaml
  LucentScreen.ps1
tools/
  Take-LuScreenshots.ps1   Halbautomatischer Screenshot-Generator
luscreen-docs/             Zensical-Site (./run.ps1 d)
  docs/
    images/luscreen/0.2.0/manifest.json   14 geplante PNGs
  mermaid-sources/                         5 .mmd-Quellen
LucentScreen.docs.html     Single-Page-Doku (Mermaid via CDN)
```

## Wichtige Memory-Punkte (alle bereits im Project-Memory)

- **PS 5.1 only** — kein Ternary, kein `?.`/`??`/`&&`/`||`, kein `$IsWindows`
- **No-NuGet** — Dev-Module aus `_deps/`
- **Keine Claude/AI-Marker** in Commits/Code/Doku
- **Setup in run.ps1** — env-vars und Stop/Start-Sequenzen gehören in run.ps1-Actions, nicht in die User-Shell
- **`C:\_Projects\.erkenntnisse\wpf-powershell-gotchas.md`** — projektübergreifender Lessons-Pool. Aktuell **9 Atoms** drin: BitmapImage-leere-Tiles, FileSystemWatcher-killt-Prozess, ScriptBlock-Closures, switch -CaseSensitive, INPC für lazy WPF-Bindings, DispatcherUnhandledException-Erweiterung, nested @() mit Operatoren, .GetNewClosure() friert Forward-Refs als $null ein, .GetNewClosure() killt $script:-Schreibzugriffe + _Underscore-Funktionen, PS 5.1 liest psm1 ohne BOM als CP-1252.
- **Datumsformat** in `erledigt.md`: `YYYYMMDD-HHMM`
- **Hash-Backfill-Regel:** `_pending_` bleibt, `git log` ist die Wahrheit

## todo.md aktueller Stand

Nur noch **AP 10** (Integration & Politur) + **AP 11** (Packaging & Verteilung). Details siehe `todo.md` im Repo-Root.

---

**TL;DR für die nächste Session:** Tobias hat die 14 Doku-Screenshots manuell aufgenommen → ich liste was unter `~/Pictures/LucentScreen/` neu ist, mit ihm zusammen jeder PNG einen Manifest-Eintrag zuordnen, in `luscreen-docs/docs/images/luscreen/0.2.0/` umbenennen, Single-Page-HTML-Platzhalter durch `<img>` ersetzen, commit + push. Danach optional ActiveWindow-Foreground-Fix oder direkt AP 10/11.
