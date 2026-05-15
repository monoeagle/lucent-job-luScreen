# Helper, die aus `GetNewClosure`-ScriptBlocks aufgerufen werden, als ScriptBlock-Variablen definieren, nicht als private Modul-Funktionen mit `_`-Praefix.

**Warum:** PowerShell-Modul-Funktionen mit Underscore-Praefix (z.B. `_New-HistoryEntry`) sind in regulaeren Funktionen desselben Moduls aufloesbar, aber in ScriptBlocks die via `.GetNewClosure()` an WPF-Event-Handler (`Add_Click`, `Add_Tick`) uebergeben werden, werden sie zur Aufrufzeit **nicht gefunden** — Laufzeitfehler `Die Benennung "_New-HistoryEntry" wurde nicht als Name eines Cmdlet … erkannt`. Closure-SessionState und Modul-internes Function-Lookup vertragen sich offenbar nicht zuverlaessig.

**Wie anwenden:** Helper, die nur innerhalb einer einzigen Funktion gebraucht werden und in Event-Closures landen, als ScriptBlock-Variable in derselben Funktion definieren und mit `& $helper $arg` aufrufen. Closure-Capture transportiert sie sicher in jeden Event-Handler.

```powershell
function Show-MyWindow {
    $mkEntry = {
        param([hashtable]$Item)
        $e = New-Object MyType
        $e.Name = $Item.Name
        return $e
    }
    $cmdClick = { foreach ($it in $items) { & $mkEntry $it } }.GetNewClosure()
    ...
}
```
