#Requires -Version 5.1
Set-StrictMode -Version Latest

# ---------------------------------------------------------------
#  Tray-Icon mit Kontextmenue
#
#  Verwendet System.Windows.Forms.NotifyIcon (WPF hat keinen eigenen
#  Tray-Support -- Standard-Praxis).
#
#  API:
#    Initialize-Tray -Icon <path> -Version <string> -Callbacks <hashtable>
#      Callbacks: Region, ActiveWindow, Monitor, AllMonitors,
#                 History, Config, About, Exit
#      Jeder Callback ist ein ScriptBlock; nicht-vorhandene Eintraege
#      werden disabled angezeigt.
#    -> hashtable { NotifyIcon, Menu, Dispose }
#
#  Wichtig: Initialize-Tray muss im STA-Thread aufgerufen werden,
#  und die App-Loop (Application.Run) muss laufen, damit Klicks ankommen.
# ---------------------------------------------------------------

function _New-MenuItem {
    param(
        [string]$Text,
        [scriptblock]$Action,
        [string]$ShortcutText
    )
    $item = New-Object System.Windows.Forms.ToolStripMenuItem $Text
    if ($Action) {
        $item.add_Click($Action)
    } else {
        $item.Enabled = $false
    }
    # ShortcutKeyDisplayString rendert rechtsbuendig als zweite Spalte im Menue.
    # Wir registrieren den Hotkey global via WM_HOTKEY -- nicht ueber Form-Shortcut.
    if ($ShortcutText) { $item.ShortcutKeyDisplayString = $ShortcutText }
    return $item
}

function _New-TrayIcon {
    <#
    .SYNOPSIS
        Erzeugt ein System.Drawing.Icon aus einem ICO oder PNG.
    .DESCRIPTION
        NotifyIcon.Icon nimmt nur Icon. Fuer ICO -> direktes Laden.
        Fuer PNG (alpha-faehig, hoehere Aufloesung) -> via Bitmap.GetHicon().
        Mit -Invert wird das Icon farblich invertiert (Schwarz -> Weiss),
        Alpha bleibt erhalten -- noetig fuer dunkle Taskleisten-Themes.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Invert
    )
    Add-Type -AssemblyName System.Drawing | Out-Null
    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()

    if (-not $Invert) {
        if ($ext -eq '.ico') {
            return New-Object System.Drawing.Icon $Path
        }
        # PNG / andere Bitmap -> via HICON. Der HICON-Handle bleibt fuer Lebens-
        # zeit der App gueltig; Tray-Dispose ruft Icon.Dispose, das das HICON
        # freigibt.
        $bmp = New-Object System.Drawing.Bitmap $Path
        try {
            $hicon = $bmp.GetHicon()
            return [System.Drawing.Icon]::FromHandle($hicon)
        } finally {
            $bmp.Dispose()
        }
    }

    # Invertierter Pfad: ICO/PNG nach Bitmap, ColorMatrix invertiert RGB,
    # Alpha bleibt unangetastet -- danach via GetHicon zurueck.
    $srcBmp = $null
    $dstBmp = $null
    $g = $null
    $attrs = $null
    try {
        if ($ext -eq '.ico') {
            $ico = New-Object System.Drawing.Icon $Path
            try { $srcBmp = $ico.ToBitmap() } finally { $ico.Dispose() }
        } else {
            $srcBmp = New-Object System.Drawing.Bitmap $Path
        }

        $dstBmp = New-Object System.Drawing.Bitmap $srcBmp.Width, $srcBmp.Height
        $g = [System.Drawing.Graphics]::FromImage($dstBmp)

        $cm = New-Object System.Drawing.Imaging.ColorMatrix
        $cm.Matrix00 = -1.0
        $cm.Matrix11 = -1.0
        $cm.Matrix22 = -1.0
        $cm.Matrix33 = 1.0
        $cm.Matrix44 = 1.0
        $cm.Matrix40 = 1.0
        $cm.Matrix41 = 1.0
        $cm.Matrix42 = 1.0
        $attrs = New-Object System.Drawing.Imaging.ImageAttributes
        $attrs.SetColorMatrix($cm)

        $rect = New-Object System.Drawing.Rectangle 0, 0, $srcBmp.Width, $srcBmp.Height
        $g.DrawImage($srcBmp, $rect, 0, 0, $srcBmp.Width, $srcBmp.Height,
            [System.Drawing.GraphicsUnit]::Pixel, $attrs)

        $hicon = $dstBmp.GetHicon()
        return [System.Drawing.Icon]::FromHandle($hicon)
    } finally {
        if ($attrs) { $attrs.Dispose() }
        if ($g) { $g.Dispose() }
        if ($srcBmp) { $srcBmp.Dispose() }
        if ($dstBmp) { $dstBmp.Dispose() }
    }
}

