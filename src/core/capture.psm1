#Requires -Version 5.1
Set-StrictMode -Version Latest

# ---------------------------------------------------------------
#  Capture-Engine
#
#  Modi:
#    Monitor      = Bildschirm unter Cursor
#    AllMonitors  = Virtual Screen (Bounding-Box ueber alle Monitore)
#    ActiveWindow = Vordergrundfenster mit DWM-Frame
#    Region       = User-Rechteck (Overlay liefert RECT, hier nur Crop)
#
#  API:
#    Get-AllScreens               -> System.Windows.Forms.Screen[]
#    Get-VirtualScreenBounds      -> System.Drawing.Rectangle
#    Get-ScreenUnderCursor        -> System.Windows.Forms.Screen
#    Get-ForegroundWindowRect     -> @{ Left,Top,Right,Bottom,Width,Height,Source }
#    Capture-Rect -L -T -W -H     -> [System.Drawing.Bitmap]   (Caller disposed)
#    Save-Capture -Bitmap -Mode -OutputDir
#                                 -> Result-Hashtable mit Path
#    Invoke-Capture -Mode <Mode> [-RegionRect $rect] [-DelaySeconds 0]
#                                 -> Result-Hashtable
#                                    { Success, Mode, Width, Height, Bitmap }
#
#  Voraussetzungen:
#    - System.Drawing + System.Windows.Forms geladen
#    - core/native.psm1 geladen (RECT, POINT, GetForegroundWindow, ...)
# ---------------------------------------------------------------

function Get-AllScreens {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param()
    return , @([System.Windows.Forms.Screen]::AllScreens)
}

function Get-VirtualScreenBounds {
    [CmdletBinding()]
    [OutputType([System.Drawing.Rectangle])]
    param()
    return [System.Windows.Forms.SystemInformation]::VirtualScreen
}

function Get-ScreenUnderCursor {
    [CmdletBinding()]
    [OutputType([System.Windows.Forms.Screen])]
    param()
    $pt = New-Object LucentScreen.Native+POINT
    [void][LucentScreen.Native]::GetCursorPos([ref]$pt)
    $cursor = New-Object System.Drawing.Point($pt.X, $pt.Y)
    return [System.Windows.Forms.Screen]::FromPoint($cursor)
}

function Get-ForegroundWindowRect {
    <#
    .SYNOPSIS
        Liefert das Rect des Vordergrundfensters. Bevorzugt DWM-Extended-
        Frame-Bounds (ohne DropShadow), Fallback auf GetWindowRect.
    .OUTPUTS
        hashtable mit Left/Top/Right/Bottom/Width/Height/Source/Hwnd, oder
        $null wenn kein Vordergrundfenster ermittelbar.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $hwnd = [LucentScreen.Native]::GetForegroundWindow()
    if ($hwnd -eq [IntPtr]::Zero) { return $null }

    $rect = New-Object LucentScreen.Native+RECT
    $sz = [System.Runtime.InteropServices.Marshal]::SizeOf([Type]'LucentScreen.Native+RECT')
    $hr = [LucentScreen.Native]::DwmGetWindowAttribute(
        $hwnd, [LucentScreen.Native]::DWMWA_EXTENDED_FRAME_BOUNDS, [ref]$rect, $sz)

    $source = 'DWM'
    if ($hr -ne 0) {
        # Fallback
        $rect = New-Object LucentScreen.Native+RECT
        $ok = [LucentScreen.Native]::GetWindowRect($hwnd, [ref]$rect)
        if (-not $ok) { return $null }
        $source = 'GetWindowRect'
    }

    return @{
        Left   = $rect.Left
        Top    = $rect.Top
        Right  = $rect.Right
        Bottom = $rect.Bottom
        Width  = $rect.Right - $rect.Left
        Height = $rect.Bottom - $rect.Top
        Source = $source
        Hwnd   = $hwnd
    }
}

function Capture-Rect {
    <#
    .SYNOPSIS
        Liest die Pixel im angegebenen Bildschirm-Rechteck per GDI+ aus.
    .OUTPUTS
        [System.Drawing.Bitmap] -- Caller MUSS Dispose() aufrufen.
    #>
    [CmdletBinding()]
    [OutputType([System.Drawing.Bitmap])]
    param(
        [Parameter(Mandatory)][int]$Left,
        [Parameter(Mandatory)][int]$Top,
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Height
    )

    if ($Width -le 0 -or $Height -le 0) {
        throw "Capture-Rect: Width/Height muessen positiv sein (got $Width x $Height)."
    }

    $bmp = New-Object System.Drawing.Bitmap($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $gfx.CopyFromScreen(
            $Left, $Top, 0, 0,
            (New-Object System.Drawing.Size($Width, $Height)),
            [System.Drawing.CopyPixelOperation]::SourceCopy)
    } finally {
        $gfx.Dispose()
    }
    return $bmp
}

