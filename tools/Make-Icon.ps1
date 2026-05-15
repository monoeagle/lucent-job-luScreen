#Requires -Version 5.1
<#
.SYNOPSIS
    Erzeugt assets/luscreen.ico aus generierten Bitmaps (16/32/48 px).

.DESCRIPTION
    Platzhalter-Icon mit "LS" auf accent-farbenem Hintergrund. Wird im
    Tray angezeigt, kann spaeter durch ein gestaltetes Icon ersetzt werden.
    Pflicht-Eigenschaft: Multi-Resolution ICO (Windows skaliert je nach
    Render-Kontext).
#>

[CmdletBinding()]
param(
    [string]$Out
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path "$PSScriptRoot/.."
if (-not $Out) { $Out = Join-Path $repoRoot 'assets/luscreen.ico' }

$assetsDir = Split-Path -Parent $Out
$null = New-Item -ItemType Directory -Force -Path $assetsDir

Add-Type -AssemblyName System.Drawing

function New-LuscreenBitmap {
    param([int]$Size)

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $gfx.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $gfx.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias

        # Hintergrund: Lucent-Hub-Accent (#00B7EB)
        $bg = [System.Drawing.Color]::FromArgb(255, 0, 183, 235)
        $gfx.Clear([System.Drawing.Color]::Transparent)
        $brush = New-Object System.Drawing.SolidBrush $bg
        $gfx.FillEllipse($brush, 1, 1, $Size - 2, $Size - 2)
        $brush.Dispose()

        # Text "LS" zentriert
        $fontSize = [Math]::Max(6, [int]($Size * 0.45))
        $font = New-Object System.Drawing.Font('Segoe UI Semibold', $fontSize, [System.Drawing.GraphicsUnit]::Pixel)
        $textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $fmt = New-Object System.Drawing.StringFormat
        $fmt.Alignment = [System.Drawing.StringAlignment]::Center
        $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
        $rect = New-Object System.Drawing.RectangleF(0, 0, $Size, $Size)
        $gfx.DrawString('LS', $font, $textBrush, $rect, $fmt)
        $font.Dispose()
        $textBrush.Dispose()
        $fmt.Dispose()
    } finally {
        $gfx.Dispose()
    }
    return $bmp
}

# Multi-Size ICO bauen: wir schreiben ein gueltiges ICO-File mit eingebetteten
# PNG-Frames. Format-Referenz: https://en.wikipedia.org/wiki/ICO_(file_format)
$sizes = @(16, 32, 48, 64)
$pngBytes = New-Object 'System.Collections.Generic.List[byte[]]'
foreach ($s in $sizes) {
    $bmp = New-LuscreenBitmap -Size $s
    try {
        $ms = New-Object System.IO.MemoryStream
        try {
            $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
            $pngBytes.Add($ms.ToArray())
        } finally {
            $ms.Dispose()
        }
    } finally {
        $bmp.Dispose()
    }
}

# ICO-Bytes manuell zusammenbauen (BinaryWriter-Konstruktor mucken in PS 5.1)
$bytes = New-Object 'System.Collections.Generic.List[byte]'

function _Add-UInt16 {
    param([System.Collections.Generic.List[byte]]$List, [uint16]$Value)
    $List.Add([byte]($Value -band 0xFF))
    $List.Add([byte](($Value -shr 8) -band 0xFF))
}
function _Add-UInt32 {
    param([System.Collections.Generic.List[byte]]$List, [uint32]$Value)
    $List.Add([byte]($Value -band 0xFF))
    $List.Add([byte](($Value -shr 8) -band 0xFF))
    $List.Add([byte](($Value -shr 16) -band 0xFF))
    $List.Add([byte](($Value -shr 24) -band 0xFF))
}

# ICONDIR Header
_Add-UInt16 $bytes 0
_Add-UInt16 $bytes 1
_Add-UInt16 $bytes ([uint16]$sizes.Count)

$offsetStart = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]
    $data = $pngBytes[$i]
    $w = if ($s -ge 256) { 0 } else { $s }
    $h = if ($s -ge 256) { 0 } else { $s }

    $bytes.Add([byte]$w)
    $bytes.Add([byte]$h)
    $bytes.Add([byte]0)
    $bytes.Add([byte]0)
    _Add-UInt16 $bytes 1
    _Add-UInt16 $bytes 32
    _Add-UInt32 $bytes ([uint32]$data.Length)
    _Add-UInt32 $bytes ([uint32]$offsetStart)
    $offsetStart += $data.Length
}
foreach ($data in $pngBytes) {
    $bytes.AddRange([byte[]]$data)
}

[System.IO.File]::WriteAllBytes($Out, $bytes.ToArray())

$fi = Get-Item $Out
Write-Host ("luscreen.ico erstellt: {0} ({1} Bytes, {2} Aufloesungen)" -f $Out, $fi.Length, $sizes.Count) -ForegroundColor Green
