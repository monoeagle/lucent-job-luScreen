#Requires -Version 5.1
<#
.SYNOPSIS
    Task-Runner und interaktives Menue fuer LucentScreen.
.DESCRIPTION
    Mit Argument: direkter Task. Ohne Argument: Menue.
    Bsp.: ./run.ps1 l   -> PSScriptAnalyzer-Lint
          ./run.ps1     -> interaktives Menue
.EXAMPLE
    ./run.ps1 prereqs
.EXAMPLE
    ./run.ps1 l
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Action
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

# -----------------------------------------------------------------
# Pfade
# -----------------------------------------------------------------
$srcDir = Join-Path $root 'src'
$testsDir = Join-Path $root 'tests'
$entryScript = Join-Path $srcDir 'LucentScreen.ps1'
$pssaTool = Join-Path $root 'tools/Invoke-PSSA.ps1'
$pssaInstall = Join-Path $root 'tools/Install-PSScriptAnalyzer-Offline.ps1'
$docsDir = Join-Path $root 'luscreen-docs'
$htmlDoc = Join-Path $root 'LucentScreen.docs.html'
$reportsDir = Join-Path $root 'reports'
$appPidFile = Join-Path $env:LOCALAPPDATA 'LucentScreen/run/app.pid'
$editorDbgLog = Join-Path $env:LOCALAPPDATA 'LucentScreen/logs/editor-debug.log'

# -----------------------------------------------------------------
# Actions
# -----------------------------------------------------------------
function Action-Prereqs {
    Write-Host "Pruefe Voraussetzungen..." -ForegroundColor Cyan
    $ok = $true

    # PowerShell-Version (Pflicht: Windows PowerShell 5.1)
    $psVer = $PSVersionTable.PSVersion
    if ($psVer.Major -lt 5 -or ($psVer.Major -eq 5 -and $psVer.Minor -lt 1)) {
        Write-Host "  [FEHLT] Windows PowerShell 5.1 (gefunden: $psVer)" -ForegroundColor Red
        $ok = $false
    } else {
        Write-Host "  [OK]   Windows PowerShell $psVer" -ForegroundColor Green
    }

    # STA-Apartment (nur warnen, run.ps1 selbst muss kein STA sein)
    $apt = [Threading.Thread]::CurrentThread.GetApartmentState()
    Write-Host "  [INFO] Aktuelles Apartment: $apt (App startet via -STA)" -ForegroundColor DarkGray

    # PSScriptAnalyzer
    $bundle = Get-ChildItem -Directory -EA SilentlyContinue (Join-Path $root '_deps/PSScriptAnalyzer') |
        Where-Object Name -match '^\d+\.\d+\.\d+$' | Select-Object -First 1
    if ($bundle) {
        Write-Host "  [OK]   PSScriptAnalyzer (Bundle $($bundle.Name))" -ForegroundColor Green
    } elseif (Get-Module -ListAvailable PSScriptAnalyzer) {
        $v = (Get-Module -ListAvailable PSScriptAnalyzer | Select-Object -First 1).Version
        Write-Host "  [OK]   PSScriptAnalyzer (System $v)" -ForegroundColor Green
    } else {
        Write-Host "  [FEHLT] PSScriptAnalyzer (./run.ps1 i fuer Install)" -ForegroundColor Yellow
    }

    # Pester (Bundle bevorzugt, dann System)
    $pesterBundle = Get-ChildItem -Directory -EA SilentlyContinue (Join-Path $root '_deps/Pester') |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
        Sort-Object -Property @{Expression = { [version]$_.Name } } -Descending |
        Select-Object -First 1
    if ($pesterBundle) {
        Write-Host "  [OK]   Pester (Bundle $($pesterBundle.Name))" -ForegroundColor Green
    } elseif (Get-Module -ListAvailable Pester | Where-Object Version -ge ([Version]'5.0')) {
        $v = (Get-Module -ListAvailable Pester | Where-Object Version -ge ([Version]'5.0') | Sort-Object Version -Descending | Select-Object -First 1).Version
        Write-Host "  [OK]   Pester (System $v)" -ForegroundColor Green
    } else {
        Write-Host "  [FEHLT] Pester 5+ (./run.ps1 ip fuer Bundle-Install)" -ForegroundColor Yellow
    }

    # Python (fuer Zensical-Doku-Build)
    $py = Get-Command python -EA SilentlyContinue
    if ($py) {
        Write-Host "  [OK]   Python (fuer luscreen-docs Build)" -ForegroundColor Green
    } else {
        Write-Host "  [INFO] Python fehlt -- nur noetig fuer 'd' (Docs bauen)" -ForegroundColor DarkGray
    }

    if (-not $ok) { Write-Host "Pflicht-Voraussetzung fehlt. Bitte beheben." -ForegroundColor Red }
}

