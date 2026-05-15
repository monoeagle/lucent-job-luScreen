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

Export-ModuleMember -Function Format-EditedFilename, Save-EditedImage
