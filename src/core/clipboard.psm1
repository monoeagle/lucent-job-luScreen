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
#  Voraussetzungen:
#    - STA-Apartment (Clipboard.SetImage erfordert STA)
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

Export-ModuleMember -Function Convert-BitmapToBitmapSource, Set-ClipboardImage
