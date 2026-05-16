#Requires -Version 5.1
<#
.SYNOPSIS
    LucentScreen -- Einstiegspunkt der Anwendung.
.DESCRIPTION
    Bootstrap-Sequenz (Reihenfolge ist nicht verhandelbar):
        1. STA-Apartment sicherstellen (Self-Relaunch falls noetig)
        2. Single-Instance-Mutex (zweite Instanz bricht still ab)
        3. Logging initialisieren
        4. DPI-Awareness PER_MONITOR_AWARE_V2 (vor jeder UI-Operation)
        5. WPF-Assemblies laden
        6. Globale Fehlerbehandlung (Dispatcher + AppDomain)
        7. System.Windows.Application-Instanz, ShutdownMode=OnExplicitShutdown
        8. Application.Run() -- blockierender Message-Loop

    Im aktuellen Stand (AP 0) gibt es noch keine UI. Die App startet, laeuft
    leer, kann ueber Ctrl+C bzw. den Task-Manager beendet werden. UI/Tray
    folgen mit AP 2.

    Parameter:
        -Debug  schaltet Log-MinLevel auf 'Debug'.
#>

[CmdletBinding()]
param(
    [switch]$DebugMode
)

# ---------------------------------------------------------------
# 1) STA-Apartment sicherstellen
# ---------------------------------------------------------------
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    # Self-Relaunch mit -STA. Windows PowerShell 5.1 (powershell.exe) ist
    # einziges Target -- garantiert auf jedem Windows-Enterprise-Host.
    $relaunchArgs = @('-NoProfile', '-STA', '-File', $PSCommandPath)
    if ($DebugMode) { $relaunchArgs += '-DebugMode' }
    Start-Process powershell.exe -ArgumentList $relaunchArgs | Out-Null
    exit 0
}

# ---------------------------------------------------------------
# 2) Single-Instance-Mutex
# ---------------------------------------------------------------
$script:InstanceMutex = [System.Threading.Mutex]::new($false, 'Global\LucentScreen.SingleInstance')
$script:MutexAcquired = $false
try {
    $script:MutexAcquired = $script:InstanceMutex.WaitOne(0, $false)
} catch [System.Threading.AbandonedMutexException] {
    # Vorherige Instanz beendete sich ohne Release -> wir uebernehmen
    $script:MutexAcquired = $true
}
if (-not $script:MutexAcquired) {
    exit 0
}

# ---------------------------------------------------------------
# 3) Logging
# ---------------------------------------------------------------
$rootDir = Split-Path -Parent $PSCommandPath
$coreDir = Join-Path $rootDir 'core'

Import-Module (Join-Path $coreDir 'logging.psm1') -Force
$logLevel = if ($DebugMode) { 'Debug' } else { 'Info' }
[void](Initialize-Logging -MinLevel $logLevel)
Write-LsLog -Level Info  -Source 'boot' -Message 'LucentScreen startet'
Write-LsLog -Level Debug -Source 'boot' -Message ("LogPath: " + (Get-LogPath))

# ---------------------------------------------------------------
# 3a) Konfiguration laden
# ---------------------------------------------------------------
Import-Module (Join-Path $coreDir 'config.psm1') -Force
$script:Config = Read-Config
Write-LsLog -Level Info  -Source 'boot' -Message ("Config geladen: " + (Get-ConfigPath))
Write-LsLog -Level Debug -Source 'boot' -Message ("OutputDir: " + $script:Config.OutputDir)
Write-LsLog -Level Debug -Source 'boot' -Message ("SchemaVersion: " + $script:Config.SchemaVersion)

# ---------------------------------------------------------------
# 4) DPI-Awareness
# ---------------------------------------------------------------
Import-Module (Join-Path $coreDir 'native.psm1') -Force
$dpi = Set-DpiAwareness
Write-LsLog -Level Info -Source 'boot' -Message ("DPI: " + $dpi.Status + " -- " + $dpi.Message)

# ---------------------------------------------------------------
# 5) WPF + Drawing + WinForms (NotifyIcon)
# ---------------------------------------------------------------
try {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    Add-Type -AssemblyName System.Xaml
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms
    Write-LsLog -Level Debug -Source 'boot' -Message 'WPF-Assemblies geladen'
} catch {
    Write-LsLog -Level Error -Source 'boot' -Message ("Assembly-Load fehlgeschlagen: " + $_.Exception.Message)
    exit 1
}

