# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/de/1.1.0/) · Versionierung: [SemVer](https://semver.org/lang/de/).

## [Unreleased]

(noch nichts)

## [0.2.1] — 2026-05-16

### Hinzugefügt

- **Verlauf-Schloss pro Bild:** kleiner Toggle-Button rechts oben auf jedem Thumbnail. Offen = grün (Bild löschbar), zu = rot (vor versehentlichem Löschen geschützt). Default unsperrt. Persistiert als NTFS-`ReadOnly`-Attribut — überlebt App-Neustart, keine Sidecar-Datei. Im Dateisystem direkt gelöschte Bilder verschwinden weiterhin aus dem Verlauf, dort ist die Sperre nicht wirksam.
- **Single-Instance für Dialoge:** Verlauf, Konfiguration und Über-Dialog öffnen nicht mehr mehrfach, wenn ein bereits offenes Fenster durch einen zweiten Tray-Klick erneut aufgerufen wird — der vorhandene Dialog wird stattdessen in den Vordergrund geholt.

### Geändert

- **Verlauf-Toolbar:** Löschen-Button vom Anfang ans Ende der Reihe verschoben und mit eigenem Trenner abgesetzt — verringert das Risiko, beim Klicken auf Anzeigen/Bearbeiten versehentlich zu löschen.
- **Tray-Icon:** Farben werden beim Laden invertiert (Schwarz → Weiß) — bleibt auf dunkler Taskleiste lesbar. Per `Initialize-Tray -InvertIcon $false` abschaltbar.

### Behoben

- Single-Instance-Guard scheiterte beim ersten Aufruf an `Set-StrictMode -Version Latest`. Modul-Slot `$script:OpenWindow` wird jetzt zu Lade-Zeit initialisiert.

## [0.2.0] — 2026-05-16

### Hinzugefügt

**Capture & Hotkeys**

- Capture-Engine mit vier Modi: Region (Maus-Drag-Auswahl), Aktives Fenster, Monitor unter Maus, Alle Monitore (virtueller Gesamt-Bildschirm). GDI+ via `System.Drawing.Graphics::CopyFromScreen`. (AP 4)
- Globale Hotkeys via `RegisterHotKey` + `WM_HOTKEY`-Hook auf einem unsichtbaren HwndSource. Konflikt-Erkennung beim Registrieren, Re-Registrierung nach Config-Änderung. (AP 3)
- Default-Hotkeys: `Strg+Shift+1..4` für Capture-Modi, `Strg+Shift+0` Tray-Menü, `Strg+Shift+H` Verlauf öffnen, `Strg+Shift+R` Delay reset, `Strg+Shift+T` Delay +5 s.
- Countdown-Overlay vor Capture wenn `DelaySeconds > 0` — Topmost, Click-Through, ESC bricht ab. (AP 5)
- Dateinamen-Schema mit Token-Renderer (`yyyyMMdd_HHmm_{mode}.png` Default; `{postfix}` für Editor-Save), Kollisionsschutz via `-2`, `-3` …, Permission-Probe auf den Output-Ordner. (AP 6)
- Auto-Clipboard: nach jedem Capture landet das Bild zusätzlich als Image in der Zwischenablage, mit Retry-Backoff bei Clipboard-Locks. (AP 7)

**Verlauf**

- Verlaufsfenster (`Strg+Shift+H` oder Tray → Verlauf öffnen) mit Thumbnail-Grid, Live-Polling (2 s), Multi-Auswahl, 7-Icon-Toolbar (Anzeigen / Bearbeiten / Löschen / Speicherort / Clipboard / Datei-Liste / Refresh), Kontextmenü. (AP 8)
- Druck-Button: speichert das Bild aus der Zwischenablage als PNG mit Mode `DruckTaste`. Strg+V als Shortcut. `IsEnabled` folgt `Clipboard.ContainsImage()` via Poller. `Save-ClipboardImageAsPng` nutzt `PngBitmapEncoder` direkt — kein GDI+-Roundtrip.
- Umbenennen via Toolbar-Button, Kontextmenü-Eintrag oder `F2`. Validierung gegen ungültige Zeichen + Ziel-Kollision. Prompt via `Microsoft.VisualBasic.Interaction.InputBox`.
- Anti-Focus-Stealing: Verlauf + Editor erzwingen den Vordergrund per Topmost-Toggle in `SourceInitialized` — zuverlässig auch bei Tray- und Hotkey-Trigger.
- Multi-Copy als `FileDropList` — Word/Outlook fügen alle markierten Bilder ein.

