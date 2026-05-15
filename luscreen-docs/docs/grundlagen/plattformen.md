# Plattformen

| Komponente | Anforderung |
|---|---|
| Windows | 10 (Build 1809+) oder 11 |
| PowerShell | Windows PowerShell 5.1 (`powershell.exe`) |
| .NET | 4.7.2+ — im OS enthalten |
| Apartment | STA (wird automatisch via Self-Relaunch sichergestellt) |
| DPI | PER_MONITOR_AWARE_V2 |

Nicht unterstützt: PowerShell 5.0 oder älter, PowerShell 7 (siehe Hinweis), Windows Server Core (kein WPF), macOS, Linux.

> **PowerShell 7**: aktuell nicht unterstützt. Doppelter Support kostet nur Boilerplate, und auf den Enterprise-Ziel-Hosts ist `pwsh.exe` nicht garantiert. Die Frage wird neu bewertet, sobald PS 7 flächendeckend ausgerollt ist.
