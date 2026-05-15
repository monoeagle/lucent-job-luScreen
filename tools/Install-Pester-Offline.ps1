#Requires -Version 5.1
<#
.SYNOPSIS
    Laedt Pester 5 offline-faehig nach _deps/Pester.

.DESCRIPTION
    Drei Modi:
      1. -Source <Pfad>: kopiert ein vorhandenes Pester-Verzeichnis (z.B. von
         einer Online-Maschine via Save-Module geholt) nach _deps/Pester.
      2. Ohne Parameter, mit Internet: laedt Pester via Save-Module.
      3. -Url <https://...>: laedt das nupkg-Paket direkt via Invoke-WebRequest
         (kein NuGet-Provider noetig).

    Ergebnis: _deps/Pester/<version>/Pester.psd1 ist verfuegbar und wird von
    run.ps1 / tools/ vor dem System-Modul bevorzugt geladen.

.PARAMETER Source
    Lokaler Pfad zu einem bereits geladenen Pester-Ordner (Save-Module-Output).

.PARAMETER Url
    Direkter Download eines Pester.<version>.nupkg von der PSGallery oder einer
    internen Mirror-URL. Beispiel:
        https://www.powershellgallery.com/api/v2/package/Pester/5.7.1

.PARAMETER Force
    Vorhandenes _deps/Pester ueberschreiben.

.EXAMPLE
    .\tools\Install-Pester-Offline.ps1
.EXAMPLE
    .\tools\Install-Pester-Offline.ps1 -Source 'C:\PesterCache\Pester\5.7.1'
.EXAMPLE
    .\tools\Install-Pester-Offline.ps1 -Url 'https://www.powershellgallery.com/api/v2/package/Pester/5.7.1'
#>

[CmdletBinding()]
param(
    [string]$Source,
    [string]$Url,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path "$PSScriptRoot/.."
$target = Join-Path $repoRoot '_deps'
$pesterRoot = Join-Path $target 'Pester'

$null = New-Item -ItemType Directory -Force -Path $target

# ---------------------------------------------------------------
#  Modus 1: -Source <Pfad>
# ---------------------------------------------------------------
if ($Source) {
    if (-not (Test-Path -LiteralPath $Source)) {
        Write-Host "Source-Pfad existiert nicht: $Source" -ForegroundColor Red
        exit 2
    }

    # Pruefe ob $Source der "Pester"-Ordner ist oder ein Versionsordner darunter
    $manifest = Get-ChildItem -LiteralPath $Source -Recurse -Filter 'Pester.psd1' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $manifest) {
        Write-Host "Keine Pester.psd1 unterhalb $Source gefunden." -ForegroundColor Red
        exit 2
    }

    if ((Test-Path -LiteralPath $pesterRoot) -and -not $Force) {
        Write-Host "Ziel existiert bereits: $pesterRoot (verwende -Force zum Ueberschreiben)" -ForegroundColor Yellow
        exit 0
    }
    if (Test-Path -LiteralPath $pesterRoot) { Remove-Item -Recurse -Force $pesterRoot }

    Copy-Item -Recurse $Source $pesterRoot
    Write-Host "Pester aus '$Source' uebernommen nach: $pesterRoot" -ForegroundColor Green
}
# ---------------------------------------------------------------
#  Modus 3: -Url <nupkg>
# ---------------------------------------------------------------
elseif ($Url) {
    $tmp = New-Item -ItemType Directory -Force -Path (Join-Path $env:TEMP "lucentscreen-pester-$([guid]::NewGuid().ToString('N'))")
    try {
        # PS 5.1's Expand-Archive akzeptiert nur .zip -- nupkg ist ein ZIP,
        # also direkt mit .zip-Extension speichern.
        $nupkg = Join-Path $tmp.FullName 'Pester.zip'
        Write-Host "Lade $Url ..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $Url -OutFile $nupkg -UseBasicParsing

        $unzipDir = Join-Path $tmp.FullName 'unzip'
        Expand-Archive -LiteralPath $nupkg -DestinationPath $unzipDir -Force

        # nupkg-Layout: <root>/Pester.psd1 + Pester.psm1 + bin/...
        $manifest = Get-ChildItem -LiteralPath $unzipDir -Recurse -Filter 'Pester.psd1' -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $manifest) { throw "Pester.psd1 fehlt im nupkg." }

        $data = Import-PowerShellDataFile -LiteralPath $manifest.FullName
        $version = "$($data.ModuleVersion)"
        if (-not $version) { throw "ModuleVersion fehlt in Pester.psd1." }

        $verDir = Join-Path $pesterRoot $version
        if ((Test-Path -LiteralPath $verDir) -and -not $Force) {
            Write-Host "Pester $version ist bereits in $verDir (verwende -Force)" -ForegroundColor Yellow
            exit 0
        }
        if (Test-Path -LiteralPath $verDir) { Remove-Item -Recurse -Force $verDir }

        $null = New-Item -ItemType Directory -Force -Path $verDir
        # Inhalt des Manifest-Ordners (=Pester-Modulwurzel) hineinkopieren
        $sourceDir = $manifest.Directory.FullName
        Get-ChildItem -LiteralPath $sourceDir -Force | Copy-Item -Destination $verDir -Recurse -Force

        # NuGet-Metadaten (_rels, package, [Content_Types].xml) wegraeumen
        foreach ($noise in '_rels', 'package', '[Content_Types].xml') {
            $p = Join-Path $verDir $noise
            if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
        }

        Write-Host "Pester $version installiert nach $verDir" -ForegroundColor Green
    } finally {
        Remove-Item -LiteralPath $tmp.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}
# ---------------------------------------------------------------
#  Modus 2: PSGallery via Save-Module (Online-Convenience)
# ---------------------------------------------------------------
else {
    Write-Host "Lade Pester via Save-Module nach $target ..." -ForegroundColor Cyan
    Save-Module -Name Pester -MinimumVersion 5.0 -Path $target -Force
    Write-Host "Fertig." -ForegroundColor Green
}

Write-Host ""
Write-Host "Pruefe Inhalt:" -ForegroundColor DarkGray
Get-ChildItem -Directory $pesterRoot -ErrorAction SilentlyContinue |
    Select-Object Name, LastWriteTime
