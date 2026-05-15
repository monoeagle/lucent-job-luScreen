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

$script:CurrentSchemaVersion = 5

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
        SchemaVersion    = $script:CurrentSchemaVersion
        OutputDir        = $outputDir
        DelaySeconds     = 0
        FileNameFormat   = 'yyyyMMdd_HHmm_{mode}.png'
        EditPostfix      = '_edited'
        HistoryIconSize  = 20    # Toolbar-Icon-Groesse im Verlaufsfenster (16-32 pt)
        Hotkeys          = @{
            Region       = @{ Modifiers = @('Control', 'Shift'); Key = 'D1' }
            ActiveWindow = @{ Modifiers = @('Control', 'Shift'); Key = 'D2' }
            Monitor      = @{ Modifiers = @('Control', 'Shift'); Key = 'D3' }
            AllMonitors  = @{ Modifiers = @('Control', 'Shift'); Key = 'D4' }
            TrayMenu     = @{ Modifiers = @('Control', 'Shift'); Key = 'D0' }
            DelayReset   = @{ Modifiers = @('Control', 'Shift'); Key = 'R' }
            DelayPlus5   = @{ Modifiers = @('Control', 'Shift'); Key = 'T' }
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
        if ($from -eq 1) {
            # Schema 2: HistoryIconSize fuer konfigurierbare Toolbar-Icon-Groesse
            # im Verlaufsfenster.
            if (-not $Config.ContainsKey('HistoryIconSize')) {
                $Config['HistoryIconSize'] = 20
            }
        }
        if ($from -eq 2) {
            # Schema 3: 'LucentScreen_'-Praefix aus dem Default-FileNameFormat
            # entfernen. Nur ersetzen, wenn der User exakt das alte Default
            # eingestellt hat -- bewusst angepasste Templates bleiben unangetastet.
            if ($Config.ContainsKey('FileNameFormat') -and
                $Config['FileNameFormat'] -eq 'LucentScreen_yyyy-MM-dd_HH-mm-ss_{mode}.png') {
                $Config['FileNameFormat'] = 'yyyy-MM-dd_HH-mm-ss_{mode}.png'
            }
        }
        if ($from -eq 3) {
            # Schema 4: zwei neue Hotkey-Slots (Verzoegerung-Reset, +5sek).
            # Nur ergaenzen wenn nicht schon vom User gesetzt.
            if ($Config.ContainsKey('Hotkeys') -and ($Config['Hotkeys'] -is [hashtable])) {
                if (-not $Config['Hotkeys'].ContainsKey('DelayReset')) {
                    $Config['Hotkeys']['DelayReset'] = @{ Modifiers = @('Control', 'Shift'); Key = 'R' }
                }
                if (-not $Config['Hotkeys'].ContainsKey('DelayPlus5')) {
                    $Config['Hotkeys']['DelayPlus5'] = @{ Modifiers = @('Control', 'Shift'); Key = 'T' }
                }
            }
        }
        if ($from -eq 4) {
            # Schema 5: kompakteres Default-FileNameFormat (yyyyMMdd_HHmm_{mode}.png
            # statt yyyy-MM-dd_HH-mm-ss_{mode}.png). Nur das alte Default ersetzen,
            # eigene Templates bleiben erhalten.
            if ($Config.ContainsKey('FileNameFormat') -and
                $Config['FileNameFormat'] -eq 'yyyy-MM-dd_HH-mm-ss_{mode}.png') {
                $Config['FileNameFormat'] = 'yyyyMMdd_HHmm_{mode}.png'
            }
        }
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

# ---------------------------------------------------------------
#  Hotkey-Helpers (UI-unabhaengig, daher hier in core)
# ---------------------------------------------------------------

# Erlaubte Modifier-Tokens (case-insensitive beim Parsen)
$script:ValidModifiers = @('Control', 'Ctrl', 'Shift', 'Alt', 'Win', 'Windows')

# Mapping von User-Eingaben zu kanonischen Modifier-Namen (wie in Config gespeichert)
$script:CanonicalModifier = @{
    'control' = 'Control'
    'ctrl'    = 'Control'
    'shift'   = 'Shift'
    'alt'     = 'Alt'
    'win'     = 'Win'
    'windows' = 'Win'
}

function Format-Hotkey {
    <#
    .SYNOPSIS
        Wandelt einen Hotkey-Hashtable in einen lesbaren String.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][hashtable]$Hotkey)

    $parts = @()
    foreach ($m in @($Hotkey.Modifiers)) {
        if ($m) { $parts += $m }
    }
    if ($Hotkey.ContainsKey('Key') -and $Hotkey.Key) {
        # D1..D9, D0 -> nur die Ziffer anzeigen; sonst Original
        if ($Hotkey.Key -match '^D(\d)$') {
            $parts += $Matches[1]
        } else {
            $parts += $Hotkey.Key
        }
    }
    return ($parts -join '+')
}