# XAML-Loader nachladen (braucht WPF-Assemblies)
Import-Module (Join-Path $coreDir 'xaml-loader.psm1') -Force

# ---------------------------------------------------------------
# 6) Globale Fehlerbehandlung
# ---------------------------------------------------------------
[System.AppDomain]::CurrentDomain.add_UnhandledException({
        param($src, $e)
        try {
            $ex = $e.ExceptionObject
            Write-LsLog -Level Error -Source 'appdomain' -Message ("Unhandled: " + $ex)
        } catch {
            # Logging selbst ist im Fehlerfall stumm -- die App soll trotzdem
            # weiterleben, falls der Handler greift.
            $null = $_
        }
    })

# ---------------------------------------------------------------
# 7) Application + Lifecycle
# ---------------------------------------------------------------
$app = [System.Windows.Application]::Current
if (-not $app) {
    $app = [System.Windows.Application]::new()
}
$app.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown

$app.add_DispatcherUnhandledException({
        param($src, $e)
        try {
            $ex = $e.Exception
            Write-LsLog -Level Error -Source 'dispatcher' -Message ("Unhandled: " + $ex.GetType().FullName + ": " + $ex.Message)
            # Bei PowerShell-ScriptBlock-Fehlern landet die Quelle als
            # InnerException -- die hat oft den interessanten Origin.
            $inner = $ex
            $depth = 0
            while ($null -ne $inner -and $depth -lt 5) {
                if ($inner.StackTrace) {
                    Write-LsLog -Level Error -Source 'dispatcher' -Message ("Stack[$depth]: " + ($inner.StackTrace -replace "`r?`n", ' | '))
                }
                $inner = $inner.InnerException
                $depth++
            }
            $e.Handled = $true  # App nicht crashen lassen
        } catch {
            $null = $_
        }
    })

$app.add_Exit({
        Write-LsLog -Level Info -Source 'shutdown' -Message 'Application.Exit-Event'
        if ($script:HotkeyHwnd -and $script:HotkeyHwnd -ne [IntPtr]::Zero) {
            try { Unregister-AllHotkeys -Hwnd $script:HotkeyHwnd } catch { $null = $_ }
        }
        if ($script:TrayDispose) {
            try { $script:TrayDispose.Invoke() } catch { $null = $_ }
        }
        try { $script:InstanceMutex.ReleaseMutex() } catch { $null = $_ }
        try { $script:InstanceMutex.Dispose() } catch { $null = $_ }
    })

# ---------------------------------------------------------------
# 8) Tray-Icon + Kontextmenue
# ---------------------------------------------------------------
$uiDir = Join-Path $rootDir 'ui'
Import-Module (Join-Path $coreDir 'hotkeys.psm1') -Force
Import-Module (Join-Path $coreDir 'capture.psm1') -Force
Import-Module (Join-Path $coreDir 'clipboard.psm1') -Force
Import-Module (Join-Path $uiDir 'about-dialog.psm1') -Force
Import-Module (Join-Path $uiDir 'config-dialog.psm1') -Force
Import-Module (Join-Path $uiDir 'region-overlay.psm1') -Force
Import-Module (Join-Path $uiDir 'countdown-overlay.psm1') -Force
Import-Module (Join-Path $uiDir 'capture-toast.psm1') -Force
Import-Module (Join-Path $coreDir 'history.psm1') -Force
Import-Module (Join-Path $uiDir 'history-window.psm1') -Force
Import-Module (Join-Path $coreDir 'editor.psm1') -Force
Import-Module (Join-Path $uiDir 'editor-window.psm1') -Force
Import-Module (Join-Path $uiDir 'tray.psm1') -Force

