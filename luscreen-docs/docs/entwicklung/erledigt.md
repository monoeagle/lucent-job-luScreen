# Erledigt

Chronologisches Logbuch über bereits abgeschlossene Arbeitspakete und alle Commits/Pushes.

> **Workflow:** Sobald ein Punkt in `todo.md` vollständig erledigt ist, wird er **hier** einsortiert (im AP-Block) und in `todo.md` gelöscht. So bleibt die Todo-Liste schlank.
>
> **Datumsformat:** Immer `YYYYMMDD-HHMM` (z.B. `20260515-1412`) — sortierbar, eindeutig, ohne Trennzeichen-Mehrdeutigkeit.

---

## Arbeitspakete

### AP 9 Etappe 2a — Editor-Tools, Color/Stroke, Undo/Redo — abgeschlossen `20260515-1850`

- [x] Tool-Palette als Side-Panel links (170 px): RadioButtons fuer Auswahl/Rahmen/Linie/Pfeil/Balken/Marker mit eigener Styled-Template (Selected = blauer Hintergrund)
- [x] Rahmen: `System.Windows.Shapes.Rectangle` mit Stroke, kein Fill
- [x] Linie: `System.Windows.Shapes.Line` mit `StrokeStartLineCap=Round`/`EndLineCap=Round`
- [x] Pfeil: `System.Windows.Shapes.Polyline` mit 5 Punkten (Schaft + 2 Spitzen-Schenkel); Geometrie aus `core/editor.psm1::Get-ArrowGeometry` (HeadSize skaliert mit `Stroke*4`)
- [x] Balken: gefuelltes Rectangle ohne Stroke (Redact/Schwaerzen)
- [x] Marker: gefuelltes Rectangle mit Alpha 0x66 (40 %) auf die gewaehlte Farbe -- Look wie ein Textmarker, darunterliegende Bildinhalte bleiben sichtbar
- [x] Zuschnitt-Tool (`C`): Drag-to-Select erzeugt initiales Rechteck, danach 8 Handles (4 Ecken + 4 Kanten) zum Justieren plus Drag-im-Inneren zum Verschieben. Dimmer-Overlay zeigt den abgeschnittenen Bereich abgedunkelt. `Enter` bzw. Toolbar-Button schneidet, `Esc` bzw. Toolbar-Button bricht ab. Beim Anwenden werden alle bestehenden Shapes mit `-CropOffset` translatiert; Undo/Redo-Stacks werden geleert (Translation invalidiert die alten Visual-Positionen).
- [x] Color-Palette: 8 Swatches (Rot/Orange/Gelb/Gruen/Blau/Magenta/Schwarz/Weiss) + `CurrentColor`-Anzeige
- [x] Strichstaerken-Slider 1–20 px mit Live-Label
- [x] Vektor-Layer: WPF-Shapes direkt in `ShapeLayer.Children` (Canvas-Position via `Canvas.SetLeft`/`SetTop` fuer Rectangles, X1/Y1/X2/Y2 fuer Lines, `PointCollection` fuer Polyline)
- [x] Maus-Drawing: `Add_MouseLeftButtonDown/Move/Up` auf `ShapeLayer` mit `CaptureMouse`/`ReleaseMouseCapture`; Mini-Shapes (Drag < 3 px) werden verworfen statt commited; `LostMouseCapture` raeumt Preview auf
- [x] Undo/Redo via zwei `Stack[UIElement]`-Instances; Strg+Z entfernt letzte Shape, Strg+Y stellt wieder her; jeder neue Stroke clearet Redo-Stack; Toolbar-Buttons `BtnUndo`/`BtnRedo` mit Enabled-State-Sync
- [x] Tastatur-Tools: V/R/L/A/B/M/C schalten Tool um (nur wenn Strg nicht gedrueckt — sonst kollidiert es mit Strg+V usw.)
- [x] Save-Render mit Shape-Layer: Zoom temporaer auf 1.0 zuruecksetzen, `StageRoot.UpdateLayout()`, dann `RenderTargetBitmap.Render($StageRoot)`. Anschliessend Zoom wiederherstellen. Damit landen Bitmap + Annotations in Original-Aufloesung im PNG, ohne dass ein Offscreen-Klon der Shapes gebaut werden muss.