function Action-ParseCheck {
    Write-Host "Parse-Check aller *.ps1/*.psm1 ..." -ForegroundColor Cyan
    $reportDir = Join-Path $reportsDir 'parse'
    $null = New-Item -ItemType Directory -Force -Path $reportDir

    $report = [System.Text.StringBuilder]::new()
    [void]$report.AppendLine("# Parse Report")
    [void]$report.AppendLine("")
    [void]$report.AppendLine("Generiert: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    [void]$report.AppendLine("")

    $files = Get-ChildItem -Recurse -Include *.ps1, *.psm1 -Path $srcDir, $testsDir, (Join-Path $root 'tools'), $root -EA SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\(_deps|reports|\.git)\\' }

    $errorCount = 0
    foreach ($f in $files) {
        $errs = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errs)
        $rel = $f.FullName.Substring($root.Length).TrimStart('\', '/')
        if ($errs.Count -gt 0) {
            $errorCount += $errs.Count
            Write-Host "  [FEHLER] $rel ($($errs.Count))" -ForegroundColor Red
            [void]$report.AppendLine("## ``$rel``")
            [void]$report.AppendLine("")
            foreach ($e in $errs) {
                [void]$report.AppendLine("- L$($e.Extent.StartLineNumber):$($e.Extent.StartColumnNumber) -- $($e.Message)")
            }
            [void]$report.AppendLine("")
        }
    }

    if ($errorCount -eq 0) {
        Write-Host "  Alle $($files.Count) Dateien parse-clean." -ForegroundColor Green
        [void]$report.AppendLine("Alle $($files.Count) Dateien parse-clean.")
    } else {
        Write-Host "  $errorCount Parse-Fehler in $($files.Count) Dateien." -ForegroundColor Red
    }
    Set-Content -LiteralPath (Join-Path $reportDir 'parse-report.md') -Value $report.ToString() -Encoding UTF8
    Write-Host "  Report: reports/parse/parse-report.md" -ForegroundColor DarkGray
}

function Action-PSSA {
    param([switch]$OnlyChanged, [switch]$FailOnError)
    Write-Host "Starte PSScriptAnalyzer ..." -ForegroundColor Cyan
    $pArgs = @()
    if ($OnlyChanged) { $pArgs += '-OnlyChangedSinceMain' }
    if ($FailOnError) { $pArgs += '-FailOnError' }
    & powershell.exe -NoProfile -File $pssaTool @pArgs
    $report = Join-Path $reportsDir 'pssa/pssa-report.md'
    if (Test-Path -LiteralPath $report) {
        Write-Host ""
        Write-Host ("Report: {0}" -f $report) -ForegroundColor DarkGray
    }
}

function Import-PesterBundled {
    <#
    Laedt Pester 5+ bevorzugt aus _deps/Pester/<ver>/, mit Fallback auf
    ein systemweit installiertes Pester-Modul. Wirft, wenn weder Bundle
    noch System-Modul (>=5.0) vorhanden ist.
    #>
    Remove-Module Pester -ErrorAction SilentlyContinue
    $bundle = Get-ChildItem -Directory -EA SilentlyContinue (Join-Path $root '_deps/Pester') |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
        Sort-Object -Property @{Expression = { [version]$_.Name } } -Descending |
        Select-Object -First 1
    if ($bundle) {
        $manifest = Join-Path $bundle.FullName 'Pester.psd1'
        if (Test-Path -LiteralPath $manifest) {
            Import-Module $manifest -Force
            Write-Host ("  Pester {0} (Bundle)" -f $bundle.Name) -ForegroundColor DarkGray
            return
        }
    }
    $sys = Get-Module -ListAvailable Pester | Where-Object Version -ge ([Version]'5.0') |
        Sort-Object Version -Descending | Select-Object -First 1
    if (-not $sys) {
        throw "Pester >= 5.0 fehlt. Optionen: './run.ps1 ip' fuer Bundle-Install oder 'Install-Module Pester -MinimumVersion 5.0'."
    }
    Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
    Write-Host ("  Pester {0} (System)" -f $sys.Version) -ForegroundColor DarkGray
}

function Action-PesterAll {
    Write-Host "Starte Pester (alle Tests) ..." -ForegroundColor Cyan
    $reportDir = Join-Path $reportsDir 'pester'
    $null = New-Item -ItemType Directory -Force -Path $reportDir
    $xml = Join-Path $reportDir 'pester-results.xml'

    if (-not (Test-Path $testsDir) -or -not (Get-ChildItem $testsDir -Filter *.Tests.ps1 -EA SilentlyContinue)) {
        Write-Host "  Keine Tests gefunden in $testsDir." -ForegroundColor Yellow
        return
    }

    Import-PesterBundled
    $cfg = [PesterConfiguration]::Default
    $cfg.Run.Path = $testsDir
    $cfg.Output.Verbosity = 'Detailed'
    $cfg.TestResult.Enabled = $true
    $cfg.TestResult.OutputPath = $xml
    Invoke-Pester -Configuration $cfg
    Write-Host ""
    Write-Host ("NUnit-XML: {0}" -f $xml) -ForegroundColor DarkGray
}

function Action-PesterOne {
    Write-Host "Verfuegbare Test-Dateien:" -ForegroundColor Cyan
    $tests = Get-ChildItem $testsDir -Filter *.Tests.ps1 -EA SilentlyContinue
    if (-not $tests) { Write-Host "  Keine Tests gefunden." -ForegroundColor Yellow; return }
    for ($i = 0; $i -lt $tests.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $tests[$i].Name)
    }
    $sel = Read-Host "Nummer waehlen"
    $idx = [int]$sel - 1
    if ($idx -lt 0 -or $idx -ge $tests.Count) { Write-Host "Ungueltig." -ForegroundColor Red; return }
    Import-PesterBundled
    Invoke-Pester -Path $tests[$idx].FullName -Output Detailed
}