$assetsDir = Join-Path $rootDir '..\assets'
# Zwei Icon-Pfade: ICO fuer scharfe Tray-/Window-Titelleisten-Anzeige,
# PNG fuer den hochaufloesenden About-Dialog-Header.
# ICO-Auswahl: bevorzugt 'luscreen.ico'. Falls nicht vorhanden, suche nach
# *.ico mit groesster Aufloesung (Tray skaliert ggf. runter).
$iconPath = $null
$preferred = Join-Path $assetsDir 'luscreen.ico'
if (Test-Path -LiteralPath $preferred) {
    $iconPath = (Resolve-Path $preferred).Path
} else {
    # Fallback: groesste *.ico waehlen (Heuristik: Dateiname mit groessten
    # Pixel-Dimensionen, sonst die groesste Datei).
    $icoFiles = Get-ChildItem -LiteralPath $assetsDir -Filter '*.ico' -File -EA SilentlyContinue
    if ($icoFiles) {
        $sizeFromName = { param($f) if ($f.BaseName -match '(\d+)x\d+') { [int]$Matches[1] } else { 0 } }
        $sortBySize = @{ Expression = $sizeFromName; Descending = $true }
        $sortByLen = @{ Expression = 'Length'; Descending = $true }
        $picked = $icoFiles | Sort-Object -Property $sortBySize, $sortByLen | Select-Object -First 1
        $iconPath = $picked.FullName
    }
}
if (-not $iconPath) {
    throw "Kein Icon gefunden in $assetsDir (weder luscreen.ico noch sonstiges *.ico)."
}
$iconPngPath = Join-Path $assetsDir 'icon.png'
if (Test-Path -LiteralPath $iconPngPath) { $iconPngPath = (Resolve-Path $iconPngPath).Path } else { $iconPngPath = $null }
# Default-Window-Icon fuer alle Dialoge (Konfig/Editor/Verlauf/About-Titelleiste)
Set-AppDefaultIcon -Path $iconPath
$appVersion = '0.2.0'

$script:TrayDispose = $null

