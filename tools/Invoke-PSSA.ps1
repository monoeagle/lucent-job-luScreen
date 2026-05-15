#Requires -Version 5.1
<#
.SYNOPSIS
    PSScriptAnalyzer-Lint fuer alle PowerShell-Sources des Repos.
.DESCRIPTION
    Laedt PSSA aus _deps/PSScriptAnalyzer (Bundle) oder als Fallback aus dem
    System-Module-Pfad. Scannt alle .ps1/.psm1/.psd1-Dateien unterhalb des
    Repo-Roots, ausser:
        .git/, .archiv/, _deps/, reports/

    Erzeugt zwei Reports unter reports/pssa/:
        pssa-report.md    -- Markdown-Zusammenfassung (gruppiert nach Severity,
                            Rule und Datei)
        pssa-report.json  -- Raw-Diagnostik fuer Diff-Vergleiche

    Konfiguration via PSScriptAnalyzerSettings.psd1 im Repo-Root (falls
    vorhanden) -- sonst Default-Regeln.

.PARAMETER FailOnError
    Exit-Code 1 wenn mindestens ein Finding mit Severity=Error existiert.
    Sinnvoll fuer CI / Pre-Commit-Hooks.

.PARAMETER OnlyChangedSinceMain
    Lintet nur Dateien, die sich gegenueber origin/main unterscheiden.
    Nuetzlich fuer Pre-Push.

.EXAMPLE
    .\tools\Invoke-PSSA.ps1
    .\tools\Invoke-PSSA.ps1 -FailOnError
#>

[CmdletBinding()]
param(
    [switch]$FailOnError,
    [switch]$OnlyChangedSinceMain
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot  = Resolve-Path (Join-Path $scriptDir '..')
$reportDir = Join-Path $repoRoot 'reports\pssa'
$null = New-Item -ItemType Directory -Force -Path $reportDir

# -----------------------------------------------------------------
#  PSSA laden -- erst Bundle, dann System
# -----------------------------------------------------------------
function _Find-BundledPssa {
    $root = Join-Path $repoRoot '_deps\PSScriptAnalyzer'
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    $versions = Get-ChildItem -LiteralPath $root -Directory -EA SilentlyContinue |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' }
    if (-not $versions) { return $null }
    $highest = $versions | Sort-Object -Property @{Expression={[version]$_.Name}} -Descending |
        Select-Object -First 1
    $manifest = Join-Path $highest.FullName 'PSScriptAnalyzer.psd1'
    if (Test-Path -LiteralPath $manifest) { return $manifest }
    return $null
}

Write-Host "Lade PSScriptAnalyzer..." -ForegroundColor Cyan
$bundle = _Find-BundledPssa
if ($bundle) {
    Remove-Module PSScriptAnalyzer -EA SilentlyContinue
    Import-Module $bundle -Force
    $pssaSource = "Bundle ($bundle)"
} else {
    if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
        Write-Host "  PSSA weder im Bundle noch systemweit gefunden." -ForegroundColor Red
        Write-Host "  Bundle erwartet unter: $(Join-Path $repoRoot '_deps\PSScriptAnalyzer\<ver>\')" -ForegroundColor Red
        exit 2
    }
    Import-Module PSScriptAnalyzer -Force
    $pssaSource = "System"
}
$pssaVersion = (Get-Module PSScriptAnalyzer).Version
Write-Host ("  PSSA {0} aus {1}" -f $pssaVersion, $pssaSource) -ForegroundColor Green

# -----------------------------------------------------------------
#  Source-Dateien sammeln
# -----------------------------------------------------------------
$exclusions = @('.git','.archiv','_deps','reports','docs','luscreen-docs','.erkenntnisse','node_modules','packaging')
$allFiles = Get-ChildItem -LiteralPath $repoRoot -Recurse -File -EA SilentlyContinue |
    Where-Object { $_.Extension -in '.ps1','.psm1','.psd1' }

# Pfad-Token-basierte Exclusion: jede Pfad-Komponente prueffen,
# damit ein Match nicht von Substring-Treffern (z.B. .archiv-irgendwas) abhaengt.
$files = foreach ($f in $allFiles) {
    $rel = $f.FullName.Substring($repoRoot.Path.Length).TrimStart('\','/')
    $tokens = $rel -split '[\\/]'
    $skip = $false
    foreach ($t in $tokens) { if ($exclusions -contains $t) { $skip = $true; break } }
    if (-not $skip) { $f }
}

if ($OnlyChangedSinceMain) {
    Write-Host "Filter: nur Dateien geaendert ggue. origin/main..." -ForegroundColor DarkGray
    $changed = & git -C $repoRoot diff --name-only origin/main...HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $changed) {
        $changedSet = @{}
        foreach ($c in $changed) { $changedSet[(Join-Path $repoRoot $c).ToLowerInvariant()] = $true }
        $files = $files | Where-Object { $changedSet.ContainsKey($_.FullName.ToLowerInvariant()) }
    } else {
        Write-Host "  git-diff lieferte nichts oder schlug fehl, lintete alle Dateien." -ForegroundColor Yellow
    }
}

$fileCount = (@($files)).Count
Write-Host ("Scanne {0} Datei(en)..." -f $fileCount) -ForegroundColor Cyan

# -----------------------------------------------------------------
#  Settings-Datei einbinden (falls vorhanden)
# -----------------------------------------------------------------
$settingsFile = Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'
$pssaArgs = @{ Recurse = $false }
if (Test-Path -LiteralPath $settingsFile) {
    $pssaArgs.Settings = $settingsFile
    Write-Host ("  Settings: {0}" -f $settingsFile) -ForegroundColor DarkGray
}

