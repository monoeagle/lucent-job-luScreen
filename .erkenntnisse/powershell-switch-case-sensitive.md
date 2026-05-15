# PowerShell `switch` ist standardmaessig **case-insensitive** — `'s'` matcht auch den `'S'`-Branch, beide werden ausgefuehrt.

**Warum:** Anders als `switch` in C oder C# vergleicht PowerShell ohne explizites `-CaseSensitive` ohne Beachtung von Gross-/Kleinschreibung. `switch ($x) { 's' {...} 'S' {...} }` mit `$x = 's'` fuehrt **beide** Branches aus — bei AP 8 startete `run.ps1 s` die App und stoppte sie sofort wieder, weil `s` und `S` derselben Eingabe entsprachen. Gleiches Problem fuer `l/L`, `d/D`, `t/T` (PSSA full vs. changed, Docs build vs. serve, Pester all vs. one).

**Wie anwenden:** Immer `switch -CaseSensitive ($Code)` verwenden, wenn die Branches sich nur durch Gross-/Kleinschreibung unterscheiden. Bei Menue-Dispatchern wie `run.ps1` ist das Pflicht.

```powershell
switch -CaseSensitive ($Code) {
    's' { Action-AppStart }
    'S' { Action-AppStop }
}
```
