#Requires -Version 5.1
Set-StrictMode -Version Latest

# ---------------------------------------------------------------
#  Clipboard-Integration
#
#  API:
#    Convert-BitmapToBitmapSource -Bitmap <System.Drawing.Bitmap>
#      -> [System.Windows.Media.Imaging.BitmapSource] (Frozen)
#
#    Set-ClipboardImage -Bitmap <Bitmap> [-MaxAttempts 5] [-InitialDelayMs 50]
#      -> Result-Hashtable @{ Success; Status; Message; Attempts }
#
#    Save-ClipboardImageAsPng -Path <string> [-MaxAttempts 5] [-InitialDelayMs 50]
#      -> Result-Hashtable @{ Success; Status; Message; Path; Width; Height; Attempts }
#
#  Voraussetzungen:
#    - STA-Apartment (Clipboard.SetImage/GetImage erfordert STA)
#    - WPF-Assemblies geladen (PresentationCore, WindowsBase)
# ---------------------------------------------------------------

function Convert-BitmapToBitmapSource {
    <#
    .SYNOPSIS
        Wandelt ein System.Drawing.Bitmap in einen WPF BitmapSource.
    .DESCRIPTION
        Roundtrip ueber MemoryStream + PNG-Encoding. Vermeidet das
        HBITMAP-Handle-Leak von Imaging.CreateBitmapSourceFromHBitmap
        und liefert ein Frozen-BitmapSource (threadsafe, fuer Clipboard
        + Cross-Thread-Verwendung geeignet).
    #>
    [CmdletBinding()]
    [OutputType([System.Windows.Media.Imaging.BitmapSource])]
    param([Parameter(Mandatory)][System.Drawing.Bitmap]$Bitmap)

    $stream = New-Object System.IO.MemoryStream
    try {
        $Bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        $stream.Position = 0

        $src = New-Object System.Windows.Media.Imaging.BitmapImage
        $src.BeginInit()
        # OnLoad: laedt das ganze Bild beim EndInit, damit der Stream
        # danach geschlossen werden kann.
        $src.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $src.StreamSource = $stream
        $src.EndInit()
        $src.Freeze()
        return $src
    } finally {
        $stream.Dispose()
    }
}

function Set-ClipboardImage {
    <#
    .SYNOPSIS
        Legt ein Bitmap als Bild in die Windows-Zwischenablage.
    .DESCRIPTION
        Macht intern ein Bitmap->BitmapSource-Roundtrip. Bei
        Clipboard-Locks (z.B. wenn gerade eine andere App schreibt)
        wird mit exponentiellem Backoff bis MaxAttempts retried.
    .OUTPUTS
        hashtable @{ Success, Status, Message, Attempts }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][System.Drawing.Bitmap]$Bitmap,
        [int]$MaxAttempts = 5,
        [int]$InitialDelayMs = 50
    )

    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        return @{
            Success  = $false
            Status   = 'NotSta'
            Message  = 'Clipboard.SetImage erfordert STA-Apartment.'
            Attempts = 0
        }
    }

    try {
        $src = Convert-BitmapToBitmapSource -Bitmap $Bitmap
    } catch {
        return @{
            Success  = $false
            Status   = 'ConvertFailed'
            Message  = "Bitmap-Konvertierung fehlgeschlagen: $($_.Exception.Message)"
            Attempts = 0
        }
    }

    $delay = $InitialDelayMs
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        try {
            [System.Windows.Clipboard]::SetImage($src)
            return @{
                Success  = $true
                Status   = 'OK'
                Message  = "In Zwischenablage kopiert (Versuch $i)"
                Attempts = $i
            }
        } catch {
            if ($i -ge $MaxAttempts) {
                return @{
                    Success  = $false
                    Status   = 'ClipboardLocked'
                    Message  = "Clipboard nach $i Versuchen nicht zugaenglich: $($_.Exception.Message)"
                    Attempts = $i
                }
            }
            Start-Sleep -Milliseconds $delay
            $delay = [int][Math]::Min($delay * 2, 2000)
        }
    }
}

function Save-ClipboardImageAsPng {
    <#
    .SYNOPSIS
        Liest das Bild aus der Zwischenablage und speichert es als PNG.
    .DESCRIPTION
        Nutzt Clipboard.GetImage() (BitmapSource) + PngBitmapEncoder --
        kein System.Drawing.Bitmap-Roundtrip noetig. Mit Retry-Loop fuer
        den Fall, dass eine andere App das Clipboard gerade haelt.

        Der Zielpfad muss vorher bereits eindeutig sein (Resolve-UniqueFilename);
        FileMode.CreateNew schlaegt fehl wenn die Datei existiert.
    .OUTPUTS
        hashtable @{ Success, Status, Message, Path, Width, Height, Attempts }
        Status-Werte: OK | NotSta | NoImage | ClipboardLocked | SaveFailed
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$MaxAttempts = 5,
        [int]$InitialDelayMs = 50
    )

    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        return @{
            Success  = $false
            Status   = 'NotSta'
            Message  = 'Clipboard.GetImage erfordert STA-Apartment.'
            Path     = $null
            Width    = 0
            Height   = 0
            Attempts = 0
        }
    }

    # ContainsImage ist non-throwing, GetImage kann werfen wenn das
    # Clipboard gerade von einer anderen App gehalten wird.
    $src = $null
    $attempts = 0
    $delay = $InitialDelayMs
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        $attempts = $i
        try {
            if (-not [System.Windows.Clipboard]::ContainsImage()) {
                return @{
                    Success  = $false
                    Status   = 'NoImage'
                    Message  = 'Kein Bild in der Zwischenablage.'
                    Path     = $null
                    Width    = 0
                    Height   = 0
                    Attempts = $i
                }
            }
            $src = [System.Windows.Clipboard]::GetImage()
            if ($null -eq $src) {
                return @{
                    Success  = $false
                    Status   = 'NoImage'
                    Message  = 'Clipboard.GetImage() lieferte null.'
                    Path     = $null
                    Width    = 0
                    Height   = 0
                    Attempts = $i
                }
            }
            break
        } catch {
            if ($i -ge $MaxAttempts) {
                return @{
                    Success  = $false
                    Status   = 'ClipboardLocked'
                    Message  = "Clipboard nach $i Versuchen nicht lesbar: $($_.Exception.Message)"
                    Path     = $null
                    Width    = 0
                    Height   = 0
                    Attempts = $i
                }
            }
            Start-Sleep -Milliseconds $delay
            $delay = [int][Math]::Min($delay * 2, 2000)
        }
    }

    try {
        if (-not $src.IsFrozen) { $src.Freeze() }
        $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $frame = [System.Windows.Media.Imaging.BitmapFrame]::Create($src)
        $encoder.Frames.Add($frame) | Out-Null

        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew)
        try {
            $encoder.Save($stream)
        } finally {
            $stream.Dispose()
        }

        return @{
            Success  = $true
            Status   = 'OK'
            Message  = "Gespeichert: $Path"
            Path     = $Path
            Width    = $src.PixelWidth
            Height   = $src.PixelHeight
            Attempts = $attempts
        }
    } catch {
        return @{
            Success  = $false
            Status   = 'SaveFailed'
            Message  = "Speichern fehlgeschlagen: $($_.Exception.Message)"
            Path     = $null
            Width    = 0
            Height   = 0
            Attempts = $attempts
        }
    }
}

Export-ModuleMember -Function Convert-BitmapToBitmapSource, Set-ClipboardImage, Save-ClipboardImageAsPng
