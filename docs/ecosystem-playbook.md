# Lucent-Hub Project-Bootstrap-Playbook

> Wiederverwendbares Rezept für neue `lucent-job-*`-Projekte.
> Diese Vorlage wurde beim Anlegen von **LucentScreen** destilliert und sollte
> für die nächsten Projekte als Copy-Paste-Startpunkt dienen.

---

## 1. Repository-Skeleton

```
lucent-job-<name>/
├── CLAUDE.md                        # Architektur-Regeln, Konventionen, Sprache
├── README.md                        # Anwender-Einstieg
├── CHANGELOG.md                     # Keep-a-Changelog-Format
├── PSScriptAnalyzerSettings.psd1    # PSSA-Konfiguration (Projekt-spezifische Excludes)
├── run.ps1                          # Task-Runner mit Menü
├── todo.md                          # Arbeitspakete (AP 0 .. AP n)
├── <App>.docs.html                  # Single-Page-HTML-Doku (portable)
│
├── src/                             # Anwendungscode
├── tests/                           # Pester
├── tools/                           # Helper-Skripte (PSSA, Pack, Setup)
├── packaging/                       # Transfer-Bundle / MSI-Handoff
│
├── docs/                            # Entwickler-/Design-Doku (intern)
│   ├── Architektur.md
│   ├── Bedienung.md
│   ├── Entwicklung.md
│   ├── Troubleshooting.md
│   ├── lessons/                     # narrativ, session-bezogen
│   ├── superpowers/
│   │   ├── specs/                   # was + warum
│   │   └── plans/                   # wie
│   ├── handoffs/                    # Session-Übergaben
│   └── screenshots/
│
├── <name>-docs/                     # Public-Doku-Site (Zensical)
│   ├── zensical.toml
│   ├── build_docs.py
│   ├── run_<name>_docs.sh
│   └── docs/
│       ├── index.md
│       ├── grundlagen/
│       ├── anleitung/
│       ├── referenz/
│       └── entwicklung/
│
├── .erkenntnisse/                   # Kurze, kontextfreie Aha-Momente
│
├── reports/                         # Automatisierte Berichte
│   ├── pssa/
│   ├── pester/
│   ├── parse/
│   └── audit/
│
└── .claude/
    ├── agents/                      # Projekt-spezifische Specialists
    └── settings.local.json          # Permissions + Hooks
```

---

## 2. Agenten-Set (typisch)

Modell-Empfehlung:
- **Opus** — Audit, Cross-File-Reasoning, große Refactorings
- **Sonnet** — Implementation, Tests, Specialists
- **Haiku** — DE-Doku, Stil-Konsolidierung, repetitive Aufgaben

| Agent | Modell | Wann | Datei |
|---|---|---|---|
| `auditor` | opus | Audit (Parse, PSSA, Pester, Architektur, Doc-Sync) | `.claude/agents/auditor.md` |
| `powershell-specialist` | sonnet | PS-Module, Pester | `.claude/agents/powershell-specialist.md` |
| `wpf-ui-specialist` / `winforms-ui-specialist` | sonnet | XAML/WinForms-UI | `.claude/agents/<ui>-specialist.md` |
| `csharp-specialist` | sonnet | Add-Type, P/Invoke, POCOs | `.claude/agents/csharp-specialist.md` |
| `<domain>-specialist` | sonnet | Domain-spezifisch (Capture, GitLab-API, MECM, …) | `.claude/agents/<domain>-specialist.md` |
| `packaging-specialist` | sonnet | Bundle, Signing, MSI-Handoff | `.claude/agents/packaging-specialist.md` |
| `doc-writer` | haiku | DE-Anwenderdoku, HTML-Sync | `.claude/agents/doc-writer.md` |

Jede Agent-Datei hat:
- YAML-Frontmatter mit `name`, `description`, `model`, `color`, mind. 2 `<example>`-Tags
- Body mit: Projekt-Kontext, Konventionen, Patterns, Code-Beispielen, Don'ts

**Wichtig:** Agent-Definitionen enthalten den **Projekt-Namen** im Beschreibungstext, damit Claude weiß, wann der Agent zuständig ist. Generische Agents werden seltener dispatched.

---

## 3. PSSA-Integration

### Dateien

| Datei | Quelle | Zweck |
|---|---|---|
| `PSScriptAnalyzerSettings.psd1` | aus BM-Template | Projekt-spezifische Excludes |
| `tools/Invoke-PSSA.ps1` | aus BM (`tools/Invoke-PSSA.ps1`) | Lint-Runner, schreibt nach `reports/pssa/` |
| `tools/Install-PSScriptAnalyzer-Offline.ps1` | aus CSC | Offline-Bundle nach `_deps/PSScriptAnalyzer/<ver>/` |
| `tools/Install-Pester-Offline.ps1` | LucentScreen | Offline-Bundle nach `_deps/Pester/<ver>/` (3 Modi: Save-Module / -Source / -Url) |

### Settings-Template

