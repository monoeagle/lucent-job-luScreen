# LucentScreen — Arbeitspakete

Windows Screenshot-Tool als PowerShell-basierte **WPF-Anwendung** mit Tray-Integration, Hotkeys, Editor und Verlauf. Verteilung als signiertes Paket → MSI vom Softwareverteilteam.

Reihenfolge: von unten nach oben aufbauend — erst Grundgerüst (Tray, Konfig), dann Capture-Kern, dann Persistenz/Verlauf, dann Editor, dann Packaging/Verteilung. Innerhalb eines Pakets sind die Häkchen in empfohlener Bearbeitungsreihenfolge sortiert.

**UI-Stack:** WPF (XAML in PS via `[Windows.Markup.XamlReader]::Parse`). Tray-Icon kommt aus `System.Windows.Forms.NotifyIcon` — WPF hat keinen eigenen Tray, das ist Standard-Praxis und wird mit-geladen.

---

## AP 0 — Projekt-Setup & Grundgerüst

- [x] Ordnerstruktur anlegen (`src/`, `src/views/` für XAML, `assets/` für Icons, `config/`, `docs/`, `packaging/`)
- [x] Einstiegsskript `LucentScreen.ps1` mit STA-Apartment-Check (`-STA` ist Pflicht für WPF und Clipboard)
- [x] Single-Instance-Mutex (verhindert Mehrfachstart)
- [x] Assemblies laden: `PresentationCore`, `PresentationFramework`, `WindowsBase`, `System.Xaml`, `System.Drawing`, `System.Windows.Forms` (nur für NotifyIcon)
- [x] XAML-Loader-Helper (`Load-Xaml` Funktion, Named-Elements per `FindName` extrahieren)
- [x] Zentrales Logging (Datei in `%LOCALAPPDATA%\LucentScreen\logs\` + optional Debug-Konsole)
- [x] Globale Fehlerbehandlung (`DispatcherUnhandledException`, `AppDomain.UnhandledException`)
- [x] App-Lifecycle: `[System.Windows.Application]::new()` + `Run()` als Message-Loop-Anker, `ShutdownMode = OnExplicitShutdown` (sonst beendet sich App beim Schließen jedes Fensters)

## AP 1 — Konfiguration

- [ ] Default-Konfig im Code (Hotkeys, Zielordner, Verzögerung, Dateinamensschema)
- [ ] Konfig-Datei `config.json` in `%APPDATA%\LucentScreen\` (User-scope, NICHT im Programmordner — wichtig für MSI/Per-Machine-Install)
- [ ] Laden/Speichern der Konfig (mit Migrations-/Default-Fallback, Schema-Version)
- [ ] Konfig-Dialog als **WPF-Fenster** (XAML)
  - [ ] Zielordner wählen (über `Microsoft.Win32` oder WinForms-FolderBrowserDialog als Fallback)
  - [ ] Hotkeys einstellen (Modifier + Taste, mit Konflikterkennung)
    - [ ] Hotkey „Bereich"
    - [ ] Hotkey „Aktives Fenster"
    - [ ] Hotkey „Monitor unter Maus"
    - [ ] Hotkey „Alle Monitore"
  - [ ] Verzögerung in Sekunden (0–30)
  - [ ] Dateinamen-Schema (Zeitstempel-Format, Postfix für Edit)
  - [ ] Speichern/Abbrechen, Live-Validierung
- [ ] Konfig-Änderungen wirken zur Laufzeit (Hotkeys neu registrieren, FileWatcher-Pfad aktualisieren)

## AP 2 — Tray-Icon & Kontextmenü

- [ ] `System.Windows.Forms.NotifyIcon` mit Programm-Icon (ICO in `assets/`)
- [ ] Tooltip (Programmname + Version)
- [ ] Kontextmenü (`ContextMenuStrip`)
  - [ ] „Bereich aufnehmen"
  - [ ] „Aktives Fenster aufnehmen"
  - [ ] „Monitor (Maus)"
  - [ ] „Alle Monitore"
  - [ ] Trenner
  - [ ] „Verlauf öffnen"
  - [ ] „Konfiguration…"
  - [ ] „Über…"
  - [ ] Trenner
  - [ ] „Beenden" (ruft `Application.Current.Shutdown()`)
- [ ] „Über"-Dialog als WPF-Fenster (Name, Version, Autor, Lizenz)
- [ ] Sauberes Dispose des NotifyIcon beim Beenden (sonst bleibt Icon bis Hover hängen)

## AP 3 — Globale Hotkeys

- [ ] P/Invoke für `RegisterHotKey` / `UnregisterHotKey` (user32.dll) via `Add-Type`
- [ ] Hidden-Window für `WM_HOTKEY` — in WPF via `HwndSource.FromHwnd` + `AddHook` an einem unsichtbaren Fenster
- [ ] Hotkey-Registry-Dictionary (ID ↔ Aktion)
- [ ] Re-Registrierung bei Konfig-Änderung
- [ ] Konfliktbehandlung (Hotkey schon vergeben → Userdialog mit Vorschlag)
- [ ] Cleanup beim Beenden (alle IDs unregistern)

## AP 4 — Capture-Engine

- [ ] DPI-Awareness via App-Manifest **oder** `SetProcessDpiAwarenessContext(PER_MONITOR_AWARE_V2)` ganz früh im Startup (vor jeglicher UI-Initialisierung)
- [ ] Multi-Monitor-Erkennung (`System.Windows.Forms.Screen.AllScreens` — funktioniert auch in WPF-Apps)
- [ ] Capture-Helfer: `System.Drawing.Bitmap` + `Graphics.CopyFromScreen` (GDI+); Konvertierung zu `BitmapSource` für WPF-Anzeige
- [ ] **Modus „Alle Monitore"**: Virtual Screen Bounding-Box (`SystemInformation.VirtualScreen`)
- [ ] **Modus „Monitor unter Maus"**: `Screen.FromPoint(Cursor.Position)`
- [ ] **Modus „Aktives Fenster"**
  - [ ] `GetForegroundWindow` + `DwmGetWindowAttribute(DWMWA_EXTENDED_FRAME_BOUNDS)` für korrekte Frame-Größe
  - [ ] Fallback `GetWindowRect` bei Fehler
- [ ] **Modus „Bereich"**
  - [ ] WPF-Vollbild-Overlay-Fenster (`WindowStyle=None`, `AllowsTransparency=True`, `Topmost=True`, über alle Monitore gestreckt)
  - [ ] Maus-Rechteck-Auswahl mit Live-Vorschau (Canvas + Rectangle-Shape)
  - [ ] ESC = Abbruch, Loslassen = Bestätigen
  - [ ] Auswahl-Bitmap aus Vollbild-Capture ausschneiden
- [ ] Speichern als PNG (lossless, mit korrekter DPI im Metadaten-Header)

## AP 5 — Verzögerter Auslöser & Countdown-Overlay

- [ ] Verzögerung aus Konfig lesen (0 = sofort)
- [ ] Countdown-Overlay als WPF-Fenster
  - [ ] Randlos (`WindowStyle=None`), `Topmost`, `ShowInTaskbar=False`
  - [ ] Unten rechts auf primärem (oder „Maus-")Monitor positionieren
  - [ ] Große Schrift, halbtransparenter Hintergrund
  - [ ] Click-through via `WS_EX_TRANSPARENT` (P/Invoke `SetWindowLong`)
  - [ ] `DispatcherTimer` tickt sekündlich runter
- [ ] **Wichtig:** Overlay verschwindet bevor Capture läuft, damit es nicht im Bild landet
  - [ ] `window.Hide()` + Dispatcher-Yield (`InvokeAsync(..., Background)`) + kurzer `Thread.Sleep(50)`, dann Screenshot
- [ ] Abbruch per ESC während Countdown

## AP 6 — Dateinamen & Speicherung

- [ ] Schema: `YYYYMMDD-HHmmss_<name>.png` (minimaler Zeitstempel)
- [ ] Edit-Variante: `YYYYMMDD-HHmmss_<name>_<postfix>.png` (Postfix aus Konfig, z. B. `edit`)
- [ ] Kollisionsschutz (Suffix `-2`, `-3`, … falls Datei existiert)
- [ ] Zielordner anlegen, falls fehlt (inkl. Berechtigungsprüfung)
- [ ] Schreiben mit `Bitmap.Save(..., ImageFormat.Png)` ODER `PngBitmapEncoder` (WPF-nativ)

## AP 7 — Zwischenablage

- [ ] Helper „Bitmap → Clipboard" via `System.Windows.Clipboard.SetImage(BitmapSource)` — STA beachten
- [ ] Nach jedem Capture: aktuellstes Bild in Clipboard
- [ ] Im Verlaufsfenster: STRG+C kopiert selektiertes Bild in Clipboard
- [ ] Robust gegen Clipboard-Locks (Retry mit Backoff, Logging)

## AP 8 — Verlaufsfenster (Bildliste)

- [ ] WPF-Fenster mit `ListBox` (oder `ItemsControl` + `WrapPanel`) und `DataTemplate` für Thumbnail+Name
- [ ] Thumbnails über `BitmapImage` mit `DecodePixelWidth` (spart RAM massiv) und `BitmapCacheOption.OnLoad` (Datei nicht gelockt halten)
- [ ] Thumbnails async in Background-Thread laden, per `Dispatcher` ins ViewModel zurück
- [ ] Sortierung neueste zuerst
- [ ] `FileSystemWatcher` für Live-Update bei neuen/gelöschten Dateien (Events auf UI-Thread marshalln)
- [ ] Tastatur-Navigation (Pfeiltasten via ListBox-Default, Pos1/Ende)
- [ ] Maus-Auswahl + optionale Mehrfachauswahl
- [ ] STRG+C → Clipboard (KeyBinding im XAML)
- [ ] Doppelklick / Enter → Editor öffnen
- [ ] Kontextmenü pro Eintrag (Öffnen, Editieren, Im Ordner zeigen, Löschen, In Clipboard kopieren)
- [ ] Statuszeile (Anzahl, Pfad, Dateigröße)

## AP 9 — Mini-Editor

- [ ] Eigenes WPF-Fenster mit `Canvas` über `Image` (Background-Bitmap)
- [ ] Zoom (Maus-Rad mit `ScaleTransform`, Fit-to-Window)
- [ ] Tool-Palette (XAML-Toolbar oder Side-Panel)
  - [ ] Rahmen (Rechteck, Konturstärke + Farbe)
  - [ ] Pfeil (Start–Ende, Spitze als Path/Polygon)
  - [ ] Linie
  - [ ] Balken (gefülltes Rechteck = Schwärzen/Redacten)
  - [ ] Radierer (entfernt Objekte aus Vektor-Layer — kein Pixel-Erase)
- [ ] Farb- und Strichstärken-Auswahl (ColorPicker, NumericUpDown / Slider)
- [ ] Vektor-Layer-Modell (`ObservableCollection<Shape>` über Bitmap-Background)
  - [ ] Undo/Redo (Command-Stack)
  - [ ] Auswählen/Verschieben/Löschen einzelner Shapes (HitTest, Adorner für Selection)
- [ ] Render-Pipeline: `RenderTargetBitmap` über Canvas → PNG via `PngBitmapEncoder`
- [ ] Speichern
  - [ ] Speichert IMMER als neue Datei mit Postfix (Original bleibt unberührt)
  - [ ] Editiertes Bild zusätzlich in Clipboard
- [ ] Tastenkürzel (STRG+Z/Y, STRG+S, ESC=Schließen mit Nachfrage bei ungespeicherten Änderungen)

## AP 10 — Integration & Politur

- [ ] End-to-End-Smoketest jeder Capture-Modus auf Single- und Multi-Monitor
- [ ] DPI-Skalierungs-Test (100 %, 150 %, 200 %, gemischte Monitore — gerade WPF + GDI-Capture ist hier heikel)
- [ ] Verhalten bei gesperrter Datei / vollem Ziel-Datenträger / fehlenden Schreibrechten
- [ ] Autostart-Option (Registry `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`) — optional in Konfig
- [ ] Sprachstrings zentralisieren (DE primär, EN optional) — `ResourceDictionary` in XAML
- [ ] README mit Installation, Start, Hotkeys, FAQ
- [ ] Versionierung + Changelog

## AP 11 — Packaging & Verteilung

**Ziel:** versioniertes, signiertes ZIP, das das Softwareverteilteam in ein MSI wickelt. Reihenfolge: erst lokal lauffähiges Bundle → dann Signatur → dann Übergabe.

### 11.1 Bundle-Layout (für MSI-Mapping)

- [ ] Soll-Layout festlegen und in `packaging/LAYOUT.md` dokumentieren:
  - [ ] `%ProgramFiles%\LucentScreen\` → Skripte, Assets, Launcher-EXE (read-only)
  - [ ] `%APPDATA%\LucentScreen\config.json` → User-Konfig (vom MSI NICHT überschrieben)
  - [ ] `%LOCALAPPDATA%\LucentScreen\logs\` → Logs
  - [ ] `%USERPROFILE%\Pictures\LucentScreen\` → Default-Zielordner für Screenshots
- [ ] Alle Pfade im Code über Helper, nie hartkodiert

### 11.2 Launcher-EXE (C#)

- [ ] Mini-C#-Projekt `LucentScreen.Launcher` (Single-File-EXE, .NET Framework 4.8 — auf jedem Win10/11 vorhanden, kein Runtime-Install nötig)
- [ ] Launcher startet `powershell.exe -STA -ExecutionPolicy AllSigned -File "<Pfad>\LucentScreen.ps1"` ohne Konsolenfenster
- [ ] Eigenes App-Icon, Versionsinformationen, Manifest mit `dpiAwareness = PerMonitorV2`
- [ ] Build-Skript (`packaging/build-launcher.ps1`) erzeugt `LucentScreen.exe` reproducible

### 11.3 Code-Signing

- [ ] Klären: Zertifikat von interner CA (vermutlich) oder Drittanbieter (Sectigo/DigiCert)?
- [ ] Build-Skript signiert ALLE `.ps1`-Skripte (`Set-AuthenticodeSignature`) und die Launcher-EXE (`signtool sign /tr <timestamp> /fd SHA256 /td SHA256`)
- [ ] Timestamp-Server pflichtmäßig setzen (sonst läuft Signatur mit Zertifikat-Ablauf aus)
- [ ] Verifikationsschritt im Build (`Get-AuthenticodeSignature` muss `Valid` zurückgeben)

### 11.4 Release-Bundle

- [ ] Build-Skript `packaging/build-release.ps1`
  - [ ] Erzeugt `release/LucentScreen-<version>/` mit fertigem Layout
  - [ ] Signiert alle Artefakte
  - [ ] Erzeugt `LucentScreen-<version>.zip` für Übergabe
  - [ ] Erzeugt `SHA256SUMS.txt`
- [ ] Versionsnummer-Schema (SemVer, in einem zentralen `version.json`)

### 11.5 Übergabe an Softwareverteilteam

- [ ] `packaging/HANDOVER.md` mit:
  - [ ] Soll-Installationspfade (siehe 11.1)
  - [ ] Welche Dateien per User / per Machine
  - [ ] Autostart-Empfehlung (HKCU\…\Run-Eintrag, optional über MSI-Eigenschaft)
  - [ ] Start-Menü-Eintrag + Icon
  - [ ] Uninstall-Verhalten: User-Daten in `%APPDATA%` BLEIBEN, Programmdateien werden entfernt
  - [ ] Upgrade-Verhalten (MSI Major-Upgrade-Code festlegen)
  - [ ] Liste der signierten Artefakte + Zertifikats-Thumbprint
  - [ ] Mindest-OS: Windows 10 1809+, PowerShell 5.1 (vorinstalliert)
  - [ ] Empfohlene Group-Policy: ExecutionPolicy = `AllSigned` für betroffene User
- [ ] Test-Installation mit MSI auf einer sauberen VM (Install / Run / Uninstall / Upgrade)

### 11.6 Fallback-Verteilung (für Pilotphase, vor MSI)

- [ ] „Portable"-Modus dokumentieren: ZIP entpacken, `LucentScreen.exe` starten — keine Installation
- [ ] Erkennt automatisch ob portable (Config dann neben EXE) oder installed (Config in `%APPDATA%`)

## AP 12 — Optionale Erweiterungen (Backlog)

- [ ] Bild-Vorschau (Hover-Tooltip) im Verlauf
- [ ] OCR / Text-Extraktion aus Screenshot
- [ ] Upload-Hook (z. B. in S3, eigener Webdienst)
- [ ] Mehrere Speicherprofile (z. B. „Arbeit" / „Privat")
- [ ] Hotkey für „letzten Screenshot erneut in Clipboard"
- [ ] Dark-/Light-Theme für Editor und Verlauf
- [ ] Auto-Update-Check (gegen interne URL)

---

## Empfohlene Umsetzungsreihenfolge (Meilensteine)

1. **M1 — Lauffähiges Tray-Skelett:** AP 0, AP 2 (Menü ohne Funktion), AP 1 (Konfig laden/speichern minimal)
2. **M2 — Erstes Bild auf Platte:** AP 3, AP 4 (Modus „Monitor unter Maus" zuerst), AP 6
3. **M3 — Alle Capture-Modi:** restliche AP 4, AP 5
4. **M4 — Clipboard & Verlauf:** AP 7, AP 8
5. **M5 — Editor:** AP 9
6. **M6 — Politur:** AP 10
7. **M7 — Packaging & MSI-Übergabe:** AP 11 (Launcher + Signatur + Handover-Dokumente)
8. **M8 — Optional:** AP 12

---

## Commits & Pushes (chronologisch)

Tabelle pro Commit/Push — wird vor jedem Push manuell ergänzt. Reihenfolge ist Wahrheit, nicht Datum (mehrere Commits am selben Tag möglich).

| # | Datum (lokal) | Hash | Push | Scope | Beschreibung |
|---|---|---|---|---|---|
| 1 | 2026-05-15 13:02 | `a23a0fa` | ✓ | meta | Initial todo |
| 2 | 2026-05-15 13:31 | `3704a64` | ✓ | scaffold | Bootstrap LucentScreen scaffolding (Ordner, Agenten, PSSA, Reports, Doku, HTML-Single-Page, Hooks, Ecosystem-Playbook) |
| 3 | 2026-05-15 13:49 | `5e69a08` | ✓ | AP 0 | Projekt-Setup und Grundgerüst — `src/LucentScreen.ps1`, `src/core/{native,logging,xaml-loader}.psm1`, Pester-Tests (10/10), PSSA 0 Findings |
| 4 | 2026-05-15 14:12 | `9c375a7` | ✓ | compat | PS 5.1-Kompatibilität, Shell-Detection, Pester-Offline-Bundle (`tools/Install-Pester-Offline.ps1`), No-NuGet-Runtime-Doku |
| 5 | 2026-05-15 14:12 | `28313f5` | ✓ | chore | Commit-Log-Eintrag 4 mit finalem Hash nachgetragen |

**Regeln:**
- Eintrag VOR `git commit` ergänzen (Hash und Datum nach erfolgreichem Commit nachtragen)
- `Push ✓` setzen nach `git push`
- Scope-Tag: `meta`, `scaffold`, `AP <n>`, `compat`, `fix`, `docs`, `chore`
- Bei Force-Push oder Revert: zusätzliche Zeile mit Vermerk anhängen, **nicht** alte Zeile editieren
