#Requires -Version 7.0
<#
.SYNOPSIS
    Laedt PSScriptAnalyzer offline-faehig nach _deps/PSScriptAnalyzer.

.DESCRIPTION
    Auf Maschinen ohne PSGallery-Zugriff: Modul auf einer Online-Maschine
    via `Save-Module PSScriptAnalyzer -Path .\_deps\` herunterladen, dann
    den _deps-Ordner committen oder per ZIP uebertragen.

    Dieses Skript wickelt beide Faelle ab:
      - Mit Internet: Save-Module direkt
      - Ohne Internet: Bundle aus uebergebenem -Source-Pfad uebernehmen
#>

[CmdletBinding()]
param(
    [string]$Source,                       # Lokaler Pfad zu einem bereits geladenen PSSA-Ordner
    [switch]$Force                         # Vorhandenes _deps/PSScriptAnalyzer ueberschreiben
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path "$PSScriptRoot/.."
$target   = Join-Path $repoRoot '_deps'

$null = New-Item -ItemType Directory -Force -Path $target

if ($Source) {
    if (-not (Test-Path -LiteralPath $Source)) {
        Write-Host "Source-Pfad existiert nicht: $Source" -ForegroundColor Red
        exit 2
    }
    $dest = Join-Path $target 'PSScriptAnalyzer'
    if (Test-Path -LiteralPath $dest) {
        if (-not $Force) {
            Write-Host "Ziel existiert bereits: $dest (verwende -Force zum Ueberschreiben)" -ForegroundColor Yellow
            exit 0
        }
        Remove-Item -Recurse -Force $dest
    }
    Copy-Item -Recurse $Source $dest
    Write-Host "PSSA aus '$Source' uebernommen nach: $dest" -ForegroundColor Green
} else {
    Write-Host "Lade PSScriptAnalyzer von PSGallery nach $target ..." -ForegroundColor Cyan
    Save-Module -Name PSScriptAnalyzer -Path $target -Force
    Write-Host "Fertig." -ForegroundColor Green
}

Write-Host ""
Write-Host "Pruefe Inhalt:" -ForegroundColor DarkGray
Get-ChildItem -Directory (Join-Path $target 'PSScriptAnalyzer') |
    Select-Object Name, LastWriteTime
