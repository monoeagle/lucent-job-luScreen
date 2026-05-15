# reports/

Alle automatisierten Reports landen hier — sauber nach Werkzeug getrennt.
Inhalte werden regelmäßig überschrieben; vor Releases gehören Snapshots
in `reports/<tool>/history/yyyy-mm-dd_HHmm/`.

## Aufbau

```
reports/
├── pssa/
│   ├── pssa-report.md      ← menschenlesbar, gruppiert nach Severity/Regel/Datei
│   ├── pssa-report.json    ← Raw — Quelle für Diff-Vergleiche und den auditor-Agent
│   └── history/            ← optional, Snapshot pro Release
├── pester/
│   ├── pester-report.md
│   ├── pester-results.xml  ← NUnit-XML (für CI / VS Code Test Explorer)
│   └── coverage.xml        ← JaCoCo (sobald Coverage aktiviert)
├── parse/
│   └── parse-report.md     ← AST-Parse-Sweep aller *.ps1/*.psm1
└── audit/
    └── audit-yyyy-mm-dd.md ← vom auditor-Agent (model: opus)
```

## Erzeugen

| Report | Befehl |
|---|---|
| Parse | `./run.ps1 p` |
| PSSA (alle) | `./run.ps1 l` |
| PSSA (Diff zu main) | `./run.ps1 L` |
| Pester | `./run.ps1 t` |
| Audit | `./run.ps1 a` → dann `auditor`-Agent |

## Auditor-Pipeline

Der **auditor**-Agent (`.claude/agents/auditor.md`, `model: opus`) konsumiert:

1. `reports/parse/parse-report.md` — Parse-Fehler
2. `reports/pssa/pssa-report.json` — alle PSSA-Findings, mapped:
   - `Error` → **Critical**
   - `Warning` → **Major**
   - `Information` → **Minor**
3. `reports/pester/pester-results.xml` — Testergebnisse

Und schreibt:

```
reports/audit/audit-2026-05-15.md
```

Datumsformat ist `yyyy-mm-dd`. Bei zwei Audits am selben Tag: `-2`, `-3`, …

## Snapshots vor Release

```powershell
$ts = Get-Date -Format 'yyyy-MM-dd_HHmm'
foreach ($tool in 'pssa','pester','parse','audit') {
    $src = "reports/$tool"
    $dst = "reports/$tool/history/$ts"
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    Get-ChildItem $src -File | Copy-Item -Destination $dst
}
```

## Ignorieren in PSSA

`reports/` ist in `tools/Invoke-PSSA.ps1` ausgeschlossen — keine Selbst-Analyse
der Reports.
