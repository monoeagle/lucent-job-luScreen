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
        'BtnUndo', 'BtnRedo', 'BtnCropApply', 'BtnCropCancel',
        'Scroller', 'StageRoot', 'StageScale', 'ImgBitmap', 'ShapeLayer',
        'TxtStatus', 'TxtZoom',
        'ToolSelect', 'ToolRectangle', 'ToolLine', 'ToolArrow', 'ToolBar', 'ToolMarker', 'ToolCrop',
        'ClrRed', 'ClrOrange', 'ClrYellow', 'ClrGreen', 'ClrBlue', 'ClrMagenta', 'ClrBlack', 'ClrWhite',
        'CurrentColor', 'SldStroke', 'TxtStroke')
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

    # --- Debug-Logger (Crop-Diagnose) ---------------------------------------
    # Gesteuert ueber $env:LUSCREEN_EDITOR_DEBUG. Setze auf '1' fuer Logfile,
    # '2' fuer zusaetzliche Sonden (rotes Test-Rect, ImgBitmap.HitTest=$false).
    # Logfile: %LOCALAPPDATA%\LucentScreen\logs\editor-debug.log
    $dbgLevel = 0
    try { $dbgLevel = [int]($env:LUSCREEN_EDITOR_DEBUG) } catch { $dbgLevel = 0 }
    $dbgLogPath = Join-Path $env:LOCALAPPDATA 'LucentScreen\logs\editor-debug.log'
    if ($dbgLevel -gt 0) {
        try {
            $dbgDir = [System.IO.Path]::GetDirectoryName($dbgLogPath)
            if (-not (Test-Path -LiteralPath $dbgDir)) {
                New-Item -ItemType Directory -Path $dbgDir -Force | Out-Null
            }
        } catch { $null = $_ }
    }
    $dbg = {
        param([string]$Msg)
        if ($dbgLevel -le 0) { return }
        try {
            $ts = (Get-Date).ToString('yyyyMMdd-HHmmss.fff')
            Add-Content -LiteralPath $dbgLogPath -Value ("[{0}] {1}" -f $ts, $Msg) -Encoding UTF8
        } catch { $null = $_ }
    }.GetNewClosure()

    & $dbg ("=== Editor opened: {0} ({1}x{2}) dbgLevel={3} ===" -f $ImagePath, $bitmap.PixelWidth, $bitmap.PixelHeight, $dbgLevel)

    # ImgBitmap als HitTest-blind: alle Maus-Events sollen am ShapeLayer ankommen,
    # nicht am darunterliegenden Image. Ohne dies fing das Image die Crop-Drag-
    # Events ab und der Crop-Tool-Branch in ShapeLayer.MouseDown wurde nie erreicht.
    $c.ImgBitmap.IsHitTestVisible = $false

    $state = @{
        ImagePath  = $ImagePath
        Bitmap     = $bitmap
        Saved      = $false
        SavedPath  = $null
        Zoom       = 1.0
        Tool       = 'Select'         # Select|Rectangle|Line|Arrow|Bar|Marker|Crop
        Color      = [System.Windows.Media.Colors]::Red
        Stroke     = 3.0
        # Undo/Redo speichern Hashtables mit dispatch-Key 'Kind'='Shape'|'Crop'.
        # Shape-Eintrag:  @{ Kind='Shape'; Element=<UIElement> }
        # Crop-Eintrag:   @{ Kind='Crop'; OldBitmap=<bm>; OldWidth; OldHeight;
        #                                 NewBitmap; NewWidth; NewHeight; Dx; Dy }
        UndoStack  = New-Object System.Collections.Generic.Stack[hashtable]
        RedoStack  = New-Object System.Collections.Generic.Stack[hashtable]
        Dragging   = $false
        StartPoint = $null
        Preview    = $null
        Crop       = @{
            Rect      = $null    # @{X=;Y=;W=;H=} in ShapeLayer-Koordinaten
            Overlay   = $null    # Canvas-Container im ShapeLayer
            DragMode  = $null    # 'New'|'Move'|'NW'|'NE'|'SW'|'SE'|'N'|'E'|'S'|'W'
            DragStart = $null    # Point bei MouseDown
            StartRect = $null    # CropRect bei MouseDown (fuer Move/Resize)
        }
        # Slots fuer Closures, die spaeter definiert werden -- Forward-Refs in
        # ScriptBlocks via $state, weil .GetNewClosure() die Variable beim Erstellen
        # einfriert und sonst $null sehen wuerde (Closure-Hoisting-Falle).
        RebuildCrop = $null
        FitToWindow = $null
    }

    $updateZoomLabel = {
        $c.TxtZoom.Text = ("{0:N0} %" -f ($state.Zoom * 100))
    }.GetNewClosure()

    # --- Tool-Helpers --------------------------------------------------------

    $brushFromColor = {
        param([System.Windows.Media.Color]$Color)
        $b = New-Object System.Windows.Media.SolidColorBrush ($Color)
        $b.Freeze()
        return $b
    }

    $updateUndoButtons = {
        $c.BtnUndo.IsEnabled = $state.UndoStack.Count -gt 0
        $c.BtnRedo.IsEnabled = $state.RedoStack.Count -gt 0
    }.GetNewClosure()

    $createShape = {
        param([string]$Tool)
        switch ($Tool) {
            'Rectangle' {
                $r = New-Object System.Windows.Shapes.Rectangle
                $r.Stroke = & $brushFromColor $state.Color
                $r.StrokeThickness = [double]$state.Stroke
                $r.Fill = $null
                return $r
            }
            'Line' {
                $l = New-Object System.Windows.Shapes.Line
                $l.Stroke = & $brushFromColor $state.Color
                $l.StrokeThickness = [double]$state.Stroke
                $l.StrokeStartLineCap = [System.Windows.Media.PenLineCap]::Round
                $l.StrokeEndLineCap = [System.Windows.Media.PenLineCap]::Round
                return $l
            }
            'Arrow' {
                $p = New-Object System.Windows.Shapes.Polyline
                $p.Stroke = & $brushFromColor $state.Color
                $p.StrokeThickness = [double]$state.Stroke
                $p.StrokeStartLineCap = [System.Windows.Media.PenLineCap]::Round
                $p.StrokeEndLineCap = [System.Windows.Media.PenLineCap]::Round
                $p.StrokeLineJoin = [System.Windows.Media.PenLineJoin]::Round
                return $p
            }
            'Bar' {
                $r = New-Object System.Windows.Shapes.Rectangle
                $r.Fill = & $brushFromColor $state.Color
                $r.Stroke = $null
                return $r
            }
            'Marker' {
                # Textmarker: gefuelltes Rechteck mit 40% Alpha auf die
                # gewaehlte Farbe. Look-and-Feel wie ein klassischer
                # Highlighter -- darunterliegendes Bild bleibt sichtbar.
                $r = New-Object System.Windows.Shapes.Rectangle
                $base = $state.Color
                $semi = [System.Windows.Media.Color]::FromArgb(0x66, $base.R, $base.G, $base.B)
                $br = New-Object System.Windows.Media.SolidColorBrush ($semi)
                $br.Freeze()
                $r.Fill = $br
                $r.Stroke = $null
                return $r
            }
        }
        return $null
    }.GetNewClosure()

    $updateShape = {
        param($Shape, [System.Windows.Point]$Start, [System.Windows.Point]$End)
        if ($null -eq $Shape) { return }
        if ($Shape -is [System.Windows.Shapes.Rectangle]) {
            $x = [math]::Min($Start.X, $End.X)
            $y = [math]::Min($Start.Y, $End.Y)
            $w = [math]::Abs($End.X - $Start.X)
            $h = [math]::Abs($End.Y - $Start.Y)
            [System.Windows.Controls.Canvas]::SetLeft($Shape, $x)
            [System.Windows.Controls.Canvas]::SetTop($Shape, $y)
            $Shape.Width = $w
            $Shape.Height = $h
            return
        }
        if ($Shape -is [System.Windows.Shapes.Line]) {
            $Shape.X1 = $Start.X
            $Shape.Y1 = $Start.Y
            $Shape.X2 = $End.X
            $Shape.Y2 = $End.Y
            return
        }
        if ($Shape -is [System.Windows.Shapes.Polyline]) {
            $geo = Get-ArrowGeometry -X1 $Start.X -Y1 $Start.Y -X2 $End.X -Y2 $End.Y `
                -HeadSize ([math]::Max(8.0, [double]$state.Stroke * 4))
            $pts = New-Object System.Windows.Media.PointCollection
            foreach ($pt in $geo.Points) {
                $pts.Add((New-Object System.Windows.Point ([double]$pt.X), ([double]$pt.Y)))
            }
            $Shape.Points = $pts
            return
        }
    }.GetNewClosure()

    # Verschiebt alle Shapes in der ShapeLayer um (Dx, Dy). Wird bei Crop-Apply,
    # Crop-Undo und Crop-Redo aufgerufen -- gleicher Translations-Code, nur mit
    # umgekehrten Vorzeichen fuer Undo.
    $translateShapes = {
        param([double]$Dx, [double]$Dy)
        foreach ($child in @($c.ShapeLayer.Children)) {
            if ($child -is [System.Windows.Shapes.Line]) {
                $child.X1 += $Dx; $child.Y1 += $Dy
                $child.X2 += $Dx; $child.Y2 += $Dy
            } elseif ($child -is [System.Windows.Shapes.Polyline]) {
                $newPts = New-Object System.Windows.Media.PointCollection
                foreach ($p in $child.Points) {
                    $newPts.Add((New-Object System.Windows.Point (($p.X + $Dx), ($p.Y + $Dy))))
                }
                $child.Points = $newPts
            } elseif ($child -is [System.Windows.Shapes.Rectangle]) {
                $oldX = [System.Windows.Controls.Canvas]::GetLeft($child)
                $oldY = [System.Windows.Controls.Canvas]::GetTop($child)
                if ([double]::IsNaN($oldX)) { $oldX = 0 }
                if ([double]::IsNaN($oldY)) { $oldY = 0 }
                [System.Windows.Controls.Canvas]::SetLeft($child, $oldX + $Dx)
                [System.Windows.Controls.Canvas]::SetTop($child, $oldY + $Dy)
            }
        }
    }.GetNewClosure()

    # Wendet die Bitmap-Seite eines Crop-Eintrags an: setzt Bitmap + ImgBitmap +
    # ShapeLayer-Masse. Wird bei cropApply (vorwaerts), Crop-Undo (rueckwaerts)
    # und Crop-Redo (vorwaerts) genutzt -- jeweils mit der passenden Bitmap.
    $applyCropBitmap = {
        param($Bitmap, [double]$W, [double]$H)
        $state.Bitmap = $Bitmap
        $c.ImgBitmap.Source = $Bitmap
        $c.ImgBitmap.Width = $W
        $c.ImgBitmap.Height = $H
        $c.ShapeLayer.Width = $W
        $c.ShapeLayer.Height = $H
    }.GetNewClosure()

    $pushUndo = {
        param([hashtable]$Entry)
        $state.UndoStack.Push($Entry) | Out-Null
        $state.RedoStack.Clear()
        & $updateUndoButtons
    }.GetNewClosure()

    $doUndo = {
        if ($state.UndoStack.Count -le 0) { return }
        $top = $state.UndoStack.Pop()
        switch ($top.Kind) {
            'Shape' {
                $c.ShapeLayer.Children.Remove($top.Element)
            }
            'Crop' {
                # Rueckwaerts: Shapes zurueck-translatieren, alte Bitmap+Masse wiederherstellen
                $undoDx = 0.0 - [double]$top.Dx
                $undoDy = 0.0 - [double]$top.Dy
                & $translateShapes $undoDx $undoDy
                & $applyCropBitmap $top.OldBitmap $top.OldWidth $top.OldHeight
                $c.TxtStatus.Text = "Bild: " + [System.IO.Path]::GetFileName($state.ImagePath) + ("  ({0}x{1})" -f [int]$top.OldWidth, [int]$top.OldHeight)
            }
        }
        $state.RedoStack.Push($top) | Out-Null
        & $updateUndoButtons
    }.GetNewClosure()

    $doRedo = {
        if ($state.RedoStack.Count -le 0) { return }
        $top = $state.RedoStack.Pop()
        switch ($top.Kind) {
            'Shape' {
                [void]$c.ShapeLayer.Children.Add($top.Element)
            }
            'Crop' {
                # Vorwaerts: Shapes wieder verschieben, neue Bitmap+Masse setzen
                & $translateShapes ([double]$top.Dx) ([double]$top.Dy)
                & $applyCropBitmap $top.NewBitmap $top.NewWidth $top.NewHeight
                $c.TxtStatus.Text = "Bild: " + [System.IO.Path]::GetFileName($state.ImagePath) + ("  ({0}x{1})" -f [int]$top.NewWidth, [int]$top.NewHeight) + " (zugeschnitten)"
            }
        }
        $state.UndoStack.Push($top) | Out-Null
        & $updateUndoButtons
    }.GetNewClosure()

    $applyColor = {
        param([System.Windows.Media.Color]$Color)
        $state.Color = $Color
        $c.CurrentColor.Background = & $brushFromColor $Color
    }.GetNewClosure()

    # --- Crop-Tool ----------------------------------------------------------

    # Hit-Test-Toleranz und Handle-Groesse sind in BILDSCHIRM-Pixeln gemeint.
    # Da die Stage zoom-skaliert ist, muessen wir durch den Zoom teilen, damit
    # die Handles auf dem Bildschirm immer ~14 px gross bleiben.

    $cropHitTest = {
        param([System.Windows.Point]$Pt)
        $r = $state.Crop.Rect
        if ($null -eq $r -or $r.W -le 0 -or $r.H -le 0) { return 'New' }
        $tol = 10.0 / [math]::Max(0.05, $state.Zoom)
        # Hashtables statt nested Arrays: PS 5.1 + Strict-Mode parst @(@(..),@(..))
        # mit Komma-Trennung und Operatoren wie '+'/'/' inkonsistent und versucht
        # arithmetik auf [Object[]] (op_Addition/op_Division) -- Hashtables im
        # aeusseren @() sind eindeutig.
        $hits = @(
            @{ Name = 'NW'; X = $r.X; Y = $r.Y },
            @{ Name = 'NE'; X = $r.X + $r.W; Y = $r.Y },
            @{ Name = 'SW'; X = $r.X; Y = $r.Y + $r.H },
            @{ Name = 'SE'; X = $r.X + $r.W; Y = $r.Y + $r.H },
            @{ Name = 'N'; X = $r.X + $r.W / 2; Y = $r.Y },
            @{ Name = 'E'; X = $r.X + $r.W; Y = $r.Y + $r.H / 2 },
            @{ Name = 'S'; X = $r.X + $r.W / 2; Y = $r.Y + $r.H },
            @{ Name = 'W'; X = $r.X; Y = $r.Y + $r.H / 2 }
        )
        foreach ($h in $hits) {
            if ([math]::Abs($Pt.X - $h.X) -le $tol -and [math]::Abs($Pt.Y - $h.Y) -le $tol) {
                return $h.Name
            }
        }
        if ($Pt.X -gt $r.X -and $Pt.X -lt $r.X + $r.W -and $Pt.Y -gt $r.Y -and $Pt.Y -lt $r.Y + $r.H) {
            return 'Move'
        }
        return 'New'
    }.GetNewClosure()

    $cropCursorFor = {
        param([string]$Mode)
        switch ($Mode) {
            'New' { return [System.Windows.Input.Cursors]::Cross }
            'Move' { return [System.Windows.Input.Cursors]::SizeAll }
            'N' { return [System.Windows.Input.Cursors]::SizeNS }
            'S' { return [System.Windows.Input.Cursors]::SizeNS }
            'E' { return [System.Windows.Input.Cursors]::SizeWE }
            'W' { return [System.Windows.Input.Cursors]::SizeWE }
            'NW' { return [System.Windows.Input.Cursors]::SizeNWSE }
            'SE' { return [System.Windows.Input.Cursors]::SizeNWSE }
            'NE' { return [System.Windows.Input.Cursors]::SizeNESW }
            'SW' { return [System.Windows.Input.Cursors]::SizeNESW }
        }
        return [System.Windows.Input.Cursors]::Arrow
    }

    $cropClampRect = {
        param($Rect)
        $maxW = [double]$c.ShapeLayer.Width
        $maxH = [double]$c.ShapeLayer.Height
        $x = [math]::Max(0.0, [math]::Min([double]$Rect.X, $maxW))
        $y = [math]::Max(0.0, [math]::Min([double]$Rect.Y, $maxH))
        $w = [math]::Max(0.0, [math]::Min([double]$Rect.W, $maxW - $x))
        $h = [math]::Max(0.0, [math]::Min([double]$Rect.H, $maxH - $y))
        return @{ X = $x; Y = $y; W = $w; H = $h }
    }.GetNewClosure()

    $cropUpdateApplyButtons = {
        $active = ($state.Tool -eq 'Crop')
        $hasRect = ($null -ne $state.Crop.Rect -and $state.Crop.Rect.W -gt 1 -and $state.Crop.Rect.H -gt 1)
        $c.BtnCropApply.Visibility = if ($active) { 'Visible' } else { 'Collapsed' }
        $c.BtnCropCancel.Visibility = if ($active) { 'Visible' } else { 'Collapsed' }
        $c.BtnCropApply.IsEnabled = $hasRect
    }.GetNewClosure()

    $cropRemoveOverlay = {
        if ($null -ne $state.Crop.Overlay) {
            try { $c.ShapeLayer.Children.Remove($state.Crop.Overlay) } catch { $null = $_ }
            $state.Crop.Overlay = $null
        }
    }.GetNewClosure()

    $cropRebuildOverlay = {
        & $cropRemoveOverlay
        $r = $state.Crop.Rect
        if ($null -eq $r -or $r.W -le 0 -or $r.H -le 0) {
            & $cropUpdateApplyButtons
            return
        }
        & $dbg ("cropRebuildOverlay: Rect X={0:N1} Y={1:N1} W={2:N1} H={3:N1} Zoom={4:N3} ShapeLayer={5:N0}x{6:N0}" -f $r.X, $r.Y, $r.W, $r.H, $state.Zoom, $c.ShapeLayer.Width, $c.ShapeLayer.Height)
        $w = [double]$c.ShapeLayer.Width
        $h = [double]$c.ShapeLayer.Height
        # Zoom-Inversion: Handles und Border-Strichstaerke werden in DIP gemessen,
        # aber die Stage ist via LayoutTransform skaliert. Damit die Visuals auf
        # dem Bildschirm immer gleich gross erscheinen, durch den Zoom teilen.
        $zinv = 1.0 / [math]::Max(0.05, $state.Zoom)
        $handleSize = 14.0 * $zinv
        $borderStroke = 2.0 * $zinv

        $canvas = New-Object System.Windows.Controls.Canvas
        $canvas.Width = $w
        $canvas.Height = $h
        $canvas.IsHitTestVisible = $false   # HitTesting macht der ShapeLayer-Handler

        $dim = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(0x80, 0, 0, 0))
        $dim.Freeze()

        $addDimRect = {
            param([double]$X, [double]$Y, [double]$RW, [double]$RH, $Fill, $Container)
            if ($RW -le 0 -or $RH -le 0) { return }
            $rect = New-Object System.Windows.Shapes.Rectangle
            $rect.Width = $RW
            $rect.Height = $RH
            $rect.Fill = $Fill
            [System.Windows.Controls.Canvas]::SetLeft($rect, $X)
            [System.Windows.Controls.Canvas]::SetTop($rect, $Y)
            [void]$Container.Children.Add($rect)
        }
        # 4 Dimmer: oben / unten / links / rechts
        & $addDimRect 0 0 $w $r.Y $dim $canvas
        & $addDimRect 0 ($r.Y + $r.H) $w ($h - $r.Y - $r.H) $dim $canvas
        & $addDimRect 0 $r.Y $r.X $r.H $dim $canvas
        & $addDimRect ($r.X + $r.W) $r.Y ($w - $r.X - $r.W) $r.H $dim $canvas

        # Crop-Border: schwarzer Outline darunter + weisser Innenrand fuer
        # Kontrast auf hellen wie dunklen Bildhintergrund.
        $borderBlack = New-Object System.Windows.Shapes.Rectangle
        $borderBlack.Width = $r.W
        $borderBlack.Height = $r.H
        $borderBlack.Stroke = [System.Windows.Media.Brushes]::Black
        $borderBlack.StrokeThickness = $borderStroke * 2
        $borderBlack.Fill = $null
        [System.Windows.Controls.Canvas]::SetLeft($borderBlack, $r.X)
        [System.Windows.Controls.Canvas]::SetTop($borderBlack, $r.Y)
        [void]$canvas.Children.Add($borderBlack)

        $borderWhite = New-Object System.Windows.Shapes.Rectangle
        $borderWhite.Width = $r.W
        $borderWhite.Height = $r.H
        $borderWhite.Stroke = [System.Windows.Media.Brushes]::White
        $borderWhite.StrokeThickness = $borderStroke
        $borderWhite.Fill = $null
        [System.Windows.Controls.Canvas]::SetLeft($borderWhite, $r.X)
        [System.Windows.Controls.Canvas]::SetTop($borderWhite, $r.Y)
        [void]$canvas.Children.Add($borderWhite)

        # 8 Handles (zoom-invariant, knallig blau mit weissem Rand).
        # Hashtables statt nested Arrays -- siehe Kommentar in cropHitTest.
        $handles = @(
            @{ X = $r.X; Y = $r.Y },
            @{ X = $r.X + $r.W; Y = $r.Y },
            @{ X = $r.X; Y = $r.Y + $r.H },
            @{ X = $r.X + $r.W; Y = $r.Y + $r.H },
            @{ X = $r.X + $r.W / 2; Y = $r.Y },
            @{ X = $r.X + $r.W; Y = $r.Y + $r.H / 2 },
            @{ X = $r.X + $r.W / 2; Y = $r.Y + $r.H },
            @{ X = $r.X; Y = $r.Y + $r.H / 2 }
        )
        $handleFill = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#2563EB'))
        $handleFill.Freeze()
        foreach ($hp in $handles) {
            $hd = New-Object System.Windows.Shapes.Rectangle
            $hd.Width = $handleSize
            $hd.Height = $handleSize
            $hd.Fill = $handleFill
            $hd.Stroke = [System.Windows.Media.Brushes]::White
            $hd.StrokeThickness = $borderStroke
            [System.Windows.Controls.Canvas]::SetLeft($hd, $hp.X - $handleSize / 2)
            [System.Windows.Controls.Canvas]::SetTop($hd, $hp.Y - $handleSize / 2)
            [void]$canvas.Children.Add($hd)
        }

        # Crop-Overlay als LETZTES Child anhaengen (over alles drueber).
        # Plus explizit Position (0,0), damit das Canvas-in-Canvas korrekt sitzt.
        [System.Windows.Controls.Canvas]::SetLeft($canvas, 0)
        [System.Windows.Controls.Canvas]::SetTop($canvas, 0)
        [System.Windows.Controls.Panel]::SetZIndex($canvas, 9999)
        [void]$c.ShapeLayer.Children.Add($canvas)
        $state.Crop.Overlay = $canvas
        & $cropUpdateApplyButtons
    }.GetNewClosure()

    # Slot fuellen, damit $setZoom (oben definiert) das Overlay bei Zoom-Aenderung
    # neu rendern kann.
    $state.RebuildCrop = $cropRebuildOverlay

    $cropCancel = {
        $state.Crop.Rect = $null
        $state.Crop.DragMode = $null
        $state.Crop.DragStart = $null
        $state.Crop.StartRect = $null
        & $cropRemoveOverlay
        & $cropUpdateApplyButtons
        $c.ShapeLayer.Cursor = [System.Windows.Input.Cursors]::Arrow
    }.GetNewClosure()

    $cropApply = {
        if ($null -eq $state.Crop.Rect -or $state.Crop.Rect.W -lt 1 -or $state.Crop.Rect.H -lt 1) {
            return
        }
        & $dbg ("cropApply: ENTER Rect X={0:N1} Y={1:N1} W={2:N1} H={3:N1} Bitmap={4}x{5}" -f $state.Crop.Rect.X, $state.Crop.Rect.Y, $state.Crop.Rect.W, $state.Crop.Rect.H, $state.Bitmap.PixelWidth, $state.Bitmap.PixelHeight)
        try {
            $r = & $cropClampRect $state.Crop.Rect
            $x = [int][math]::Round($r.X)
            $y = [int][math]::Round($r.Y)
            $w = [math]::Max(1, [int][math]::Round($r.W))
            $h = [math]::Max(1, [int][math]::Round($r.H))
            # Bitmap-Pixel-Bounds sind das Mass aller Dinge
            $bmpW = [int]$state.Bitmap.PixelWidth
            $bmpH = [int]$state.Bitmap.PixelHeight
            if ($x + $w -gt $bmpW) { $w = $bmpW - $x }
            if ($y + $h -gt $bmpH) { $h = $bmpH - $y }
            $rect = New-Object System.Windows.Int32Rect ($x, $y, $w, $h)
            $cropped = New-Object System.Windows.Media.Imaging.CroppedBitmap ($state.Bitmap, $rect)
            $cropped.Freeze()

            # Vor-Crop-Snapshot fuer Undo
            $oldBitmap = $state.Bitmap
            $oldW = [double]$c.ShapeLayer.Width
            $oldH = [double]$c.ShapeLayer.Height
            $dx = - [double]$x
            $dy = - [double]$y

            # Shapes translate (- crop.X, - crop.Y) -- Crop-Overlay vorher entfernen
            & $cropRemoveOverlay
            & $translateShapes $dx $dy

            # Bitmap + Layer-Masse auf Crop-Ergebnis setzen
            & $applyCropBitmap $cropped ([double]$w) ([double]$h)

            # Statuszeile aktualisieren
            $sizeText = ("  ({0}x{1})" -f $w, $h)
            $c.TxtStatus.Text = "Bild: " + [System.IO.Path]::GetFileName($state.ImagePath) + $sizeText + " (zugeschnitten)"

            # Undo-Snapshot pushen -- Crop ist jetzt rueckgaengig-machbar.
            # Vorher-Shape-Eintraege im Stack bleiben gueltig (UIElements existieren
            # weiter, nur in neuen Positionen). doUndo/doRedo dispatcht nach Kind.
            & $pushUndo @{
                Kind      = 'Crop'
                OldBitmap = $oldBitmap
                OldWidth  = $oldW
                OldHeight = $oldH
                NewBitmap = $cropped
                NewWidth  = [double]$w
                NewHeight = [double]$h
                Dx        = $dx
                Dy        = $dy
            }

            # Tool zurueck auf Select
            & $cropCancel
            $c.ToolSelect.IsChecked = $true

            # Fit-to-Window auf neue Dimensionen.
            # Achtung: $fitToWindow wird erst NACH $cropApply definiert -- die
            # Closure-Variable waere $null. Daher Slot via $state.FitToWindow.
            if ($null -ne $state.FitToWindow) { & $state.FitToWindow }
            & $dbg ("cropApply: DONE -> ShapeLayer={0:N0}x{1:N0}" -f $c.ShapeLayer.Width, $c.ShapeLayer.Height)
        } catch {
            & $dbg ("!! cropApply EXCEPTION: {0} | {1}" -f $_.Exception.GetType().FullName, $_.Exception.Message)
            & $dbg ("!! at: {0}" -f $_.InvocationInfo.PositionMessage)
            [System.Windows.MessageBox]::Show(
                "Zuschnitt fehlgeschlagen:`n" + $_.Exception.Message,
                'LucentScreen', [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning) | Out-Null
        }
    }.GetNewClosure()

    $c.BtnCropApply.Add_Click({ param($s, $e); & $cropApply }.GetNewClosure())
    $c.BtnCropCancel.Add_Click({ param($s, $e); & $cropCancel }.GetNewClosure())

    # --- Tool-RadioButton-Bindings ------------------------------------------

    $toolButtons = @{
        Select    = $c.ToolSelect
        Rectangle = $c.ToolRectangle
        Line      = $c.ToolLine
        Arrow     = $c.ToolArrow
        Bar       = $c.ToolBar
        Marker    = $c.ToolMarker
        Crop      = $c.ToolCrop
    }
    foreach ($kv in $toolButtons.GetEnumerator()) {
        $tool = $kv.Key
        $btn = $kv.Value
        $btn.Add_Checked({
                param($s, $e)
                $prevTool = $state.Tool
                $state.Tool = $tool
                & $dbg ("ToolSwitch: {0} -> {1} (ShapeLayer={2:N0}x{3:N0} Children={4})" -f $prevTool, $tool, $c.ShapeLayer.Width, $c.ShapeLayer.Height, $c.ShapeLayer.Children.Count)
                # Wechsel weg von Crop: aufraeumen
                if ($prevTool -eq 'Crop' -and $tool -ne 'Crop') {
                    & $cropCancel
                }
                # Wechsel zu Crop: Initial-Rect 80% in der Bildmitte, damit
                # der User sofort sieht, dass das Tool aktiv ist.
                if ($tool -eq 'Crop' -and $null -eq $state.Crop.Rect) {
                    $cw = [double]$c.ShapeLayer.Width
                    $ch = [double]$c.ShapeLayer.Height
                    if ($cw -gt 10 -and $ch -gt 10) {
                        $state.Crop.Rect = @{
                            X = $cw * 0.1
                            Y = $ch * 0.1
                            W = $cw * 0.8
                            H = $ch * 0.8
                        }
                        & $dbg ("ToolSwitch->Crop: initial Rect set X={0:N1} Y={1:N1} W={2:N1} H={3:N1}" -f $state.Crop.Rect.X, $state.Crop.Rect.Y, $state.Crop.Rect.W, $state.Crop.Rect.H)
                        & $cropRebuildOverlay
                    } else {
                        & $dbg ("ToolSwitch->Crop: SKIPPED initial Rect, ShapeLayer too small ({0}x{1})" -f $cw, $ch)
                    }
                }
                # Mauszeiger ueber dem Canvas spiegelt das Tool
                $c.ShapeLayer.Cursor = if ($state.Tool -eq 'Select') {
                    [System.Windows.Input.Cursors]::Arrow
                } elseif ($state.Tool -eq 'Crop') {
                    [System.Windows.Input.Cursors]::Cross
                } else {
                    [System.Windows.Input.Cursors]::Cross
                }
                & $cropUpdateApplyButtons
            }.GetNewClosure())
    }

    # --- Color-Swatch-Bindings ----------------------------------------------

    $colorMap = @{
        ClrRed     = '#E11D48'
        ClrOrange  = '#F97316'
        ClrYellow  = '#FACC15'
        ClrGreen   = '#16A34A'
        ClrBlue    = '#2563EB'
        ClrMagenta = '#DB2777'
        ClrBlack   = '#111827'
        ClrWhite   = '#FFFFFF'
    }
    foreach ($kv in $colorMap.GetEnumerator()) {
        $btn = $c.($kv.Key)
        $hex = $kv.Value
        $btn.Add_Click({
                param($s, $e)
                $color = [System.Windows.Media.ColorConverter]::ConvertFromString($hex)
                & $applyColor $color
            }.GetNewClosure())
    }

    # --- Stroke-Slider ------------------------------------------------------

    $c.SldStroke.Add_ValueChanged({
            param($s, $e)
            $state.Stroke = [double]$c.SldStroke.Value
            $c.TxtStroke.Text = ("{0:N0} px" -f $state.Stroke)
        }.GetNewClosure())

    # --- Maus-Drawing auf ShapeLayer ----------------------------------------

    $c.ShapeLayer.Add_MouseLeftButtonDown({
            param($s, $e)
            $pt = $e.GetPosition($c.ShapeLayer)

            if ($state.Tool -eq 'Crop') {
                $hit = & $cropHitTest $pt
                $state.Crop.DragMode = $hit
                $state.Crop.DragStart = $pt
                if ($hit -eq 'New') {
                    $state.Crop.Rect = @{ X = $pt.X; Y = $pt.Y; W = 0; H = 0 }
                }
                if ($null -ne $state.Crop.Rect) {
                    $state.Crop.StartRect = @{
                        X = $state.Crop.Rect.X
                        Y = $state.Crop.Rect.Y
                        W = $state.Crop.Rect.W
                        H = $state.Crop.Rect.H
                    }
                }
                $state.Dragging = $true
                [void]$c.ShapeLayer.CaptureMouse()
                & $cropRebuildOverlay
                $e.Handled = $true
                return
            }

            if ($state.Tool -eq 'Select') { return }
            $state.StartPoint = $pt
            $state.Dragging = $true
            $state.Preview = & $createShape $state.Tool
            if ($null -ne $state.Preview) {
                & $updateShape $state.Preview $state.StartPoint $state.StartPoint
                [void]$c.ShapeLayer.Children.Add($state.Preview)
            }
            [void]$c.ShapeLayer.CaptureMouse()
            $e.Handled = $true
        }.GetNewClosure())

    $c.ShapeLayer.Add_MouseMove({
            param($s, $e)
            $pt = $e.GetPosition($c.ShapeLayer)

            if ($state.Tool -eq 'Crop') {
                if (-not $state.Dragging) {
                    # Cursor je nach Hit-Test setzen
                    $hit = & $cropHitTest $pt
                    $c.ShapeLayer.Cursor = & $cropCursorFor $hit
                    return
                }
                $sr = $state.Crop.StartRect
                $ds = $state.Crop.DragStart
                $dx = $pt.X - $ds.X
                $dy = $pt.Y - $ds.Y
                $new = @{ X = $sr.X; Y = $sr.Y; W = $sr.W; H = $sr.H }
                switch ($state.Crop.DragMode) {
                    'New' {
                        $x = [math]::Min($ds.X, $pt.X); $y = [math]::Min($ds.Y, $pt.Y)
                        $w = [math]::Abs($pt.X - $ds.X); $h = [math]::Abs($pt.Y - $ds.Y)
                        $new = @{ X = $x; Y = $y; W = $w; H = $h }
                    }
                    'Move' {
                        $new.X = $sr.X + $dx; $new.Y = $sr.Y + $dy
                    }
                    'NW' { $new.X = $sr.X + $dx; $new.Y = $sr.Y + $dy; $new.W = $sr.W - $dx; $new.H = $sr.H - $dy }
                    'N' { $new.Y = $sr.Y + $dy; $new.H = $sr.H - $dy }
                    'NE' { $new.Y = $sr.Y + $dy; $new.W = $sr.W + $dx; $new.H = $sr.H - $dy }
                    'E' { $new.W = $sr.W + $dx }
                    'SE' { $new.W = $sr.W + $dx; $new.H = $sr.H + $dy }
                    'S' { $new.H = $sr.H + $dy }
                    'SW' { $new.X = $sr.X + $dx; $new.W = $sr.W - $dx; $new.H = $sr.H + $dy }
                    'W' { $new.X = $sr.X + $dx; $new.W = $sr.W - $dx }
                }
                # Negative Width/Height korrigieren (Resize ueber den Anker hinaus)
                if ($new.W -lt 0) { $new.X = $new.X + $new.W; $new.W = - $new.W }
                if ($new.H -lt 0) { $new.Y = $new.Y + $new.H; $new.H = - $new.H }
                $state.Crop.Rect = & $cropClampRect $new
                & $cropRebuildOverlay
                return
            }

            if (-not $state.Dragging -or $null -eq $state.Preview) { return }
            & $updateShape $state.Preview $state.StartPoint $pt
        }.GetNewClosure())

    $c.ShapeLayer.Add_MouseLeftButtonUp({
            param($s, $e)
            if (-not $state.Dragging) { return }
            $end = $e.GetPosition($c.ShapeLayer)

            if ($state.Tool -eq 'Crop') {
                $state.Dragging = $false
                $state.Crop.DragMode = $null
                $c.ShapeLayer.ReleaseMouseCapture()
                & $cropUpdateApplyButtons
                $e.Handled = $true
                return
            }

            if ($null -ne $state.Preview) {
                & $updateShape $state.Preview $state.StartPoint $end
                $dx = [math]::Abs($end.X - $state.StartPoint.X)
                $dy = [math]::Abs($end.Y - $state.StartPoint.Y)
                if ($dx -lt 3 -and $dy -lt 3) {
                    $c.ShapeLayer.Children.Remove($state.Preview)
                } else {
                    & $pushUndo @{ Kind = 'Shape'; Element = $state.Preview }
                }
            }
            $state.Preview = $null
            $state.Dragging = $false
            $c.ShapeLayer.ReleaseMouseCapture()
            $e.Handled = $true
        }.GetNewClosure())

    $c.ShapeLayer.Add_LostMouseCapture({
            param($s, $e)
            if ($state.Tool -eq 'Crop') {
                $state.Dragging = $false
                $state.Crop.DragMode = $null
                return
            }
            if ($state.Dragging -and $null -ne $state.Preview) {
                $c.ShapeLayer.Children.Remove($state.Preview)
                $state.Preview = $null
                $state.Dragging = $false
            }
        }.GetNewClosure())

    # --- Undo/Redo-Buttons --------------------------------------------------

    $c.BtnUndo.Add_Click({ param($s, $e); & $doUndo }.GetNewClosure())
    $c.BtnRedo.Add_Click({ param($s, $e); & $doRedo }.GetNewClosure())
    & $updateUndoButtons

    $setZoom = {
        param([double]$NewZoom)
        $z = [math]::Max(0.05, [math]::Min(8.0, $NewZoom))
        $state.Zoom = $z
        $c.StageScale.ScaleX = $z
        $c.StageScale.ScaleY = $z
        & $updateZoomLabel
        # Bei aktivem Crop: Overlay zoom-invariant neu rendern (Handles bleiben
        # auf dem Bildschirm 14 px gross, egal wie weit rein/raus gezoomt ist).
        if ($state.Tool -eq 'Crop' -and $null -ne $state.Crop.Rect -and $null -ne $state.RebuildCrop) {
            & $state.RebuildCrop
        }
    }.GetNewClosure()

    $fitToWindow = {
        # Verfuegbarer Platz im ScrollViewer abzueglich kleinem Rand
        $availW = [math]::Max(50.0, $c.Scroller.ActualWidth - 20)
        $availH = [math]::Max(50.0, $c.Scroller.ActualHeight - 20)
        # Aktuelle Bitmap aus $state -- $bitmap waere nach Crop noch die alte.
        $bm = $state.Bitmap
        if ($bm.PixelWidth -le 0 -or $bm.PixelHeight -le 0) { return }
        $z = [math]::Min($availW / $bm.PixelWidth, $availH / $bm.PixelHeight)
        if ($z -le 0) { $z = 1 }
        # Nur kleiner-machen automatisch (downscale); bei kleinen Bildern bleibt 100%
        if ($z -gt 1) { $z = 1.0 }
        & $setZoom $z
    }.GetNewClosure()
    $state.FitToWindow = $fitToWindow

    # Toolbar-Bindings
    $c.BtnFit.Add_Click({ param($s, $e); & $fitToWindow }.GetNewClosure())
    $c.BtnZoom100.Add_Click({ param($s, $e); & $setZoom 1.0 }.GetNewClosure())
    $c.BtnZoomIn.Add_Click({ param($s, $e); & $setZoom ($state.Zoom * 1.25) }.GetNewClosure())
    $c.BtnZoomOut.Add_Click({ param($s, $e); & $setZoom ($state.Zoom / 1.25) }.GetNewClosure())
    $c.BtnClose.Add_Click({ param($s, $e); $win.Close() }.GetNewClosure())

    # Save-Aktion: temporaer Zoom auf 1.0 zuruecksetzen, StageRoot rendern,
    # damit Bitmap + Vektor-Shapes in Original-Aufloesung im PNG landen.
    # Anschliessend Zoom wiederherstellen.
    $cmdSave = {
        param($s, $e)
        try {
            $w = [int]$state.Bitmap.PixelWidth
            $h = [int]$state.Bitmap.PixelHeight
            $dpiX = $state.Bitmap.DpiX
            $dpiY = $state.Bitmap.DpiY
            if ($dpiX -le 0) { $dpiX = 96 }
            if ($dpiY -le 0) { $dpiY = 96 }

            $origScale = $c.StageScale.ScaleX
            $c.StageScale.ScaleX = 1.0
            $c.StageScale.ScaleY = 1.0
            try {
                # Layout-Pass forcieren, damit die neuen Massen aktiv sind,
                # BEVOR RenderTargetBitmap snapshotet.
                $c.StageRoot.UpdateLayout()

                $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap (
                    $w, $h, $dpiX, $dpiY,
                    [System.Windows.Media.PixelFormats]::Pbgra32)
                $rtb.Render($c.StageRoot)
                $rtb.Freeze()
            } finally {
                $c.StageScale.ScaleX = $origScale
                $c.StageScale.ScaleY = $origScale
            }

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

            try { [System.Windows.Clipboard]::SetImage($rtb) } catch { $null = $_ }

            # Toast mit Copy-Glyph (Segoe MDL2 0xE8C8) + Auto-Close des Editors.
            # Show-CaptureToast ist ueber LucentScreen.ps1 modul-weit verfuegbar.
            if (Get-Command Show-CaptureToast -ErrorAction SilentlyContinue) {
                $copyGlyph = "$([char]0xE8C8)"
                $fname = [System.IO.Path]::GetFileName($r.Path)
                Show-CaptureToast -Title 'Gespeichert + kopiert' -Subtitle $fname -Glyph $copyGlyph
            }
            $win.Close()
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
            # Wenn Fokus in einem Eingabefeld liegt (z.B. Slider), nicht stehlen
            switch ($e.Key) {
                'Escape' {
                    if ($state.Tool -eq 'Crop' -and $null -ne $state.Crop.Rect) {
                        & $cropCancel
                    } else {
                        $win.Close()
                    }
                    $e.Handled = $true; break
                }
                'Enter' {
                    if ($state.Tool -eq 'Crop') { & $cropApply; $e.Handled = $true }
                    break
                }
                'Return' {
                    if ($state.Tool -eq 'Crop') { & $cropApply; $e.Handled = $true }
                    break
                }
                default {
                    if ($ctrl -and $e.Key -eq [System.Windows.Input.Key]::S) {
                        & $cmdSave $null $null
                        $e.Handled = $true
                    } elseif ($ctrl -and $e.Key -eq [System.Windows.Input.Key]::Z) {
                        & $doUndo
                        $e.Handled = $true
                    } elseif ($ctrl -and $e.Key -eq [System.Windows.Input.Key]::Y) {
                        & $doRedo
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
                    } elseif (-not $ctrl) {
                        # Tool-Tastatur-Kuerzel nur ohne Strg, damit Strg+V o.ae.
                        # nicht das Tool umschaltet.
                        switch ($e.Key) {
                            'V' { $c.ToolSelect.IsChecked = $true; $e.Handled = $true }
                            'R' { $c.ToolRectangle.IsChecked = $true; $e.Handled = $true }
                            'L' { $c.ToolLine.IsChecked = $true; $e.Handled = $true }
                            'A' { $c.ToolArrow.IsChecked = $true; $e.Handled = $true }
                            'B' { $c.ToolBar.IsChecked = $true; $e.Handled = $true }
                            'M' { $c.ToolMarker.IsChecked = $true; $e.Handled = $true }
                            'C' { $c.ToolCrop.IsChecked = $true; $e.Handled = $true }
                        }
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
    & $applyColor $state.Color
    $c.TxtStroke.Text = ("{0:N0} px" -f $state.Stroke)
    $c.ShapeLayer.Cursor = [System.Windows.Input.Cursors]::Arrow

    [void]$win.ShowDialog()

    return @{
        Saved     = $state.Saved
        SavedPath = $state.SavedPath
        Status    = if ($state.Saved) { 'Saved' } else { 'Closed' }
        Message   = if ($state.Saved) { "Gespeichert: $($state.SavedPath)" } else { 'Editor geschlossen' }
    }
}

Export-ModuleMember -Function Show-EditorWindow
