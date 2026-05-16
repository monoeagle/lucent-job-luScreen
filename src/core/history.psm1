#Requires -Version 5.1
Set-StrictMode -Version Latest

# ---------------------------------------------------------------
#  Verlaufs-Backend
#
#  Reine Datei-/IO-Schicht. Liefert Listen-Metadaten und kapselt
#  Dateioperationen (Oeffnen, Im Ordner zeigen, Loeschen,
#  In Zwischenablage kopieren). KEINE WPF-Abhaengigkeit -- die UI
#  lebt in src/ui/history-window.psm1.
#
#  API:
#    Format-FileSize -Bytes <long>             -> "234 KB"
#    Get-HistoryFiles -Path <dir> [-Filter '*.png']
#                                              -> FileInfo[] (sortiert, neueste zuerst)
#    Get-HistoryItems -Path <dir> [-Filter '*.png']
#                                              -> hashtable[] (FullName/FileName/Size/...)
#    New-HistoryItem -File <FileInfo>          -> hashtable
#    Open-HistoryFile -Path <file>             -> Result-Hashtable
#    Show-HistoryInFolder -Path <file>         -> Result-Hashtable
#    Remove-HistoryItem -Path <file> [-Permanent]
#                                              -> Result-Hashtable
#    Copy-HistoryFileToClipboard -Path <file>  -> Result-Hashtable
#    Rename-HistoryItem -Path <file> -NewName <name> [-KeepExtension]
#                                              -> Result-Hashtable @{ ...; Path = neuerPfad }
#
#  Voraussetzungen:
#    System.Drawing geladen (fuer Copy-HistoryFileToClipboard).
#    core/clipboard.psm1 geladen (Set-ClipboardImage).
# ---------------------------------------------------------------

function Format-FileSize {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][long]$Bytes)

    if ($Bytes -lt 1024) { return "$Bytes B" }
    $kb = $Bytes / 1024.0
    if ($kb -lt 1024) { return ("{0:N0} KB" -f $kb) }
    $mb = $kb / 1024.0
    if ($mb -lt 1024) { return ("{0:N1} MB" -f $mb) }
    $gb = $mb / 1024.0
    return ("{0:N2} GB" -f $gb)
}

function New-HistoryItem {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)

    return @{
        FullName      = $File.FullName
        FileName      = $File.Name
        Size          = [long]$File.Length
        SizeDisplay   = (Format-FileSize -Bytes $File.Length)
        LastWriteTime = $File.LastWriteTime
        TimeDisplay   = $File.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
        IsReadOnly    = [bool]$File.IsReadOnly
    }
}

function Get-HistoryFiles {
    <#
    .SYNOPSIS
        Liest die PNG-Dateien aus dem Zielordner. Neueste zuerst.
    .DESCRIPTION
        Filtert per Wildcard, gibt ein Array von FileInfo zurueck.
        Wenn der Ordner nicht existiert -> leeres Array (kein Fehler).
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Filter = '*.png'
    )

    if (-not (Test-Path -LiteralPath $Path)) { return , @() }
    try {
        $files = Get-ChildItem -LiteralPath $Path -Filter $Filter -File -ErrorAction Stop |
            Sort-Object -Property LastWriteTime -Descending
    } catch {
        return , @()
    }
    return , @($files)
}

function Get-HistoryItems {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Filter = '*.png'
    )

    $files = Get-HistoryFiles -Path $Path -Filter $Filter
    $items = @()
    foreach ($f in $files) { $items += , (New-HistoryItem -File $f) }
    return , $items
}

function Open-HistoryFile {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return @{ Success = $false; Status = 'NotFound'; Message = "Datei nicht gefunden: $Path"; Path = $Path }
    }
    try {
        Start-Process -FilePath $Path -ErrorAction Stop | Out-Null
        return @{ Success = $true; Status = 'OK'; Message = "Geoeffnet: $Path"; Path = $Path }
    } catch {
        return @{ Success = $false; Status = 'OpenFailed'; Message = $_.Exception.Message; Path = $Path }
    }
}

