# Bedienung (Entwicklersicht)

> Anwender-Bedienung in `luscreen-docs/docs/anleitung/`.
> Hier nur, was Entwickler wissen müssen, um die App zu bedienen während sie noch im Bau ist.

## Start

```powershell
./run.ps1 s       # startet -STA, PID in %LOCALAPPDATA%\LucentScreen\run\app.pid
./run.ps1 S       # stoppt
```

Direkt-Start (für Debugging):
```powershell
pwsh -STA -File ./src/LucentScreen.ps1
```

## Default-Hotkeys (Plan)

| Hotkey | Aktion |
|---|---|
| `Ctrl+Shift+1` | Bereich aufnehmen |
| `Ctrl+Shift+2` | Aktives Fenster |
| `Ctrl+Shift+3` | Monitor unter Maus |
| `Ctrl+Shift+4` | Alle Monitore |
| `Ctrl+Shift+0` | Tray-Menü anzeigen |

Anpassbar im Config-Dialog (AP 1).

## Log-Inspektion

```powershell
Get-Content "$env:LOCALAPPDATA\LucentScreen\logs\app.log" -Tail 50 -Wait
```

## Verlauf zurücksetzen

```powershell
Remove-Item "$env:APPDATA\LucentScreen\history.json"
```

## Hartes Beenden falls Tray-Beenden hängt

```powershell
Get-Process pwsh | Where-Object { $_.MainWindowTitle -eq '' } | Stop-Process
# alternativ:
$pid = Get-Content "$env:LOCALAPPDATA\LucentScreen\run\app.pid"
Stop-Process -Id $pid -Force
```
