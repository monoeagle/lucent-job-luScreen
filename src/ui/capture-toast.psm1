#Requires -Version 5.1
Set-StrictMode -Version Latest

# ---------------------------------------------------------------
#  Capture-Toast
#
#  Kurze visuelle Bestaetigung oben rechts nach erfolgreichem Capture.
#  Kamera-Glyph + Titel + Subtitle (Modus/Dateiname), fade-in/fade-out,
#  Auto-Close nach DurationMs.
#
#  Show-CaptureToast -Title <string> -Subtitle <string> [-DurationMs 1400]
#    -> nichts (non-blocking, kehrt sofort zurueck)
#
#  Verhalten:
#    - Click-through (WS_EX_TRANSPARENT) + NoActivate + ToolWindow
#    - Position rechts oben auf dem Monitor unter Maus (WorkingArea)
#    - DispatcherTimer triggert FadeOut + Close
#    - Wenn schon ein Toast offen ist: alten schliessen, neuen zeigen
#
#  Voraussetzungen: STA, WPF + System.Windows.Forms, native.psm1,
#  core/xaml-loader.psm1
# ---------------------------------------------------------------

$script:CurrentToast = $null

function _Close-ExistingToast {
    if ($null -ne $script:CurrentToast) {
        try { $script:CurrentToast.Close() } catch { $null = $_ }
        $script:CurrentToast = $null
    }
}

function Show-CaptureToast {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [string]$Subtitle = '',
        [int]$DurationMs = 1400
    )

    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        # Stiller Fail -- Toast ist nice-to-have
        return
    }

    _Close-ExistingToast

    try {
        $xamlPath = Join-Path $PSScriptRoot '..\views\capture-toast.xaml'
        $win = Load-Xaml -Path $xamlPath
        $c = Get-XamlControls -Root $win -Names 'TxtTitle', 'TxtSubtitle'
        $c.TxtTitle.Text = $Title
        $c.TxtSubtitle.Text = $Subtitle

        # Position rechts oben auf dem Maus-Monitor
        $cursor = [System.Windows.Forms.Cursor]::Position
        $screen = [System.Windows.Forms.Screen]::FromPoint($cursor)
        $b = $screen.WorkingArea
        $win.Left = $b.Right - $win.Width - 24
        $win.Top = $b.Top + 24
        $win.Opacity = 0

        # Click-through + no focus stealing
        $win.Add_SourceInitialized({
                param($s, $e)
                $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper $win).Handle
                $ex = [LucentScreen.Native]::GetWindowLong($hwnd, [LucentScreen.Native]::GWL_EXSTYLE)
                $ex = $ex -bor [LucentScreen.Native]::WS_EX_TRANSPARENT `
                    -bor [LucentScreen.Native]::WS_EX_NOACTIVATE `
                    -bor [LucentScreen.Native]::WS_EX_TOOLWINDOW
                [void][LucentScreen.Native]::SetWindowLong($hwnd, [LucentScreen.Native]::GWL_EXSTYLE, $ex)
            })

        $script:CurrentToast = $win

        $win.Show()
        # FadeIn
        $fadeIn = $win.FindResource('FadeIn')
        $win.BeginStoryboard($fadeIn)

        # Auto-Close-Timer
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromMilliseconds($DurationMs)
        $state = @{ Win = $win; Timer = $timer }
        $timer.Add_Tick({
                param($s, $e)
                $state.Timer.Stop()
                try {
                    $fadeOut = $state.Win.FindResource('FadeOut')
                    $fadeOut.Completed.Add({
                            try { $state.Win.Close() } catch { $null = $_ }
                            if ($script:CurrentToast -eq $state.Win) { $script:CurrentToast = $null }
                        }.GetNewClosure())
                    $state.Win.BeginStoryboard($fadeOut)
                } catch {
                    try { $state.Win.Close() } catch { $null = $_ }
                    if ($script:CurrentToast -eq $state.Win) { $script:CurrentToast = $null }
                }
            }.GetNewClosure())
        $timer.Start()
    } catch {
        Write-Warning ("Capture-Toast fehlgeschlagen: " + $_.Exception.Message)
        $script:CurrentToast = $null
    }
}

Export-ModuleMember -Function Show-CaptureToast
