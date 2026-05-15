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
            Write-LsLog -Level Error -Source 'dispatcher' -Message ("Unhandled: " + $e.Exception.Message)
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
Import-Module (Join-Path $uiDir 'about-dialog.psm1') -Force
Import-Module (Join-Path $uiDir 'config-dialog.psm1') -Force
Import-Module (Join-Path $uiDir 'region-overlay.psm1') -Force
Import-Module (Join-Path $uiDir 'tray.psm1') -Force

$assetsDir = Join-Path $rootDir '..\assets'
$iconPath = Resolve-Path (Join-Path $assetsDir 'luscreen.ico')
$appVersion = '0.1.0'

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

        $r = Invoke-Capture -Mode $mode -RegionRect $regionRect -DelaySeconds $delay
        if (-not $r.Success) {
            Write-LsLog -Level Warn -Source 'capture' -Message ("Capture fehlgeschlagen: " + $r.Message)
            return
        }
        try {
            $save = Save-Capture -Bitmap $r.Bitmap -Mode $mode -OutputDir $script:Config.OutputDir
            if ($save.Success) {
                Write-LsLog -Level Info -Source 'capture' -Message ("OK: {0} ({1}x{2}) -> {3}" -f $mode, $r.Width, $r.Height, $save.Path)
            } else {
                Write-LsLog -Level Error -Source 'capture' -Message ("Speichern fehlgeschlagen: " + $save.Message)
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

    History = {
        Write-LsLog -Level Info -Source 'tray' -Message 'Verlauf angefordert (AP 8 -- noch nicht implementiert)'
        [System.Windows.MessageBox]::Show(
            'Verlauf folgt mit AP 8.',
            'LucentScreen',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information) | Out-Null
    }.GetNewClosure()

    Config = {
        Write-LsLog -Level Info -Source 'tray' -Message 'Konfig-Dialog geoeffnet'
        $updated = Show-ConfigDialog -Config $script:Config
        if ($null -ne $updated) {
            $r = Save-Config -Config $updated
            if ($r.Success) {
                $script:Config = $updated
                Write-LsLog -Level Info -Source 'tray' -Message 'Konfig gespeichert'
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
        Show-AboutDialog -Version $appVersion -IconPath $iconPath.Path
    }.GetNewClosure()

    Exit = {
        Write-LsLog -Level Info -Source 'tray' -Message 'Beenden ueber Tray-Menue'
        [System.Windows.Application]::Current.Shutdown()
    }.GetNewClosure()
}

$trayResult = Initialize-Tray -Icon $iconPath.Path -Version $appVersion -Callbacks $callbacks
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
