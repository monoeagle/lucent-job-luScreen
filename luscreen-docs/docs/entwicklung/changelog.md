# Changelog

Aktueller Changelog im Repo-Root: [`CHANGELOG.md`](https://github.com/monoeagle/lucent-job-luScreen/blob/main/CHANGELOG.md).

Vollständige Tabelle aller Commits + AP-Einträge: [Erledigt](erledigt.md).

## Aktuelle Version

**0.2.1** — siehe Über-Dialog (Tray → Über…) für die Live-Version.

## Schema-Versionen

Konfig-Schema (in `%APPDATA%\LucentScreen\config.json`):

- v1 — Initial
- v2 — `HistoryIconSize` (20 default)
- v3 — `LucentScreen_`-Präfix aus Default-Filename raus
- v4 — `DelayReset` + `DelayPlus5` Hotkeys
- v5 — Filename-Schema kompakt (`yyyyMMdd_HHmm_{mode}.png`)
- v6 — `HistoryOpen`-Hotkey

Alle Migrationen laufen automatisch beim Lesen — siehe [Konfiguration](../referenz/konfiguration.md).
