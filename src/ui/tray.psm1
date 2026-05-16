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
    #>
    param([Parameter(Mandatory)][string]$Path)
    Add-Type -AssemblyName System.Drawing | Out-Null
    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
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
        [hashtable]$HotkeyMap
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
    $tray.Icon = _New-TrayIcon -Path $Icon
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
