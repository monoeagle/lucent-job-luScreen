#Requires -Version 5.1
Set-StrictMode -Version Latest

# ---------------------------------------------------------------
#  Editor-Backend
#
#  Save-Pipeline fuer Annotations-Bilder. UI lebt in src/ui/editor-window.psm1.
#
#  API:
#    Format-EditedFilename -OriginalPath <p> [-Postfix '_edited']
#                                       -> string (Default-Pfad fuer Save)
#    Save-EditedImage -Source <BitmapSource> -OriginalPath <p>
#                     [-Postfix '_edited']
#                                       -> Result-Hashtable mit Path
#
#  Verhalten:
#    - Speichert IMMER als neue Datei -- Original bleibt unangetastet.
#    - Bei Namens-Kollisionen wird per Resolve-UniqueFilename ein
#      Suffix -2, -3 ... vor der Endung angefuegt.
#    - PNG-Format via PngBitmapEncoder.
#
#  Voraussetzungen:
#    PresentationCore + WindowsBase geladen (BitmapSource, PngBitmapEncoder).
#    core/capture.psm1 fuer Resolve-UniqueFilename.
# ---------------------------------------------------------------

function Format-EditedFilename {
    <#
    .SYNOPSIS
        Berechnet den Default-Pfad fuer eine editierte Variante.
    .DESCRIPTION
        Original 'foo.png' + Postfix '_edited' -> 'foo_edited.png' im gleichen
        Ordner. Endung wird vom Original uebernommen; fehlt sie, ist sie '.png'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$OriginalPath,
        [string]$Postfix = '_edited'
    )

    $dir = Split-Path -Parent $OriginalPath
    if (-not $dir) { $dir = '.' }
    $base = [System.IO.Path]::GetFileNameWithoutExtension($OriginalPath)
    $ext = [System.IO.Path]::GetExtension($OriginalPath)
    if (-not $ext) { $ext = '.png' }
    return (Join-Path $dir ($base + $Postfix + $ext))
}

function Save-EditedImage {
    <#
    .SYNOPSIS
        Speichert eine BitmapSource als PNG neben dem Original.
    .DESCRIPTION
        Wendet Format-EditedFilename an, dann Resolve-UniqueFilename fuer
        Kollisionsschutz, dann PngBitmapEncoder. Quelle muss Frozen sein
        (oder im STA-Thread aufgerufen werden).
    .OUTPUTS
        hashtable @{ Success; Status; Message; Path }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][System.Windows.Media.Imaging.BitmapSource]$Source,
        [Parameter(Mandatory)][string]$OriginalPath,
        [string]$Postfix = '_edited'
    )

    $candidate = Format-EditedFilename -OriginalPath $OriginalPath -Postfix $Postfix
    $finalPath = Resolve-UniqueFilename -Path $candidate

    $stream = $null
    try {
        $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $frame = [System.Windows.Media.Imaging.BitmapFrame]::Create($Source)
        $encoder.Frames.Add($frame)
        $stream = [System.IO.File]::OpenWrite($finalPath)
        $encoder.Save($stream)
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
    } finally {
        if ($null -ne $stream) { try { $stream.Dispose() } catch { $null = $_ } }
    }
}

function Get-ArrowGeometry {
    <#
    .SYNOPSIS
        Berechnet die Polyline-Punkte fuer einen Pfeil von (X1,Y1) nach (X2,Y2).
    .DESCRIPTION
        Liefert ein Array aus 5 Punkten:
          - Schenkel-Ende-1 -> Spitze (X2,Y2) -> Schenkel-Ende-2
          - kombiniert mit dem Schaft (X1,Y1) -> (X2,Y2)
        Reihenfolge fuer eine einzige Polyline:
          [(X1,Y1), (X2,Y2), Spitze1, (X2,Y2), Spitze2]
        Damit zeichnet eine einzige Polyline-Form sowohl den Schaft als auch
        beide Spitzen-Schenkel. Bei Start == End wird nur (X1,Y1) zurueckgegeben.
    .PARAMETER HeadSize
        Laenge der Spitzen-Schenkel in Pixeln. Default 14.
    .PARAMETER HeadAngleDeg
        Winkel pro Schenkel relativ zum Schaft (in Grad). Default 25.
    .OUTPUTS
        hashtable @{ Points = @( @{X=;Y=}, ... ); IsDegenerate = $bool }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][double]$X1,
        [Parameter(Mandatory)][double]$Y1,
        [Parameter(Mandatory)][double]$X2,
        [Parameter(Mandatory)][double]$Y2,
        [double]$HeadSize = 14,
        [double]$HeadAngleDeg = 25
    )

    $dx = $X2 - $X1
    $dy = $Y2 - $Y1
    $len = [math]::Sqrt($dx * $dx + $dy * $dy)

    if ($len -lt 0.5) {
        return @{
            Points       = @(@{ X = $X1; Y = $Y1 })
            IsDegenerate = $true
        }
    }

    # Winkel des Schafts; Spitzen-Schenkel zeigen vom End-Punkt RUECKWAERTS
    # ausgehend, jeweils um HeadAngleDeg vom Schaft weggedreht.
    $angle = [math]::Atan2($dy, $dx)
    $rad = [math]::PI * $HeadAngleDeg / 180.0

    $a1 = $angle + [math]::PI - $rad   # zurueck minus Winkel
    $a2 = $angle + [math]::PI + $rad   # zurueck plus Winkel

    $hx1 = $X2 + $HeadSize * [math]::Cos($a1)
    $hy1 = $Y2 + $HeadSize * [math]::Sin($a1)
    $hx2 = $X2 + $HeadSize * [math]::Cos($a2)
    $hy2 = $Y2 + $HeadSize * [math]::Sin($a2)

    return @{
        Points       = @(
            @{ X = $X1; Y = $Y1 },
            @{ X = $X2; Y = $Y2 },
            @{ X = $hx1; Y = $hy1 },
            @{ X = $X2; Y = $Y2 },
            @{ X = $hx2; Y = $hy2 }
        )
        IsDegenerate = $false
    }
}

Export-ModuleMember -Function Format-EditedFilename, Save-EditedImage, Get-ArrowGeometry
