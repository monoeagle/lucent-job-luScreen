# Handoff 2026-05-15 — AP 9 Etappe 2a, Crop-Tool unfertig

## Stand

- **Branch:** `main`
- **Letzter gepushter Commit:** `5ecf650` (AP 9 Etappe 1 — Editor-Gerüst + Save)
- **WIP (uncommitted bzw. WIP-Commit, siehe unten):** AP 9 Etappe 2a — Tools, Marker, Crop
- **Remote:** `monoeagle/lucent-job-luScreen` — `main` ist ohne Etappe 2a aktuell
- **Quality (lokal):** Parse 65/65 clean · PSSA 0 · Pester 101/101 grün (1 skipped) — **App vorher mit `.\run.ps1 S` stoppen, sonst kollidieren die Hotkey-Tests**
- **Test-Bilder:** `C:\Users\User\Pictures\LucentScreen\` (mehrere PNGs aus Smoke-Tests)

## Was heute (im Vergleich zum M3-Handoff) erledigt wurde

### Gepusht (`504dd10` → `5ecf650`):

- **AP 8 — Verlaufsfenster** (`02a0935`)
- **`.erkenntnisse` AP-8-Lessons** lokal angelegt (`96a079a`), dann nach `C:\_Projects\.erkenntnisse\wpf-powershell-gotchas.md` globalisiert (`504dd10`)
- **AP 9 Etappe 1 — Editor-Gerüst + Save** (`5ecf650`):
  - `src/core/editor.psm1` (Format-EditedFilename, Save-EditedImage) + 6 Pester-Tests
  - `src/views/editor-window.xaml` + `src/ui/editor-window.psm1` mit `Show-EditorWindow`, Zoom, Strg+S, ESC
  - Verlaufs-Hook: Doppelklick/Enter/Kontextmenü „Editieren" öffnen den Editor

### Lokal in der Working Copy (WIP, NICHT auf `origin`):

- **AP 9 Etappe 2a — Tools, Color/Stroke, Undo, Marker, Crop**:
  - `core/editor.psm1`: `Get-ArrowGeometry` + 5 Tests (alles grün)
  - Editor-Toolbar: 7 Tools (Auswahl/Rahmen/Linie/Pfeil/Balken/Marker/Zuschneiden), 8 Color-Swatches, Stroke-Slider 1–20
  - Mouse-Drawing für Rahmen/Linie/Pfeil/Balken/Marker (Pfeil-Geometrie aus Get-ArrowGeometry)
  - Undo/Redo via `Stack[UIElement]` + Strg+Z/Y + Toolbar-Buttons
  - Save mit Shape-Layer: temp Zoom=1.0 → `StageRoot.UpdateLayout()` → `RenderTargetBitmap` → Zoom zurück
  - Tastatur-Shortcuts V/R/L/A/B/M/C
  - Crop-Tool mit 8 Handles, Apply/Cancel-Buttons, Enter/Esc — **funktioniert NICHT** (siehe Open Issue)
- `todo.md` und `luscreen-docs/docs/entwicklung/erledigt.md` reflektieren bereits den Etappe-2a-Stand — der Tabellen-Eintrag `#29` steht schon drin

## Open Issue: Crop-Handles unsichtbar

**User-Symptom:** „beim zuschnitt sind die angriffspunkte an den ecken und den geraden nicht zu sehen und dementsprechend kann nichts zugeschnitten werden"

**Bereits versucht (alle nicht erfolgreich):**

1. Handle-Größe von 10 px auf 14 px erhöht
2. Zoom-invariante Skalierung: `handleSize = 14.0 / $state.Zoom` — damit Handles bei jedem Zoom 14 Bildschirm-px sind
3. Border zwei-stufig (schwarz dann weiß) für Kontrast auf hellen wie dunklen Bildhintergrund
4. `Panel.SetZIndex($canvas, 9999)` explizit
5. Initial-Rect 80 % der Bildfläche, sobald das Crop-Tool aktiviert wird — damit der User sofort etwas sieht
6. Handle-Fill knallig blau (`#2563EB`)

