#Requires -Version 5.1
Set-StrictMode -Version Latest

# ---------------------------------------------------------------
#  Mini-Editor (AP 9, Etappe 1)
#
#  Show-EditorWindow -ImagePath <p> [-Owner <Window>] [-Postfix <s>]
#    -> Result-Hashtable @{ Saved=$bool; SavedPath=$null|string }
#
#  Aktueller Stand (Etappe 1 -- Geruest + Save):
#    - Bild laden via BitmapFrame.Create (robust, ohne Decode-Edge-Cases)
#    - Zoom: Mausrad (+ Strg fuer feinere Schritte), Fit-to-Window, 100%,
#      +/- in Toolbar
#    - Speichern: RenderTargetBitmap ueber den StageRoot-Grid -> PNG via
#      core/editor.psm1::Save-EditedImage; editiertes Bild wandert auch
#      in die Zwischenablage
#    - ESC schliesst (ohne Confirm -- Etappe 3 holt das nach)
#    - Postfix kommt aus Config.EditPostfix, Fallback '_edited'
#
#  Folgt mit Etappe 2/3:
#    - Annotations-Tools (Rahmen, Linie, Pfeil, Balken, Radierer)
#    - Vektor-Layer mit Undo/Redo
#    - Selection mit Adorner
#    - Confirm-Dialog bei ungespeicherten Aenderungen
#
#  Voraussetzungen: STA, WPF + WinForms, core/xaml-loader.psm1,
#  core/capture.psm1 (Resolve-UniqueFilename), core/clipboard.psm1
#  (Set-ClipboardImage), core/editor.psm1
# ---------------------------------------------------------------

