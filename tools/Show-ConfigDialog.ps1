#Requires -Version 5.1
<#
.SYNOPSIS
    Interaktiver Smoke-Test fuer den Konfig-Dialog (bis Tray-Menue in AP 2 vorhanden ist).
.DESCRIPTION
    Laedt aktuelle Config, zeigt den Dialog und speichert das Ergebnis, falls
    der User auf Speichern klickt. Muss in STA-Apartment laufen.
#>
[CmdletBinding()]
param()

if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    throw 'Show-ConfigDialog.ps1 muss mit -STA gestartet werden (pwsh -STA -File ...).'
}

$root = Split-Path -Parent $PSScriptRoot
$coreDir = Join-Path $root 'src/core'
$uiDir = Join-Path $root 'src/ui'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

Import-Module (Join-Path $coreDir 'config.psm1') -Force
Import-Module (Join-Path $coreDir 'xaml-loader.psm1') -Force
Import-Module (Join-Path $uiDir 'config-dialog.psm1') -Force

$current = Read-Config
Write-Host ("Aktuelle Config: {0}" -f (Get-ConfigPath)) -ForegroundColor Cyan
Write-Host "  OutputDir: $($current.OutputDir)" -ForegroundColor DarkGray
Write-Host "  Delay:     $($current.DelaySeconds)s" -ForegroundColor DarkGray

$updated = Show-ConfigDialog -Config $current
if ($null -eq $updated) {
    Write-Host "Abgebrochen." -ForegroundColor Yellow
    exit 0
}

$r = Save-Config -Config $updated
if ($r.Success) {
    Write-Host ("Gespeichert: {0}" -f $r.Path) -ForegroundColor Green
} else {
    Write-Host ("Fehler: {0}" -f $r.Message) -ForegroundColor Red
    exit 1
}
