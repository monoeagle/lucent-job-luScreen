#Requires -Version 5.1
<#
.SYNOPSIS
    Halbautomatischer Screenshot-Generator für die LucentScreen-Doku.

.DESCRIPTION
    Iteriert über luscreen-docs/docs/images/luscreen/<version>/manifest.json
    und captured pro Eintrag das passende UI-Element nach
    luscreen-docs/docs/images/luscreen/<version>/<file>.png.

    Für jeden Eintrag:
      - Skript zeigt Beschreibung + Datei-Name
      - Wenn auto-fähig: bietet automatisches Öffnen + Capture an
      - Sonst: User macht Setup (Tray rechtsklick, Editor öffnen + annotieren etc.),
        drückt ENTER, Skript captured Vollbild oder spezifisches Window per Title

    Output: PNG-Files + manifest.json mit aktualisiertem capturedAt.

.PARAMETER Version
    Versions-Ordner unter docs/images/luscreen/. Default: 0.2.0.

.PARAMETER Only
    Nur ein bestimmtes Item aufnehmen (matched gegen file-Feld im manifest).
    Beispiel: -Only tray-menu

.PARAMETER Skip
    Liste von Item-Files zum Überspringen.

.PARAMETER FullScreen
    Statt Window-Capture per HWND immer Vollbild aufnehmen (Fallback).

.EXAMPLE
    .\tools\Take-LuScreenshots.ps1
    Alle Items im manifest abarbeiten.

.EXAMPLE
    .\tools\Take-LuScreenshots.ps1 -Only config-dialog
    Nur den Konfig-Dialog neu aufnehmen.
#>
[CmdletBinding()]
param(
    [string]$Version = '0.2.0',
    [string]$Only,
    [string[]]$Skip = @(),
    [switch]$FullScreen
)

$ErrorActionPreference = 'Stop'

# ─── Setup ──────────────────────────────────────────────────────────────────
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ImagesDir = Join-Path $RepoRoot ("luscreen-docs/docs/images/luscreen/{0}" -f $Version)
$Manifest = Join-Path $ImagesDir 'manifest.json'

if (-not (Test-Path -LiteralPath $Manifest)) {
    throw "Manifest nicht gefunden: $Manifest"
}