**Artefakte:**
- `src/core/editor.psm1` — neu: `Get-ArrowGeometry -X1 -Y1 -X2 -Y2 [-HeadSize] [-HeadAngleDeg]` mit 5 Pester-Tests (5-Punkt-Reihenfolge, Spitzen-Symmetrie, Degenerate-Case bei Start==End, HeadSize-Skalierung)
- `src/views/editor-window.xaml` — Side-Panel mit Tool-RadioButtons, Color-Swatches, Stroke-Slider; Top-Toolbar erweitert um `BtnUndo`/`BtnRedo`; Window-Default-Groesse 1240x820
- `src/ui/editor-window.psm1` — Tool-State-Block, Helper-ScriptBlocks (`$createShape`, `$updateShape`, `$pushUndo`, `$doUndo`/`$doRedo`, `$applyColor`, `$brushFromColor`, `$updateUndoButtons`); Mouse-Drawing-Pipeline; Save-Pipeline gerendert ueber `$StageRoot` mit Zoom-Reset
- `tests/core.editor.Tests.ps1` — 5 neue Tests fuer `Get-ArrowGeometry`

**Implementierungs-Detail:**
- **Save ohne Offscreen-Klon:** Statt einen Klon des Stage-Inhalts (Bitmap + Shapes) offscreen aufzubauen, wird der **echte** `StageRoot` gerendert. Damit das nicht im aktuellen Zoom landet (Aufloesungs-Verlust), wird `StageScale.ScaleX`/`Y` temporaer auf 1.0 gesetzt, `UpdateLayout()` aufgerufen, RTB rendert, dann Zoom zurueck. Kein Klonen, kein doppelter Parent-Konflikt.
- **Mini-Shape-Verwerfen:** Bei `Klick ohne Drag` (∆x, ∆y < 3 px) wird die Preview-Shape verworfen statt commited — sonst entstehen Pixel-grosse Geister-Shapes.
- **`LostMouseCapture` als Sicherheits-Netz:** Falls der User Alt-Tab/Modal-Dialog auslost waehrend des Dragging, fangen wir das ab und raeumen den unvollstaendigen Shape auf.
- **Tool-Shortcut nur ohne Strg:** Wuerde sonst `Strg+V` (geplant: Paste in Etappe 3) den Tool-Modus auf 'Select' schalten.

**Quality-Stand:** Parse 65/65 clean · PSSA 0 Findings · Pester 101/101 gruen (1 skipped — STA-Guard).

**Offen fuer Etappe 2b/3:**
- Selection mit HitTest + Adorner (verschieben, loeschen einzelner Shapes)
- Radierer-Tool
- ESC-Confirm bei ungespeicherten Aenderungen
- Crop-Undo (Snapshot-basiert; aktuell loescht Crop die Annotation-Undo-Stacks)

### AP 9 Etappe 1 — Mini-Editor (Geruest + Save) — abgeschlossen `20260515-1828`

- [x] Hook aus Verlaufsfenster: Doppelklick / Enter / Kontextmenue „Editieren" oeffnet den Editor; bestehendes „Oeffnen" bleibt fuer die Default-App
- [x] Eigenes WPF-Fenster mit `Canvas` ueber `Image` (Background-Bitmap), eingebettet in `ScrollViewer` + `Grid.LayoutTransform` mit `ScaleTransform`
- [x] Zoom: Mausrad (Strg+Wheel = fein 1.1x, sonst 1.25x), Toolbar-Buttons `Fit`/`100%`/`+`/`−`, Tastatur `Strg+0`/`Strg++`/`Strg+−`
- [x] Render-Pipeline: `RenderTargetBitmap` ueber den `StageRoot`-Grid -> PNG via `PngBitmapEncoder`. Ueber den Canvas-Layer geht in Etappe 1 noch nichts drauf; das Save-Geruest steht trotzdem schon und kann in Etappe 2 unveraendert weiterverwendet werden.
- [x] Speichern: IMMER als neue Datei (`<original>_edited.png`, Postfix konfigurierbar via `Config.EditPostfix`), Kollisionsschutz mit `-2/-3` ueber `Resolve-UniqueFilename`. Editiertes Bild zusaetzlich in Clipboard.
- [x] Tastenkuerzel: `Strg+S` (Save), `Esc` (Schliessen)
- [x] Workarea-Clamping (max 1100x780, kleiner bei knapperer Monitor-Workarea)