**Was noch nicht systematisch geprüft wurde:**

- Wird das Crop-Overlay-Canvas wirklich in `ShapeLayer.Children` hinzugefügt? (`$state.Crop.Overlay` nach dem Tool-Switch prüfen)
- Kommen die MouseDown-Events auf dem `ShapeLayer` überhaupt an, wenn das Tool auf Crop steht? (Das `ImgBitmap` direkt darunter könnte HitTest fangen.)
- `IsHitTestVisible = $false` auf dem inneren Canvas — sollte nur HitTest, nicht Rendering beeinflussen. Trotzdem testweise auf `$true` setzen
- `ShapeLayer.Background="Transparent"` sollte HitTest enablen, aber `IsHitTestVisible` auf dem ShapeLayer selbst prüfen
- Werden die Closures korrekt aufgelöst? `& $cropRebuildOverlay` aus dem RadioButton-Handler heraus — der RadioButton-Handler ist eine Closure mit `.GetNewClosure()`, aber `$cropRebuildOverlay` ist eine **Variable**, kein Modul-Function — Closure-Capture sollte das Bind machen

**Konkrete Debug-Reihenfolge für die nächste Session:**

1. **File-Log einbauen** (wie bei AP 8 für den Delete-Bug). In `src/ui/editor-window.psm1` einen `$dbg`-ScriptBlock mit `Add-Content` in `%LOCALAPPDATA%\LucentScreen\logs\editor-debug.log`. Logge:
   - Tool-Switch (`$state.Tool` vorher/nachher)
   - `$cropRebuildOverlay`-Aufruf (mit `$state.Crop.Rect`-Inhalt)
   - `$c.ShapeLayer.Children.Count` vor und nach `Add($canvas)`
   - `MouseLeftButtonDown` auf `ShapeLayer` (mit `$state.Tool` und `$pt`)
2. **Visual-Tree-Inspector**: in einer Test-Session per `Snoop` oder per kurzem PowerShell-Skript den `ShapeLayer.Children`-Tree dumpen, um zu sehen, ob das Crop-Canvas wirklich angehängt wird und welche Position/Größe es hat.
3. **HitTest auf ImgBitmap deaktivieren**: `$c.ImgBitmap.IsHitTestVisible = $false` setzen. Falls das die Crop-Mouse-Events erst auslöst, ist klar dass `ImgBitmap` die Events vorher gefangen hat (vor `ShapeLayer`).
4. **Alternativtest**: temporär ein einzelnes großes rotes Rechteck statisch in `ShapeLayer.Children` einfügen ohne Crop-Logik — sollte sofort sichtbar sein. Falls nicht, ist das Problem nicht der Crop-Code, sondern eine generelle Render-Reihenfolge im `StageRoot`-Grid.
5. **`Visual.Effect`-Renderer-Bug ausschließen**: `RenderOptions.ClearTypeHint`, `BitmapScalingMode` checken — manchmal blendet ein Render-Hint Children aus.

**Tip:** der Schmerz wirkt klein und konkret. Wahrscheinlich Punkt 3 oder 4 — entweder das `ImgBitmap` schluckt den HitTest oder das Crop-Overlay-Canvas wird gar nicht ins Visual-Tree gehängt.

## Andere Punkte, die in Etappe 2a noch nicht interaktiv getestet sind

Tobias hat die übrigen Tools (Rahmen, Linie, Pfeil, Balken, Marker) und Undo/Redo seit dem Etappe-2a-Build noch nicht in einer Smoke-Session durchgegangen. **Vor allem auf:**

- Pfeil-Spitze korrekt? Geometrie aus `Get-ArrowGeometry` ist getestet, aber das gerenderte Polyline-Bild ist es nicht.
- Marker mit Alpha sichtbar? Bei Wahl von Schwarz/Dunkel wird Alpha=0x66 sehr blass — eventuell ist der Marker-Effekt unauffällig.
- Save mit Annotations: kommen alle Shapes im PNG an? (Zoom-Reset-Trick getestet, aber nicht mit echten Shapes.)

