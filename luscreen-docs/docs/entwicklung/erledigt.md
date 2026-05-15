# Erledigt

Chronologisches Logbuch über bereits abgeschlossene Arbeitspakete und alle Commits/Pushes.

> **Workflow:** Sobald ein Punkt in `todo.md` vollständig erledigt ist, wird er **hier** einsortiert (im AP-Block) und in `todo.md` gelöscht. So bleibt die Todo-Liste schlank.
>
> **Datumsformat:** Immer `YYYYMMDD-HHMM` (z.B. `20260515-1412`) — sortierbar, eindeutig, ohne Trennzeichen-Mehrdeutigkeit.

---

## Arbeitspakete

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

**Regeln:**
- **Datumsformat ist `YYYYMMDD-HHMM`** (z.B. `20260515-1412`).
- Scope-Tag: `meta`, `scaffold`, `AP <n>`, `compat`, `fix`, `docs`, `chore`.
- Bei Force-Push oder Revert: zusätzliche Zeile mit Vermerk anhängen, **nicht** alte Zeile editieren.
- Bei mehreren Commits derselben Minute: weiter zählen — die `#` ist Wahrheits-Reihenfolge, nicht das Datum.
