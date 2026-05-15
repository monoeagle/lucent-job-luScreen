#Requires -Version 5.1
<#
.SYNOPSIS
    LucentScreen-Docs -- Zensical-Doku-Wrapper fuer Windows (PowerShell).

.DESCRIPTION
    Verwaltet eine isolierte Python-venv unter luscreen-docs/.venv-docs,
    installiert Zensical hinein und baut/serviert die Doku-Site.

    Ohne Argument: interaktives Menue.
    Mit Argument: direkter Task.

.PARAMETER Action
    prereqs | build | serve | clean | menu (Default = menu)

.PARAMETER Port
    Port fuer den Live-Server (Default 8000).

.EXAMPLE
    .\luscreen-docs\run.ps1 prereqs
.EXAMPLE
    .\luscreen-docs\run.ps1 build
.EXAMPLE
    .\luscreen-docs\run.ps1 serve -Port 8046
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('menu', 'prereqs', 'build', 'serve', 'clean')]
    [string]$Action = 'menu',
    [int]$Port = 8000
)

$ErrorActionPreference = 'Stop'

# Pfade
$script:Root         = $PSScriptRoot
$script:VenvDir      = Join-Path $Root '.venv-docs'
$script:VenvPython   = if ($IsLinux -or $IsMacOS) { Join-Path $script:VenvDir 'bin/python' } else { Join-Path $script:VenvDir 'Scripts/python.exe' }
$script:BuildScript  = Join-Path $Root 'build_docs.py'
$script:DocsDir      = Join-Path $Root 'docs'
$script:SiteDir      = Join-Path $Root 'site'
$script:ConfigFile   = Join-Path $Root 'zensical.toml'

# Mindest-Python-Version fuer Zensical
$script:MinMajor = 3
$script:MinMinor = 10

# ============================================================================
# Helpers
# ============================================================================

function _Find-PythonAtLeast {
    param([int]$Major, [int]$Minor)

    # Reihenfolge: explizite Versionen (Win py-Launcher), dann generisches python.
    $candidates = @(
        @('py', '-3.13'),
        @('py', '-3.12'),
        @('py', '-3.11'),
        @('py', '-3.10'),
        @('python3.13', $null),
        @('python3.12', $null),
        @('python3.11', $null),
        @('python3.10', $null),
        @('python', $null),
        @('python3', $null)
    )

    foreach ($c in $candidates) {
        $exe = $c[0]
        $arg = $c[1]
        if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { continue }

        # py -3.X gibt bei fehlender Version eine Meldung auf stdout aus, deshalb
        # alle Output-Zeilen sammeln und nur die "<major>.<minor>"-Zeile
        # akzeptieren. Stderr nach $null umlenken.
        try {
            $lines = if ($arg) {
                & $exe $arg -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null
            } else {
                & $exe -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null
            }
        } catch {
            continue
        }

        $line = @($lines) | Where-Object { $_ -match '^\s*\d+\.\d+\s*$' } | Select-Object -First 1
        if (-not $line) { continue }
        if ($line.Trim() -notmatch '^(\d+)\.(\d+)$') { continue }
        $maj = [int]$Matches[1]
        $min = [int]$Matches[2]
        if ($maj -gt $Major -or ($maj -eq $Major -and $min -ge $Minor)) {
            return [pscustomobject]@{ Exe = $exe; Arg = $arg; Version = "$maj.$min" }
        }
    }
    return $null
}

function _Get-VenvPythonVersion {
    if (-not (Test-Path -LiteralPath $script:VenvPython)) { return $null }
    try {
        $ver = & $script:VenvPython -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null
        if ($ver -match '^\d+\.\d+$') { return $ver }
    } catch {
        return $null
    }
    return $null
}

function _Test-VersionAtLeast {
    param([string]$Version, [int]$Major, [int]$Minor)
    if ($Version -notmatch '^(\d+)\.(\d+)$') { return $false }
    $m1 = [int]$Matches[1]
    $m2 = [int]$Matches[2]
    if ($m1 -gt $Major) { return $true }
    if ($m1 -eq $Major -and $m2 -ge $Minor) { return $true }
    return $false
}