**Artefakte:**
- `src/core/editor.psm1` — `Format-EditedFilename`, `Save-EditedImage` (BitmapSource → PNG via `PngBitmapEncoder`)
- `src/views/editor-window.xaml` — Toolbar (Save/Fit/100%/+/-/Close), `ScrollViewer` mit `StageRoot`-Grid (Image + Shape-Layer Canvas) und `LayoutTransform`-Scale, Statusbar
- `src/ui/editor-window.psm1` — `Show-EditorWindow -ImagePath [-Owner] [-Postfix]`, `BitmapFrame.Create` zum Laden, Zoom-Closures, Save-Action mit Offscreen-Grid-Render
- `tests/core.editor.Tests.ps1` — 6 Pester-Tests (Format-EditedFilename: 3 Cases, Save-EditedImage: PNG-Magic, Kollisions-Suffix, Postfix-Parameter)
- `src/LucentScreen.ps1` — Module-Imports + History-Callback reicht `EditPostfix` aus `Config` durch
- `src/ui/history-window.psm1` + `src/views/history-window.xaml` — neuer `MiEdit`-Kontextmenueintrag, `BtnOpen` + `MiOpen` bleiben als „Default-App", Doppelklick + Enter rufen jetzt den Editor, `$cmdEdit` ruft `Show-EditorWindow` und triggert Refresh

**Implementierungs-Detail:**
- **Offscreen-Render statt direktes `RenderTargetBitmap` ueber sichtbaren Stage:** Der sichtbare `StageRoot` hat eine `LayoutTransform` (Zoom). `RenderTargetBitmap` rendert Visuals **inklusive** Transform, was beim Zoom > 1 zu Aufploppen der Aufloesung fuehrt. Loesung: in der Save-Action ein temporaeres `Grid` ohne Transform mit derselben Bitmap (und spaeter den Shapes) bauen, `Measure`/`Arrange`/`UpdateLayout`, dann rendern. Zoom-State bleibt davon unberuehrt.
- **Pseudo-Code-Behind:** XAML hat `Window.Loaded`-Trigger fuer Initial-Fit, weil die ScrollViewer-`ActualWidth`/`ActualHeight` erst nach erstem Layout-Pass valide sind.
- **Doppelklick/Enter → Editor (statt Default-App):** Vorher hatte der Verlauf Doppelklick=Default-App; jetzt ist Editor die primaere Aktion, „Oeffnen" bleibt im Kontextmenue als Sekundaerpfad fuer Bildbetrachter / Vollbild-Vorschau.

**Quality-Stand:** Parse 65/65 clean · PSSA 0 Findings · Pester 96/96 gruen (1 skipped — STA-Guard).

**Bewusst noch offen (Etappe 2/3):**
- Annotations-Tools (Rahmen, Linie, Pfeil, Balken, Radierer) + Vektor-Layer
- Undo/Redo, Selection mit Adorner
- ESC-Confirm bei ungespeicherten Aenderungen

### AP 8 — Verlaufsfenster — abgeschlossen `20260515-1810`

- [x] WPF-Fenster mit `ListBox` (`WrapPanel`-ItemsPanel, VirtualizingPanel-Recycling) und `DataTemplate` für Thumbnail + Name + Zeit/Größe
- [x] Thumbnails via `BitmapFrame.Create` + `TransformedBitmap`-Downscale (auf 200 px), mit `BitmapCacheOption.OnLoad` (Datei wird nicht gelockt) und `IgnoreColorProfile`
- [x] Thumbnails werden synchron im `refresh` geladen — Latenz pro Bild < 50 ms mit Downscale, bei typischen Verlaufs-Größen (< einige hundert Bilder) ohne spürbares UI-Blockieren
- [x] Sortierung neueste zuerst (`LastWriteTime` desc)
- [x] Live-Update via `DispatcherTimer`-Polling alle 2 s (Snapshot-Signatur aus Anzahl + neueste `LastWriteTime`) — `FileSystemWatcher` lief auf Worker-Thread und killte den Prozess silent
- [x] Tastatur-Navigation (ListBox-Default für Pfeile/Pos1/Ende) — sowie zusätzlich `Strg+C`, `Entf`, `Enter`/`Return`, `F5`, `Esc` als Window-PreviewKeyDown
- [x] Maus-Auswahl + Mehrfachauswahl (`SelectionMode=Extended`)
- [x] `Strg+C` kopiert das selektierte Bild in die Zwischenablage (über `Set-ClipboardImage` aus `core/clipboard.psm1`, gemeinsamer Codepfad mit der Capture-Engine)
- [x] Doppelklick / Enter öffnet die Datei aktuell mit der Default-App (`Start-Process`); Editor-Hook folgt mit AP 9
- [x] Kontextmenü pro Eintrag: Öffnen, Im Ordner zeigen, In Zwischenablage kopieren, In Papierkorb verschieben — „Editieren" verschiebt sich zu AP 9
- [x] Statuszeile: Anzahl der Bilder + Anzahl ausgewählter; Ordner-Pfad steht oben in der Toolbar; Dateigröße + Zeit pro Eintrag
- [x] Fenstergröße 1110×1080 (Workarea-clamped) — passt 5 Spalten × 5 Zeilen sichtbar auf Standard-Monitoren
- [x] Tray-Menü „Verlauf öffnen" ruft `Show-HistoryWindow -OutputDir $Config.OutputDir` (vorher Placeholder-MessageBox)