function ConvertFrom-HotkeyString {
    <#
    .SYNOPSIS
        Wandelt einen String wie "Ctrl+Shift+1" in einen Hotkey-Hashtable.
    .DESCRIPTION
        Akzeptiert '+' als Trenner, beliebige Reihenfolge, Modifier-Aliase
        (Ctrl=Control, Win=Windows). Returns $null bei Parse-Fehler.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][string]$Text)

    $tokens = @($Text -split '\+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($tokens.Count -lt 1) { return $null }

    $mods = @()
    $key = $null
    foreach ($t in $tokens) {
        $lt = $t.ToLowerInvariant()
        if ($script:CanonicalModifier.ContainsKey($lt)) {
            $mods += $script:CanonicalModifier[$lt]
            continue
        }
        # Reine Ziffer -> D<n>
        if ($t -match '^\d$') {
            $key = "D$t"
            continue
        }
        # Alles andere als Key uebernehmen (z.B. F1, A, Space). Letzter Token gewinnt.
        $key = $t
    }
    if (-not $key) { return $null }

    return @{ Modifiers = @($mods); Key = $key }
}

function Test-ConfigValid {
    <#
    .SYNOPSIS
        Validiert ein Config-Hashtable. Liefert Result-Hashtable mit Liste
        der Fehlermeldungen (leer wenn alles ok).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][hashtable]$Config)

    $errors = New-Object System.Collections.Generic.List[string]

    if (-not $Config.ContainsKey('OutputDir') -or [string]::IsNullOrWhiteSpace($Config.OutputDir)) {
        $errors.Add('Zielordner darf nicht leer sein.')
    }

    if ($Config.ContainsKey('DelaySeconds')) {
        $d = $Config.DelaySeconds
        if (-not ($d -is [int] -or $d -is [long]) -or $d -lt 0 -or $d -gt 30) {
            $errors.Add('Verzoegerung muss eine ganze Zahl zwischen 0 und 30 sein.')
        }
    } else {
        $errors.Add('Verzoegerung fehlt.')
    }

    if (-not $Config.ContainsKey('FileNameFormat') -or [string]::IsNullOrWhiteSpace($Config.FileNameFormat)) {
        $errors.Add('Dateinamen-Schema darf nicht leer sein.')
    } elseif ($Config.FileNameFormat -notmatch '\{mode\}') {
        $errors.Add('Dateinamen-Schema muss den Platzhalter "{mode}" enthalten.')
    }

    if ($Config.ContainsKey('HistoryIconSize')) {
        $s = $Config.HistoryIconSize
        if (-not ($s -is [int] -or $s -is [long]) -or $s -lt 16 -or $s -gt 32) {
            $errors.Add('Verlauf-Iconsize muss eine ganze Zahl zwischen 16 und 32 sein.')
        }
    }

    if ($Config.ContainsKey('Hotkeys') -and ($Config.Hotkeys -is [hashtable])) {
        $conflict = Test-HotkeyConflict -Hotkeys $Config.Hotkeys
        if (-not $conflict.IsValid) {
            foreach ($c in $conflict.Conflicts) {
                # Extra-Klammer noetig: Methoden-Komma wuerde sonst die -f-Argumente
                # aufteilen und ".Add(<format-string>, $b, $c)" daraus machen.
                $msg = ("Hotkey-Konflikt: {0} und {1} teilen sich '{2}'." -f $c.Names[0], $c.Names[1], $c.Display)
                $errors.Add($msg)
            }
        }
    }

    return @{
        IsValid = ($errors.Count -eq 0)
        Errors  = @($errors)
    }
}

function Test-HotkeyConflict {
    <#
    .SYNOPSIS
        Prueft eine Hotkey-Map auf doppelte Bindings.
    .OUTPUTS
        IsValid (bool) + Conflicts (Array aus @{ Names = @(name1,name2); Display = 'Ctrl+Shift+1' }).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][hashtable]$Hotkeys)

    # Normalisierte Repraesentation pro Hotkey: sortierte Modifier + Key
    $seen = @{}
    $conflicts = New-Object System.Collections.Generic.List[hashtable]

    foreach ($name in @($Hotkeys.Keys)) {
        $hk = $Hotkeys[$name]
        if (-not ($hk -is [hashtable])) { continue }
        $mods = @($hk.Modifiers) | Sort-Object
        $sig = ($mods -join '+') + '|' + [string]$hk.Key
        if ($seen.ContainsKey($sig)) {
            $conflicts.Add(@{
                    Names   = @($seen[$sig], $name)
                    Display = (Format-Hotkey $hk)
                })
        } else {
            $seen[$sig] = $name
        }
    }
    return @{
        IsValid   = ($conflicts.Count -eq 0)
        Conflicts = @($conflicts)
    }
}

Export-ModuleMember -Function Get-ConfigPath, Get-DefaultConfig, Read-Config, Save-Config, Format-Hotkey, ConvertFrom-HotkeyString, Test-ConfigValid, Test-HotkeyConflict
