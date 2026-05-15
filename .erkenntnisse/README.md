# .erkenntnisse/

Kurze, **kontextfrei lesbare** Aha-Momente — eine pro Datei.

## Warum extra-Ordner?

- **Lessons** sind narrativ und session-bezogen (siehe `../docs/lessons/`).
- **Erkenntnisse** sind generalisierte Regeln — Truth-Atoms die jederzeit ohne Hintergrundwissen verstanden werden.

## Format

```
<kebab-thema>.md
```

## Vorlage

```markdown
# <Eintitel-Satz, der die Erkenntnis enthält>

**Warum:** 1 Satz — wie wir darauf gekommen sind.
**Wie anwenden:** 1–2 Sätze — was man konkret tun (oder lassen) soll.

(Optional) Quellen / verwandte Erkenntnisse: [[name-ohne-md]]
```

## Beispiele

- `psCustomObject-binding-leer.md`
  ```
  WPF-DataBinding zu PSCustomObject zeigt leere Cells, weil PSNoteProperty kein CLR-Property ist.
  Warum: WPF nutzt TypeDescriptor.GetProperties, das sieht keine PSNoteProperty.
  Wie anwenden: Für jede WPF-gebundene Liste C#-POCO via Add-Type definieren.
  ```

- `sta-pflicht-fuer-wpf.md`
  ```
  WPF und Clipboard.SetImage funktionieren nur in einem STA-Apartment.
  Warum: COM-Single-Threaded-Apartment-Anforderung der WPF-Dispatcher.
  Wie anwenden: pwsh.exe immer mit -STA starten; STA-Check als erste Zeile im Entry-Script.
  ```

## Disziplin

- Nur eine Erkenntnis pro Datei
- Bestehende Erkenntnis aktualisieren statt Duplikat anlegen
- Bei Korrektur: Datei umbenennen, Inhalt überschreiben
