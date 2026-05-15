# LucentScreen — Projekt-Kontext für Claude

Windows-Screenshot-Tool als **WPF-Anwendung in Windows PowerShell 5.1** mit Tray-Integration, globalen Hotkeys, Editor und Verlauf. Verteilung als signiertes Paket → MSI durch das Softwareverteilteam.

> **PS 5.1 ist einziges Target.** PowerShell 7 wird nicht unterstützt (Enterprise-Hosts haben es nicht garantiert; doppelter Support kostet nur Boilerplate). Erwägen wir später erneut, wenn `pwsh.exe` flächendeckend ausgerollt ist.
> Kein PS-7-Sprachfeature nutzen: keine Ternary `? :`, keine Null-Conditional `?.`/`??`, kein `&&`/`||` in der Pipeline.
> `$IsWindows` existiert in 5.1 nicht — nie referenzieren.

> Lies vor jeder Implementierung `todo.md` (offene Arbeitspakete) und `docs/Architektur.md` (Module + Datenfluss).
> Was bereits erledigt ist, steht in `luscreen-docs/docs/entwicklung/erledigt.md` (inkl. Commit-Log).
> **Datumsformat** in Logs/Tabellen: `YYYYMMDD-HHMM` (z.B. `20260515-1412`).

---

## Architektur (nicht verhandelbar)

| Layer | Pfad | Darf | Darf nicht |
|---|---|---|---|
| **core** | `src/core/*.psm1` | Logik, GDI+, P/Invoke, Konfig, Logging | `PresentationFramework`, XAML, Tray |
| **ui** | `src/ui/*.psm1` | XAML laden, Fenster, Hotkey-Hook, NotifyIcon | Direkte Domain-Logik (delegiert an core) |
| **views** | `src/views/*.xaml` | reine XAML-Markup-Dateien | Code-Behind (Logik gehört in ui-Module) |
| **main.ps1** | `src/LucentScreen.ps1` | Bootstrap + Application-Loop | Sonst nichts |

Regel: **`main.ps1` ist der einzige Ort, der core und ui zusammensteckt.** Module untereinander dürfen `Import-Module` aufrufen, aber `ui` darf nicht von `core` umgekehrt importiert werden.

---

## STA + Single-Instance (Pflicht)

```powershell
# 1. STA prüfen -- WPF und Clipboard funktionieren sonst nicht.
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    Start-Process powershell.exe -ArgumentList '-STA','-File',$PSCommandPath
    exit
}

# 2. Single-Instance via Named-Mutex (kein File-Lock)
$mutex = [System.Threading.Mutex]::new($false, 'Global\LucentScreen.SingleInstance')
if (-not $mutex.WaitOne(0, $false)) { exit }

# 3. DPI-Awareness als allererste Zeile nach Logging
[LucentScreen.Native]::SetProcessDpiAwarenessContext(-4)  # PER_MONITOR_AWARE_V2
```

---

## Konventionen

- **Sprache:** UI/Doku **Deutsch**, Code/Variablen/Logs intern **Englisch**, User-sichtbare Logs **Deutsch**.
- **Keine Claude/AI-Marker** in Commits, Code-Kommentaren, Doku.
- **Keine globalen Variablen** (`$global:`). Innerhalb Modul: `$script:`-Scope.
- **Funktionen die fehlschlagen können**, geben strukturiertes Hashtable zurück:
  ```powershell
  return @{ Success = $true;  Status = 'OK';    Message = '…'; Path = $path }
  return @{ Success = $false; Status = 'Error'; Message = '…'; Path = $null }
  ```
- **Config-Pfad:** `%APPDATA%\LucentScreen\config.json` — NIE im Programmordner (MSI-/Per-Machine-kompatibel).
- **WPF-Disposing:** `NotifyIcon`, `Bitmap`, `Graphics`, `BitmapSource`-Streams müssen `.Dispose()` bekommen. Faustregel: jedes `New-Object` mit IDisposable → `try/finally`.
- **Hotkey-Lifecycle:** jedes `RegisterHotKey` braucht zwingenden `UnregisterHotKey`-Counterpart im Shutdown-Path.
- **PSSA-clean:** Code muss `tools/Invoke-PSSA.ps1` ohne Errors überstehen. Warnings tolerieren, dokumentieren. Konfig: `PSScriptAnalyzerSettings.psd1` im Repo-Root.