function Show-HistoryInFolder {
    <#
    .SYNOPSIS
        Oeffnet den Datei-Explorer mit der angegebenen Datei markiert.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return @{ Success = $false; Status = 'NotFound'; Message = "Datei nicht gefunden: $Path"; Path = $Path }
    }
    try {
        $arg = "/select,`"$Path`""
        Start-Process -FilePath 'explorer.exe' -ArgumentList $arg -ErrorAction Stop | Out-Null
        return @{ Success = $true; Status = 'OK'; Message = "Im Ordner gezeigt"; Path = $Path }
    } catch {
        return @{ Success = $false; Status = 'ExplorerFailed'; Message = $_.Exception.Message; Path = $Path }
    }
}

function Remove-HistoryItem {
    <#
    .SYNOPSIS
        Loescht eine Verlaufsdatei. Default: in den Papierkorb.
    .PARAMETER Permanent
        Wenn gesetzt -> Remove-Item -Force (kein Recycle-Bin).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Permanent
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @{ Success = $false; Status = 'NotFound'; Message = "Datei nicht gefunden: $Path"; Path = $Path }
    }

    if ($Permanent) {
        try {
            Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
            return @{ Success = $true; Status = 'OK'; Message = "Endgueltig geloescht"; Path = $Path }
        } catch {
            return @{ Success = $false; Status = 'DeleteFailed'; Message = $_.Exception.Message; Path = $Path }
        }
    }

    # Papierkorb via Microsoft.VisualBasic.FileIO -- in .NET Framework 4.x
    # ohne Zusatz-Install vorhanden, in PS 5.1 nicht standardmaessig
    # geladen, deshalb explizit nachladen.
    try {
        Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
            $Path,
            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
        return @{ Success = $true; Status = 'OK'; Message = "In Papierkorb verschoben"; Path = $Path }
    } catch {
        return @{ Success = $false; Status = 'DeleteFailed'; Message = $_.Exception.Message; Path = $Path }
    }
}

function Copy-HistoryFileToClipboard {
    <#
    .SYNOPSIS
        Laedt eine Bilddatei und legt sie als Bild in die Zwischenablage.
    .DESCRIPTION
        Nutzt Set-ClipboardImage aus core/clipboard.psm1 (STA-Pflicht).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return @{ Success = $false; Status = 'NotFound'; Message = "Datei nicht gefunden: $Path"; Path = $Path }
    }

    $bmp = $null
    try {
        # Bitmap.FromFile haelt den File-Lock, also lieber via Stream laden
        # und sofort schliessen.
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $ms = New-Object System.IO.MemoryStream (, $bytes)
        try {
            $bmp = [System.Drawing.Image]::FromStream($ms)
        } finally {
            $ms.Dispose()
        }
        if ($bmp -isnot [System.Drawing.Bitmap]) {
            # Image.FromStream liefert je nach Format Bitmap oder Metafile.
            # Wir brauchen explizit ein Bitmap -- konvertieren.
            $tmp = New-Object System.Drawing.Bitmap $bmp
            $bmp.Dispose()
            $bmp = $tmp
        }
        $clip = Set-ClipboardImage -Bitmap $bmp
        return $clip
    } catch {
        return @{ Success = $false; Status = 'LoadFailed'; Message = $_.Exception.Message; Path = $Path; Attempts = 0 }
    } finally {
        if ($bmp) { $bmp.Dispose() }
    }
}

function Rename-HistoryItem {
    <#
    .SYNOPSIS
        Benennt eine Verlaufsdatei im selben Ordner um.
    .PARAMETER NewName
        Neuer Datei-Name (ohne Ordner-Pfad). Wenn -KeepExtension, wird die
        Original-Extension automatisch angehaengt -- sonst nimmt der Caller
        die Extension selbst mit (z.B. "screenshot.png").
    .OUTPUTS
        hashtable @{ Success; Status; Message; Path; OldPath }
        Status-Werte: OK | NotFound | InvalidName | TargetExists | RenameFailed
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$NewName,
        [switch]$KeepExtension
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @{ Success = $false; Status = 'NotFound'; Message = "Datei nicht gefunden: $Path"; Path = $null; OldPath = $Path }
    }

    $trimmed = $NewName.Trim()
    if ([string]::IsNullOrEmpty($trimmed)) {
        return @{ Success = $false; Status = 'InvalidName'; Message = 'Neuer Name darf nicht leer sein.'; Path = $null; OldPath = $Path }
    }

    # Verbotene Zeichen via System.IO.Path.GetInvalidFileNameChars
    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($ch in $invalid) {
        if ($trimmed.Contains($ch)) {
            return @{
                Success = $false; Status = 'InvalidName'
                Message = "Ungueltiges Zeichen im Dateinamen: '$ch'"
                Path = $null; OldPath = $Path
            }
        }
    }

    if ($KeepExtension) {
        $origExt = [System.IO.Path]::GetExtension($Path)
        $newExt = [System.IO.Path]::GetExtension($trimmed)
        if ([string]::IsNullOrEmpty($newExt)) {
            $trimmed = $trimmed + $origExt
        }
    }

    $dir = Split-Path -Parent $Path
    $newPath = Join-Path $dir $trimmed

    if ([System.IO.Path]::GetFullPath($newPath) -eq [System.IO.Path]::GetFullPath($Path)) {
        return @{ Success = $false; Status = 'InvalidName'; Message = 'Neuer Name ist identisch mit dem alten.'; Path = $null; OldPath = $Path }
    }

    if (Test-Path -LiteralPath $newPath) {
        return @{
            Success = $false; Status = 'TargetExists'
            Message = "Eine Datei mit dem Namen '$trimmed' existiert bereits."
            Path = $null; OldPath = $Path
        }
    }

    try {
        Move-Item -LiteralPath $Path -Destination $newPath -ErrorAction Stop
        return @{
            Success = $true; Status = 'OK'
            Message = "Umbenannt: $trimmed"
            Path = $newPath; OldPath = $Path
        }
    } catch {
        return @{
            Success = $false; Status = 'RenameFailed'
            Message = "Umbenennen fehlgeschlagen: $($_.Exception.Message)"
            Path = $null; OldPath = $Path
        }
    }
}

Export-ModuleMember -Function Format-FileSize, New-HistoryItem, Get-HistoryFiles, Get-HistoryItems, Open-HistoryFile, Show-HistoryInFolder, Remove-HistoryItem, Copy-HistoryFileToClipboard, Rename-HistoryItem