# Win32 API für Window-Lookup + Capture
if (-not ('LuScreenshots.Win32' -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
namespace LuScreenshots {
    public static class Win32 {
        [DllImport("user32.dll")] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
        [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
        [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
        [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
        [StructLayout(LayoutKind.Sequential)]
        public struct RECT { public int Left, Top, Right, Bottom; }
    }
}
"@
}

# ─── Helpers ────────────────────────────────────────────────────────────────

function Get-WindowByTitlePart {
    param([Parameter(Mandatory)][string]$Pattern)
    $script:foundHwnd = [IntPtr]::Zero
    $callback = [LuScreenshots.Win32+EnumWindowsProc] {
        param($hwnd, $lparam)
        $null = $lparam
        if (-not [LuScreenshots.Win32]::IsWindowVisible($hwnd)) { return $true }
        $sb = New-Object System.Text.StringBuilder 256
        [void][LuScreenshots.Win32]::GetWindowText($hwnd, $sb, 256)
        if ($sb.ToString() -like "*$Pattern*") {
            $script:foundHwnd = $hwnd
            return $false
        }
        return $true
    }
    [void][LuScreenshots.Win32]::EnumWindows($callback, [IntPtr]::Zero)
    return $script:foundHwnd
}

function Capture-Hwnd {
    param([Parameter(Mandatory)][IntPtr]$Hwnd, [Parameter(Mandatory)][string]$OutPath)
    $rect = New-Object LuScreenshots.Win32+RECT
    if (-not [LuScreenshots.Win32]::GetWindowRect($Hwnd, [ref]$rect)) {
        throw "GetWindowRect fehlgeschlagen für $Hwnd"
    }
    $w = $rect.Right - $rect.Left
    $h = $rect.Bottom - $rect.Top
    if ($w -le 0 -or $h -le 0) { throw "Window hat keine Dimensionen ($w x $h)" }
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, (New-Object System.Drawing.Size $w, $h))
    } finally { $g.Dispose() }
    $bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host ("  -> {0}x{1} px geschrieben: {2}" -f $w, $h, (Split-Path $OutPath -Leaf)) -ForegroundColor Green
}

function Capture-FullScreen {
    param([Parameter(Mandatory)][string]$OutPath)
    $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.CopyFromScreen($b.Left, $b.Top, 0, 0, (New-Object System.Drawing.Size $b.Width, $b.Height))
    } finally { $g.Dispose() }
    $bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host ("  -> {0}x{1} px geschrieben: {2} (Vollbild)" -f $b.Width, $b.Height, (Split-Path $OutPath -Leaf)) -ForegroundColor Green
}

function Wait-Enter {
    param([string]$Prompt)
    Write-Host ""
    Write-Host $Prompt -ForegroundColor Yellow
    Write-Host "  Bereit? ENTER drücken (oder S zum Skippen, Q zum Beenden)" -ForegroundColor DarkGray
    while ($true) {
        $key = [System.Console]::ReadKey($true)
        switch ($key.Key) {
            'Enter' { return 'Capture' }
            'S' { return 'Skip' }
            'Q' { return 'Quit' }
        }
    }
}

# ─── Capture-Plan pro Item ──────────────────────────────────────────────────
# Mapping: file -> @{ TitlePattern (für Window-Capture); Setup-Hint }
$captureMap = @{
    'tray-menu.png' = @{ Title = $null; Hint = "Rechtsklick auf das LucentScreen-Tray-Icon -- Menue oeffnet sich. Maus auf einem Eintrag stehen lassen, dann ENTER. (Vollbild-Capture)" }
    'config-dialog.png' = @{ Title = 'Konfiguration'; Hint = "Tray -> Konfiguration... -- Dialog ist offen." }
    'history-window.png' = @{ Title = 'Verlauf'; Hint = "Tray -> Verlauf oeffnen -- Fenster zeigt Bilder." }
    'history-context.png' = @{ Title = $null; Hint = "Im Verlauf rechtsklick auf ein Bild -- Kontextmenue offen. (Vollbild-Capture)" }
    'editor-empty.png' = @{ Title = 'Editor'; Hint = "Verlauf -> Doppelklick auf ein Bild -- Editor offen, KEINE Annotations, Tool=Auswahl." }
    'editor-tools.png' = @{ Title = 'Editor'; Hint = "Editor mit Pfeil + Rahmen + Marker auf einem Bild gezeichnet." }
    'editor-crop.png' = @{ Title = 'Editor'; Hint = "Editor mit aktivem Crop-Tool (Taste C) -- 8 blaue Handles + Dimmer sichtbar." }
    'editor-selection.png' = @{ Title = 'Editor'; Hint = "Editor mit Selection-Adorner: Tool=Auswahl, einmal auf eine gezeichnete Shape klicken -- gestricheltes blaues Bounding-Box-Rect." }
    'about-dialog.png' = @{ Title = 'Ueber LucentScreen'; Hint = "Tray -> Ueber... -- Dialog zeigt Tab Info." }
    'about-changelog.png' = @{ Title = 'Ueber LucentScreen'; Hint = "Tray -> Ueber... -- Tab Changelog aktiv." }
    'toast-saved.png' = @{ Title = $null; Hint = "Editor -> Strg+S -- Toast oben rechts erscheint. ENTER innerhalb 1.4 Sek. (Vollbild-Capture)" }
    'toast-capture.png' = @{ Title = $null; Hint = "Strg+Shift+3 (Monitor-Capture) -- Toast oben rechts. ENTER innerhalb 1.4 Sek. (Vollbild-Capture)" }
    'region-overlay.png' = @{ Title = $null; Hint = "Strg+Shift+1 -- Vollbild-Overlay aktiv (Crosshair sichtbar). ENTER vor dem Drag. (Vollbild-Capture)" }
    'countdown.png' = @{ Title = $null; Hint = "Verzoegerung +5 Sek (Strg+Shift+T), dann Strg+Shift+3 -- Countdown laeuft. ENTER waehrend der Countdown noch sichtbar. (Vollbild-Capture)" }
}

# ─── Manifest laden ─────────────────────────────────────────────────────────
$mf = Get-Content -LiteralPath $Manifest -Raw -Encoding UTF8 | ConvertFrom-Json

Write-Host ""
Write-Host "=== LucentScreen Screenshot-Generator ===" -ForegroundColor Cyan
Write-Host ("Version:     {0}" -f $Version)
Write-Host ("Output-Dir:  {0}" -f $ImagesDir)
Write-Host ("Items:       {0}" -f $mf.images.Count)
if ($Only) { Write-Host ("Only:        {0}" -f $Only) -ForegroundColor Yellow }
if ($Skip.Count) { Write-Host ("Skip:        {0}" -f ($Skip -join ', ')) -ForegroundColor Yellow }
if ($FullScreen) { Write-Host "FullScreen-Modus aktiv (HWND-Lookup wird übersprungen)" -ForegroundColor Yellow }
Write-Host ""
Write-Host "Hinweis: App muss bereits laufen (./run.ps1 s)." -ForegroundColor DarkGray

$capturedCount = 0
foreach ($img in $mf.images) {
    if ($Only -and $img.file -ne "$Only.png" -and $img.file -ne $Only) { continue }
    if ($Skip -contains $img.file -or $Skip -contains $img.file.Replace('.png', '')) { continue }

    $cfg = $captureMap[$img.file]
    if (-not $cfg) { $cfg = @{ Title = $null; Hint = $img.description } }

    Write-Host ""
    Write-Host ("──── {0} ────" -f $img.file) -ForegroundColor Cyan
    Write-Host ("  View: {0}" -f $img.view)
    Write-Host ("  {0}" -f $img.description) -ForegroundColor DarkGray

    $action = Wait-Enter -Prompt ("  Setup: " + $cfg.Hint)
    if ($action -eq 'Quit') { Write-Host "Abbruch." -ForegroundColor Yellow; break }
    if ($action -eq 'Skip') { Write-Host "  Übersprungen." -ForegroundColor DarkGray; continue }

    $outPath = Join-Path $ImagesDir $img.file
    try {
        if ($cfg.Title -and -not $FullScreen) {
            $hwnd = Get-WindowByTitlePart -Pattern $cfg.Title
            if ($hwnd -ne [IntPtr]::Zero) {
                [void][LuScreenshots.Win32]::SetForegroundWindow($hwnd)
                Start-Sleep -Milliseconds 300
                Capture-Hwnd -Hwnd $hwnd -OutPath $outPath
            } else {
                Write-Host "  Window mit Title '$($cfg.Title)' nicht gefunden -- Vollbild-Fallback." -ForegroundColor Yellow
                Capture-FullScreen -OutPath $outPath
            }
        } else {
            Capture-FullScreen -OutPath $outPath
        }
        $capturedCount++
    } catch {
        Write-Host ("  FEHLER: " + $_.Exception.Message) -ForegroundColor Red
    }
}

# ─── Manifest aktualisieren ─────────────────────────────────────────────────
if ($capturedCount -gt 0) {
    $mf.capturedAt = (Get-Date).ToString('o')
    $json = $mf | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $Manifest -Value $json -Encoding UTF8
    Write-Host ""
    Write-Host ("Fertig. {0} Screenshots aufgenommen, manifest.json aktualisiert." -f $capturedCount) -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "Keine Screenshots aufgenommen." -ForegroundColor DarkGray
}
