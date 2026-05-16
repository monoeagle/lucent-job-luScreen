# LucentScreen — Arbeitspakete

Windows Screenshot-Tool als PowerShell-basierte **WPF-Anwendung** mit Tray-Integration, Hotkeys, Editor und Verlauf. Verteilung als signiertes Paket → MSI vom Softwareverteilteam.

Reihenfolge: von unten nach oben aufbauend — erst Grundgerüst (Tray, Konfig), dann Capture-Kern, dann Persistenz/Verlauf, dann Editor, dann Packaging/Verteilung. Innerhalb eines Pakets sind die Häkchen in empfohlener Bearbeitungsreihenfolge sortiert.

**UI-Stack:** WPF (XAML in PS via `[Windows.Markup.XamlReader]::Parse`). Tray-Icon kommt aus `System.Windows.Forms.NotifyIcon` — WPF hat keinen eigenen Tray, das ist Standard-Praxis und wird mit-geladen.

---

> Erledigte Arbeitspakete + Commit/Push-Log siehe [`luscreen-docs/docs/entwicklung/erledigt.md`](../luscreen-docs/docs/entwicklung/erledigt.md).

## AP 10 — Integration & Politur

- [ ] End-to-End-Smoketest jeder Capture-Modus auf Single- und Multi-Monitor
- [ ] DPI-Skalierungs-Test (100 %, 150 %, 200 %, gemischte Monitore — gerade WPF + GDI-Capture ist hier heikel)
- [ ] Verhalten bei gesperrter Datei / vollem Ziel-Datenträger / fehlenden Schreibrechten
- [ ] README mit Installation, Start, Hotkeys, FAQ

---

## Restplan (Meilensteine)

> M1–M5 abgeschlossen — siehe [`erledigt.md`](../luscreen-docs/docs/entwicklung/erledigt.md). Offene Etappen:

1. **M6 — Politur:** AP 10 (DPI-Tests, Sprach-Resources, Autostart, README)

---

## Erledigt + Commit-Log

Chronologische Liste aller fertiggestellten Arbeitspakete inkl. Commit-/Push-Tabelle in [`luscreen-docs/docs/entwicklung/erledigt.md`](../luscreen-docs/docs/entwicklung/erledigt.md) (Datumsformat `YYYYMMDD-HHMM`).

**Workflow:**
- Sobald ein AP-Block hier vollständig abgehakt ist, wandert er als Eintrag in `erledigt.md` und wird hier gelöscht.
- Vor jedem `git commit` neuen Eintrag in der Tabelle in `erledigt.md` anlegen; Hash bleibt `_pending_`, Push-Spalte `—` (siehe Hash-Backfill-Regel im ecosystem-playbook).
