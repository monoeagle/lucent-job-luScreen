#Requires -Version 5.1
Set-StrictMode -Version Latest

# ---------------------------------------------------------------
#  LucentScreen Config
#
#  Pfad:    %APPDATA%/LucentScreen/config.json
#  Format:  JSON, UTF-8 ohne BOM
#  Schema:  versioniert ueber Feld 'SchemaVersion'
#
#  API:
#    Get-DefaultConfig           -> hashtable mit allen Defaults
#    Get-ConfigPath              -> string (Default-Pfad)
#    Read-Config [-Path <p>]     -> hashtable (Defaults + persistente Werte,
#                                    Migration angewendet)
#    Save-Config -Config <h> [-Path <p>]
#                                -> result-hashtable (Success/Status/Message/Path)
#
#  Verhalten:
#    - Datei fehlt    -> Defaults zurueck, NICHT automatisch anlegen
#    - Datei kaputt   -> Defaults zurueck, Eintrag im Log (durch Caller)
#    - Schema veraltet-> Migration via _Migrate-Config (fuer kuenftige Versionen)
#    - Geladene Werte werden mit Defaults gemerged: fehlende Keys
#      bekommen den Default, ueberzaehlige Keys bleiben erhalten.
# ---------------------------------------------------------------

$script:CurrentSchemaVersion = 1

function Get-ConfigPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return (Join-Path $env:APPDATA 'LucentScreen/config.json')
}

function Get-DefaultConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    # Standard-Zielordner: ~/Pictures/LucentScreen. Wird beim ersten Save
    # angelegt; Existenzpruefung passiert in core/files (kommt mit AP 6).
    $pics = [Environment]::GetFolderPath('MyPictures')
    if (-not $pics) { $pics = Join-Path $env:USERPROFILE 'Pictures' }
    $outputDir = Join-Path $pics 'LucentScreen'

    return @{
        SchemaVersion  = $script:CurrentSchemaVersion
        OutputDir      = $outputDir
        DelaySeconds   = 0
        FileNameFormat = 'LucentScreen_yyyy-MM-dd_HH-mm-ss_{mode}.png'
        EditPostfix    = '_edited'
        Hotkeys        = @{
            Region       = @{ Modifiers = @('Control', 'Shift'); Key = 'D1' }
            ActiveWindow = @{ Modifiers = @('Control', 'Shift'); Key = 'D2' }
            Monitor      = @{ Modifiers = @('Control', 'Shift'); Key = 'D3' }
            AllMonitors  = @{ Modifiers = @('Control', 'Shift'); Key = 'D4' }
            TrayMenu     = @{ Modifiers = @('Control', 'Shift'); Key = 'D0' }
        }
    }
}

# Wandelt einen PSCustomObject (aus ConvertFrom-Json) rekursiv in eine
# Hashtable um. Notwendig, weil PowerShell 5.1 kein -AsHashtable auf
# ConvertFrom-Json hat (das kam erst mit PS 6).
function _ConvertTo-HashtableDeep {
    param($Object)

    if ($null -eq $Object) { return $null }

    if ($Object -is [System.Collections.IDictionary]) {
        $h = @{}
        foreach ($k in $Object.Keys) { $h[$k] = _ConvertTo-HashtableDeep $Object[$k] }
        return $h
    }

    if ($Object -is [System.Management.Automation.PSCustomObject]) {
        $h = @{}
        foreach ($p in $Object.PSObject.Properties) {
            $h[$p.Name] = _ConvertTo-HashtableDeep $p.Value
        }
        return $h
    }

    if ($Object -is [System.Collections.IEnumerable] -and $Object -isnot [string]) {
        $list = @()
        foreach ($item in $Object) { $list += , (_ConvertTo-HashtableDeep $item) }
        # Skalare Werte werden als 1-Element-Array zurueckgegeben, deshalb
        # nur dann als Array belassen, wenn das Original auch eines war.
        return , $list | ForEach-Object { $_ }
    }

    return $Object
}