$invokeCapture = {
    param($mode)
    try {
        Write-LsLog -Level Info -Source 'capture' -Message "Mode=$mode angefordert"
        $delay = [int]$script:Config.DelaySeconds

        $regionRect = $null
        if ($mode -eq 'Region') {
            $regionRect = Show-RegionOverlay
            if ($null -eq $regionRect) {
                Write-LsLog -Level Info -Source 'capture' -Message 'Region-Auswahl abgebrochen'
                return
            }
        }

        # Countdown vor Capture -- Overlay verschwindet beim Close() und der
        # WPF-Dispatcher rendert das vor dem naechsten Screenshot.
        if ($delay -gt 0) {
            $proceed = Show-CountdownOverlay -Seconds $delay
            if (-not $proceed) {
                Write-LsLog -Level Info -Source 'capture' -Message 'Countdown abgebrochen'
                return
            }
            # Kleiner Yield, damit das Overlay sicher weg ist
            Start-Sleep -Milliseconds 80
        }

        # Delay=0 hier -- das Warten hat das Overlay schon erledigt
        $r = Invoke-Capture -Mode $mode -RegionRect $regionRect -DelaySeconds 0
        if (-not $r.Success) {
            Write-LsLog -Level Warn -Source 'capture' -Message ("Capture fehlgeschlagen: " + $r.Message)
            return
        }
        try {
            $tmpl = if ($script:Config.ContainsKey('FileNameFormat') -and $script:Config.FileNameFormat) {
                $script:Config.FileNameFormat
            } else {
                'yyyyMMdd_HHmm_{mode}.png'
            }
            $save = Save-Capture -Bitmap $r.Bitmap -Mode $mode `
                -OutputDir $script:Config.OutputDir -Template $tmpl
            if ($save.Success) {
                Write-LsLog -Level Info -Source 'capture' -Message ("OK: {0} ({1}x{2}) -> {3}" -f $mode, $r.Width, $r.Height, $save.Path)
                $fname = [System.IO.Path]::GetFileName($save.Path)
                Show-CaptureToast -Title 'Aufgenommen' -Subtitle ("{0}  {1}x{2}" -f $fname, $r.Width, $r.Height)
            } else {
                Write-LsLog -Level Error -Source 'capture' -Message ("Speichern fehlgeschlagen: " + $save.Message)
            }

            $clip = Set-ClipboardImage -Bitmap $r.Bitmap
            if ($clip.Success) {
                Write-LsLog -Level Debug -Source 'capture' -Message ("Clipboard: " + $clip.Message)
            } else {
                Write-LsLog -Level Warn -Source 'capture' -Message ("Clipboard fehlgeschlagen: " + $clip.Message)
            }
        } finally {
            if ($r.Bitmap) { $r.Bitmap.Dispose() }
        }
    } catch {
        Write-LsLog -Level Error -Source 'capture' -Message ("Capture-Exception: " + $_.Exception.Message)
    }
}

$callbacks = @{
    Region       = { $invokeCapture.Invoke('Region') }.GetNewClosure()
    ActiveWindow = { $invokeCapture.Invoke('ActiveWindow') }.GetNewClosure()
    Monitor      = { $invokeCapture.Invoke('Monitor') }.GetNewClosure()
    AllMonitors  = { $invokeCapture.Invoke('AllMonitors') }.GetNewClosure()

    HistoryOpen = {
        Write-LsLog -Level Info -Source 'tray' -Message 'Verlauf geoeffnet'
        try {
            $postfix = if ($script:Config.ContainsKey('EditPostfix') -and $script:Config.EditPostfix) { $script:Config.EditPostfix } else { '_edited' }
            $iconSize = if ($script:Config.ContainsKey('HistoryIconSize')) { [int]$script:Config.HistoryIconSize } else { 20 }
            Write-LsLog -Level Info -Source 'tray' -Message ("Verlauf: IconSize={0}" -f $iconSize)
            Show-HistoryWindow -OutputDir $script:Config.OutputDir -EditPostfix $postfix -IconSize $iconSize
        } catch {
            Write-LsLog -Level Error -Source 'tray' -Message ("Verlauf fehlgeschlagen: " + $_.Exception.Message)
        }
    }.GetNewClosure()

    Config = {
        Write-LsLog -Level Info -Source 'tray' -Message 'Konfig-Dialog geoeffnet'
        $updated = Show-ConfigDialog -Config $script:Config
        if ($null -ne $updated) {
            $r = Save-Config -Config $updated
            if ($r.Success) {
                # Inplace-Update der bestehenden Hashtable -- $script:Config = $updated
                # wuerde im .GetNewClosure()-Closure in einen isolierten Scope schreiben,
                # andere Closures saehen den alten Wert weiter. Reference bleibt erhalten.
                foreach ($k in @($script:Config.Keys)) { $script:Config.Remove($k) }
                foreach ($k in $updated.Keys) { $script:Config[$k] = $updated[$k] }
                Write-LsLog -Level Info -Source 'tray' -Message ("Konfig gespeichert (HistoryIconSize={0})" -f $script:Config.HistoryIconSize)
                if ($script:HotkeyHwnd -and $script:HotkeyHwnd -ne [IntPtr]::Zero) {
                    $hkResult = Register-AllHotkeys -Hwnd $script:HotkeyHwnd -HotkeyMap $script:Config.Hotkeys -Callbacks $callbacks
                    Write-LsLog -Level Info -Source 'hotkey' -Message ("Re-registriert: {0}, Konflikte: {1}" -f $hkResult.Registered.Count, $hkResult.Conflicts.Count)
                }
            } else {
                Write-LsLog -Level Error -Source 'tray' -Message ("Konfig-Speichern fehlgeschlagen: " + $r.Message)
            }
        }
    }.GetNewClosure()

    About = {
        # Header-Icon = PNG (gross + alpha), Window-Titel-Icon = ICO (multi-size)
        $hdr = if ($iconPngPath) { $iconPngPath } else { $iconPath }
        Show-AboutDialog -Version $appVersion -IconPath $hdr -WindowIconPath $iconPath
    }.GetNewClosure()

    DelayReset = {
        $script:Config.DelaySeconds = 0
        $r = Save-Config -Config $script:Config
        if ($r.Success) {
            Write-LsLog -Level Info -Source 'tray' -Message 'Verzoegerung -> 0'
            try { Show-CaptureToast -Title 'Verzögerung zurückgesetzt' -Subtitle '0 Sek' -Glyph "$([char]0xE777)" } catch { $null = $_ }
        } else {
            Write-LsLog -Level Error -Source 'tray' -Message ("DelayReset Save fehlgeschlagen: " + $r.Message)
        }
    }.GetNewClosure()

    DelayPlus5 = {
        $cur = if ($script:Config.ContainsKey('DelaySeconds')) { [int]$script:Config.DelaySeconds } else { 0 }
        $new = [math]::Min(30, $cur + 5)
        $script:Config.DelaySeconds = $new
        $r = Save-Config -Config $script:Config
        if ($r.Success) {
            Write-LsLog -Level Info -Source 'tray' -Message ("Verzoegerung {0} -> {1}" -f $cur, $new)
            try { Show-CaptureToast -Title ("Verzögerung {0} Sek" -f $new) -Subtitle ("vorher {0}" -f $cur) -Glyph "$([char]0xE916)" } catch { $null = $_ }
        } else {
            Write-LsLog -Level Error -Source 'tray' -Message ("DelayPlus5 Save fehlgeschlagen: " + $r.Message)
        }
    }.GetNewClosure()

    Exit = {
        Write-LsLog -Level Info -Source 'tray' -Message 'Beenden ueber Tray-Menue'
        [System.Windows.Application]::Current.Shutdown()
    }.GetNewClosure()
}

$trayResult = Initialize-Tray -Icon $iconPath -Version $appVersion -Callbacks $callbacks -HotkeyMap $script:Config.Hotkeys
$script:TrayDispose = $trayResult.Dispose
Write-LsLog -Level Info -Source 'boot' -Message 'Tray-Icon aktiv'

# ---------------------------------------------------------------
# 9) Globale Hotkeys
# ---------------------------------------------------------------
# Hidden-WPF-Fenster, das nie sichtbar wird -- liefert nur den HWND,
# an dem WM_HOTKEY ankommt. EnsureHandle() erzeugt den Handle ohne
# Show() aufzurufen.
$script:HotkeyHwnd = [IntPtr]::Zero
$hiddenWindow = New-Object System.Windows.Window
$hiddenWindow.WindowStyle = [System.Windows.WindowStyle]::None
$hiddenWindow.ShowInTaskbar = $false
$hiddenWindow.Width = 0
$hiddenWindow.Height = 0
$hiddenWindow.Top = -10000
$hiddenWindow.Left = -10000
$hiddenWindow.Visibility = [System.Windows.Visibility]::Hidden

$helper = New-Object System.Windows.Interop.WindowInteropHelper $hiddenWindow
[void]$helper.EnsureHandle()
$script:HotkeyHwnd = $helper.Handle

$hotkeyHook = {
    param($h, $msg, $wp, $lp, [ref]$handled)
    if ($msg -eq [LucentScreen.HotKey]::WM_HOTKEY) {
        $id = [int]$wp
        Invoke-HotkeyById -Id $id
        $handled.Value = $true
    }
    return [IntPtr]::Zero
}
$hotkeySource = [System.Windows.Interop.HwndSource]::FromHwnd($script:HotkeyHwnd)
$hotkeySource.AddHook($hotkeyHook)

$hkResult = Register-AllHotkeys -Hwnd $script:HotkeyHwnd -HotkeyMap $script:Config.Hotkeys -Callbacks $callbacks
Write-LsLog -Level Info -Source 'hotkey' -Message ("Registriert: {0}, Konflikte: {1}" -f $hkResult.Registered.Count, $hkResult.Conflicts.Count)
foreach ($c in $hkResult.Conflicts) {
    Write-LsLog -Level Warn -Source 'hotkey' -Message ("Konflikt '{0}' ({1}): {2}" -f $c.Name, $c.Display, $c.Reason)
}
if ($hkResult.Conflicts.Count -gt 0) {
    $msg = "Folgende Hotkeys konnten nicht registriert werden (vermutlich von einer anderen Anwendung belegt):`n`n"
    foreach ($c in $hkResult.Conflicts) {
        $msg += " - $($c.Name): $($c.Display)`n"
    }
    $msg += "`nBitte in der Konfiguration eine andere Kombination waehlen."
    [System.Windows.MessageBox]::Show(
        $msg, 'LucentScreen -- Hotkey-Konflikt',
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Warning) | Out-Null
}

Write-LsLog -Level Info -Source 'boot' -Message 'Bootstrap abgeschlossen, App-Loop startet'

# ---------------------------------------------------------------
# 10) Message-Loop
# ---------------------------------------------------------------
[void]$app.Run()