function Action-Audit {
    Write-Host "Audit umfasst Parse + PSSA + Pester + Architektur-Pruefungen." -ForegroundColor Cyan
    Write-Host "Verwende dafuer den auditor-Agent (model: opus, .claude/agents/auditor.md)." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Schritt 1: Parse-Check"
    Action-ParseCheck
    Write-Host ""
    Write-Host "Schritt 2: PSScriptAnalyzer"
    Action-PSSA
    Write-Host ""
    Write-Host "Schritt 3: Pester"
    Action-PesterAll
    Write-Host ""
    Write-Host "Schritt 4 (manuell): auditor-Agent dispatchen" -ForegroundColor Yellow
    Write-Host "  -> der Agent liest reports/parse/, reports/pssa/, reports/pester/"
    Write-Host "     und erstellt reports/audit/audit-<yyyy-mm-dd>.md"
}

function Action-AppStart {
    param(
        [int]$DebugLevel = 0,
        [switch]$ResetLog
    )
    if (-not (Test-Path $entryScript)) {
        Write-Host "Einstiegsskript fehlt: $entryScript" -ForegroundColor Yellow
        return
    }
    # Saubere Sequenz: erst stoppen (idempotent), dann starten -- damit der
    # Kindprozess garantiert mit den gewuenschten env-vars startet und nicht
    # eine alte Instanz mit altem Code weiterlaeuft.
    if (Test-Path $appPidFile) {
        Action-AppStop | Out-Null
        Start-Sleep -Milliseconds 250
    }
    if ($ResetLog -and (Test-Path -LiteralPath $editorDbgLog)) {
        try { Remove-Item -LiteralPath $editorDbgLog -Force -EA SilentlyContinue } catch { $null = $_ }
        Write-Host "  Editor-Debug-Log geleert." -ForegroundColor DarkGray
    }
    if ($DebugLevel -gt 0) {
        $env:LUSCREEN_EDITOR_DEBUG = "$DebugLevel"
        Write-Host ("  Debug-Level $DebugLevel aktiv (LUSCREEN_EDITOR_DEBUG)") -ForegroundColor Yellow
        Write-Host ("  Logfile: {0}" -f $editorDbgLog) -ForegroundColor DarkGray
    } else {
        Remove-Item Env:\LUSCREEN_EDITOR_DEBUG -ErrorAction SilentlyContinue
    }
    Write-Host "Starte LucentScreen (-STA) ..." -ForegroundColor Cyan
    $null = New-Item -ItemType Directory -Force -Path (Split-Path $appPidFile -Parent)
    $proc = Start-Process powershell.exe -ArgumentList '-STA', '-NoProfile', '-File', $entryScript -PassThru -WindowStyle Hidden
    $proc.Id | Set-Content -LiteralPath $appPidFile -Encoding UTF8
    Write-Host "  PID: $($proc.Id)" -ForegroundColor Green
}

