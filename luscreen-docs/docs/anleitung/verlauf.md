# Verlauf

Übersicht aller Screenshots im Zielordner. Tray → **Verlauf öffnen** (oder `Strg+Shift+H`).

![Verlaufsfenster](../images/luscreen/0.2.0/history-window.png){ width=700 }

## Toolbar

Icon-Buttons (Segoe MDL2). Die Größe ist konfigurierbar (Konfig → Toolbar-Icon-Größe, 16–32 pt). **Löschen** sitzt am rechten Rand hinter einem Trenner — damit klickt man beim Greifen nach Anzeigen / Bearbeiten nicht versehentlich darauf.

| Icon | Aktion | Was es macht |
|---|---|---|
| 👁 | **Anzeigen** | Bild im Standard-Bildbetrachter (Default-App) |
| ✎ | **Bearbeiten** | Editor öffnen (= Doppelklick / `Enter`) |
| ✏ | **Umbenennen** | Markierte Datei neu benennen (`F2`) |
| 📂 | **Speicherort** | Explorer öffnet, Datei markiert |
| 📋 | **Zwischenablage** | Markiertes Bild als Image ins Clipboard (`Strg+C`) |
| 📑 | **Zwischenablage (Liste)** | Mehrere Dateien als Datei-Liste — Word/Outlook fügt alle ein |
| ↻ | **Aktualisieren** | Verlauf neu einlesen (`F5`) |
| ─ | *Trenner* | |
| 🖨 | **Druck** | Bild aus der Zwischenablage als PNG speichern (`Strg+V`; aktiv sobald Druck/Snipping/Copy ein Bild abgelegt hat) |
| ─ | *Trenner* | |
| 🗑 | **Löschen** | Markierte Bilder in den Papierkorb (gesperrte Bilder werden übersprungen) |

## Schloss pro Bild

Jedes Thumbnail bekommt rechts oben einen kleinen Schloss-Button:

- **Grün, offen** — Bild ist *nicht* gesperrt, Löschen ist erlaubt.
- **Rot, zu** — Bild ist gesperrt, der Löschen-Button überspringt es.

Klick auf das Schloss schaltet um. Default beim Speichern: offen. Der Lock-Zustand entspricht dem NTFS-`ReadOnly`-Attribut, überlebt also App-Neustarts ohne Sidecar-Datei. Wer ein gesperrtes Bild *im Dateisystem* löscht (Explorer, Shell), bekommt das Bild trotzdem aus dem Verlauf entfernt — die Sperre wirkt nur innerhalb der LucentScreen-UI.

## Tastatur

| Taste | Aktion |
|---|---|
| `Doppelklick` / `Enter` | Editor öffnen |
| `Strg+C` | Single-Bild ins Clipboard |
| `Strg+V` | Bild aus Zwischenablage speichern (Mode `DruckTaste`) |
| `F2` | Markierte Datei umbenennen |
| `Entf` | In Papierkorb |
| `F5` | Refresh |
| `Esc` | Verlauf schließen |

## Kontextmenü

Rechtsklick auf ein Bild zeigt:

![Verlauf-Kontextmenü](../images/luscreen/0.2.0/history-context.png){ width=400 }

- Editieren
- Öffnen (Default-App)
- Im Ordner zeigen
- In Zwischenablage kopieren
- ─
- Umbenennen…
- In Papierkorb verschieben

## Live-Polling

Der Verlauf aktualisiert sich automatisch alle 2 Sekunden — neue Captures erscheinen ohne manuellen Refresh. Implementierung via `DispatcherTimer` (kein `FileSystemWatcher` — der schießt unter PowerShell den Worker-Thread ab; siehe [Stolpersteine](../entwicklung/stolpersteine.md)).

## Multi-Auswahl

`Strg+Klick` / `Shift+Klick` markiert mehrere Bilder. Aktionen wirken auf alle:

- **Löschen**: alle markierten in den Papierkorb (mit Confirm)
- **Zwischenablage (Liste)**: alle Dateien als FileDropList
- **Bearbeiten**: öffnet sequentiell mehrere Editor-Fenster (jedes blockierend)

## Speicherort konfigurieren

Tray → Konfiguration → **Zielordner**. Default ist `%USERPROFILE%\Pictures\LucentScreen\`. Nach Änderung neu öffnen.