function Format-CaptureFilename {
    <#
    .SYNOPSIS
        Wendet das User-konfigurierbare FileNameFormat auf den aktuellen
        Zeitpunkt + Mode + optionalem Postfix an.
    .DESCRIPTION
        Unterstuetzte Tokens (alle case-sensitive):
          {mode}    -- Capture-Modus (Region/ActiveWindow/Monitor/AllMonitors)
          {postfix} -- optionaler Suffix (EditPostfix aus Config)
          yyyy yy   -- Jahr (4- oder 2-stellig)
          MM        -- Monat (01-12)
          dd        -- Tag (01-31)
          HH        -- Stunde 24h (00-23)
          mm        -- Minute (00-59)
          ss        -- Sekunde (00-59)
        Andere Buchstaben bleiben literal -- wir verwenden NICHT
        DateTime.ToString, weil dort u.a. 'g' (Era) und einzelne 'M'/'d'
        eigene Bedeutung haben und unwillkommen in Dateinamen sind.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Template,
        [Parameter(Mandatory)][string]$Mode,
        [string]$Postfix = '',
        [datetime]$Now = (Get-Date)
    )

    # Reihenfolge: lange Tokens zuerst (yyyy vor yy). -creplace ist
    # case-sensitive, damit MM und mm unterscheidbar bleiben.
    $r = $Template
    $r = $r -creplace 'yyyy', $Now.ToString('yyyy')
    $r = $r -creplace 'yy', $Now.ToString('yy')
    $r = $r -creplace 'MM', $Now.ToString('MM')
    $r = $r -creplace 'dd', $Now.ToString('dd')
    $r = $r -creplace 'HH', $Now.ToString('HH')
    $r = $r -creplace 'mm', $Now.ToString('mm')
    $r = $r -creplace 'ss', $Now.ToString('ss')

    return $r.Replace('{mode}', $Mode).Replace('{postfix}', $Postfix)
}

function Resolve-UniqueFilename {
    <#
    .SYNOPSIS
        Liefert einen freien Dateipfad. Bei Kollision wird vor der Endung
        ein Suffix -2, -3, ... angehaengt.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $Path }

    $dir = Split-Path -Parent $Path
    $base = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $ext = [System.IO.Path]::GetExtension($Path)

    $i = 2
    while ($true) {
        $candidate = Join-Path $dir ("{0}-{1}{2}" -f $base, $i, $ext)
        if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }
        $i++
        if ($i -gt 9999) { throw "Kein freier Dateiname unter $Path (>9999 Kollisionen)" }
    }
}

function _Test-DirectoryWritable {
    param([string]$Path)
    $probe = Join-Path $Path (".lucentscreen-write-probe-" + [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllBytes($probe, [byte[]]@(0))
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        return $false
    }
}

function Save-Capture {
    <#
    .SYNOPSIS
        Speichert ein Bitmap als PNG mit benutzerdefiniertem Schema und
        Kollisionsschutz.
    .PARAMETER Template
        Dateinamenschema (siehe Format-CaptureFilename). Optional -- ohne
        Wert wird ein Default mit Mode genutzt.
    .PARAMETER Postfix
        Wert fuer {postfix}-Token, typischerweise '' bei direkten Captures,
        '_edited' o.ae. beim Speichern aus dem Editor (AP 9).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][System.Drawing.Bitmap]$Bitmap,
        [Parameter(Mandatory)][string]$Mode,
        [Parameter(Mandatory)][string]$OutputDir,
        [string]$Template = 'LucentScreen_yyyyMMdd-HHmmss_{mode}.png',
        [string]$Postfix = ''
    )

    if (-not (Test-Path -LiteralPath $OutputDir)) {
        try {
            $null = New-Item -ItemType Directory -Force -Path $OutputDir
        } catch {
            return @{
                Success = $false
                Status  = 'OutputDirFailed'
                Message = "Konnte Zielordner nicht anlegen: $($_.Exception.Message)"
                Path    = $null
            }
        }
    }

    if (-not (_Test-DirectoryWritable -Path $OutputDir)) {
        return @{
            Success = $false
            Status  = 'PermissionDenied'
            Message = "Keine Schreibrechte auf '$OutputDir'."
            Path    = $null
        }
    }

    $filename = Format-CaptureFilename -Template $Template -Mode $Mode -Postfix $Postfix
    $candidate = Join-Path $OutputDir $filename
    $finalPath = Resolve-UniqueFilename -Path $candidate

    try {
        $Bitmap.Save($finalPath, [System.Drawing.Imaging.ImageFormat]::Png)
        return @{
            Success = $true
            Status  = 'OK'
            Message = "Gespeichert: $finalPath"
            Path    = $finalPath
        }
    } catch {
        return @{
            Success = $false
            Status  = 'SaveFailed'
            Message = "Speichern fehlgeschlagen: $($_.Exception.Message)"
            Path    = $null
        }
    }
}

