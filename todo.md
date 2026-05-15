# LucentScreen — Arbeitspakete

Windows Screenshot-Tool als PowerShell-basierte **WPF-Anwendung** mit Tray-Integration, Hotkeys, Editor und Verlauf. Verteilung als signiertes Paket → MSI vom Softwareverteilteam.

Reihenfolge: von unten nach oben aufbauend — erst Grundgerüst (Tray, Konfig), dann Capture-Kern, dann Persistenz/Verlauf, dann Editor, dann Packaging/Verteilung. Innerhalb eines Pakets sind die Häkchen in empfohlener Bearbeitungsreihenfolge sortiert.

**UI-Stack:** WPF (XAML in PS via `[Windows.Markup.XamlReader]::Parse`). Tray-Icon kommt aus `System.Windows.Forms.NotifyIcon` — WPF hat keinen eigenen Tray, das ist Standard-Praxis und wird mit-geladen.

---

> Erledigte Arbeitspakete + Commit/Push-Log siehe [`luscreen-docs/docs/entwicklung/erledigt.md`](../luscreen-docs/docs/entwicklung/erledigt.md).


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
- [ ] OutputDir-Änderungen aus dem Konfig-Dialog zur Laufzeit übernehmen (kein App-Restart nötig — `$script:Config.OutputDir` wird beim nächsten Capture gelesen, also keine zusätzliche Logik nötig; nur sicherstellen, dass Save-Pfad lazy resolved wird)

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

## Erledigt + Commit-Log

Wird ausgelagert nach [`luscreen-docs/docs/entwicklung/erledigt.md`](../luscreen-docs/docs/entwicklung/erledigt.md). Dort findet sich die chronologische Liste aller bisher fertiggestellten Arbeitspakete sowie die Commit/Push-Tabelle (Datumsformat `YYYYMMDD-HHMM`).

**Workflow:**
- Sobald ein AP-Block hier vollständig abgehakt ist, wandert er als Eintrag in `erledigt.md` und wird hier gelöscht.
- Vor jedem `git commit` neuen Eintrag in der Tabelle in `erledigt.md` anlegen; Hash nach `git commit` und Push-Status nach `git push` nachtragen.