```powershell
@{
    Severity = @('Error','Warning','Information')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',                          # run.ps1/tools/ bewusst
        'PSUseShouldProcessForStateChangingFunctions',    # UI ohne -WhatIf
        'PSUseSingularNouns',                             # Domain-Plural-Funktionen
        'PSReviewUnusedParameter',                        # Event-Handler-Signature
        'PSAvoidUsingPositionalParameters',
        'PSProvideCommentHelp'
    )
    Rules = @{
        PSUseConsistentWhitespace  = @{ Enable = $true; CheckOpenBrace = $true; ... }
        PSUseConsistentIndentation = @{ Enable = $true; IndentationSize = 4; Kind = 'space' }
    }
}
```

### `tools/Invoke-PSSA.ps1` Anpassungen pro Projekt

Im Skript die `$exclusions` anpassen — der Pfad-Filter ist Token-basiert:

```powershell
$exclusions = @('.git','.archiv','_deps','reports','docs','<name>-docs','.erkenntnisse','node_modules','packaging')
```

Nur Ordner ausschließen, die **definitiv keine** zu lintenden PS-Quellen enthalten.

---

## 4. Reports-Struktur

```
reports/
├── README.md           ← erklärt Aufbau und Lesart
├── pssa/
│   ├── pssa-report.md
│   ├── pssa-report.json
│   └── history/
├── pester/
│   ├── pester-report.md
│   ├── pester-results.xml
│   └── coverage.xml
├── parse/
│   └── parse-report.md
└── audit/
    └── audit-<yyyy-mm-dd>.md
```

**Konvention:**
- Tool schreibt nach `reports/<tool>/<report>.{md,json,xml}`
- Snapshots vor Release nach `reports/<tool>/history/<yyyy-mm-dd_HHmm>/`
- `reports/` ist in PSSA-Exclusions

---

## 4a. PowerShell-Version-Target

`lucent-job-*`-Projekte haben **Windows PowerShell 5.1 als Pflicht-Target**. Enterprise-Hosts (User-PCs nach MSI-Install) haben oft kein PS 7.

Dev und Test darf 7+ nutzen, aber die Runtime-Artefakte (`src/`, embedded Add-Type, P/Invoke) müssen 5.1-kompatibel bleiben.

**Konsequenzen:**

- `#Requires -Version 5.1` (NICHT 7.0)
- Keine Ternary `? :`, kein `?.`, kein `??`, kein `&&`/`||` in Pipeline-Chains
- `$IsWindows` nicht verwenden
- Shell-Detection in jedem `Start-Process`/`& <shell>`-Aufruf:
  ```powershell
  $shell = if (Get-Command pwsh -EA SilentlyContinue) { 'pwsh' } else { 'powershell.exe' }
  ```
- App-Runtime: **keine externen PowerShell-Module** (keine PSGallery-Abhängigkeiten zur Laufzeit). Nur OS-eingebaute Assemblies.
- Dev-Tools (PSSA, Pester): über `_deps/<Modul>/<Version>/` Offline-Bundles laden.

## 5. `run.ps1`-Menü-Standard

Drei Blöcke + Werkzeuge:

```
--- Code-Qualität ---
  p) Parse-Check
  l) PSSA Lint (alle)
  L) PSSA nur geänderte (-OnlyChangedSinceMain)
  t) Pester (alle)
  T) Pester (einzelne)
  a) Audit (Parse + PSSA + Pester + auditor-Agent)

--- App ---
  s) Start
  S) Stop
  prereqs) Voraussetzungen prüfen

--- Doku ---
  d) Zensical-Site bauen
  h) HTML-Single-Page-Status

--- Werkzeuge ---
  i)  PSSA offline installieren
  ip) Pester offline installieren
  c)  reports/ leeren
```

Direkt-Aufruf: `./run.ps1 <code>` (z.B. `./run.ps1 l`).

---

## 6. Hooks-Set (`.claude/settings.local.json`)

Empfohlene Minimal-Hooks (alle non-blocking):

1. **Parse-Check** auf `PostToolUse(Edit|Write)` für `*.ps1`/`*.psm1`
2. **PSSA-on-save** auf `PostToolUse(Edit|Write)` für `*.ps1`/`*.psm1`
3. **Doc-Sync-Reminder** auf `SessionStart` — vergleicht HTML-Single-Page mit Markdown-Quellen

**Wichtig:** Hooks werden vom Harness ausgeführt, nicht von Claude — Memory/Preferences erfüllen sie nicht.

---

## 7. Doku-Struktur (zwei Lese-Kanäle)

### Intern (`docs/`)
- Architektur, Stolpersteine, Lessons, Specs/Plans, Handoffs — für Entwickler
- Markdown only, kein Build, kein Theming

### Public-Site (`<name>-docs/`)
- Zensical (MkDocs-Material-Wrapper) — `pip install zensical`
- Sektionen: Grundlagen / Anleitung / Referenz / Entwicklung
- Build via `build_docs.py` (Python) oder `run_<name>_docs.sh` (Live-Server)