function Show-EditorWindow {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$ImagePath,
        [System.Windows.Window]$Owner,
        [string]$Postfix = '_edited'
    )

    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        throw 'Show-EditorWindow benoetigt ein STA-Apartment.'
    }
    if (-not (Test-Path -LiteralPath $ImagePath)) {
        return @{ Saved = $false; SavedPath = $null; Status = 'NotFound'; Message = "Datei nicht gefunden: $ImagePath" }
    }

    $xamlPath = Join-Path $PSScriptRoot '..\views\editor-window.xaml'
    $win = Load-Xaml -Path $xamlPath
    if ($Owner) { $win.Owner = $Owner }

    $names = @('BtnSave', 'BtnFit', 'BtnZoom100', 'BtnZoomIn', 'BtnZoomOut', 'BtnClose',
        'Scroller', 'StageRoot', 'StageScale', 'ImgBitmap', 'ShapeLayer',
        'TxtStatus', 'TxtZoom')
    $c = Get-XamlControls -Root $win -Names $names

    # Workarea-clamping (analog Verlaufsfenster)
    $cursor = [System.Windows.Forms.Cursor]::Position
    $screen = [System.Windows.Forms.Screen]::FromPoint($cursor)
    $wa = $screen.WorkingArea
    $win.Width = [math]::Min(1100, [int]($wa.Width - 40))
    $win.Height = [math]::Min(780, [int]($wa.Height - 40))

    # Bitmap laden (BitmapFrame.Create -- BitmapImage hatte fragile Render-Pfade)
    try {
        $uri = New-Object System.Uri ($ImagePath, [System.UriKind]::Absolute)
        $bitmap = [System.Windows.Media.Imaging.BitmapFrame]::Create(
            $uri,
            [System.Windows.Media.Imaging.BitmapCreateOptions]::IgnoreColorProfile,
            [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
        $bitmap.Freeze()
    } catch {
        return @{ Saved = $false; SavedPath = $null; Status = 'LoadFailed'; Message = "Bild konnte nicht geladen werden: $($_.Exception.Message)" }
    }

    $c.ImgBitmap.Source = $bitmap
    $c.ImgBitmap.Width = $bitmap.PixelWidth
    $c.ImgBitmap.Height = $bitmap.PixelHeight
    $c.ShapeLayer.Width = $bitmap.PixelWidth
    $c.ShapeLayer.Height = $bitmap.PixelHeight

    $state = @{
        ImagePath = $ImagePath
        Bitmap    = $bitmap
        Saved     = $false
        SavedPath = $null
        Zoom      = 1.0
    }

    $updateZoomLabel = {
        $c.TxtZoom.Text = ("{0:N0} %" -f ($state.Zoom * 100))
    }.GetNewClosure()

    $setZoom = {
        param([double]$NewZoom)
        $z = [math]::Max(0.05, [math]::Min(8.0, $NewZoom))
        $state.Zoom = $z
        $c.StageScale.ScaleX = $z
        $c.StageScale.ScaleY = $z
        & $updateZoomLabel
    }.GetNewClosure()

    $fitToWindow = {
        # Verfuegbarer Platz im ScrollViewer abzueglich kleinem Rand
        $availW = [math]::Max(50.0, $c.Scroller.ActualWidth - 20)
        $availH = [math]::Max(50.0, $c.Scroller.ActualHeight - 20)
        if ($bitmap.PixelWidth -le 0 -or $bitmap.PixelHeight -le 0) { return }
        $z = [math]::Min($availW / $bitmap.PixelWidth, $availH / $bitmap.PixelHeight)
        if ($z -le 0) { $z = 1 }
        # Nur kleiner-machen automatisch (downscale); bei kleinen Bildern bleibt 100%
        if ($z -gt 1) { $z = 1.0 }
        & $setZoom $z
    }.GetNewClosure()

    # Toolbar-Bindings
    $c.BtnFit.Add_Click({ param($s, $e); & $fitToWindow }.GetNewClosure())
    $c.BtnZoom100.Add_Click({ param($s, $e); & $setZoom 1.0 }.GetNewClosure())
    $c.BtnZoomIn.Add_Click({ param($s, $e); & $setZoom ($state.Zoom * 1.25) }.GetNewClosure())
    $c.BtnZoomOut.Add_Click({ param($s, $e); & $setZoom ($state.Zoom / 1.25) }.GetNewClosure())
    $c.BtnClose.Add_Click({ param($s, $e); $win.Close() }.GetNewClosure())

    # Save-Aktion: nimmt die aktuelle Bitmap-Quelle (in Etappe 1 noch ohne
    # Vektor-Overlay) und schreibt sie als <name>_edited.png. RenderTargetBitmap
    # ist trotzdem schon eingebaut, damit Etappe 2 nur die Tools dazu legen muss.
    $cmdSave = {
        param($s, $e)
        try {
            $w = [int]$state.Bitmap.PixelWidth
            $h = [int]$state.Bitmap.PixelHeight
            $dpiX = $state.Bitmap.DpiX
            $dpiY = $state.Bitmap.DpiY
            if ($dpiX -le 0) { $dpiX = 96 }
            if ($dpiY -le 0) { $dpiY = 96 }

            # RenderTargetBitmap erwartet ein gerendertes Visual ohne Transform.
            # Wir rendern den ShapeLayer-Container in den Original-Pixel-Massen,
            # mit der Bitmap als Hintergrund. In Etappe 1 ist der ShapeLayer leer,
            # also produzieren wir effektiv eine Kopie der Quelle.
            $offscreen = New-Object System.Windows.Controls.Grid
            $offscreen.Width = $w
            $offscreen.Height = $h
            $imgClone = New-Object System.Windows.Controls.Image
            $imgClone.Source = $state.Bitmap
            $imgClone.Width = $w
            $imgClone.Height = $h
            [void]$offscreen.Children.Add($imgClone)
            # Forcier Layout-Pass
            $offscreen.Measure((New-Object System.Windows.Size($w, $h)))
            $offscreen.Arrange((New-Object System.Windows.Rect(0, 0, $w, $h)))
            $offscreen.UpdateLayout()

            $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap (
                $w, $h, $dpiX, $dpiY,
                [System.Windows.Media.PixelFormats]::Pbgra32)
            $rtb.Render($offscreen)
            $rtb.Freeze()

            $r = Save-EditedImage -Source $rtb -OriginalPath $state.ImagePath -Postfix $Postfix
            if (-not $r.Success) {
                [System.Windows.MessageBox]::Show(
                    "Speichern fehlgeschlagen:`n" + $r.Message,
                    'LucentScreen', [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning) | Out-Null
                return
            }
            $state.Saved = $true
            $state.SavedPath = $r.Path
            $c.TxtStatus.Text = "Gespeichert: $($r.Path)"

            # Zusaetzlich in Clipboard -- aus Bitmap-Roundtrip via System.Drawing
            # waere komplexer; einfacher: Frozen-BitmapSource direkt setzen.
            try {
                [System.Windows.Clipboard]::SetImage($rtb)
            } catch {
                # Clipboard ist nice-to-have, kein Fehler
                $null = $_
            }
        } catch {
            [System.Windows.MessageBox]::Show(
                "Unerwarteter Fehler beim Speichern:`n" + $_.Exception.Message,
                'LucentScreen', [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error) | Out-Null
        }
    }.GetNewClosure()

    $c.BtnSave.Add_Click($cmdSave)

    # Mausrad-Zoom: Strg+Wheel = fein (1.1x), sonst grob (1.25x)
    $c.Scroller.Add_PreviewMouseWheel({
            param($s, $e)
            $factor = if (([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) -ne 0) {
                if ($e.Delta -gt 0) { 1.10 } else { 1.0 / 1.10 }
            } else {
                if ($e.Delta -gt 0) { 1.25 } else { 1.0 / 1.25 }
            }
            & $setZoom ($state.Zoom * $factor)
            $e.Handled = $true
        }.GetNewClosure())

    # Tastenkuerzel
    $win.add_PreviewKeyDown({
            param($s, $e)
            $ctrl = ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) -ne 0
            switch ($e.Key) {
                'Escape' { $win.Close(); $e.Handled = $true; break }
                default {
                    if ($ctrl -and $e.Key -eq [System.Windows.Input.Key]::S) {
                        & $cmdSave $null $null
                        $e.Handled = $true
                    } elseif ($ctrl -and ($e.Key -eq [System.Windows.Input.Key]::OemPlus -or $e.Key -eq [System.Windows.Input.Key]::Add)) {
                        & $setZoom ($state.Zoom * 1.25)
                        $e.Handled = $true
                    } elseif ($ctrl -and ($e.Key -eq [System.Windows.Input.Key]::OemMinus -or $e.Key -eq [System.Windows.Input.Key]::Subtract)) {
                        & $setZoom ($state.Zoom / 1.25)
                        $e.Handled = $true
                    } elseif ($ctrl -and $e.Key -eq [System.Windows.Input.Key]::D0) {
                        & $setZoom 1.0
                        $e.Handled = $true
                    }
                }
            }
        }.GetNewClosure())

    # Initialer Fit nach erstem Layout-Pass
    $win.Add_Loaded({
            param($s, $e)
            & $fitToWindow
        }.GetNewClosure())

    $sizeText = ("  ({0}x{1})" -f $bitmap.PixelWidth, $bitmap.PixelHeight)
    $c.TxtStatus.Text = "Bild: " + [System.IO.Path]::GetFileName($ImagePath) + $sizeText
    & $updateZoomLabel

    [void]$win.ShowDialog()

    return @{
        Saved     = $state.Saved
        SavedPath = $state.SavedPath
        Status    = if ($state.Saved) { 'Saved' } else { 'Closed' }
        Message   = if ($state.Saved) { "Gespeichert: $($state.SavedPath)" } else { 'Editor geschlossen' }
    }
}

Export-ModuleMember -Function Show-EditorWindow
