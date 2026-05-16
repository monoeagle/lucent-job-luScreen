# Projektstruktur

```
lucent-job-luScreen/
├── src/
│   ├── LucentScreen.ps1            Bootstrap, Mutex, DPI, App-Loop, Tray, Hotkeys
│   ├── core/
│   │   ├── capture.psm1            Get-AllScreens, Capture-Rect, Format-CaptureFilename, Save-Capture, Invoke-Capture
│   │   ├── clipboard.psm1          Convert-BitmapToBitmapSource, Set-ClipboardImage
│   │   ├── config.psm1             Read-Config, Save-Config, Format-Hotkey, Test-ConfigValid (Schema 1-6)
│   │   ├── editor.psm1             Format-EditedFilename, Save-EditedImage, Get-ArrowGeometry
│   │   ├── history.psm1            Get-HistoryItems, Open-/Show-/Remove-/Copy-HistoryFile…
│   │   ├── hotkeys.psm1            Convert-ModifiersToFlags, Convert-KeyNameToVirtualKey, Register/Unregister-AllHotkeys, Invoke-HotkeyById
│   │   ├── logging.psm1            Initialize-Logging, Write-LsLog (Mutex-geschützt, 7-Tage-Rotation)
│   │   ├── native.psm1             P/Invoke-Block LucentScreen.Native (DPI, Cursor, Window, Hotkey)
│   │   └── xaml-loader.psm1        Load-Xaml, Get-XamlControls, Set-AppDefaultIcon, Set-AppWindowIcon
│   ├── ui/
│   │   ├── about-dialog.psm1       Show-AboutDialog (Tabs Info + Changelog)
│   │   ├── capture-toast.psm1      Show-CaptureToast (Glyph-konfigurierbar)
│   │   ├── config-dialog.psm1      Show-ConfigDialog (mit Helpers als ScriptBlock-Vars)
│   │   ├── countdown-overlay.psm1  Show-CountdownOverlay
│   │   ├── editor-window.psm1      Show-EditorWindow (Tools, Crop, Selection, Eraser, Save)
│   │   ├── history-window.psm1     Show-HistoryWindow (Toolbar, Polling, Multi-Copy)
│   │   ├── region-overlay.psm1     Show-RegionOverlay
│   │   └── tray.psm1               Initialize-Tray (Hotkey-Anzeige im Menue)
│   └── views/
│       └── *.xaml                  Eines pro UI-Modul (about, capture-toast, config-dialog, countdown, editor, history, region)
├── tests/
│   └── core.*.Tests.ps1            Pester 5+ -- 110 Tests, 1 skipped
├── tools/
│   ├── Invoke-PSSA.ps1             PSScriptAnalyzer-Wrapper (Reports unter reports/pssa/)
│   ├── Install-PSScriptAnalyzer-Offline.ps1
│   ├── Install-Pester-Offline.ps1
│   └── Show-ConfigDialog.ps1       Standalone-Aufruf des Konfig-Dialogs (für Test)
├── assets/
│   ├── icon.png                    App-Icon (PNG, About-Header, Source für ICO)
│   ├── 55819_32x32.ico             Tray + Window-Titelleiste (Multi-Size-Auto-Discovery)
│   └── 55819_48x48.ico             dito
├── _deps/                          PSScriptAnalyzer + Pester gebundelt (offline-fähig)
├── docs/handoffs/                  Stand-Berichte für Session-Übergabe
├── luscreen-docs/                  Diese Doku-Site (Zensical, Python venv)
├── packaging/                      AP 11 (Layout, Build-Skripte, HANDOVER.md)
├── reports/                        Output von Parse / PSSA / Pester
├── CHANGELOG.md
├── CLAUDE.md                       Projekt-Kontext für AI-Assistenten
├── LucentScreen.docs.html          Offline-Single-Page-Doku
├── PSScriptAnalyzerSettings.psd1
├── README.md
├── run.ps1                         Task-Runner (s/S/sd/lg/p/l/L/t/T/a/d/D/m/h/cfg/i/ip/c)
└── todo.md                         Restplan AP 10 + AP 11
```

## Run-Tasks (`./run.ps1`)

| Buchstabe | Aktion |
|---|---|
| `p` | Parse-Check (AST aller `*.ps1`/`*.psm1`) |
| `l` / `L` | PSScriptAnalyzer (alle / nur geänderte Dateien) |
| `t` / `T` | Pester (alle / einzelne Test-Datei) |
| `a` | Audit (Parse + PSSA + Pester) |
| `s` / `S` | App Start (`-STA`) / Stop |
| `sd` | Start mit Editor-Debug (`LUSCREEN_EDITOR_DEBUG=2`) |
| `lg` | Letzte 80 Zeilen aus `editor-debug.log` |
| `cfg` | Konfig-Dialog standalone öffnen |
| `d` / `D` | Doku bauen / Live-Server (Zensical) |
| `m` | Mermaid-Diagramme rendern (`.mmd → .svg`) |
| `h` | HTML-Single-Page Status |
| `i` / `ip` | PSScriptAnalyzer / Pester offline installieren |
| `c` | `reports/` leeren |

## Reports

Alle Werkzeuge schreiben nach `reports/<tool>/`:

- `reports/pssa/pssa-report.{md,json}`
- `reports/pester/pester-report.md` + `pester-results.xml` (NUnit)
- `reports/parse/parse-report.md`
- `reports/audit/audit-yyyy-mm-dd.md` (manuell vom Auditor-Agent erzeugt)

## Module-Konventionen

- Jedes Modul: `#Requires -Version 5.1` + `Set-StrictMode -Version Latest` als erste zwei Zeilen.
- Funktionen sind entweder exportiert oder fangen mit `_` an (privat).
- `Export-ModuleMember -Function …` als letzte Zeile, nur die public-Funktionen.
- **Wichtig**: Modul-private `_`-Funktionen sind aus `.GetNewClosure()`-Closures NICHT erreichbar. Helper, die in WPF-Click-Handlern landen, **müssen als ScriptBlock-Variablen** im Funktions-Scope definiert werden. Siehe [Stolpersteine](stolpersteine.md).