### Single-Page-HTML (`<App>.docs.html`)
- Eine Datei, embedded CSS, Dark/Light-Theme
- Spiegelt die Zensical-Site, kompakter
- Wird **manuell** vom `doc-writer`-Agent synchronisiert (kein Auto-Build)
- Vorteil: portable, kein Web-Server, offline lesbar, ideal für MSI-Übergabe an Admins
- Vorlage: `lucent-job-boundaryManager/BoundaryManager.docs.html`

---

## 8. CLAUDE.md (Skelett)

```markdown
# <Projektname> — Projekt-Kontext für Claude

<1-Satz-Beschreibung der App>

## Architektur (nicht verhandelbar)
| Layer | Pfad | Darf | Darf nicht |

## STA / Single-Instance / DPI (für WPF-Apps)
- STA-Check
- Mutex
- DPI-Awareness vor jeder UI-Initialisierung

## Konventionen
- Sprache: UI/Doku DE, Code/Logs intern EN
- **Keine Claude/AI-Marker** in Commits, Code-Kommentaren, Doku
- Keine `$global:`, nur `$script:`
- Result-Hashtable-Pattern bei fehlerbehafteten Funktionen
- Config in `%APPDATA%\<Name>\config.json`

## Modulvorlage
…

## Test-Konventionen (Pester 5)
…

## Run-Tasks (./run.ps1)
…

## Reports
…

## Specialist-Agents
…
```

---

## 9. Erkenntnisse-Format (`.erkenntnisse/`)

Drei Doku-Formen abgrenzen:

| Format | Ort | Länge | Tonalität |
|---|---|---|---|
| **Lesson** | `docs/lessons/` | 1–3 Seiten | Narrativ, Session-bezogen |
| **Erkenntnis** | `.erkenntnisse/` | 1 Absatz | Kontextfrei lesbar, generelle Regel |
| **Spec/Plan** | `docs/superpowers/` | beliebig | Implementierungsvorhaben |
| **Handoff** | `docs/handoffs/` | 1 Seite | Session-Übergabe |

Erkenntnis-Format:

```markdown
# <Eintitel-Satz>

**Warum:** 1 Satz.
**Wie anwenden:** 1–2 Sätze.
```

---

## 10. Setup-Reihenfolge (Checkliste für neues Projekt)

1. [ ] GitHub-Repo anlegen, lokal `git init`, `git config user.*` (siehe Memory)
2. [ ] `todo.md` aus erster User-Spezifikation
3. [ ] Ordner-Skeleton anlegen (Punkt 1)
4. [ ] `CLAUDE.md` mit projekt-spezifischer Architektur befüllen
5. [ ] `README.md`, `CHANGELOG.md`
6. [ ] `.claude/agents/` — mindestens `auditor`, `powershell-specialist`, ggf. UI-Specialist
7. [ ] `PSScriptAnalyzerSettings.psd1`, `tools/Invoke-PSSA.ps1` (aus BM kopieren, Excludes anpassen)
8. [ ] `tools/Install-PSScriptAnalyzer-Offline.ps1`
9. [ ] `reports/README.md` + leere Unterordner
10. [ ] `run.ps1` mit Standard-Menü
11. [ ] `docs/` Gerüst (Architektur/Bedienung/Entwicklung/Troubleshooting/lessons/superpowers/handoffs)
12. [ ] `<name>-docs/` Zensical-Setup (aus CSC kopieren, `zensical.toml` anpassen)
13. [ ] `<App>.docs.html` Bootstrap (aus BM kopieren, Inhalt anpassen)
14. [ ] `.erkenntnisse/README.md`
15. [ ] `.claude/settings.local.json` mit Permissions + Hooks
16. [ ] `docs/ecosystem-playbook.md` mit projekt-spezifischen Anpassungen ergänzen
17. [ ] Erst-Commit + Push

---

## 11. Maintenance

- **Vor jedem Push:** `./run.ps1 L` (PSSA-Diff) + `./run.ps1 t` (Pester)
- **Vor jedem Release:** `./run.ps1 a` + `auditor`-Agent + Findings beheben + HTML-Doc sync
- **Pro Architektur-Entscheidung:** Spec in `docs/superpowers/specs/`, Plan in `docs/superpowers/plans/`
- **Pro Aha-Moment:** `.erkenntnisse/<kebab>.md` (1 Absatz)
- **Session-Ende mit unfertiger Arbeit:** Handoff in `docs/handoffs/yyyy-mm-dd-<kebab>.md`

---

## Referenz-Implementierungen im Lucent-Hub

| Pattern | Vorlage |
|---|---|
| Zensical-Doc-Site | `lucent-job-CodeSigningCommander/csc-docs/` |
| Single-Page-HTML | `lucent-job-boundaryManager/BoundaryManager.docs.html` |
| PSSA-Tool | `lucent-job-boundaryManager/tools/Invoke-PSSA.ps1` |
| Agent-Set | `lucent-job-CodeSigningCommander/.claude/agents/` |
| Lessons-Format | `lucent-job-CodeSigningCommander/docs/lessons/` |
| Packaging-Bundle | `lucent-job-CodeSigningCommander/tools/pack-bundle.ps1` |
| Run-Menü | `lucent-job-boundaryManager/run.ps1` |