**Editor**

- Mini-Editor mit Annotation-Tools (Auswahl, Rahmen, Linie, Pfeil, Balken, Marker, Radierer) + Crop, Zoom (Strg+Mausrad / 100%), 8 Farb-Swatches, Strichstärke-Slider 1–20 px. (AP 9 Etappen 1, 2a, 2b, 3)
- Crop mit 8 Handles + Dimmer-Overlay, undo-fähig.
- Selection-Adorner mit Move + Delete (Entf).
- Undo/Redo (Strg+Z / Strg+Y) für Shape, ShapeRemove, ShapeMove, Crop.
- Speichern mit `Strg+S` → `*_edited.png` + Clipboard + Save-Toast + Editor schließt automatisch.
- ESC bei ungespeicherten Änderungen → Confirm-Dialog (Ja/Nein).

**UI rund um die App**

- Tray-Icon mit Kontextmenü inkl. konfigurierter Hotkey-Anzeige rechts neben jedem Eintrag, Linksklick-Doppelklick = Region. (AP 2 + Politur)
- Konfig-Dialog mit Hotkey-Capture, Zielordner-Browser, Dateinamen-Schema, Delay-Slider, Toolbar-Icon-Größe (16–32 pt), Live-Validation und Schema-Migration. (AP 1 Teil 2 + Politur)
- Über-Dialog mit Tab `Info` (Version, System, Komponenten) und Tab `Changelog` (rendert diese Datei).
- Capture-Toast oben rechts (Kamera-Glyph) und Save-Toast (Copy-Glyph) — Click-Through, Fade-in/out, Auto-Close nach 1.4 s.

**Konfiguration & Persistenz**

- Konfig-Backend (`%APPDATA%\LucentScreen\config.json`) mit Schema v1–v6 + Migrations-Kette (Read-Config), atomarem Save (`.tmp`-Rename). (AP 1 Teil 1)
- Migrationen: HistoryIconSize-Default, neue Hotkey-Slots, Filename-Format-Defaults — User-Anpassungen bleiben unangetastet.
- Log-Pfad `%LOCALAPPDATA%\LucentScreen\logs\app.log` mit 7-Tage-Rotation + Mutex-geschütztem Append.

**Tools & Doku**

- `tools/Take-LuScreenshots.ps1` — halbautomatischer Screenshot-Generator über `manifest.json`.
- `tools/Capture-ToastShots.ps1` — rendert die Toast-Varianten headless für die Doku.
- Vollständige Zensical-Doku unter `luscreen-docs/` mit Grundlagen, Anleitungen, Referenz, Entwicklung. 9 Screenshots integriert. Layer-Modell in zwei Sichten gesplittet (UI-Schicht + Core-Schicht).
- `LucentScreen.docs.html` als Single-Page-Version für Offline-Übergabe.

### Geändert

- `run.ps1`: `Action-Screenshots` läuft per Dot-Source statt Child-Process — Errors + Output sofort sichtbar.
- Layer-Modell-Diagramm in zwei kleinere, lesbarere Mermaid-Diagramme aufgeteilt.

### Entfernt

- Packaging-Dokumentationsseite (`referenz/packaging.md`) entfernt — Verteilungs-Format ist noch offen.
- PS-7-Support entfernt — Windows PowerShell 5.1 ist einziges Target.

### Quality

- PSSA: 0 Findings.
- Pester: 118/118 grün (2 STA-Guard-Skips, in MTA nicht testbar).
- Parse-Check: 69/69 clean.

## [0.1.0] — Bootstrap

### Hinzugefügt (AP 0)

- `src/LucentScreen.ps1` — Bootstrap mit STA-Self-Relaunch, Single-Instance-Mutex, DPI-Awareness (PER_MONITOR_AWARE_V2), WPF/Drawing/Forms-Assemblies, globale Fehlerhandler (Dispatcher + AppDomain), `Application.Run()` mit `ShutdownMode=OnExplicitShutdown`.
- `src/core/native.psm1` — P/Invoke-Block `LucentScreen.Native` mit `SetProcessDpiAwarenessContext`, `RECT`-Struct.
- `src/core/logging.psm1` — `Initialize-Logging`, `Write-LsLog` mit Level-Filter + Mutex-Append + Rotation.
- `src/core/xaml-loader.psm1` — `Load-Xaml` (strippt `x:Class`), `Get-XamlControls`.
- Pester-Tests + PSSA-Setup + Agent-Definitionen + Reports-Layout + Doku-Gerüst.