function Invoke-Capture {
    <#
    .SYNOPSIS
        Fuehrt einen Capture aus und liefert das Bitmap zurueck.
    .PARAMETER Mode
        Monitor | AllMonitors | ActiveWindow | Region
    .PARAMETER RegionRect
        Pflicht-Parameter fuer Mode=Region: hashtable mit Left/Top/Width/Height.
    .PARAMETER DelaySeconds
        Optionale Verzoegerung vor der Aufnahme (0..30).
    .OUTPUTS
        hashtable mit Success / Mode / Width / Height / Bitmap / Source
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][ValidateSet('Monitor', 'AllMonitors', 'ActiveWindow', 'Region')]
        [string]$Mode,
        [hashtable]$RegionRect,
        [ValidateRange(0, 30)][int]$DelaySeconds = 0
    )

    if ($DelaySeconds -gt 0) {
        Start-Sleep -Seconds $DelaySeconds
    }

    switch ($Mode) {
        'Monitor' {
            $screen = Get-ScreenUnderCursor
            $b = $screen.Bounds
            $bmp = Capture-Rect -Left $b.Left -Top $b.Top -Width $b.Width -Height $b.Height
            return @{
                Success = $true; Mode = $Mode
                Width   = $b.Width; Height = $b.Height
                Bitmap  = $bmp
                Source  = "Screen $($screen.DeviceName)"
            }
        }

        'AllMonitors' {
            $b = Get-VirtualScreenBounds
            $bmp = Capture-Rect -Left $b.Left -Top $b.Top -Width $b.Width -Height $b.Height
            return @{
                Success = $true; Mode = $Mode
                Width   = $b.Width; Height = $b.Height
                Bitmap  = $bmp
                Source  = 'VirtualScreen'
            }
        }

        'ActiveWindow' {
            $r = Get-ForegroundWindowRect
            if ($null -eq $r) {
                return @{ Success = $false; Mode = $Mode; Message = 'Kein Vordergrundfenster gefunden.' }
            }
            if ($r.Width -le 0 -or $r.Height -le 0) {
                return @{ Success = $false; Mode = $Mode; Message = "Ungueltige Fenster-Groesse: $($r.Width)x$($r.Height)" }
            }
            $bmp = Capture-Rect -Left $r.Left -Top $r.Top -Width $r.Width -Height $r.Height
            return @{
                Success = $true; Mode = $Mode
                Width   = $r.Width; Height = $r.Height
                Bitmap  = $bmp
                Source  = "ForegroundWindow ($($r.Source))"
            }
        }

        'Region' {
            if (-not $RegionRect) {
                return @{ Success = $false; Mode = $Mode; Message = 'RegionRect fehlt (Overlay-Aufruf vergessen?).' }
            }
            $bmp = Capture-Rect -Left $RegionRect.Left -Top $RegionRect.Top -Width $RegionRect.Width -Height $RegionRect.Height
            return @{
                Success = $true; Mode = $Mode
                Width   = $RegionRect.Width; Height = $RegionRect.Height
                Bitmap  = $bmp
                Source  = 'Region'
            }
        }
    }
}

Export-ModuleMember -Function Get-AllScreens, Get-VirtualScreenBounds, Get-ScreenUnderCursor, Get-ForegroundWindowRect, Capture-Rect, Save-Capture, Invoke-Capture, Format-CaptureFilename, Resolve-UniqueFilename
