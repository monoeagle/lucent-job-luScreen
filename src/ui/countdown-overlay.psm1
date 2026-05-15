#Requires -Version 5.1
Set-StrictMode -Version Latest

# ---------------------------------------------------------------
#  Countdown-Overlay vor Capture
#
#  Show-CountdownOverlay -Seconds <int>
#    -> $true wenn Countdown durchlief (Capture kann starten)
#    -> $false wenn vom User per ESC abgebrochen wurde
#
#  Verhalten:
#    - Seconds <= 0 -> direkt $true (kein Fenster)
#    - Click-Through via WS_EX_TRANSPARENT (User kann durch Overlay
#      klicken)
#    - WS_EX_NOACTIVATE (Overlay zieht keinen Fokus)
#    - DispatcherTimer tickt sekuendlich, ESC bricht ab
#    - Position: rechts unten auf dem Monitor unter der Maus, mit
#      einem Sicherheitsabstand fuer Taskbar
#
#  Voraussetzungen: STA, WPF-Assemblies + System.Windows.Forms,
#  core/native.psm1, core/xaml-loader.psm1
# ---------------------------------------------------------------

function Show-CountdownOverlay {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][int]$Seconds)

    if ($Seconds -le 0) { return $true }

    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        throw 'Show-CountdownOverlay benoetigt ein STA-Apartment.'
    }

    $xamlPath = Join-Path $PSScriptRoot '..\views\countdown-overlay.xaml'
    $win = Load-Xaml -Path $xamlPath
    $c = Get-XamlControls -Root $win -Names 'TxtCount'

    # Position rechts unten auf dem Maus-Monitor
    $cursor = [System.Windows.Forms.Cursor]::Position
    $screen = [System.Windows.Forms.Screen]::FromPoint($cursor)
    $b = $screen.WorkingArea  # respektiert Taskbar
    $win.Left = $b.Right - $win.Width - 24
    $win.Top = $b.Bottom - $win.Height - 24

    $c.TxtCount.Text = $Seconds.ToString()

    # State via Hashtable -- closures sehen die gleiche Referenz
    $state = @{
        Remaining = $Seconds
        Cancelled = $false
        Timer     = $null
    }

    # Click-Through + No-Activate setzen, sobald HWND existiert
    $win.Add_SourceInitialized({
            param($s, $e)
            $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper $win).Handle
            $ex = [LucentScreen.Native]::GetWindowLong($hwnd, [LucentScreen.Native]::GWL_EXSTYLE)
            $ex = $ex -bor [LucentScreen.Native]::WS_EX_TRANSPARENT `
                -bor [LucentScreen.Native]::WS_EX_NOACTIVATE `
                -bor [LucentScreen.Native]::WS_EX_TOOLWINDOW
            [void][LucentScreen.Native]::SetWindowLong($hwnd, [LucentScreen.Native]::GWL_EXSTYLE, $ex)
        }.GetNewClosure())

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(1)
    $state.Timer = $timer

    $timer.Add_Tick({
            param($s, $e)
            $state.Remaining--
            if ($state.Remaining -le 0) {
                $state.Timer.Stop()
                $win.Close()
            } else {
                $c.TxtCount.Text = $state.Remaining.ToString()
            }
        }.GetNewClosure())

    # ESC abfangen -- WS_EX_TRANSPARENT blockt Maus, aber Tastatur funktioniert
    # weiter, sobald das Fenster Tastatur-Fokus haette. Sicherer: ueber
    # Application-Level KeyDown. Vereinfacht: PreviewKeyDown.
    $win.Add_PreviewKeyDown({
            param($s, $e)
            if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
                $state.Cancelled = $true
                $state.Timer.Stop()
                $win.Close()
            }
        }.GetNewClosure())

    $timer.Start()
    $win.Show()

    # Modale Schleife mit DispatcherFrame -- ShowDialog scheidet aus,
    # weil WS_EX_NOACTIVATE den Fokus blockt. So warten wir auf Close().
    $frame = New-Object System.Windows.Threading.DispatcherFrame
    $win.Add_Closed({
            param($s, $e)
            $frame.Continue = $false
        }.GetNewClosure())
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)

    return (-not $state.Cancelled)
}

Export-ModuleMember -Function Show-CountdownOverlay
