# Bereich-Capture

Capture eines frei wählbaren Rechtecks. Tastenkombination: **`Strg+Shift+1`** (Default — in der Konfiguration änderbar).

## Ablauf

```mermaid
sequenceDiagram
    actor User
    participant App as LucentScreen
    participant Overlay as Region-Overlay
    User->>App: Strg+Shift+1
    App->>Overlay: Vollbild-Overlay öffnen<br/>(transparent + Crosshair)
    User->>Overlay: Maus-Drag (Klick → Ziehen → Loslassen)
    Overlay-->>App: Rect{Left, Top, Width, Height}
    App->>App: GDI+ CopyFromScreen
    App->>App: PNG speichern + Clipboard
    App->>User: Toast oben rechts
```

![Region-Overlay](../images/luscreen/0.2.0/region-overlay.png){ width=600 }

## Tipps

- **Abbruch**: `Esc` während des Overlays — kein Capture.
- **Multi-Monitor**: das Overlay deckt den **virtuellen Gesamt-Bildschirm** ab (alle Monitore zusammen). Du kannst über Monitor-Grenzen hinweg ziehen.
- **Verzögerung**: wenn `DelaySeconds > 0` (siehe [Konfiguration](../referenz/konfiguration.md)), zeigt LucentScreen vor jeder Aufnahme einen Countdown-Overlay. Praktisch z.B. um vorher noch ein Menü aufzuklappen, das bei Tastendruck verschwindet.
- **Zwischenablage**: das Bild liegt sofort als Image im Clipboard — direkt in Word/Outlook/Teams einfügbar.

![Capture-Toast](../images/luscreen/0.2.0/toast-capture.png){ width=300 }

## Speicherort

`%USERPROFILE%\Pictures\LucentScreen\<yyyyMMdd>_<HHmm>_Region.png`

Bei Kollision (zwei Aufnahmen in derselben Minute) wird `-2`, `-3`, … angehängt.

→ [Filename-Schema](../referenz/konfiguration.md#dateinamen-schema)
