# Plattformen

| Komponente | Anforderung |
|---|---|
| Windows | 10 (Build 1809+) oder 11 |
| PowerShell | **5.1** (`powershell.exe`) oder 7+ (`pwsh.exe`) |
| .NET | 4.7.2+ (bei 5.1) bzw. 6.0+ (bei 7+) — alles im OS enthalten |
| Apartment | STA (wird automatisch gestartet, mit Shell-Fallback) |
| DPI | PER_MONITOR_AWARE_V2 |

Die App startet sich bei Bedarf selbst mit `-STA` neu und wählt automatisch
`pwsh.exe` falls vorhanden, sonst `powershell.exe` (5.1). Beide unterstützen
WPF und das Clipboard im STA-Apartment.

Nicht unterstützt: PowerShell 5.0 oder älter, Windows Server Core (kein WPF), macOS, Linux.