**Artefakte:**
- `src/core/history.psm1` — `Format-FileSize`, `New-HistoryItem`, `Get-HistoryFiles`, `Get-HistoryItems`, `Open-HistoryFile`, `Show-HistoryInFolder`, `Remove-HistoryItem` (Default in Papierkorb via `Microsoft.VisualBasic.FileIO.FileSystem`, `-Permanent` für endgültiges Löschen), `Copy-HistoryFileToClipboard`
- `src/views/history-window.xaml` — 1110×1080 Wunschgröße, ListBox + WrapPanel + DataTemplate, ContextMenu, Toolbar mit 5 Aktionen, Statusbar
- `src/ui/history-window.psm1` — `Show-HistoryWindow -OutputDir [-Owner]`, Add-Type `LucentScreen.HistoryEntry` (INPC für `Thumbnail`-Property), `ObservableCollection<HistoryEntry>`, Polling-Loader, Workarea-Clamp
- `tests/core.history.Tests.ps1` — 14 Pester-Tests (Format-FileSize, Get-HistoryFiles-Sortierung/-Filter/-Missing-Folder, New-HistoryItem-Mapping, Get-HistoryItems-Reihenfolge, Remove-HistoryItem-NotFound/-Permanent, NotFound-Guards für Open/Reveal/Copy)
- `src/LucentScreen.ps1` — neue Module-Imports, `History`-Callback ersetzt durch echten Aufruf, `DispatcherUnhandledException`-Handler um Stack-Trace + InnerException-Chain erweitert

**Implementierungs-Detail (Hard-Won Knowledge):**
- **INPC-Klasse statt Hashtables:** WPF-Binding kann keine `[hashtable]`-Keys auflösen. Lösung: via `Add-Type` einmalig eine `LucentScreen.HistoryEntry`-Klasse mit `INotifyPropertyChanged` auf dem `Thumbnail`-Property kompilieren. Damit aktualisiert die ListBox einzelne Items, sobald das Thumbnail zugewiesen wird.
- **BitmapImage+DecodePixelWidth → leere Tiles:** Die kanonische Empfehlung „`BitmapImage` mit `DecodePixelWidth=N` + `OnLoad`" lieferte bei unseren PNGs aus `Bitmap.Save()` zuverlässig **weiße** Vorschauen — das eigentliche Bild war im Decoder, aber der UriSource-Pfad rendered nicht. `BitmapFrame.Create(uri, IgnoreColorProfile, OnLoad)` + `TransformedBitmap` für Downscale ist robust und ohne Sichtbarkeits-Artefakte.
- **Private Modul-Funktionen werden aus `.GetNewClosure()`-ScriptBlocks nicht zuverlässig aufgelöst:** Helper wie `_New-HistoryEntry` und `_Load-Thumbnail` als Modul-Funktionen mit Underscore-Präfix führten zu Laufzeitfehlern (`Die Benennung … wurde nicht erkannt`), sobald sie aus einem `Add_Click`-Handler aufgerufen wurden. Lösung: Helper als ScriptBlock-Variablen direkt in `Show-HistoryWindow` definieren, sie werden via Closure-Capture sauber an alle Event-Handler weitergereicht.
- **FileSystemWatcher in PowerShell killt den Prozess silent:** Direkter `add_Created({…})`-Handler läuft auf einem Worker-Thread; sobald in einem solchen Handler eine PowerShell-Operation eine Exception wirft (auch über `Dispatcher.BeginInvoke` marshalled), kann der Prozess ohne Dispatcher- oder AppDomain-Exception-Eintrag sterben. Stattdessen `DispatcherTimer`-Polling (2 s, Snapshot-Vergleich `Anzahl + neueste LastWriteTime`) — komplett im UI-Thread, robust, Latenz akzeptabel.
- **`run.ps1`-`switch` ohne `-CaseSensitive`:** PowerShell-`switch` ist standardmäßig case-insensitive; bei den Tasten-Paaren `s`/`S`, `l`/`L`, `d`/`D`, `t`/`T` feuerten beide Branches in derselben Aktion (Start *und* Stop in einem Aufruf, PSSA full *und* changed, …). Fix: `switch -CaseSensitive ($Code)` in `Invoke-Action`.
- **Recycle-Bin-Löschung:** `Microsoft.VisualBasic.FileIO.FileSystem.DeleteFile` mit `RecycleOption.SendToRecycleBin`. Assembly muss in PS 5.1 explizit per `Add-Type -AssemblyName Microsoft.VisualBasic` nachgeladen werden.
- **Selektions-Erhalt nach Refresh:** Vor `Items.Clear()` werden die `FullName`-Pfade der aktuell selektierten Items gemerkt und nach dem Neuaufbau in `LstItems.SelectedItems` wiederhergestellt, soweit die Dateien noch existieren.