function Action-AppStop {
    if (-not (Test-Path $appPidFile)) { Write-Host "Keine laufende Instanz (kein PID-File)." -ForegroundColor Yellow; return }
    $appPid = [int](Get-Content -LiteralPath $appPidFile -Raw)
    Write-Host "Stoppe PID $appPid ..." -ForegroundColor Cyan
    try { Stop-Process -Id $appPid -Force } catch { Write-Host "  schon beendet?" -ForegroundColor DarkGray }
    Remove-Item -LiteralPath $appPidFile -Force -EA SilentlyContinue
}

function Action-EditorDebugTail {
    param([int]$Lines = 80)
    if (-not (Test-Path -LiteralPath $editorDbgLog)) {
        Write-Host "Noch kein editor-debug.log vorhanden." -ForegroundColor Yellow
        Write-Host "  Pfad: $editorDbgLog" -ForegroundColor DarkGray
        Write-Host "  Hinweis: Editor wurde noch nicht mit Debug-Level >= 1 gestartet ('sd' im Menue)." -ForegroundColor DarkGray
        return
    }
    Write-Host ("Letzte {0} Zeilen aus editor-debug.log:" -f $Lines) -ForegroundColor Cyan
    Write-Host "  $editorDbgLog" -ForegroundColor DarkGray
    Write-Host ""
    Get-Content -LiteralPath $editorDbgLog -Tail $Lines
}

function Action-MermaidRender {
    <#
    .SYNOPSIS
        Rendert alle .mmd-Dateien aus luscreen-docs/mermaid-sources/ zu .svg
        in luscreen-docs/docs/images/mermaid/. Braucht mmdc (Mermaid CLI).
    .DESCRIPTION
        Installation: 'npm i -g @mermaid-js/mermaid-cli' (braucht Node.js).
        Wenn mmdc fehlt, wird eine Anleitung ausgegeben und kein Fehler geworfen.
    #>
    $srcDir = Join-Path $docsDir 'mermaid-sources'
    $outDir = Join-Path $docsDir 'docs/images/mermaid'
    if (-not (Test-Path -LiteralPath $srcDir)) {
        Write-Host "Keine Mermaid-Quellen ($srcDir)." -ForegroundColor Yellow
        return
    }
    $null = New-Item -ItemType Directory -Force -Path $outDir
    $mmdc = Get-Command mmdc -ErrorAction SilentlyContinue
    if (-not $mmdc) {
        Write-Host "mmdc (Mermaid CLI) nicht gefunden." -ForegroundColor Yellow
        Write-Host "  Installation: 'npm i -g @mermaid-js/mermaid-cli' (braucht Node.js)." -ForegroundColor DarkGray
        Write-Host "  Alternativ: Mermaid Live Editor (https://mermaid.live) -- SVG export -> $outDir" -ForegroundColor DarkGray
        return
    }
    Get-ChildItem -LiteralPath $srcDir -Filter '*.mmd' | ForEach-Object {
        $svg = Join-Path $outDir ($_.BaseName + '.svg')
        Write-Host ("Rendere {0} -> {1}" -f $_.Name, (Split-Path $svg -Leaf)) -ForegroundColor Cyan
        & $mmdc.Source -i $_.FullName -o $svg -b transparent
    }
    Write-Host "Mermaid-Render fertig." -ForegroundColor Green
}

