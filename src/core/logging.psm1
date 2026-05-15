#Requires -Version 5.1
Set-StrictMode -Version Latest

# ---------------------------------------------------------------
#  Zentrales Logging fuer LucentScreen
#
#  Datei:           %LOCALAPPDATA%/LucentScreen/logs/app.log
#  Format:          yyyy-MM-dd HH:mm:ss.fff [LVL] [SRC] Message
#  Rotation:        taeglich, max. 7 Tage Vorhalt (alte Dateien werden
#                   beim Start automatisch geloescht)
#  Levels:          Debug | Info | Warn | Error
#  Thread-Safety:   System.Threading.Mutex pro Log-Datei
#
#  Initialisierung:
#      Initialize-Logging                       -- Default-Pfad
#      Initialize-Logging -Path '<custom>'      -- abweichender Pfad
#      Initialize-Logging -MinLevel 'Debug'     -- mehr Detail
#
#  Verwendung:
#      Write-LsLog -Level Info -Source 'app' -Message 'gestartet'
# ---------------------------------------------------------------

$script:LogPath = $null
$script:LogMutex = $null
$script:MinLevel = 'Info'
$script:LevelOrder = @{ Debug = 0; Info = 1; Warn = 2; Error = 3 }
$script:RetainDays = 7
$script:Initialized = $false

function Initialize-Logging {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$Path,
        [ValidateSet('Debug', 'Info', 'Warn', 'Error')][string]$MinLevel = 'Info',
        [int]$RetainDays = 7
    )

    if (-not $Path) {
        $base = Join-Path $env:LOCALAPPDATA 'LucentScreen/logs'
        $Path = Join-Path $base 'app.log'
    }

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Force -Path $dir
    }

    $script:LogPath = $Path
    $script:MinLevel = $MinLevel
    $script:RetainDays = $RetainDays
    $mutexName = 'Global\LucentScreen.Log.' + ([guid]::NewGuid().ToString('N'))
    $script:LogMutex = [System.Threading.Mutex]::new($false, $mutexName)
    $script:Initialized = $true

    _Rotate-Logs

    return @{
        Success = $true
        Status  = 'OK'
        Message = "Logging aktiv: $Path (MinLevel=$MinLevel, RetainDays=$RetainDays)"
        Path    = $Path
    }
}

function _Rotate-Logs {
    if (-not $script:LogPath) { return }
    $dir = Split-Path -Parent $script:LogPath
    if (-not (Test-Path -LiteralPath $dir)) { return }

    $threshold = (Get-Date).AddDays(-1 * $script:RetainDays)
    Get-ChildItem -LiteralPath $dir -File -Filter 'app*.log' -EA SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $threshold } |
        Remove-Item -Force -EA SilentlyContinue
}

function Write-LsLog {
    [CmdletBinding()]
    param(
        [ValidateSet('Debug', 'Info', 'Warn', 'Error')][string]$Level = 'Info',
        [string]$Source = 'app',
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $script:Initialized) {
        # Auto-Init mit Defaults, damit kein Aufruf still failed
        [void](Initialize-Logging)
    }

    if ($script:LevelOrder[$Level] -lt $script:LevelOrder[$script:MinLevel]) { return }

    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    $line = "$ts [$Level] [$Source] $Message"

    $acquired = $false
    try {
        $acquired = $script:LogMutex.WaitOne(1000)
        if ($acquired) {
            Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8
        }
    } catch {
        # Logging darf nie die App killen -- bewusst stumm.
        $null = $_
    } finally {
        if ($acquired) { $script:LogMutex.ReleaseMutex() }
    }
}

function Get-LogPath {
    return $script:LogPath
}

function Get-LogMinLevel {
    return $script:MinLevel
}

Export-ModuleMember -Function Initialize-Logging, Write-LsLog, Get-LogPath, Get-LogMinLevel