# -----------------------------------------------------------------
#  Analyse
# -----------------------------------------------------------------
$diagnostics = New-Object System.Collections.Generic.List[object]
$idx = 0
foreach ($f in $files) {
    $idx++
    $rel = $f.FullName.Substring($repoRoot.Path.Length).TrimStart('\','/')
    Write-Progress -Activity "PSSA" -Status $rel -PercentComplete (100.0 * $idx / [Math]::Max($fileCount,1))
    try {
        $r = Invoke-ScriptAnalyzer -Path $f.FullName @pssaArgs
        foreach ($d in @($r)) {
            $diagnostics.Add([pscustomobject]@{
                File       = $rel
                Line       = [int]$d.Line
                Column     = [int]$d.Column
                Severity   = [string]$d.Severity
                RuleName   = [string]$d.RuleName
                Message    = [string]$d.Message
            })
        }
    } catch {
        Write-Host ("  WARN: {0} -- {1}" -f $rel, $_.Exception.Message) -ForegroundColor Yellow
    }
}
Write-Progress -Activity "PSSA" -Completed

# -----------------------------------------------------------------
#  Reports schreiben
# -----------------------------------------------------------------
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

$bySeverity = @{ 'Error'=0; 'Warning'=0; 'Information'=0; 'Other'=0 }
foreach ($d in $diagnostics) {
    if ($bySeverity.ContainsKey($d.Severity)) { $bySeverity[$d.Severity]++ }
    else { $bySeverity['Other']++ }
}

# JSON
$json = [pscustomobject]@{
    GeneratedAt   = $timestamp
    PssaVersion   = "$pssaVersion"
    PssaSource    = $pssaSource
    FilesScanned  = $fileCount
    Totals        = $bySeverity
    Diagnostics   = $diagnostics
}
$jsonPath = Join-Path $reportDir 'pssa-report.json'
$json | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

# Markdown
$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine("# PSScriptAnalyzer Report")
[void]$md.AppendLine()
[void]$md.AppendLine("**Generated:** $timestamp")
[void]$md.AppendLine("**PSSA version:** $pssaVersion ($pssaSource)")
[void]$md.AppendLine("**Files scanned:** $fileCount")
[void]$md.AppendLine("**Total findings:** $($diagnostics.Count) (Error=$($bySeverity['Error']), Warning=$($bySeverity['Warning']), Information=$($bySeverity['Information']))")
[void]$md.AppendLine()

if ($diagnostics.Count -eq 0) {
    [void]$md.AppendLine("All clear -- no findings.")
} else {
    # Summary by Rule
    [void]$md.AppendLine("## Findings by Rule")
    [void]$md.AppendLine()
    [void]$md.AppendLine("| Rule | Count | Severity |")
    [void]$md.AppendLine("|---|---:|---|")
    $byRule = $diagnostics | Group-Object RuleName | Sort-Object Count -Descending
    foreach ($g in $byRule) {
        $sev = $g.Group[0].Severity
        [void]$md.AppendLine(("| ``{0}`` | {1} | {2} |" -f $g.Name, $g.Count, $sev))
    }
    [void]$md.AppendLine()

    # Summary by File
    [void]$md.AppendLine("## Findings by File")
    [void]$md.AppendLine()
    [void]$md.AppendLine("| File | Findings |")
    [void]$md.AppendLine("|---|---:|")
    $byFile = $diagnostics | Group-Object File | Sort-Object Count -Descending
    foreach ($g in $byFile) {
        [void]$md.AppendLine(("| ``{0}`` | {1} |" -f $g.Name, $g.Count))
    }
    [void]$md.AppendLine()

    # Detail by Severity
    foreach ($sev in 'Error','Warning','Information') {
        $list = $diagnostics | Where-Object Severity -eq $sev
        if (-not $list) { continue }
        [void]$md.AppendLine("## $sev ($($list.Count))")
        [void]$md.AppendLine()
        $byFileSev = $list | Group-Object File
        foreach ($g in $byFileSev) {
            [void]$md.AppendLine("### ``$($g.Name)``")
            [void]$md.AppendLine()
            foreach ($d in ($g.Group | Sort-Object Line)) {
                [void]$md.AppendLine(("- **L{0}:{1}** ``{2}`` -- {3}" -f $d.Line, $d.Column, $d.RuleName, $d.Message))
            }
            [void]$md.AppendLine()
        }
    }
}

$mdPath = Join-Path $reportDir 'pssa-report.md'
Set-Content -LiteralPath $mdPath -Value $md.ToString() -Encoding UTF8

# -----------------------------------------------------------------
#  Zusammenfassung in Konsole
# -----------------------------------------------------------------
Write-Host ""
Write-Host "-------------------------------------" -ForegroundColor DarkGray
Write-Host ("Findings:  Error={0}  Warning={1}  Information={2}" -f
    $bySeverity['Error'], $bySeverity['Warning'], $bySeverity['Information']) `
    -ForegroundColor $(if ($bySeverity['Error'] -gt 0) { 'Red' } elseif ($bySeverity['Warning'] -gt 0) { 'Yellow' } else { 'Green' })
Write-Host ("Reports:   {0}" -f $reportDir) -ForegroundColor DarkGray
Write-Host ("           {0}" -f (Split-Path -Leaf $mdPath))
Write-Host ("           {0}" -f (Split-Path -Leaf $jsonPath))

if ($FailOnError -and $bySeverity['Error'] -gt 0) {
    exit 1
}
exit 0