function Action-Screenshots {
    <#
    .SYNOPSIS
        Startet das Take-LuScreenshots.ps1-Skript fuer halbautomatische
        Screenshot-Generation. Iteriert ueber das manifest.json + fragt pro
        Item nach User-Setup.
    #>
    $script = Join-Path $root 'tools/Take-LuScreenshots.ps1'
    if (-not (Test-Path -LiteralPath $script)) {
        Write-Host "Take-LuScreenshots.ps1 fehlt." -ForegroundColor Yellow
        return
    }
    Write-Host "Starte Screenshot-Generator (Take-LuScreenshots.ps1) ..." -ForegroundColor Cyan
    Write-Host "  Hinweis: App muss laufen (./run.ps1 s) damit Tray + Hotkeys verfuegbar sind." -ForegroundColor DarkGray
    & powershell.exe -NoProfile -STA -File $script
}

function Action-DocsBuild {
    $docsRun = Join-Path $docsDir 'run.ps1'
    if (-not (Test-Path -LiteralPath $docsRun)) {
        Write-Host "Doc-Wrapper fehlt: $docsRun" -ForegroundColor Yellow
        return
    }
    Write-Host "Baue Zensical-Site (managed venv) ..." -ForegroundColor Cyan
    & powershell.exe -NoProfile -File $docsRun build
    $exit = $LASTEXITCODE

    if ($exit -ne 0) {
        Write-Host "Build fehlgeschlagen (exit $exit) -- Browser nicht geoeffnet." -ForegroundColor Red
        return
    }
    $indexHtml = Join-Path $docsDir 'site/index.html'
    if (Test-Path -LiteralPath $indexHtml) {
        Write-Host "Oeffne im Standard-Browser ..." -ForegroundColor Cyan
        Start-Process $indexHtml
    } else {
        Write-Host "site/index.html fehlt -- Build hat nichts geliefert?" -ForegroundColor Yellow
    }
}

function Action-DocsServe {
    $docsRun = Join-Path $docsDir 'run.ps1'
    if (-not (Test-Path -LiteralPath $docsRun)) {
        Write-Host "Doc-Wrapper fehlt: $docsRun" -ForegroundColor Yellow
        return
    }
    Write-Host "Starte Doku-Live-Server (Ctrl+C zum Beenden) ..." -ForegroundColor Cyan
    & powershell.exe -NoProfile -File $docsRun serve
}

function Action-HtmlDoc {
    if (Test-Path $htmlDoc) {
        Write-Host "LucentScreen.docs.html wird manuell synchronisiert." -ForegroundColor Cyan
        Write-Host "  Spezialist: doc-writer-Agent (model: haiku)" -ForegroundColor DarkGray
        Write-Host "  Quellen:    luscreen-docs/docs/**" -ForegroundColor DarkGray
        Write-Host "  Ziel:       $htmlDoc" -ForegroundColor DarkGray
        $age = (Get-Date) - (Get-Item $htmlDoc).LastWriteTime
        Write-Host ("  Letztes Update: vor {0:N0} Tag(en)" -f $age.TotalDays) -ForegroundColor DarkGray
    } else {
        Write-Host "LucentScreen.docs.html existiert noch nicht." -ForegroundColor Yellow
    }
}

function Action-InstallPssa {
    & powershell.exe -NoProfile -File $pssaInstall
}

function Action-InstallPester {
    $script = Join-Path $root 'tools/Install-Pester-Offline.ps1'
    & powershell.exe -NoProfile -File $script
}

function Action-CleanReports {
    Write-Host "Loesche reports/ (ausser README)..." -ForegroundColor Cyan
    Get-ChildItem $reportsDir -Recurse -Exclude README.md | Remove-Item -Recurse -Force -EA SilentlyContinue
    Write-Host "Fertig." -ForegroundColor Green
}

function Action-ConfigDialog {
    $script = Join-Path $root 'tools/Show-ConfigDialog.ps1'
    if (-not (Test-Path -LiteralPath $script)) {
        Write-Host "Show-ConfigDialog.ps1 fehlt." -ForegroundColor Yellow
        return
    }
    Write-Host "Oeffne Konfig-Dialog (-STA) ..." -ForegroundColor Cyan
    & powershell.exe -NoProfile -STA -File $script
}

