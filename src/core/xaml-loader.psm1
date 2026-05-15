#Requires -Version 5.1
Set-StrictMode -Version Latest

# ---------------------------------------------------------------
#  XAML-Loader fuer LucentScreen
#
#  Hinweis: dieses Modul liegt bewusst in core/ -- Load-Xaml liefert
#  ein .NET-Objekt zurueck, die WPF-Assemblies muessen aber vom Caller
#  geladen sein (passiert in LucentScreen.ps1). Das Modul selbst hat
#  KEINE direkten WPF-Module-Imports.
#
#  Verwendung:
#      $win = Load-Xaml -Path "$PSScriptRoot/../views/config.xaml"
#      $map = Get-XamlControls -Root $win -Names 'BtnOk','TxtPath'
#      $map.BtnOk.Add_Click({ ... })
# ---------------------------------------------------------------

function Load-Xaml {
    <#
    .SYNOPSIS
        Laedt eine XAML-Datei und gibt das geparste Root-Objekt zurueck.
    .DESCRIPTION
        Liest die Datei UTF-8, validiert dass kein "x:Class" enthalten ist
        (wir haben kein Code-Behind, das Attribut wuerde XamlReader::Load
        scheitern lassen) und parsed via System.Windows.Markup.XamlReader.
    #>
    [CmdletBinding()]
    [OutputType([System.Windows.DependencyObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "XAML-Datei nicht gefunden: $Path"
    }

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8

    # Code-Behind-Hinweis vor dem Parsen entfernen (haeufiger Fehler aus
    # Designer-generierten XAMLs, wuerde sonst eine XamlParseException
    # ueber fehlende generierte Klasse werfen).
    $raw = $raw -replace 'x:Class\s*=\s*"[^"]*"', ''

    try {
        [xml]$xaml = $raw
    } catch {
        throw "XAML ist kein gueltiges XML: $Path -- $($_.Exception.Message)"
    }

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    try {
        $root = [Windows.Markup.XamlReader]::Load($reader)
    } catch {
        throw "XAML-Parse fehlgeschlagen ($Path): $($_.Exception.Message)"
    }
    return $root
}

function Get-XamlControls {
    <#
    .SYNOPSIS
        Mappt eine Liste von x:Name-Werten auf die zugehoerigen
        FrameworkElement-Instanzen.
    .DESCRIPTION
        Gibt ein Hashtable zurueck. Nicht gefundene Namen erscheinen NICHT
        im Hashtable -- der Caller pruefe via .ContainsKey().
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Windows.DependencyObject]$Root,
        [Parameter(Mandatory)]
        [string[]]$Names
    )

    $map = @{}
    foreach ($n in $Names) {
        $ctl = $Root.FindName($n)
        if ($null -ne $ctl) { $map[$n] = $ctl }
    }
    return $map
}

Export-ModuleMember -Function Load-Xaml, Get-XamlControls
