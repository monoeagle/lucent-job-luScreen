# Entwicklung

> Tooling, Workflow, Konventionen. Architektur in `Architektur.md`, Konventionen in `../CLAUDE.md`.

## Setup

```powershell
./run.ps1 prereqs       # Voraussetzungen prüfen
./run.ps1 i             # PSSA offline installieren (falls keine PSGallery)
```

## Täglicher Loop

```
Code/Test schreiben
   │
   ▼
./run.ps1 p          ← Parse-Check
   │
   ▼
./run.ps1 l          ← PSSA-Lint
   │
   ▼
./run.ps1 t          ← Pester
   │
   ▼
git commit (keine Claude-Marker)
```

## Vor Push

```powershell
./run.ps1 L          # PSSA nur geänderte Dateien
./run.ps1 a          # Vollaudit
```

## Vor Release

1. `./run.ps1 a` → Audit-Bericht in `reports/audit/`
2. `auditor`-Agent dispatchen → `audit-<datum>.md`
3. Findings beheben (Critical & Major)
4. `CHANGELOG.md` aktualisieren
5. `LucentScreen.docs.html` mit `doc-writer`-Agent synchronisieren
6. `packaging-specialist`-Agent → Transfer-Bundle

## Agent-Routing-Faustregel

| Aufgabe | Agent | Modell |
|---|---|---|
| PS-Modul implementieren, Tests | `powershell-specialist` | sonnet |
| XAML, WPF-Fenster, HwndSource | `wpf-ui-specialist` | sonnet |
| P/Invoke, Add-Type, POCO | `csharp-specialist` | sonnet |
| Multi-Monitor, Capture-Modi | `capture-engine-specialist` | sonnet |
| Bundle/Signing/MSI | `packaging-specialist` | sonnet |
| DE-Anwenderdoku | `doc-writer` | haiku |
| Audit/Review | `auditor` | opus |

## TDD

Pester 5, `BeforeAll`-Imports, `AfterEach`-Cleanup, `Mock -ModuleName` für Modul-internes Mocking. Details in `.claude/agents/powershell-specialist.md`.

## Stolpersteine (siehe auch `luscreen-docs/docs/entwicklung/stolpersteine.md`)

- **STA-Apartment fehlt** → WPF wirft `InvalidOperationException`. Lösung: `pwsh -STA …`.
- **DPI-Awareness fehlt** → Screenshots auf Multi-Monitor falsch geschnitten. Lösung: `SetProcessDpiAwarenessContext(-4)` als erste Code-Zeile.
- **Add-Type doppelt** → `Type 'X' already exists`. Lösung: `if (-not ('X' -as [Type])) { Add-Type … }`.
- **NotifyIcon bleibt hängen** → kein `Dispose` im Shutdown-Path. Lösung: `Application.Exit`-Handler.
- **PSCustomObject im WPF-Binding** → leere Cells. Lösung: C#-POCO via `Add-Type`.
- **`$IsWindows` zuweisen** → Read-Only-Fehler in PS7. Lösung: anderer Variablenname.

## Lessons & Erkenntnisse

- `docs/lessons/yyyy-mm-dd-<thema>.md` — datierte Lern-Sessions (länger, narrativ)
- `.erkenntnisse/<kebab>.md` — kurze Aha-Momente (1 Absatz, kontextfrei lesbar)
