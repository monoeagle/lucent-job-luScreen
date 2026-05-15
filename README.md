# LucentScreen

Windows-Screenshot-Tool als WPF-Anwendung in Windows PowerShell 5.1. Tray-Icon, globale Hotkeys, Bereichs-/Monitor-/Fenster-Capture, Editor, Verlauf. Verteilung als signiertes Bundle → MSI. **Keine externen Module zur Laufzeit nötig** — nur OS-eingebaute WPF/GDI+.

## Einstieg

```powershell
# Voraussetzungen prüfen + installieren
./run.ps1 prereqs

# App starten (STA-Apartment wird automatisch sichergestellt)
./run.ps1 s

# Interaktives Menü
./run.ps1
```

## Struktur

| Ordner | Inhalt |
|---|---|
| `src/` | Anwendungscode (`LucentScreen.ps1`, `core/`, `ui/`, `views/`) |
| `tests/` | Pester-Tests |
| `tools/` | Helper-Skripte (PSSA, Bundle, Setup) |
| `packaging/` | MSI-Übergabe & Signing-Bundle |
| `docs/` | Entwickler-/Design-Doku (intern) |
| `luscreen-docs/` | Zensical-Site (publizierte Anwender-Doku) |
| `reports/` | PSSA/Pester/Audit-Berichte |
| `.erkenntnisse/` | Kurze Lerneinträge (siehe `.erkenntnisse/README.md`) |

Volle Konventionen und Architekturregeln: [`CLAUDE.md`](CLAUDE.md).

## Dokumentation

- **Single-Page-HTML:** [`LucentScreen.docs.html`](LucentScreen.docs.html) — eigenständig, ohne Web-Server lesbar
- **Site (Zensical):** `./run.ps1 d` → Build + Browser-Open. `./run.ps1 D` für Live-Server.
- **Architektur intern:** [`docs/Architektur.md`](docs/Architektur.md)

## Lizenz / Maintainer

Internes Lucent-Hub-Tool.
