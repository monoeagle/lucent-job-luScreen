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
        [scriptblock]$Action
    )
    $item = New-Object System.Windows.Forms.ToolStripMenuItem $Text
    if ($Action) {
        $item.add_Click($Action)
    } else {
        $item.Enabled = $false
    }
    return $item
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
        [Parameter(Mandatory)][hashtable]$Callbacks
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
    $tray.Icon = New-Object System.Drawing.Icon $Icon
    $tray.Visible = $true
    $tray.Text = "LucentScreen $Version"

    $menu = New-Object System.Windows.Forms.ContextMenuStrip

    $items = @(
        @{ Text = 'Bereich aufnehmen'; Key = 'Region' },
        @{ Text = 'Aktives Fenster aufnehmen'; Key = 'ActiveWindow' },
        @{ Text = 'Monitor (Maus)'; Key = 'Monitor' },
        @{ Text = 'Alle Monitore'; Key = 'AllMonitors' },
        @{ Separator = $true },
        @{ Text = 'Verlauf oeffnen'; Key = 'History' },
        @{ Text = 'Konfiguration...'; Key = 'Config' },
        @{ Text = 'Ueber...'; Key = 'About' },
        @{ Separator = $true },
        @{ Text = 'Beenden'; Key = 'Exit' }
    )

    foreach ($entry in $items) {
        if ($entry.ContainsKey('Separator')) {
            [void]$menu.Items.Add((_New-Separator))
            continue
        }
        $cb = if ($Callbacks.ContainsKey($entry.Key)) { $Callbacks[$entry.Key] } else { $null }
        [void]$menu.Items.Add((_New-MenuItem -Text $entry.Text -Action $cb))
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