## Offene Arbeitspakete

| AP | Umfang | Hinweis |
|---|---|---|
| AP 9 Etappe 2a (Cleanup) | klein | Crop-Bug fixen, restliche Tools smoketesten, commit auf `main`, push |
| AP 9 Etappe 2b | mittel | Selection-Adorner mit HitTest + Verschieben/Löschen einzelner Shapes, Radierer-Tool |
| AP 9 Etappe 3 | klein | ESC-Confirm bei ungespeicherten Änderungen, Crop-Undo via Snapshot |
| AP 10 | mittel | DPI-Tests, Sprach-Resources, README |
| AP 11 | groß | Launcher-EXE, Signing, MSI-Handover |
| AP 12 | klein | Backlog (Auto-Update, OCR, etc.) |

## Wiedereinstieg-Befehle

```powershell
cd C:\_Projects\lucent-job-luScreen
git status                                              # Stand prüfen
.\run.ps1 p                                              # Parse-Check (65/65)
.\run.ps1 l                                              # PSSA (0 Findings)
.\run.ps1 S                                              # App stoppen (vor Pester!)
.\run.ps1 t                                              # Pester (101/101 grün, 1 skipped)
.\run.ps1 s                                              # App starten
```

Editor öffnen: Tray → Verlauf → Bild doppelklicken (Doppelklick im Verlauf ruft den Editor, nicht die Default-App).

## Kontext für die nächste Session

Wichtige Memory-Punkte (alle bereits im Project-Memory):

- **PS 5.1 only** — kein Ternary, kein `?.`/`??`/`&&`/`||`, kein `$IsWindows`
- **No-NuGet** — Dev-Module aus `_deps/`
- **Keine Claude/AI-Marker** in Commits/Code/Doku
- **Datumsformat** in `erledigt.md`: `YYYYMMDD-HHMM`
- **Hash-Backfill-Regel:** `_pending_` bleibt, `git log` ist die Wahrheit
- **`C:\_Projects\.erkenntnisse\`** ist der projektübergreifende Pool für Truth-Atoms (außerhalb Git). `wpf-powershell-gotchas.md` enthält BitmapFrame-vs-BitmapImage, FSW-Worker-Thread-Kill, ScriptBlock-Closures, switch -CaseSensitive, INPC für lazy WPF-Bindings, DispatcherUnhandledException-Erweiterung

## Architektur-Snapshot

```
src/
  core/
    capture.psm1       Get-AllScreens, Capture-Rect, Format-CaptureFilename, Save-Capture, Invoke-Capture
    clipboard.psm1     Convert-BitmapToBitmapSource, Set-ClipboardImage
    config.psm1        Read-Config, Save-Config, Format-Hotkey, Test-ConfigValid
    editor.psm1        Format-EditedFilename, Save-EditedImage, Get-ArrowGeometry
    history.psm1       Get-HistoryItems, Open-HistoryFile, Show-HistoryInFolder, Remove-HistoryItem, Copy-HistoryFileToClipboard
    hotkeys.psm1       Register-AllHotkeys, Invoke-HotkeyById
    logging.psm1       Write-LsLog
    native.psm1        Add-Type P/Invoke: GetCursorPos, GetForegroundWindow, DwmGetWindowAttribute, RegisterHotKey
    xaml-loader.psm1   Load-Xaml, Get-XamlControls
  ui/
    about-dialog.psm1
    capture-toast.psm1
    config-dialog.psm1
    countdown-overlay.psm1
    editor-window.psm1     ← Crop unfertig
    history-window.psm1
    region-overlay.psm1
    tray.psm1
  views/
    *.xaml (eines pro UI-Modul)
  LucentScreen.ps1     Bootstrap, Mutex, DPI, App-Loop, Tray, Hotkeys
```
