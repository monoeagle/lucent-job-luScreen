#Requires -Version 7.0
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
    # Self-Relaunch mit -STA und den gleichen Parametern
    $relaunchArgs = @('-NoProfile', '-STA', '-File', $PSCommandPath)
    if ($DebugMode) { $relaunchArgs += '-DebugMode' }
    Start-Process pwsh -ArgumentList $relaunchArgs | Out-Null
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
[void](Initialize-Logging -MinLevel ($DebugMode ? 'Debug' : 'Info'))
Write-LsLog -Level Info  -Source 'boot' -Message 'LucentScreen startet'
Write-LsLog -Level Debug -Source 'boot' -Message ("LogPath: " + (Get-LogPath))

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
        try { $script:InstanceMutex.ReleaseMutex() } catch { $null = $_ }
        try { $script:InstanceMutex.Dispose() } catch { $null = $_ }
    })

Write-LsLog -Level Info -Source 'boot' -Message 'Bootstrap abgeschlossen, App-Loop startet'

# ---------------------------------------------------------------
# 8) Message-Loop
#    AP 0: keine UI -> Application.Run() ohne MainWindow blockiert
#    bis Shutdown() explizit aufgerufen wird (oder Ctrl+C / Stop-Process).
#    AP 2 (Tray-Icon) wird vor diesem Aufruf das NotifyIcon initialisieren.
# ---------------------------------------------------------------
[void]$app.Run()
