# Troubleshooting

> Entwicklersicht. Anwender-Troubleshooting in `luscreen-docs/docs/anleitung/`.

## App startet nicht

| Symptom | Diagnose | Lösung |
|---|---|---|
| `InvalidOperationException: STA required` | falsches Apartment | `pwsh -STA -File ./src/LucentScreen.ps1` |
| Stillschweigend kein Fenster | Mutex blockiert (zweite Instanz) | `Get-Process pwsh` prüfen, PID-File löschen |
| `Cannot find type [...]` | `Add-Type` nicht ausgeführt | Modul-Reihenfolge in `LucentScreen.ps1` prüfen |
| `File not found: src/views/*.xaml` | XAML-Pfad relativ falsch | `$PSScriptRoot`-basierte Pfade nutzen |

## Hotkeys reagieren nicht

1. `RegisterHotKey` schlägt fehl wenn Kombination bereits vergeben → `GetLastError` loggen, dem User einen alternativen Vorschlag machen
2. Falsches HWND im `HwndSource.AddHook` → muss das Hidden-Window sein, nicht ein UI-Fenster
3. `WM_HOTKEY` = `0x0312` — bei falscher Konstante kommt nichts an

## Screenshot ist verschoben (Multi-Monitor)

- DPI-Awareness fehlt → `[LucentScreen.Native]::SetProcessDpiAwarenessContext(-4)` als allererste Code-Zeile
- Mixed-DPI-Setup (100% + 150%): zwischen `Screen.Bounds` (logisch) und `GetWindowRect` (physisch) unterscheiden
- Sekundärmonitor links/oben → `VirtualScreen.Left`/`Top` ist negativ, das ist korrekt

## Screenshot ist schwarz

- Hardware-Acceleration / DRM (Netflix, geschützte Videos) — kein Workaround mit GDI+
- Lock-Screen / Secure-Desktop — keine Capture möglich
- Vollbild-DirectX-Anwendung (Spiele) — `CopyFromScreen` liefert je nach Treiber Schwarz; Workaround: Windowed-Mode

## Pester-Tests schlagen sporadisch fehl

- `$TestDrive`-Leakage zwischen `It`-Blocks → unique Pfade pro Test
- Timing-Abhängigkeiten in WPF-Test → asynchrone Operations mit `Wait-For`-Helper synchronisieren
- Mock fehlt `-ModuleName` → Modul-interne Aufrufe werden nicht gemockt

## PSSA wirft Errors die kein Code-Problem sind

- Settings-Datei `PSScriptAnalyzerSettings.psd1` fehlt → `./run.ps1 l` lädt sie automatisch
- Bundle in `_deps/PSScriptAnalyzer/` ist alt → `./run.ps1 i` aktualisieren

## NotifyIcon bleibt nach Beenden sichtbar bis User darüber hovert

- Klassischer Windows-Bug, kein `NotifyIcon.Dispose()` aufgerufen
- Sicherstellen: `Application.Exit`-Handler oder explizit im Tray-Quit-Handler