function _Ensure-Venv {
    # venv existiert UND hat passende Python-Version
    if (Test-Path -LiteralPath $script:VenvDir) {
        $venvVer = _Get-VenvPythonVersion
        if ($venvVer -and (_Test-VersionAtLeast -Version $venvVer -Major $script:MinMajor -Minor $script:MinMinor)) {
            return $true
        }
        $shownVer = if ($venvVer) { $venvVer } else { '?' }
        Write-Host ("  .venv-docs hat Python {0} -- benoetigt >= {1}.{2}. Wird neu gebaut." -f
            $shownVer, $script:MinMajor, $script:MinMinor) -ForegroundColor Yellow
        Remove-Item -Recurse -Force $script:VenvDir
    }

    $py = _Find-PythonAtLeast -Major $script:MinMajor -Minor $script:MinMinor
    if (-not $py) {
        Write-Host ("Kein Python >= {0}.{1} im PATH gefunden." -f $script:MinMajor, $script:MinMinor) -ForegroundColor Red
        Write-Host "  Installation: winget install Python.Python.3.12" -ForegroundColor DarkGray
        return $false
    }

    Write-Host ("  Erstelle .venv-docs mit Python {0} ({1}) ..." -f $py.Version, $py.Exe) -ForegroundColor Cyan
    if ($py.Arg) {
        & $py.Exe $py.Arg -m venv $script:VenvDir
    } else {
        & $py.Exe -m venv $script:VenvDir
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  venv-Erstellung fehlgeschlagen." -ForegroundColor Red
        return $false
    }
    return $true
}

function _Get-ZensicalVersion {
    if (-not (Test-Path -LiteralPath $script:VenvPython)) { return $null }
    try {
        $out = & $script:VenvPython -m pip show zensical 2>$null
        $line = $out | Where-Object { $_ -like 'Version:*' } | Select-Object -First 1
        if ($line) { return ($line -split ':\s*', 2)[1].Trim() }
    } catch {
        return $null
    }
    return $null
}

function _Ensure-Zensical {
    $ver = _Get-ZensicalVersion
    if ($ver -and $ver -ne '0.0.2') {
        Write-Host ("  Zensical {0}" -f $ver) -ForegroundColor DarkGray
        return $true
    }

    # pip-Self-Upgrade ist nett, aber nicht zwingend
    & $script:VenvPython -m pip install --quiet --upgrade pip 2>$null | Out-Null

    Write-Host "  Installiere Zensical ..." -ForegroundColor Cyan
    & $script:VenvPython -m pip install --quiet --upgrade zensical
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Zensical-Install fehlgeschlagen." -ForegroundColor Red
        return $false
    }
    $ver = _Get-ZensicalVersion
    $shownVer = if ($ver) { $ver } else { '?' }
    Write-Host ("  Zensical {0} installiert" -f $shownVer) -ForegroundColor Green
    return $true
}

function _Free-Port {
    param([int]$Port)
    try {
        $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop |
            Select-Object -First 1
        if ($conn) {
            $pid = $conn.OwningProcess
            Write-Host ("  Port $Port wird von PID $pid belegt -- wird beendet ...") -ForegroundColor Yellow
            Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
        }
    } catch {
        # Port frei -- nichts zu tun
    }
}

function _Prepare {
    if (-not (_Ensure-Venv)) { return $false }
    if (-not (_Ensure-Zensical)) { return $false }
    return $true
}

# ============================================================================
# Aktionen
# ============================================================================