---

## Modulvorlage

```powershell
#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-Something {
    param([string]$Param)
    # implementation
}

Export-ModuleMember -Function Get-Something
```

Jede Funktion ist entweder exportiert oder fängt mit `_` an (privat).

### PS-5.1-Tabus

| Anti-Pattern | PS-5.1-Lösung |
|---|---|
| `$cond ? 'a' : 'b'` | `if ($cond) { 'a' } else { 'b' }` |
| `$x?.Property` | `if ($null -ne $x) { $x.Property }` |
| `$val ?? 'default'` | `if ($null -eq $val) { 'default' } else { $val }` |
| `cmd1 \|\| cmd2` (Pipeline-Chain) | klassisch: separater `if`-Block über `$LASTEXITCODE` |
| `$IsWindows` lesen | nicht verfügbar in 5.1 — entweder weglassen oder `($PSVersionTable.Platform -ne 'Unix')` |
| `[Type]::new(args)` für `out`-Parameter | OK; Edge-Cases mit `[ref]` testen |
| `Invoke-RestMethod -SkipCertificateCheck` | nicht in 5.1 — `[ServicePointManager]::ServerCertificateValidationCallback` setzen |

---

## Test-Konventionen (Pester 5)

```powershell
BeforeAll {
    Import-Module "$PSScriptRoot/../src/core/<modul>.psm1" -Force
}

AfterEach {
    Get-ChildItem $TestDrive -Recurse | Remove-Item -Recurse -Force -EA SilentlyContinue
}

# Mocking von Modul-internen Aufrufen IMMER mit -ModuleName
Mock -ModuleName <modul> Get-Foo { 'mock' }
```

`$TestDrive` ist innerhalb `Describe` shared — pro `It` einzigartige Pfade benutzen.

---

## Run-Tasks (`./run.ps1`)

```
p   Parse-Check (AST aller *.ps1/*.psm1)
l   PSScriptAnalyzer Lint (alle Sources)
L   PSSA nur geänderte Dateien (-OnlyChangedSinceMain)
t   Pester (alle Tests)
T   Pester (einzelne Test-Datei)
a   Audit (auditor-Agent: parse+pssa+pester+arch+doc-sync)
s   App starten (-STA)
S   App stoppen
d   Zensical-Site bauen + im Standard-Browser öffnen
D   Doku-Live-Server starten (http://127.0.0.1:8000)
h   HTML-Single-Page Doku bauen (LucentScreen.docs.html)
```

---

## Reports

Alle Werkzeuge schreiben Reports nach `reports/<tool>/`:

- `reports/pssa/pssa-report.{md,json}`
- `reports/pester/pester-report.md` + `pester-results.xml`
- `reports/parse/parse-report.md`
- `reports/audit/audit-yyyy-mm-dd.md`

Snapshots vor Release: `reports/<tool>/history/yyyy-mm-dd_HHmm/`.

---

## Specialist-Agents

Siehe `.claude/agents/*.md`. Routing-Faustregel:

- Audit → `auditor` (opus)
- PS-Modul oder Pester → `powershell-specialist` (sonnet)
- XAML/WPF-Layout/HwndSource → `wpf-ui-specialist` (sonnet)
- `Add-Type`/P/Invoke/GDI+ → `csharp-specialist` (sonnet)
- Multi-Monitor/Bereichs-Capture → `capture-engine-specialist` (sonnet)
- MSI/Transfer-Bundle/Signing → `packaging-specialist` (sonnet)
- DE-User-Doku → `doc-writer` (haiku)

---

## Future-Erwägungen

- **PS 7-Support neu evaluieren**, sobald `pwsh.exe` Standard auf den Ziel-Hosts ist (z.B. via MSI/MDM ausgerollt). Dann lassen sich Ternary/Null-Conditional/`&&`-Chains aktivieren, was Code etwas kürzer und besser lesbar macht. Bis dahin: 5.1 only, kein doppelter Support.