function _New-Separator {
    return New-Object System.Windows.Forms.ToolStripSeparator
}

function Initialize-Tray {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$Icon,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][hashtable]$Callbacks,
        # Optional: Hotkey-Map (Schluessel = Callback-Name, Wert = @{ Modifiers; Key }).
        # Wenn vorhanden, wird der Display-Text ('Strg+Shift+1' etc.) per
        # Format-Hotkey berechnet und als ShortcutKeyDisplayString rechts neben
        # dem Eintrag angezeigt.
        [hashtable]$HotkeyMap,
        # Tray-Icon farblich invertieren (Schwarz -> Weiss). Default an, damit
        # das Icon auf dunkler Taskleiste lesbar bleibt.
        [bool]$InvertIcon = $true
    )

    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        throw 'Initialize-Tray benoetigt ein STA-Apartment.'
    }
    if (-not (Test-Path -LiteralPath $Icon)) {
        throw "Tray-Icon nicht gefunden: $Icon"
    }

    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    Add-Type -AssemblyName System.Drawing | Out-Null

    $tray = New-Object System.Windows.Forms.NotifyIcon
    $tray.Icon = _New-TrayIcon -Path $Icon -Invert:$InvertIcon
    $tray.Visible = $true
    $tray.Text = "LucentScreen $Version"

    $menu = New-Object System.Windows.Forms.ContextMenuStrip

    $items = @(
        @{ Text = 'Bereich aufnehmen'; Key = 'Region' },
        @{ Text = 'Aktives Fenster aufnehmen'; Key = 'ActiveWindow' },
        @{ Text = 'Monitor (Maus)'; Key = 'Monitor' },
        @{ Text = 'Alle Monitore'; Key = 'AllMonitors' },
        @{ Separator = $true },
        @{ Text = 'Verzögerung Reset'; Key = 'DelayReset' },
        @{ Text = 'Verzögerung +5 Sek'; Key = 'DelayPlus5' },
        @{ Separator = $true },
        @{ Text = 'Verlauf öffnen'; Key = 'HistoryOpen' },
        @{ Separator = $true },
        @{ Text = 'Konfiguration...'; Key = 'Config' },
        @{ Text = 'Über...'; Key = 'About' },
        @{ Separator = $true },
        @{ Text = 'Beenden'; Key = 'Exit' }
    )

    $hasFormatHotkey = [bool](Get-Command Format-Hotkey -ErrorAction SilentlyContinue)
    foreach ($entry in $items) {
        if ($entry.ContainsKey('Separator')) {
            [void]$menu.Items.Add((_New-Separator))
            continue
        }
        $cb = if ($Callbacks.ContainsKey($entry.Key)) { $Callbacks[$entry.Key] } else { $null }
        $sc = $null
        if ($HotkeyMap -and $HotkeyMap.ContainsKey($entry.Key) -and $hasFormatHotkey) {
            try { $sc = Format-Hotkey $HotkeyMap[$entry.Key] } catch { $sc = $null }
        }
        [void]$menu.Items.Add((_New-MenuItem -Text $entry.Text -Action $cb -ShortcutText $sc))
    }

    $tray.ContextMenuStrip = $menu

    # Doppelklick auf Tray-Icon -> Region-Capture (haeufigste Aktion).
    # Falls kein Callback gegeben, kein Hook.
    if ($Callbacks.ContainsKey('Region')) {
        $tray.add_MouseDoubleClick({
                param($s, $e)
                if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
                    $Callbacks['Region'].Invoke()
                }
            }.GetNewClosure())
    }

    # Dispose-Closure -- wird vom Caller bei Application.Exit aufgerufen.
    $disposeAction = {
        try {
            if ($tray) {
                $tray.Visible = $false
                $tray.Dispose()
            }
            if ($menu) { $menu.Dispose() }
        } catch {
            $null = $_
        }
    }.GetNewClosure()

    return @{
        NotifyIcon = $tray
        Menu       = $menu
        Dispose    = $disposeAction
    }
}

Export-ModuleMember -Function Initialize-Tray