# Rekursiver Defaults-Merge: jeder im Default vorhandene Key ist auch im
# Resultat vorhanden; existierende Werte aus $Loaded haben Vorrang.
function _Merge-Defaults {
    param([hashtable]$Defaults, [hashtable]$Loaded)

    $out = @{}
    foreach ($k in $Defaults.Keys) {
        if ($Loaded.ContainsKey($k)) {
            $dv = $Defaults[$k]
            $lv = $Loaded[$k]
            if ($dv -is [hashtable] -and $lv -is [hashtable]) {
                $out[$k] = _Merge-Defaults -Defaults $dv -Loaded $lv
            } else {
                $out[$k] = $lv
            }
        } else {
            $out[$k] = $Defaults[$k]
        }
    }
    # zusaetzlich vorhandene Keys aus $Loaded uebernehmen (Forward-Kompat)
    foreach ($k in $Loaded.Keys) {
        if (-not $out.ContainsKey($k)) { $out[$k] = $Loaded[$k] }
    }
    return $out
}

# Migrations-Framework. Pro Version eine Function _Migrate-FromVersion-<n>
# definieren, die den Config-Hashtable an den neuen Stand anpasst und die
# neue Version eintraegt. Hier noch keine Migration noetig (V1 ist erste).
function _Migrate-Config {
    param([hashtable]$Config)

    $from = if ($Config.ContainsKey('SchemaVersion')) { [int]$Config['SchemaVersion'] } else { 0 }
    $to = $script:CurrentSchemaVersion

    while ($from -lt $to) {
        # Beispiel fuer kuenftige Versions-Migration:
        # if ($from -eq 1) {
        #     $Config['NewField'] = 'default'
        #     $Config['SchemaVersion'] = 2
        # }
        $from++
    }
    $Config['SchemaVersion'] = $to
    return $Config
}

function Read-Config {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$Path
    )

    if (-not $Path) { $Path = Get-ConfigPath }
    $defaults = Get-DefaultConfig

    if (-not (Test-Path -LiteralPath $Path)) {
        return $defaults
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return $defaults }
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Warning ("config.json defekt ({0}), Defaults werden verwendet: {1}" -f $Path, $_.Exception.Message)
        return $defaults
    }

    $loaded = _ConvertTo-HashtableDeep $obj
    if (-not ($loaded -is [hashtable])) { return $defaults }

    $merged = _Merge-Defaults -Defaults $defaults -Loaded $loaded
    $merged = _Migrate-Config -Config $merged
    return $merged
}

function Save-Config {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [string]$Path
    )

    if (-not $Path) { $Path = Get-ConfigPath }

    if (-not $Config.ContainsKey('SchemaVersion')) {
        $Config['SchemaVersion'] = $script:CurrentSchemaVersion
    }

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        try {
            $null = New-Item -ItemType Directory -Force -Path $dir
        } catch {
            return @{
                Success = $false
                Status  = 'DirCreateFailed'
                Message = "Konnte $dir nicht anlegen: $($_.Exception.Message)"
                Path    = $Path
            }
        }
    }

    try {
        $json = $Config | ConvertTo-Json -Depth 10
        # Atomic-Write: erst .tmp, dann umbenennen -- damit ein
        # Abbruch keine halbgeschriebene Datei hinterlaesst.
        $tmp = "$Path.tmp"
        Set-Content -LiteralPath $tmp -Value $json -Encoding UTF8
        if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
        Move-Item -LiteralPath $tmp -Destination $Path
        return @{
            Success = $true
            Status  = 'OK'
            Message = "Config gespeichert"
            Path    = $Path
        }
    } catch {
        return @{
            Success = $false
            Status  = 'WriteFailed'
            Message = "Speichern fehlgeschlagen: $($_.Exception.Message)"
            Path    = $Path
        }
    }
}

Export-ModuleMember -Function Get-ConfigPath, Get-DefaultConfig, Read-Config, Save-Config