function Action-Prereqs {
    Write-Host ""
    Write-Host "LucentScreen-Docs -- Voraussetzungen" -ForegroundColor Cyan
    Write-Host ("-" * 40) -ForegroundColor DarkGray

    $py = _Find-PythonAtLeast -Major $script:MinMajor -Minor $script:MinMinor
    if ($py) {
        Write-Host ("  [OK]   Python {0} ({1})" -f $py.Version, $py.Exe) -ForegroundColor Green
    } else {
        Write-Host ("  [FEHLT] Python >= {0}.{1}" -f $script:MinMajor, $script:MinMinor) -ForegroundColor Red
        Write-Host "         winget install Python.Python.3.12" -ForegroundColor DarkGray
    }

    if (Test-Path -LiteralPath $script:VenvDir) {
        $vver = _Get-VenvPythonVersion
        if ($vver -and (_Test-VersionAtLeast -Version $vver -Major $script:MinMajor -Minor $script:MinMinor)) {
            Write-Host ("  [OK]   .venv-docs (Python {0})" -f $vver) -ForegroundColor Green
        } else {
            $shownVer = if ($vver) { $vver } else { '?' }
            Write-Host ("  [WARN] .venv-docs hat Python {0} (wird beim naechsten build neu gebaut)" -f $shownVer) -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [INFO] .venv-docs fehlt (wird beim ersten build angelegt)" -ForegroundColor DarkGray
    }

    if (Test-Path -LiteralPath $script:VenvPython) {
        $zen = _Get-ZensicalVersion
        if ($zen) {
            Write-Host ("  [OK]   Zensical {0}" -f $zen) -ForegroundColor Green
        } else {
            Write-Host "  [INFO] Zensical noch nicht in venv installiert" -ForegroundColor DarkGray
        }
    }

    $mdCount = (Get-ChildItem -Recurse -File -Filter *.md -Path $script:DocsDir -EA SilentlyContinue).Count
    Write-Host ("  [OK]   {0} Markdown-Dateien unter docs/" -f $mdCount) -ForegroundColor Green
}

function Action-Build {
    Write-Host ""
    Write-Host "LucentScreen-Docs -- Build" -ForegroundColor Cyan
    Write-Host ("-" * 40) -ForegroundColor DarkGray
    if (-not (_Prepare)) { return 1 }

    if (Test-Path -LiteralPath $script:SiteDir) { Remove-Item -Recurse -Force $script:SiteDir }

    Push-Location $script:Root
    try {
        & $script:VenvPython $script:BuildScript
        $exit = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    if ($exit -ne 0) {
        Write-Host "Build fehlgeschlagen (exit $exit)." -ForegroundColor Red
        return $exit
    }
    Write-Host ""
    Write-Host ("Fertig. site/index.html: {0}" -f (Join-Path $script:SiteDir 'index.html')) -ForegroundColor Green
    return 0
}

function Action-Serve {
    Write-Host ""
    Write-Host ("LucentScreen-Docs -- Live-Server (Port $Port)") -ForegroundColor Cyan
    Write-Host ("-" * 40) -ForegroundColor DarkGray
    if (-not (_Prepare)) { return 1 }
    _Free-Port -Port $Port

    Write-Host ("  http://127.0.0.1:{0}" -f $Port) -ForegroundColor Green
    Write-Host "  Ctrl+C zum Beenden" -ForegroundColor DarkGray
    Write-Host ""

    Push-Location $script:Root
    try {
        & $script:VenvPython $script:BuildScript --serve --port $Port
    } finally {
        Pop-Location
    }
}

function Action-Clean {
    Write-Host ""
    Write-Host "LucentScreen-Docs -- Clean" -ForegroundColor Cyan
    Write-Host ("-" * 40) -ForegroundColor DarkGray
    if (Test-Path -LiteralPath $script:VenvDir) {
        Remove-Item -Recurse -Force $script:VenvDir
        Write-Host "  .venv-docs geloescht" -ForegroundColor Green
    } else {
        Write-Host "  .venv-docs nicht vorhanden" -ForegroundColor DarkGray
    }
    if (Test-Path -LiteralPath $script:SiteDir) {
        Remove-Item -Recurse -Force $script:SiteDir
        Write-Host "  site/ geloescht" -ForegroundColor Green
    }
}

function Show-Menu {
    Clear-Host
    Write-Host ""
    Write-Host " LucentScreen-Docs" -ForegroundColor Cyan
    Write-Host " -------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  1) Voraussetzungen pruefen"
    Write-Host "  2) Build (statisches HTML in site/)"
    Write-Host "  3) Live-Server starten (Port $Port)"
    Write-Host "  4) .venv-docs und site/ entfernen"
    Write-Host ""
    Write-Host "  q) Beenden"
    Write-Host ""
    return (Read-Host "Auswahl")
}

# ============================================================================
# Main
# ============================================================================

function Invoke-Action {
    param([string]$Code)
    switch ($Code) {
        'prereqs' { Action-Prereqs }
        'build'   { [void](Action-Build) }
        'serve'   { Action-Serve }
        'clean'   { Action-Clean }
        '1' { Action-Prereqs }
        '2' { [void](Action-Build) }
        '3' { Action-Serve }
        '4' { Action-Clean }
        'q' { return $false }
        ''  { }
        default { Write-Host "Unbekannt: $Code" -ForegroundColor Yellow }
    }
    return $true
}

if ($Action -ne 'menu') {
    Invoke-Action -Code $Action
    exit $LASTEXITCODE
}

while ($true) {
    $c = Show-Menu
    if (-not (Invoke-Action -Code $c)) { break }
    Write-Host ""
    Read-Host "ENTER fuer Menue" | Out-Null
}
