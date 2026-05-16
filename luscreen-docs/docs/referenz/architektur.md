# Architektur

LucentScreen ist eine **Windows-PowerShell-5.1-WPF-Anwendung** mit strikter Layer-Trennung. Kein Compile-Step, kein .NET-Runtime-Install — die App läuft auf jedem Windows 10/11 mit vorinstalliertem PowerShell 5.1.

## Layer-Modell

Zwei Sichten desselben Modells — UI-Schicht (welches Fenster lädt welche XAML) und Core-Schicht (welche Logik-Module von UI angezogen werden).

### UI-Schicht: Fenster + XAML

```mermaid
flowchart TB
    Boot["LucentScreen.ps1<br/>(Bootstrap + App-Loop)"]

    subgraph UI["src/ui/ — WPF-Fenster + Tray"]
        Tray["tray.psm1"]
        Editor["editor-window.psm1"]
        History["history-window.psm1"]
        Config["config-dialog.psm1"]
        About["about-dialog.psm1"]
        Region["region-overlay.psm1"]
        Countdown["countdown-overlay.psm1"]
        Toast["capture-toast.psm1"]
    end

    subgraph Views["src/views/ — XAML"]
        XEditor["editor-window.xaml"]
        XHistory["history-window.xaml"]
        XConfig["config-dialog.xaml"]
        XAbout["about-dialog.xaml"]
        XRegion["region-overlay.xaml"]
        XCountdown["countdown-overlay.xaml"]
        XToast["capture-toast.xaml"]
    end

    Boot --> Tray
    Tray --> Editor
    Tray --> History
    Tray --> Config
    Tray --> About
    Tray --> Region
    Region --> Countdown
    Editor --> Toast
    History --> Toast

    Editor --> XEditor
    History --> XHistory
    Config --> XConfig
    About --> XAbout
    Region --> XRegion
    Countdown --> XCountdown
    Toast --> XToast
```

### Core-Schicht: Logik + UI-Anbindung

```mermaid
flowchart TB
    Boot["LucentScreen.ps1"]

    subgraph UI["src/ui/ (nur als Aufrufer)"]
        UI_Editor["editor-window"]
        UI_History["history-window"]
        UI_Region["region-overlay"]
        UI_Config["config-dialog"]
    end

    subgraph Core["src/core/ — Logik"]
        Capture["capture.psm1<br/>GDI+ Region · Window · Monitor"]
        EditorCore["editor.psm1"]
        HistCore["history.psm1"]
        Hk["hotkeys.psm1<br/>(WM_HOTKEY)"]
        Cfg["config.psm1<br/>(JSON + Migration)"]
        Clip["clipboard.psm1"]
        Log["logging.psm1"]
        Native["native.psm1<br/>(P/Invoke)"]
        XL["xaml-loader.psm1"]
    end

    Boot --> Hk
    Boot --> Cfg
    Boot --> Log

    UI_Editor --> EditorCore
    UI_Editor --> Clip
    UI_Editor --> XL
    UI_History --> HistCore
    UI_History --> Clip
    UI_History --> XL
    UI_Region --> Capture
    UI_Config --> Cfg
    UI_Config --> XL

    Capture --> Native
    Hk --> Native
```

## Layer-Regeln

| Layer | Pfad | Darf | Darf nicht |
|---|---|---|---|
| **core** | `src/core/*.psm1` | Logik, GDI+, P/Invoke, Konfig, Logging | `PresentationFramework`, XAML, Tray |
| **ui** | `src/ui/*.psm1` | XAML laden, Fenster, Hotkey-Hook, NotifyIcon | Direkte Domain-Logik (delegiert an core) |
| **views** | `src/views/*.xaml` | Reine XAML-Markup-Dateien | Code-Behind |
| **main.ps1** | `src/LucentScreen.ps1` | Bootstrap + Application-Loop | Sonst nichts |

> `main.ps1` ist der **einzige Ort**, der `core` und `ui` zusammensteckt. `ui` darf nicht von `core` umgekehrt importiert werden.

## Bootstrap-Sequenz

```mermaid
sequenceDiagram
    participant Shell as PowerShell
    participant LS as LucentScreen.ps1
    participant Cfg as config.psm1
    participant Tray as tray.psm1
    participant Hk as hotkeys.psm1
    participant App as Application

    Shell->>LS: powershell -STA -File LucentScreen.ps1
    LS->>LS: Single-Instance-Mutex prüfen
    LS->>LS: SetProcessDpiAwarenessContext(PER_MONITOR_AWARE_V2)
    LS->>LS: Module importieren (alle psm1)
    LS->>Cfg: Read-Config (mit Migration)
    LS->>LS: Set-AppDefaultIcon (Window-Icon-Default)
    LS->>Tray: Initialize-Tray (Icon + Callbacks + HotkeyMap)
    LS->>Hk: Register-AllHotkeys (HiddenWindow + Map)
    LS->>App: Application.Run()
    Note over App: Message-Loop läuft<br/>bis Application.Shutdown
```

## Process-Modell

- **Single-Instance** via `System.Threading.Mutex` (`Global\LucentScreen.SingleInstance`).
- **STA-Apartment** zwingend für WPF + Clipboard. `LucentScreen.ps1` macht ein Self-Relaunch wenn nicht im STA gestartet.
- **DPI-Awareness** PER_MONITOR_AWARE_V2 als allererster Schritt nach Logging.
- **App-Shutdown**: tray-Eintrag „Beenden" oder `Application.Current.Shutdown()`. NotifyIcon wird per Dispose-Closure beim `Application.Exit`-Event aufgeräumt (sonst bleibt das Tray-Icon bis Mouseover stehen).

## Konventionen

- **Sprache**: UI/Doku Deutsch, Code/Variablen/Logs intern Englisch, User-sichtbare Logs Deutsch.
- **Result-Hashtables** statt Exceptions für erwartbare Fehler:
  ```powershell
  return @{ Success = $true;  Status = 'OK';    Message = '…'; Path = $path }
  return @{ Success = $false; Status = 'Error'; Message = '…'; Path = $null }
  ```
- **Config-Pfad**: `%APPDATA%\LucentScreen\config.json` (NIE im Programmordner — MSI/Per-Machine-kompatibel).
- **Logs-Pfad**: `%LOCALAPPDATA%\LucentScreen\logs\app.log` (mit 7-Tage-Rotation).
- **Default-Output**: `%USERPROFILE%\Pictures\LucentScreen\`.

→ [Projektstruktur](../entwicklung/projektstruktur.md) für die konkrete Datei-Übersicht.
