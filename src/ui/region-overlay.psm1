#Requires -Version 5.1
Set-StrictMode -Version Latest

# ---------------------------------------------------------------
#  Vollbild-Overlay fuer Bereichs-Capture
#
#  Show-RegionOverlay
#    -> $null bei Abbruch (ESC)
#    -> hashtable @{ Left; Top; Width; Height } im Bildschirm-Koordinatensystem
#
#  Voraussetzungen:
#    - STA, WPF-Assemblies geladen
#    - core/xaml-loader.psm1 (Load-Xaml, Get-XamlControls)
#    - System.Windows.Forms (fuer SystemInformation.VirtualScreen)
# ---------------------------------------------------------------

function Show-RegionOverlay {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        throw 'Show-RegionOverlay benoetigt ein STA-Apartment.'
    }

    $xamlPath = Join-Path $PSScriptRoot '..\views\region-overlay.xaml'
    $win = Load-Xaml -Path $xamlPath
    $c = Get-XamlControls -Root $win -Names 'Cv', 'Sel', 'HintText', 'SizeText'

    # Window ueber das gesamte Virtual-Screen-Rechteck strecken
    $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $win.Left = $vs.Left
    $win.Top = $vs.Top
    $win.Width = $vs.Width
    $win.Height = $vs.Height

    # State per Closure
    $state = @{
        Dragging  = $false
        StartX    = 0
        StartY    = 0
        Result    = $null
        VsLeft    = [int]$vs.Left
        VsTop     = [int]$vs.Top
    }

    $win.Add_MouseLeftButtonDown({
            param($s, $e)
            $p = $e.GetPosition($c.Cv)
            $state.Dragging = $true
            $state.StartX = $p.X
            $state.StartY = $p.Y
            [System.Windows.Controls.Canvas]::SetLeft($c.Sel, $p.X)
            [System.Windows.Controls.Canvas]::SetTop($c.Sel, $p.Y)
            $c.Sel.Width = 0
            $c.Sel.Height = 0
            $c.Sel.Visibility = [System.Windows.Visibility]::Visible
            $c.HintText.Visibility = [System.Windows.Visibility]::Collapsed
            $c.SizeText.Visibility = [System.Windows.Visibility]::Visible
        }.GetNewClosure())

    $win.Add_MouseMove({
            param($s, $e)
            if (-not $state.Dragging) { return }
            $p = $e.GetPosition($c.Cv)
            $x = [Math]::Min($state.StartX, $p.X)
            $y = [Math]::Min($state.StartY, $p.Y)
            $w = [Math]::Abs($p.X - $state.StartX)
            $h = [Math]::Abs($p.Y - $state.StartY)
            [System.Windows.Controls.Canvas]::SetLeft($c.Sel, $x)
            [System.Windows.Controls.Canvas]::SetTop($c.Sel, $y)
            $c.Sel.Width = $w
            $c.Sel.Height = $h
            [System.Windows.Controls.Canvas]::SetLeft($c.SizeText, $x + $w + 8)
            [System.Windows.Controls.Canvas]::SetTop($c.SizeText, $y)
            $c.SizeText.Text = ("{0} x {1}" -f [int]$w, [int]$h)
        }.GetNewClosure())

    $win.Add_MouseLeftButtonUp({
            param($s, $e)
            if (-not $state.Dragging) { return }
            $state.Dragging = $false
            $w = [int]$c.Sel.Width
            $h = [int]$c.Sel.Height
            if ($w -lt 4 -or $h -lt 4) {
                # zu klein -> als Cancel werten
                $win.Close()
                return
            }
            $x = [int][System.Windows.Controls.Canvas]::GetLeft($c.Sel)
            $y = [int][System.Windows.Controls.Canvas]::GetTop($c.Sel)
            $state.Result = @{
                Left   = $state.VsLeft + $x
                Top    = $state.VsTop + $y
                Width  = $w
                Height = $h
            }
            $win.Close()
        }.GetNewClosure())

    $win.Add_KeyDown({
            param($s, $e)
            if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
                $state.Result = $null
                $win.Close()
            }
        }.GetNewClosure())

    [void]$win.ShowDialog()
    return $state.Result
}

Export-ModuleMember -Function Show-RegionOverlay
