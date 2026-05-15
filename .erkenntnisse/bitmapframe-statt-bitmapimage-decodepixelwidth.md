# Fuer Thumbnail-Vorschauen in WPF `BitmapFrame.Create` + `TransformedBitmap` benutzen, nicht `BitmapImage` mit `DecodePixelWidth`.

**Warum:** `BitmapImage` mit `DecodePixelWidth` (sowohl `UriSource` als auch `StreamSource`-Variante) lieferte bei PNG-Captures aus `System.Drawing.Bitmap.Save` zuverlaessig leere/weisse Tiles, obwohl die Dateien selbst korrekt waren (externe Bildbetrachter zeigten sie problemlos). Der Decoder rendert ins Bitmap, aber das Resultat ist visuell leer.

**Wie anwenden:** Statt `BitmapImage` ein `BitmapFrame.Create($uri, IgnoreColorProfile, OnLoad)` aufrufen, dann optional via `TransformedBitmap` + `ScaleTransform` runterskalieren. `Freeze()` nicht vergessen, damit es Cross-Thread-faehig ist.

```powershell
$uri = New-Object System.Uri ($Path, [System.UriKind]::Absolute)
$frame = [System.Windows.Media.Imaging.BitmapFrame]::Create(
    $uri,
    [System.Windows.Media.Imaging.BitmapCreateOptions]::IgnoreColorProfile,
    [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
$scale = 200 / $frame.PixelWidth
$tx = New-Object System.Windows.Media.ScaleTransform $scale, $scale
$tb = New-Object System.Windows.Media.Imaging.TransformedBitmap $frame, $tx
$tb.Freeze()
```
