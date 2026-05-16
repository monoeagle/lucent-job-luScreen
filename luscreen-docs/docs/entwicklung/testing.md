# Testing

LucentScreen nutzt **Pester 5+** für Unit-Tests, **PSScriptAnalyzer 1.25** für statische Analyse, und einen **Parse-Check** über alle `.ps1`/`.psm1`.

## Stand

| Tool | Aktuell |
|---|---|
| Parse-Check | 65 / 65 Dateien clean |
| PSScriptAnalyzer | 0 Findings |
| Pester | 110 / 111 grün (1 skipped) |

## Aufrufen

```powershell
.\run.ps1 p     # Parse-Check (AST aller Skripte)
.\run.ps1 l     # PSScriptAnalyzer alle
.\run.ps1 L     # PSScriptAnalyzer nur geaenderte (-OnlyChangedSinceMain)
.\run.ps1 t     # Pester alle
.\run.ps1 T     # Pester einzelne Test-Datei (interaktive Auswahl)
.\run.ps1 a     # Audit (parse + pssa + pester)
```

> **Wichtig**: `./run.ps1 S` (App stoppen) **bevor** Pester läuft, sonst kollidieren die Hotkey-Tests mit den global registrierten Hotkeys.

## Test-Konventionen

### Pester 5

```powershell
BeforeAll {
    Import-Module "$PSScriptRoot/../src/core/<modul>.psm1" -Force
}

AfterEach {
    Get-ChildItem $TestDrive -Recurse | Remove-Item -Recurse -Force -EA SilentlyContinue
}

# Mocking immer mit -ModuleName
Mock -ModuleName <modul> Get-Foo { 'mock' }
```

`$TestDrive` ist innerhalb `Describe` shared — pro `It` einzigartige Pfade verwenden.

### Test-Files

| Datei | Was getestet wird |
|---|---|
| `core.capture.Tests.ps1` | Screen-Enumeration, Capture-Rect, Filename-Format, Resolve-UniqueFilename, Save-Capture, Invoke-Capture (alle 4 Modi) |
| `core.clipboard.Tests.ps1` | BitmapToBitmapSource (frozen, threadsafe) |
| `core.config.Tests.ps1` | Defaults, Load+Migration (Schema 1→…→6), Save, Format-Hotkey, Conflict-Test, ConfigValid, alle Migration-Stufen |
| `core.editor.Tests.ps1` | Format-EditedFilename, Save-EditedImage, Get-ArrowGeometry |
| `core.history.Tests.ps1` | Format-FileSize, Get-HistoryFiles, Sort, Filter, Remove |
| `core.hotkeys.Tests.ps1` | Modifier-Flags, Key→VK, Register/Unregister mit Thread-HWND |
| `core.logging.Tests.ps1` | Init, Write, Level-Filter, Path |
| `core.xaml-loader.Tests.ps1` | Load-Xaml + Get-XamlControls |

## Reports

Alle Tools schreiben strukturierte Reports nach `reports/<tool>/`:

- `reports/parse/parse-report.md`
- `reports/pssa/pssa-report.{md,json}`
- `reports/pester/pester-report.md` + `pester-results.xml` (NUnit)

Snapshot vor Release: `reports/<tool>/history/yyyy-mm-dd_HHmm/`.

## PSScriptAnalyzer-Settings

`PSScriptAnalyzerSettings.psd1` im Repo-Root. Konfig: alle Default-Rules aktiv außer `PSReviewUnusedParameter` (zu viel Rauschen bei WPF-Event-Handlern).

## Was NICHT getestet ist

- **WPF-UI**: keine Pester-Tests für `src/ui/*.psm1`. Smoke-Test nur manuell durch Tobias mit `.\run.ps1 s`.
- **Hotkey-Konflikte zur Laufzeit**: Tests laufen mit `Hwnd=[IntPtr]::Zero`, das simuliert einen Thread-HWND ohne echte Win32-Registrierung.
- **DPI-Skalierung über mehrere Monitore**: AP 10 (DPI-Tests) noch offen.