# -----------------------------------------------------------------
# Menue
# -----------------------------------------------------------------
function Show-Menu {
    Clear-Host
    Write-Host ""
    Write-Host " LucentScreen -- Task Runner" -ForegroundColor Cyan
    Write-Host " --------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host " --- Code-Qualitaet ---" -ForegroundColor DarkCyan
    Write-Host "  p) Parse-Check (AST aller *.ps1/*.psm1)"
    Write-Host "  l) PSScriptAnalyzer Lint (alle Sources)"
    Write-Host "  L) PSSA nur geaenderte Dateien (-OnlyChangedSinceMain)"
    Write-Host "  t) Pester Tests (alle)"
    Write-Host "  T) Pester (eine Test-Datei auswaehlen)"
    Write-Host "  a) Audit (Parse + PSSA + Pester, dann auditor-Agent)"
    Write-Host ""
    Write-Host " --- App ---" -ForegroundColor DarkCyan
    Write-Host "  s)  Start (-STA, immer mit Vorab-Stop)"
    Write-Host "  S)  Stop"
    Write-Host "  sd) Start mit Editor-Debug (Level 2: Logfile + Sonden, Log wird vorher geleert)"
    Write-Host "  lg) Letzte 80 Zeilen editor-debug.log anzeigen"
    Write-Host "  cfg) Konfig-Dialog oeffnen (-STA)"
    Write-Host "  prereqs) Voraussetzungen pruefen"
    Write-Host ""
    Write-Host " --- Doku ---" -ForegroundColor DarkCyan
    Write-Host "  d) Zensical-Site bauen + im Standard-Browser oeffnen"
    Write-Host "  D) Doku-Live-Server starten (http://127.0.0.1:8000)"
    Write-Host "  m) Mermaid-Diagramme rendern (.mmd -> .svg, braucht mmdc)"
    Write-Host "  ss) Doku-Screenshots aufnehmen (Take-LuScreenshots.ps1)"
    Write-Host "  h) HTML-Single-Page Status (LucentScreen.docs.html)"
    Write-Host ""
    Write-Host " --- Werkzeuge ---" -ForegroundColor DarkCyan
    Write-Host "  i)  PSScriptAnalyzer offline installieren"
    Write-Host "  ip) Pester offline installieren"
    Write-Host "  c)  reports/ leeren"
    Write-Host ""
    Write-Host "  q) Beenden"
    Write-Host ""
    $choice = Read-Host "Aktion"
    return $choice
}

function Invoke-Action {
    param([string]$Code)
    # -CaseSensitive: in PowerShell ist switch sonst case-insensitive --
    # 's' und 'S' (Start/Stop), 'l' und 'L' (PSSA all/changed), 'd' und 'D'
    # (Docs-Build/Serve) wuerden sonst beide feuern.
    switch -CaseSensitive ($Code) {
        'p' { Action-ParseCheck }
        'l' { Action-PSSA }
        'L' { Action-PSSA -OnlyChanged }
        't' { Action-PesterAll }
        'T' { Action-PesterOne }
        'a' { Action-Audit }
        's' { Action-AppStart }
        'S' { Action-AppStop }
        'sd' { Action-AppStart -DebugLevel 2 -ResetLog }
        'lg' { Action-EditorDebugTail }
        'cfg' { Action-ConfigDialog }
        'prereqs' { Action-Prereqs }
        'd' { Action-DocsBuild }
        'm' { Action-MermaidRender }
        'ss' { Action-Screenshots }
        'D' { Action-DocsServe }
        'h' { Action-HtmlDoc }
        'i' { Action-InstallPssa }
        'ip' { Action-InstallPester }
        'c' { Action-CleanReports }
        'q' { return $false }
        '' { }
        default { Write-Host "Unbekannt: $Code" -ForegroundColor Yellow }
    }
    return $true
}

# -----------------------------------------------------------------
# Main
# -----------------------------------------------------------------
if ($Action) {
    [void](Invoke-Action -Code $Action)
    exit 0
}

while ($true) {
    $c = Show-Menu
    if (-not (Invoke-Action -Code $c)) { break }
    Write-Host ""
    Read-Host "ENTER fuer Menue"
}
