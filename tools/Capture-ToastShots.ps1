#Requires -Version 5.1
<#
.SYNOPSIS
    Rendert die zwei Toast-Varianten (Save + Capture) headless als PNG.

.DESCRIPTION
    Wird einmalig fuer die Doku-Screenshots aufgerufen. Laedt
    src/views/capture-toast.xaml direkt (ohne Auto-Close-Timer),
    positioniert es rechts oben, rendert per Dispatcher,
    captured die Region ueber GDI+ und schreibt das Ergebnis nach
    luscreen-docs/docs/images/luscreen/0.2.0/.

.NOTES
    Muss in STA laufen. Wenn nicht, startet sich selbst neu via
    powershell.exe -STA.
#>
[CmdletBinding()]
param(
    [string]$OutDir = ''
)

# $PSScriptRoot ist im Param-Default in manchen Aufruf-Varianten leer --
# deshalb hier nachziehen.
if (-not $OutDir) {
    $here = Split-Path -Parent $PSCommandPath
    $OutDir = Join-Path $here '..\luscreen-docs\docs\images\luscreen\0.2.0'
}

if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    & powershell.exe -STA -NoProfile -File $PSCommandPath -OutDir $OutDir
    return
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$XamlPath = Join-Path $RepoRoot 'src\views\capture-toast.xaml'
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path

function Capture-Toast {
    param(
        [Parameter(Mandatory)][string]$OutFile,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Subtitle,
        [Parameter(Mandatory)][string]$Glyph
    )

    # XAML laden -- x:Class entfernen damit XamlReader es schluckt
    $raw = Get-Content -LiteralPath $XamlPath -Raw -Encoding UTF8
    $raw = $raw -replace '\s+x:Class="[^"]*"', ''
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$raw)
    $win = [System.Windows.Markup.XamlReader]::Load($reader)

    $win.FindName('TxtTitle').Text = $Title
    $win.FindName('TxtSubtitle').Text = $Subtitle
    $win.FindName('TxtGlyph').Text = $Glyph

    # Position rechts oben auf Primaerbildschirm
    $primary = [System.Windows.Forms.Screen]::PrimaryScreen
    $b = $primary.WorkingArea
    $win.Left = $b.Right - $win.Width - 24
    $win.Top = $b.Top + 24
    $win.Opacity = 1   # Kein Fade -- direkt sichtbar

    $win.Show()

    # Dispatcher pumpen bis Rendering komplett (ApplicationIdle)
    $win.Dispatcher.Invoke([action] {}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
    # Sicherheits-Yield -- DWM braucht einen Frame zum Compositing
    Start-Sleep -Milliseconds 150
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 50

    # Region ermitteln (px-genau, inkl. 12px Padding rundum fuer Kontext)
    $pad = 12
    $left = [int]$win.Left - $pad
    $top = [int]$win.Top - $pad
    $w = [int]$win.Width + (2 * $pad)
    $h = [int]$win.Height + (2 * $pad)

    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.CopyFromScreen($left, $top, 0, 0, (New-Object System.Drawing.Size $w, $h))
        $bmp.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)
        Write-Host ("OK: {0} ({1}x{2})" -f $OutFile, $w, $h) -ForegroundColor Green
    } finally {
        $g.Dispose()
        $bmp.Dispose()
    }

    $win.Close()
    # Dispatcher noch einmal kurz pumpen damit das Close greift
    $win.Dispatcher.Invoke([action] {}, [System.Windows.Threading.DispatcherPriority]::Background)
}

# Save-Toast: Copy-Glyph (0xE8C8), wie history-window.psm1 ihn fuer den
# Druck-Button setzt -- semantisch "Gespeichert/Kopiert".
Capture-Toast -OutFile (Join-Path $OutDir 'toast-saved.png') `
    -Title 'Gespeichert' `
    -Subtitle '20260516_1128_DruckTaste.png  1920x1080' `
    -Glyph "$([char]0xE8C8)"

# Capture-Toast: Kamera-Glyph (0xE722), Default in capture-toast.xaml
Capture-Toast -OutFile (Join-Path $OutDir 'toast-capture.png') `
    -Title 'Aufgenommen' `
    -Subtitle '20260516_1145_Monitor.png  1920x1080' `
    -Glyph "$([char]0xE722)"

Write-Host 'Fertig.' -ForegroundColor Cyan
