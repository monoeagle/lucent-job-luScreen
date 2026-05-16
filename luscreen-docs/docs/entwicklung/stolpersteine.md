# Stolpersteine

Sammlung der ärgerlichsten WPF-/PowerShell-5.1-Fallen, in die LucentScreen während der Entwicklung gelaufen ist. Detaillierter Pool projektübergreifend in `_Projects/.erkenntnisse/wpf-powershell-gotchas.md`.

## `BitmapImage` + `DecodePixelWidth` zeigt leere Tiles

Bei PNGs aus `System.Drawing.Bitmap.Save()` lieferte `BitmapImage` mit `DecodePixelWidth=N` und `BitmapCacheOption.OnLoad` **dauerhaft leere Vorschauen** — sowohl mit `UriSource` als auch mit `StreamSource`. Externe Bildbetrachter zeigten dieselben Dateien problemlos.

**Robust:** `BitmapFrame.Create` mit `IgnoreColorProfile` + `OnLoad`, dann `TransformedBitmap` für das Downscaling.

```powershell
$frame = [BitmapFrame]::Create($uri, [BitmapCreateOptions]::IgnoreColorProfile,
                                     [BitmapCacheOption]::OnLoad)
$tx = New-Object ScaleTransform $scale, $scale
$tb = New-Object TransformedBitmap $frame, $tx
$tb.Freeze()  # Cross-Thread-fähig für ItemsControl-Bindings
```

Im Verlaufsfenster verwendet.

## `FileSystemWatcher` mit ScriptBlock-Handler killt den Prozess silent

`$fsw.add_Created({ ... })` führt den Handler auf einem **Worker-Thread** aus. Sobald PowerShell-Engine-Calls drin sind (auch nur `Dispatcher.BeginInvoke`), kann der Prozess ohne `DispatcherUnhandledException` oder Event-Log-Eintrag sterben. Symptom: nach jedem Lösch-Klick verschwindet die App.

**Robust:** `DispatcherTimer`-Polling alle 1–2 Sekunden + Snapshot-Signatur. Im Verlaufsfenster genutzt.

## Modul-private `_Underscore`-Funktionen sind aus `.GetNewClosure()` unauffindbar

`.GetNewClosure()` löst den ScriptBlock aus seinem **Module-Scope**. Dort definierte private Funktionen (z.B. `_Build-ConfigFromDialog`) sind nicht mehr aufrufbar:

```text
CommandNotFoundException: '_Build-ConfigFromDialog' wurde nicht als Cmdlet ... erkannt
```

Symptom in LucentScreen: Konfig-Dialog Save-Button reagierte nicht, weil im WPF-Click-Handler die Exception still verschluckt wird.

**Lösung:** Helpers als ScriptBlock-Variable im Funktions-Scope definieren:

```powershell
function Show-ConfigDialog {
    $buildResult = { param($Controls); ... }.GetNewClosure()

    $btn.Add_Click({
        $r = & $buildResult $controls   # funktioniert
    }.GetNewClosure())
}
```

## `$script:Variable = …` im Closure schreibt in einen anderen Scope

Der Caller liest am Ende `$null` zurück:

```powershell
function Show-MyDialog {
    $script:Result = $null
    $btn.Add_Click({
        $script:Result = $candidate    # schreibt NICHT in den Show-MyDialog-Scope
    }.GetNewClosure())
    [void]$win.ShowDialog()
    return $script:Result   # IMMER $null
}
```

Symptom in LucentScreen: Konfig-Dialog hat den Dialog korrekt geschlossen, aber Werte wurden nie persistiert.

**Lösung 1:** Hashtable-Slot statt `$script:` (Reference durchquert die Closure-Grenze):

```powershell
$state = @{ Result = $null }
$btn.Add_Click({ $state.Result = $candidate }.GetNewClosure())
return $state.Result
```

**Lösung 2 (für Bootstrap-globale Hashtables):** Inplace-Update statt Reassign:

```powershell
foreach ($k in @($script:Config.Keys)) { $script:Config.Remove($k) }
foreach ($k in $updated.Keys) { $script:Config[$k] = $updated[$k] }
```

Im Tray-Config-Callback genutzt — andere Closures sehen die neuen Werte automatisch.

