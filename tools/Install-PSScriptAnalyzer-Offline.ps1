#Requires -Version 5.1
<#
.SYNOPSIS
    Laedt PSScriptAnalyzer offline-faehig nach _deps/PSScriptAnalyzer.

.DESCRIPTION
    Drei Modi -- in Reihenfolge der Praeferenz wenn man kein NuGet/PSGallery hat:
      1. -Source <Pfad>: kopiert ein vorhandenes PSSA-Verzeichnis (z.B. von
         einer Online-Maschine via Save-Module geholt) nach _deps/PSScriptAnalyzer.
      2. -Url <https://...>: laedt das nupkg-Paket direkt via Invoke-WebRequest
         (kein NuGet-Provider noetig).
      3. Ohne Parameter: Save-Module (nutzt PSGallery + NuGet-Provider).

.PARAMETER Source
    Lokaler Pfad zu einem bereits geladenen PSSA-Ordner.

.PARAMETER Url
    Direkter Download eines PSScriptAnalyzer.<version>.nupkg von der PSGallery
    oder einer internen Mirror-URL. Beispiel:
        https://www.powershellgallery.com/api/v2/package/PSScriptAnalyzer/1.25.0

.PARAMETER Force
    Vorhandenes _deps/PSScriptAnalyzer ueberschreiben.

.EXAMPLE
    .\tools\Install-PSScriptAnalyzer-Offline.ps1 -Url 'https://www.powershellgallery.com/api/v2/package/PSScriptAnalyzer/1.25.0'
.EXAMPLE
    .\tools\Install-PSScriptAnalyzer-Offline.ps1 -Source 'C:\Cache\PSScriptAnalyzer\1.25.0'
.EXAMPLE
    .\tools\Install-PSScriptAnalyzer-Offline.ps1
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
$pssaRoot = Join-Path $target 'PSScriptAnalyzer'

$null = New-Item -ItemType Directory -Force -Path $target

# ---------------------------------------------------------------
#  Modus 1: -Source <Pfad>
# ---------------------------------------------------------------
if ($Source) {
    if (-not (Test-Path -LiteralPath $Source)) {
        Write-Host "Source-Pfad existiert nicht: $Source" -ForegroundColor Red
        exit 2
    }

    $manifest = Get-ChildItem -LiteralPath $Source -Recurse -Filter 'PSScriptAnalyzer.psd1' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $manifest) {
        Write-Host "Keine PSScriptAnalyzer.psd1 unterhalb $Source gefunden." -ForegroundColor Red
        exit 2
    }

    if ((Test-Path -LiteralPath $pssaRoot) -and -not $Force) {
        Write-Host "Ziel existiert bereits: $pssaRoot (verwende -Force zum Ueberschreiben)" -ForegroundColor Yellow
        exit 0
    }
    if (Test-Path -LiteralPath $pssaRoot) { Remove-Item -Recurse -Force $pssaRoot }

    Copy-Item -Recurse $Source $pssaRoot
    Write-Host "PSSA aus '$Source' uebernommen nach: $pssaRoot" -ForegroundColor Green
}
# ---------------------------------------------------------------
#  Modus 2: -Url <nupkg>
# ---------------------------------------------------------------
elseif ($Url) {
    # TLS 1.2 ist auf alten Hosts oft nicht Default -- wir erzwingen es,
    # sonst scheitert powershellgallery.com mit "Could not create SSL/TLS".
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    } catch {
        # TLS-Enforcement ist nice-to-have, kein Hard-Error
        $null = $_
    }

    $tmp = New-Item -ItemType Directory -Force -Path (Join-Path $env:TEMP "lucentscreen-pssa-$([guid]::NewGuid().ToString('N'))")
    try {
        # PS 5.1's Expand-Archive akzeptiert nur .zip -- nupkg ist ein ZIP,
        # also direkt mit .zip-Extension speichern.
        $nupkg = Join-Path $tmp.FullName 'PSScriptAnalyzer.zip'
        Write-Host "Lade $Url ..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $Url -OutFile $nupkg -UseBasicParsing

        $unzipDir = Join-Path $tmp.FullName 'unzip'
        Expand-Archive -LiteralPath $nupkg -DestinationPath $unzipDir -Force

        $manifest = Get-ChildItem -LiteralPath $unzipDir -Recurse -Filter 'PSScriptAnalyzer.psd1' -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $manifest) { throw "PSScriptAnalyzer.psd1 fehlt im nupkg." }

        $data = Import-PowerShellDataFile -LiteralPath $manifest.FullName
        $version = "$($data.ModuleVersion)"
        if (-not $version) { throw "ModuleVersion fehlt in PSScriptAnalyzer.psd1." }

        $verDir = Join-Path $pssaRoot $version
        if ((Test-Path -LiteralPath $verDir) -and -not $Force) {
            Write-Host "PSScriptAnalyzer $version ist bereits in $verDir (verwende -Force)" -ForegroundColor Yellow
            exit 0
        }
        if (Test-Path -LiteralPath $verDir) { Remove-Item -Recurse -Force $verDir }

        $null = New-Item -ItemType Directory -Force -Path $verDir
        $sourceDir = $manifest.Directory.FullName
        Get-ChildItem -LiteralPath $sourceDir -Force | Copy-Item -Destination $verDir -Recurse -Force

        # NuGet-Metadaten wegraeumen
        foreach ($noise in '_rels', 'package', '[Content_Types].xml') {
            $p = Join-Path $verDir $noise
            if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
        }

        Write-Host "PSScriptAnalyzer $version installiert nach $verDir" -ForegroundColor Green
    } finally {
        Remove-Item -LiteralPath $tmp.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}
# ---------------------------------------------------------------
#  Modus 3: Save-Module (PSGallery + NuGet-Provider)
# ---------------------------------------------------------------
else {
    Write-Host "Lade PSScriptAnalyzer via Save-Module nach $target ..." -ForegroundColor Cyan
    Save-Module -Name PSScriptAnalyzer -Path $target -Force
    Write-Host "Fertig." -ForegroundColor Green
}

Write-Host ""
Write-Host "Pruefe Inhalt:" -ForegroundColor DarkGray
Get-ChildItem -Directory $pssaRoot -ErrorAction SilentlyContinue |
    Select-Object Name, LastWriteTime