**Quality-Stand:** Parse 59/59 clean · PSSA 0 Findings · Pester 90/90 grün (1 skipped — STA-Guard für Set-ClipboardImage).

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

### Polish — Capture-Toast — abgeschlossen `20260515-1650`

User-Wunsch nach AP 5: kurzer Visual-Hinweis oben rechts nach erfolgreichem Capture („Foto gemacht"-Effekt).

- [x] `src/views/capture-toast.xaml`: 220×62, Kamera-Glyph aus Segoe MDL2 Assets (`&#xE722;`), abgerundete Border, FadeIn (150 ms) + FadeOut (800 ms — auf User-Wunsch verlangsamt) per Storyboard
- [x] `src/ui/capture-toast.psm1` — `Show-CaptureToast -Title -Subtitle [-DurationMs]`, non-blocking; verwendet `WS_EX_TRANSPARENT|NOACTIVATE|TOOLWINDOW` (Click-Through, kein Fokus-Diebstahl); Auto-Close via DispatcherTimer + FadeOut-Storyboard
- [x] State `$script:CurrentToast`: alter Toast wird beim nächsten Aufruf gecancelt, damit sich Toasts nicht stapeln
- [x] In `$invokeCapture` nach `Save-Capture` (nur bei Erfolg): Titel „Aufgenommen", Subtitle = Dateiname + `<W>×<H>`

**Quality-Stand:** Parse 53/53 clean · PSSA 0 Findings · Pester 76/76 grün (1 skipped).

### AP 5 — Countdown-Overlay — abgeschlossen `20260515-1632`

- [x] WPF-Fenster: randlos, `Topmost`, `ShowInTaskbar=False`, `AllowsTransparency=True`
- [x] Position rechts unten auf dem Monitor unter Maus (`WorkingArea` respektiert Taskbar)
- [x] Große Zahl (48pt) auf halbtransparentem Hintergrund mit Akzent-Border
- [x] Click-through via `WS_EX_TRANSPARENT` + `WS_EX_NOACTIVATE` + `WS_EX_TOOLWINDOW` (P/Invoke `SetWindowLong`)
- [x] `DispatcherTimer` sekündlich
- [x] Overlay schließt vor Capture (Close + 80 ms Yield, Smoke zeigt: Overlay nicht im Bild)
- [x] ESC während Countdown bricht ab (`PreviewKeyDown`)
- [x] In `$invokeCapture` eingebunden: bei `DelaySeconds > 0` Overlay zuerst, dann `Invoke-Capture` mit Delay=0

**Artefakte:**
- `src/core/native.psm1` erweitert: `GetWindowLong`, `SetWindowLong`, Konstanten `GWL_EXSTYLE=-20`, `WS_EX_TRANSPARENT=0x20`, `WS_EX_TOOLWINDOW=0x80`, `WS_EX_LAYERED=0x80000`, `WS_EX_NOACTIVATE=0x08000000`
- `src/views/countdown-overlay.xaml` — 170×110, abgerundete Border mit Akzent-Stroke
- `src/ui/countdown-overlay.psm1` — `Show-CountdownOverlay -Seconds <int>` → `$true`/`$false` (Cancel). Modale Schleife via `DispatcherFrame` (kein `ShowDialog` wegen `WS_EX_NOACTIVATE`).
- `src/LucentScreen.ps1` — Countdown vor `Invoke-Capture`; Abbruch → kein Capture; Delay wird im Overlay verbraten, `Invoke-Capture` läuft dann mit `-DelaySeconds 0`

**Interaktiver Smoke-Test mit DelaySeconds=3:**
- 3× hintereinander `Ctrl+Shift+3`: jedes Mal exakt ~3 s Latenz zwischen „angefordert" und „OK" im Log
- Overlay rechts unten sichtbar, Zahl tickt 3 → 2 → 1, Overlay erscheint nicht im finalen Screenshot

**Quality-Stand:** Parse 51/51 clean · PSSA 0 Findings · Pester 76/76 grün (1 skipped) unter PS 5.1.

### AP 7 — Zwischenablage — abgeschlossen `20260515-1624`

- [x] Helper „Bitmap → Clipboard" via `Clipboard.SetImage(BitmapSource)` mit STA-Guard
- [x] Nach jedem Capture: aktuelles Bild in die Zwischenablage
- [x] Robust gegen Clipboard-Locks (Retry mit exponentiellem Backoff: 50/100/200/400/800ms, max. 5 Versuche)
- [x] „STRG+C im Verlaufsfenster" — mit AP 8 erledigt (Window-PreviewKeyDown ruft `Copy-HistoryFileToClipboard` → `Set-ClipboardImage`)

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
| 24 | `20260515-1632` | `_pending_` | — | AP 5 | Countdown-Overlay: `src/views/countdown-overlay.xaml` + `src/ui/countdown-overlay.psm1` mit `Show-CountdownOverlay`. Click-through über `SetWindowLong(GWL_EXSTYLE)` mit `WS_EX_TRANSPARENT \| WS_EX_NOACTIVATE \| WS_EX_TOOLWINDOW`. Modale Schleife via `DispatcherFrame` (statt `ShowDialog`, weil `NoActivate` Fokus-Probleme macht). `native.psm1` erweitert um WindowLong-P/Invoke. In `$invokeCapture` vor `Invoke-Capture` eingehängt; Delay wird im Overlay statt im Capture verbraten, ESC bricht ab. Smoke mit DelaySeconds=3 zeigt 3-Sekunden-Latenz und sauberes Verschwinden des Overlays vor Screenshot. |
| 25 | `20260515-1650` | `_pending_` | — | polish | Capture-Toast: `src/views/capture-toast.xaml` + `src/ui/capture-toast.psm1` mit `Show-CaptureToast` (non-blocking, Kamera-Glyph, FadeIn 150ms + FadeOut 800ms, Click-Through, NoActivate). `$script:CurrentToast` cancelt vorherigen Toast vor Anzeige des neuen. In `$invokeCapture` nach erfolgreichem Save aufgerufen. FadeOut-Dauer auf User-Wunsch von 250ms auf 800ms verlängert. |
| 26 | `20260515-1810` | `_pending_` | — | AP 8 | Verlaufsfenster: `src/core/history.psm1` (Get-HistoryItems, Open/Reveal/Remove via Microsoft.VisualBasic-Recycle-Bin, Copy-HistoryFileToClipboard wiederverwendet `Set-ClipboardImage`). `src/views/history-window.xaml` + `src/ui/history-window.psm1` mit `Show-HistoryWindow`. INPC-Klasse `LucentScreen.HistoryEntry` via Add-Type fuer Thumbnail-Binding. ListBox+WrapPanel+VirtualizingPanel-Recycling, DataTemplate mit `BitmapFrame.Create`+`TransformedBitmap` (Downscale auf 200 px) — `BitmapImage`+`DecodePixelWidth` lieferte leere Tiles. Live-Update via `DispatcherTimer`-Polling (2 s, Snapshot-Signatur) — `FileSystemWatcher` mit PS-ScriptBlock-Handlern killte den Prozess silent vom Worker-Thread aus. Fenster 1110×1080 (Workarea-clamped, 5×5-Layout). Toolbar + Kontextmenü + Statusbar; PreviewKeyDown fuer Strg+C/Entf/Enter/F5/Esc. Selektions-Erhalt nach Refresh ueber FullName-Set. Helper als ScriptBlock-Variablen (Modul-private Underscore-Funktionen wurden aus `GetNewClosure`-Bloecken nicht aufgeloest). 14 neue Pester-Tests. `LucentScreen.ps1` History-Callback ruft `Show-HistoryWindow`; `DispatcherUnhandledException` jetzt mit Stack-Trace + InnerException-Chain. |
| 27 | `20260515-1810` | `_pending_` | — | fix | `run.ps1` Switch case-sensitiv (`switch -CaseSensitive ($Code)`) — vorher feuerten `s`/`S`, `l`/`L`, `d`/`D`, `t`/`T` beide Branches in einem Aufruf (App startete und stoppte sofort, PSSA lief zweimal, Docs Build und Serve gleichzeitig). |
| 28 | `20260515-1828` | `_pending_` | — | AP 9 (1/3) | Mini-Editor Etappe 1: `src/core/editor.psm1` (Format-EditedFilename, Save-EditedImage via PngBitmapEncoder, Wiederverwendung Resolve-UniqueFilename) + 6 Pester-Tests. `src/views/editor-window.xaml` + `src/ui/editor-window.psm1`: ScrollViewer mit StageRoot-Grid (Image + Canvas-Shape-Layer), LayoutTransform-Zoom, Toolbar (Save/Fit/100%/+/-/Close), Mausrad-Zoom (Strg=fein), Strg+S/Strg+0/Strg++/-, ESC. Save baut Offscreen-Grid (kein Zoom-Aufploppen), schreibt `<name>_edited.png` (Postfix aus Config), legt das Resultat zusaetzlich ins Clipboard. Verlaufs-Hook: Doppelklick/Enter rufen jetzt den Editor, Kontextmenue um „Editieren" erweitert, „Oeffnen" bleibt fuer Default-App. Tools, Undo/Redo, ESC-Confirm folgen mit Etappe 2/3. |
| 29 | `20260515-1905` | `_pending_` | — | AP 9 (2a/3) | Editor-Tools + Color/Stroke + Undo/Redo + Crop: Side-Panel mit Tool-RadioButtons (Auswahl/Rahmen/Linie/Pfeil/Balken/Marker/Zuschneiden), 8 Color-Swatches, Stroke-Slider 1-20. Marker = gefuelltes Rect mit 40% Alpha auf gewaehlte Farbe. Crop-Tool mit 8 Handles (4 Ecken + 4 Kanten) plus Move-im-Inneren, Dimmer-Overlay, Apply via Enter/Toolbar oder Cancel via Esc, bestehende Annotations werden mit-translatiert. Mouse-Drawing via Canvas.MouseLeftButtonDown/Move/Up mit CaptureMouse + Mini-Shape-Discard (< 3 px Drag). Vektor-Layer = WPF.Shapes direkt in ShapeLayer.Children. Pfeil-Geometrie aus core/editor.psm1::Get-ArrowGeometry (5 Punkte) + 5 Tests. Undo/Redo via zwei Stack[UIElement] mit Strg+Z/Y. Tool-Shortcuts V/R/L/A/B/M/C (nur ohne Strg). Save: temporaer Zoom auf 1.0, UpdateLayout, RenderTargetBitmap auf StageRoot, Zoom zurueck. Selection-Adorner, Radierer und ESC-Confirm folgen Etappe 2b/3. |
| 32 | `20260516-0042` | `_pending_` | — | AP 9 (2b/3) | Etappe 2b/3 -- Editor-Politur abgeschlossen: (1) ESC-Confirm bei ungespeicherten Aenderungen via `Window.Closing`-Hook (faengt ESC, X-Button und Code-`Close()`-Aufrufe); `$state.IsDirty` wird in `pushUndo` gesetzt und in `cmdSave` geloescht. (2) Radierer-Tool (`E`): Klick auf Shape entfernt sie, Undo via `Kind='ShapeRemove'` (doUndo: Children.Add zurueck, doRedo: Remove). (3) Selection-Adorner: Tool=`Select` Klick auf Shape selektiert sie -- gestricheltes blaues Bounding-Box-Rectangle (`IsHitTestVisible=$false`) ueber dem Element; Background-Klick deselektiert; Drag verschiebt; `Entf` loescht. Move-Undo via `Kind='ShapeMove'` mit `Element/Dx/Dy`; Save ruft vorher `clearSelection`, damit der Adorner nicht im PNG landet. Helpers `$moveOneShape`, `$getShapeBounds`, `$selectShape`, `$clearSelection`, `$updateSelectionAdorner`. ESC-Branch erweitert (Crop -> cropCancel, Selection -> clearSelection, sonst -> Close). Tipp-Text + `E`-Tastenkuerzel ergaenzt. AP 9 abgeschlossen (Etappen 1, 2a, 2b, 3 alle done). |
| 31 | `20260516-0010` | `_pending_` | — | AP 9 (Politur) | Verlauf-Toolbar auf 7 MDL2-Icon-Buttons + Tooltips (Anzeigen/Bearbeiten/Loeschen/Speicherort/Zwischenablage/Liste/Aktualisieren); Multi-Copy via `Clipboard.SetFileDropList`; Toast (Copy-Glyph) bei Single+Multi. HistoryIconSize konfigurierbar (Slider 16-32). Editor-Save-Versatz behoben (VisualBrush statt direkter Render -- StageRoot-Centering-Offset rutschte vorher ins Bild). Konfig-Dialog: drei Bug-Fixes (`_Underscore`-Helper als ScriptBlock-Vars, `$script:DialogResult` -> `$state.Result` Hashtable-Slot, `$script:Config` Inplace-Update statt Reassign), Scrollbalken raus + `SizeToContent='Height'`. Tray-Menue: zwei neue Eintraege fuer Verzoegerung (Reset/+5sek), Trenner zwischen Verlauf und Konfig, Umlauten-Migration (BOM auf `tray.psm1`). Hotkeys: 2 neue Default-Slots (`Strg+Shift+R/T`). About-Dialog im CSC-Stil (Tabs Info+Changelog, git-config-Entwickler, OS+PS+DPI-Info). App-Icon: `assets/icon.png` als About-Header, `*.ico` (Auto-Discovery) als Tray + Window-Titelleisten via zentralem `Set-AppDefaultIcon`/`Set-AppWindowIcon` in `xaml-loader.psm1`. Filename-Schema: `yyyyMMdd_HHmm_{mode}.png` Default; Schema-Migrationen 1->2 (HistoryIconSize), 2->3 (LucentScreen_-Praefix raus), 3->4 (Verzoegerungs-Hotkeys), 4->5 (kompaktes Datum). |
| 30 | `20260515-2225` | `_pending_` | — | AP 9 (2a-fix) | Crop wieder funktional + undofaehig + Save-UX: (1) `$hits`/`$handles` von verschachteltem `@(@(...),@(...))` auf Hashtable-Arrays umgestellt -- PS 5.1 + Strict-Mode warf bei mehrzeiligen nested Arrays mit `+`/`/` `op_Addition`/`op_Division` auf `[Object[]]`, Exception wurde von WPF-Event-Dispatch still verschluckt. (2) `$cropApply` rief `& $fitToWindow`, das aber erst NACH `cropApply` definiert wird -- `.GetNewClosure()` friert die Variable als `$null` ein. Fix: Slot via `$state.FitToWindow` analog zu `RebuildCrop`. (3) `$fitToWindow` nutzt jetzt `$state.Bitmap` statt der eingefrorenen `$bitmap`-Closure, sonst Zoom-Berechnung nach Crop auf alter Bildgroesse. (4) `$c.ImgBitmap.IsHitTestVisible = $false` -- ohne das fing das Bild Maus-Events ab, bevor sie den ShapeLayer-Crop-Branch erreichten. (5) Crop ist jetzt undofaehig: UndoStack/RedoStack umgestellt von `Stack[UIElement]` auf `Stack[hashtable]` mit Dispatch-Key `Kind='Shape'|'Crop'`; Crop-Snapshot enthaelt OldBitmap/NewBitmap + Masse + Translation; doUndo/doRedo dispatchen, `$translateShapes`-Helper wiederverwendet von Apply/Undo/Redo; UndoStack.Clear()-Aufruf in cropApply entfernt -- Shape-Eintraege bleiben gueltig. (6) Save-UX: nach erfolgreichem Save schliesst der Editor automatisch und zeigt einen Fadeout-Toast mit Copy-Glyph (Segoe MDL2 0xE8C8) + Title "Gespeichert + kopiert" + Subtitle Dateiname. `Show-CaptureToast` um `-Glyph`-Param erweitert (Default Kamera); `capture-toast.xaml` TextBlock bekam `x:Name="TxtGlyph"`. `run.ps1` um `sd` (Stop -> Log loeschen -> Debug-Start mit `LUSCREEN_EDITOR_DEBUG=2`) und `lg` (letzte 80 Zeilen `editor-debug.log`) erweitert; `Action-AppStart` macht jetzt immer Vorab-Stop. Editor-Logger via `LUSCREEN_EDITOR_DEBUG`-env-var (Default 0 = aus, 1 = Logfile, 2 = + Sonden) als Insurance fuer kuenftige WPF-Bugs. Lessons (nested Arrays, Closure-Hoisting) in `_Projects/.erkenntnisse/wpf-powershell-gotchas.md`. |

**Regeln:**
- **Datumsformat ist `YYYYMMDD-HHMM`** (z.B. `20260515-1412`).
- Scope-Tag: `meta`, `scaffold`, `AP <n>`, `compat`, `fix`, `docs`, `chore`.
- Bei Force-Push oder Revert: zusätzliche Zeile mit Vermerk anhängen, **nicht** alte Zeile editieren.
- Bei mehreren Commits derselben Minute: weiter zählen — die `#` ist Wahrheits-Reihenfolge, nicht das Datum.
- **Hash bleibt `_pending_`, Push-Spalte `—`.** Hashes nicht nachtragen — `git log` ist die Wahrheit, Backfill-Commits erzeugen nur Rauschen (siehe `docs/ecosystem-playbook.md` Abschnitt 11).