## PS 5.1 liest `psm1` ohne BOM als CP-1252

Wenn du Umlaute als UTF-8 in eine `.psm1`-Datei schreibst und kein BOM da ist, interpretiert Windows PowerShell 5.1 die Bytes als **Codepage 1252** — `'Über'` (UTF-8: `0xC3 0x9C`) wird zu `'Ãœber'`.

**Lösung:** psm1 mit BOM speichern:

```powershell
$content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
[System.IO.File]::WriteAllText((Resolve-Path $path), $content,
    (New-Object System.Text.UTF8Encoding($true)))
```

`Set-Content -Encoding UTF8` in PS 5.1 schreibt automatisch mit BOM (anders als PS 7).

XAML-Files brauchen kein BOM — der XML-Parser nimmt UTF-8 als Default.

## Verschachtelte `@(@(...),@(...))` mit Operatoren werfen `op_Addition`

Mehrzeilige Array-Literale, in denen die inneren Arrays mit `+` / `/` arithmetik kombinieren, parst PS 5.1 + Strict-Mode unzuverlässig:

```powershell
$hits = @(
    @('NW', $r.X, $r.Y),
    @('N',  $r.X + $r.W / 2, $r.Y),  # wirft op_Division auf [Object[]]
    ...
)
```

**Lösung:** Inner Arrays als Hashtables — die parsen eindeutig:

```powershell
$hits = @(
    @{ Name='NW'; X=$r.X; Y=$r.Y },
    @{ Name='N';  X=$r.X + $r.W / 2; Y=$r.Y },
    ...
)
```

## `.GetNewClosure()` friert Forward-Refs als `$null` ein

Wenn ein ScriptBlock einen anderen ScriptBlock aufruft, der erst **später** definiert wird, fängt die Closure den `$null`-Wert. Beim Aufruf:

```text
Der Ausdruck nach "&" in einem Pipelineelement hat ein ungültiges Objekt erzeugt
```

**Lösung:** Slot via shared `$state`-Hashtable. Der Hashtable-Eintrag wird zur Laufzeit gelesen, nicht beim Closure-Build:

```powershell
$state = @{ FitToWindow = $null }
$cropApply = {
    if ($null -ne $state.FitToWindow) { & $state.FitToWindow }
}.GetNewClosure()
$fitToWindow = { ... }.GetNewClosure()
$state.FitToWindow = $fitToWindow   # Slot fuellen
```

## `$rtb.Render($visual)` rendert mit Layout-Offset

Wenn das Visual `HorizontalAlignment="Center"` o.ä. hat und in einem ScrollViewer/Grid liegt, rendert RenderTargetBitmap es **mit seinem DIPs-Offset** auf der Render-Surface — das Bild rutscht verschoben rein, der Bereich oben/links bleibt schwarz.

**Lösung:** `VisualBrush` auf einem `DrawingVisual` bei (0,0) malen:

```powershell
$dv = New-Object DrawingVisual
$ctx = $dv.RenderOpen()
$brush = New-Object VisualBrush ($visual)
$brush.Stretch = [Stretch]::None
$brush.AlignmentX = [AlignmentX]::Left
$brush.AlignmentY = [AlignmentY]::Top
$ctx.DrawRectangle($brush, $null, (New-Object Rect(0,0,$w,$h)))
$ctx.Close()
$rtb.Render($dv)
```

Im Editor-Save genutzt.

## `DispatcherUnhandledException` erweitern, damit du Stack-Traces siehst

Standard-WPF-Crash-Dialog ist nutzlos. Im Bootstrap:

```powershell
$app.DispatcherUnhandledException += {
    param($s, $e)
    $msg = "$($e.Exception.GetType().FullName): $($e.Exception.Message)"
    if ($e.Exception.InnerException) { $msg += "`n--- Inner ---`n$($e.Exception.InnerException)" }
    Write-LsLog -Level Error -Source 'crash' -Message ($msg + "`n" + $e.Exception.StackTrace)
    [System.Windows.MessageBox]::Show($msg, 'LucentScreen Crash',
        [MessageBoxButton]::OK, [MessageBoxImage]::Error) | Out-Null
    $e.Handled = $true
}
```

Spart Stunden Diagnose, sobald irgendetwas im WPF-Pfad schiefläuft.
