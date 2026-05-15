#Requires -Version 5.1
Set-StrictMode -Version Latest

# ---------------------------------------------------------------
#  LucentScreen Konfig-Dialog
#
#  API:
#    Show-ConfigDialog -Config <hashtable> [-Owner <Window>]
#      -> $null bei Abbruch, sonst die gespeicherte (validierte) Config
#         als neues Hashtable.
#
#  Voraussetzungen:
#    - STA-Apartment
#    - WPF-Assemblies geladen (PresentationFramework, PresentationCore,
#      WindowsBase, System.Xaml)
#    - System.Windows.Forms fuer FolderBrowserDialog
#    - core/config.psm1 fuer Test-ConfigValid, Format-Hotkey, ...
#    - core/xaml-loader.psm1 fuer Load-Xaml / Get-XamlControls
# ---------------------------------------------------------------

# WPF-Keys, die wir als reine Modifier behandeln (kein "Key" allein)
$script:ModifierOnlyKeys = @(
    'LeftCtrl', 'RightCtrl', 'LeftShift', 'RightShift',
    'LeftAlt', 'RightAlt', 'LWin', 'RWin',
    'System', 'CapsLock', 'NumLock', 'Scroll'
)

function _Get-CurrentModifiers {
    $mods = @()
    $kbd = [System.Windows.Input.Keyboard]
    if ($kbd::IsKeyDown([System.Windows.Input.Key]::LeftCtrl) -or $kbd::IsKeyDown([System.Windows.Input.Key]::RightCtrl)) { $mods += 'Control' }
    if ($kbd::IsKeyDown([System.Windows.Input.Key]::LeftShift) -or $kbd::IsKeyDown([System.Windows.Input.Key]::RightShift)) { $mods += 'Shift' }
    if ($kbd::IsKeyDown([System.Windows.Input.Key]::LeftAlt) -or $kbd::IsKeyDown([System.Windows.Input.Key]::RightAlt)) { $mods += 'Alt' }
    if ($kbd::IsKeyDown([System.Windows.Input.Key]::LWin) -or $kbd::IsKeyDown([System.Windows.Input.Key]::RWin)) { $mods += 'Win' }
    return , $mods
}

function _Update-HotkeyTextBox {
    param(
        [System.Windows.Controls.TextBox]$Box,
        [hashtable]$Hotkey
    )
    if ($null -eq $Hotkey -or -not $Hotkey.Key) {
        $Box.Text = '(kein Hotkey)'
        $Box.Tag = $null
        return
    }
    $Box.Text = Format-Hotkey -Hotkey $Hotkey
    $Box.Tag = $Hotkey
}

function _Read-HotkeyFromBox {
    param([System.Windows.Controls.TextBox]$Box)
    if ($Box.Tag -is [hashtable]) { return $Box.Tag }
    return $null
}

function _Pick-Folder {
    param([string]$Initial)
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Zielordner fuer Screenshots waehlen'
    $dlg.ShowNewFolderButton = $true
    if ($Initial -and (Test-Path -LiteralPath $Initial)) {
        $dlg.SelectedPath = $Initial
    }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dlg.SelectedPath
    }
    return $null
}

function _Wire-HotkeyCapture {
    param(
        [System.Windows.Controls.TextBox]$Box,
        [System.Windows.Controls.Button]$ClearButton
    )
    # KeyDown: Tastenkombi einfangen, in $Box.Tag schreiben
    $Box.Add_PreviewKeyDown({
            param($s, $e)
            $e.Handled = $true
            $k = if ($e.Key -eq [System.Windows.Input.Key]::System) { $e.SystemKey } else { $e.Key }
            $keyName = $k.ToString()

            # ESC -> nichts tun (Cancel)
            if ($keyName -eq 'Escape') { return }

            # Reine Modifier-Tasten ignorieren -- wir warten auf eine echte Taste
            if ($script:ModifierOnlyKeys -contains $keyName) { return }

            $mods = _Get-CurrentModifiers
            $newHk = @{ Modifiers = @($mods); Key = $keyName }
            _Update-HotkeyTextBox -Box $s -Hotkey $newHk
        })

    $ClearButton.Add_Click({
            _Update-HotkeyTextBox -Box $Box -Hotkey $null
        }.GetNewClosure())
}

function _Set-Validation {
    param(
        [System.Windows.Controls.Border]$Box,
        [System.Windows.Controls.TextBlock]$Text,
        [string[]]$Messages
    )
    if (-not $Messages -or $Messages.Count -eq 0) {
        $Box.Visibility = [System.Windows.Visibility]::Collapsed
        $Text.Text = ''
        return
    }
    $Text.Text = ($Messages -join "`n")
    $Box.Visibility = [System.Windows.Visibility]::Visible
}

function _Build-ConfigFromDialog {
    param(
        [hashtable]$Base,
        [hashtable]$Controls
    )
    # Tiefe Kopie ueber JSON, damit Original-Config unangetastet bleibt
    $jsonClone = $Base | ConvertTo-Json -Depth 10
    # Hier verwenden wir Read-Config NICHT, sondern eigene Konvertierung,
    # damit Defaults nicht erneut gemerged werden. Stattdessen via Helper:
    $cfg = $jsonClone | ConvertFrom-Json
    $h = @{}
    foreach ($p in $cfg.PSObject.Properties) {
        if ($p.Value -is [System.Management.Automation.PSCustomObject]) {
            $sub = @{}
            foreach ($pp in $p.Value.PSObject.Properties) {
                $sub[$pp.Name] = $pp.Value
            }
            $h[$p.Name] = $sub
        } else {
            $h[$p.Name] = $p.Value
        }
    }

    $h.OutputDir = $Controls.TxtOutputDir.Text.Trim()
    $h.FileNameFormat = $Controls.TxtFileNameFormat.Text.Trim()
    $h.EditPostfix = $Controls.TxtEditPostfix.Text
    # Slider liefert Double -> int casten
    $delayDbl = [double]$Controls.SldDelay.Value
    $h.DelaySeconds = [int]$delayDbl

    $h.Hotkeys = @{
        Region       = (_Read-HotkeyFromBox $Controls.HkRegion)
        ActiveWindow = (_Read-HotkeyFromBox $Controls.HkActiveWindow)
        Monitor      = (_Read-HotkeyFromBox $Controls.HkMonitor)
        AllMonitors  = (_Read-HotkeyFromBox $Controls.HkAllMonitors)
        TrayMenu     = (_Read-HotkeyFromBox $Controls.HkTrayMenu)
    }
    # Hotkeys mit $null entfernen (Test-HotkeyConflict erwartet hashtable)
    $cleanHk = @{}
    foreach ($k in $h.Hotkeys.Keys) {
        if ($h.Hotkeys[$k] -is [hashtable]) { $cleanHk[$k] = $h.Hotkeys[$k] }
    }
    $h.Hotkeys = $cleanHk

    return $h
}

function Show-ConfigDialog {
    <#
    .SYNOPSIS
        Oeffnet den modalen Konfig-Dialog.
    .OUTPUTS
        $null bei Abbruch; bei Speichern die neue, validierte Config-Hashtable.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [System.Windows.Window]$Owner
    )

    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        throw 'Show-ConfigDialog benoetigt ein STA-Apartment.'
    }

    $xamlPath = Join-Path $PSScriptRoot '..\views\config-dialog.xaml'
    $win = Load-Xaml -Path $xamlPath
    if ($Owner) { $win.Owner = $Owner }

    $names = @(
        'TxtOutputDir', 'BtnBrowse', 'TxtFileNameFormat', 'TxtEditPostfix',
        'SldDelay', 'TxtDelay',
        'HkRegion', 'HkRegionClear',
        'HkActiveWindow', 'HkActiveWindowClear',
        'HkMonitor', 'HkMonitorClear',
        'HkAllMonitors', 'HkAllMonitorsClear',
        'HkTrayMenu', 'HkTrayMenuClear',
        'BtnSave', 'BtnCancel',
        'ValidationBox', 'ValidationText'
    )
    $c = Get-XamlControls -Root $win -Names $names

    # --- Initial-Werte einsetzen ---
    $c.TxtOutputDir.Text = [string]$Config.OutputDir
    $c.TxtFileNameFormat.Text = [string]$Config.FileNameFormat
    $c.TxtEditPostfix.Text = [string]$Config.EditPostfix
    $c.SldDelay.Value = [double]([int]$Config.DelaySeconds)
    $c.TxtDelay.Text = [string]([int]$Config.DelaySeconds)

    # Slider <-> TextBox koppeln
    $c.SldDelay.Add_ValueChanged({
            param($s, $e)
            $c.TxtDelay.Text = [string]([int]$s.Value)
        }.GetNewClosure())
    $c.TxtDelay.Add_LostFocus({
            param($s, $e)
            $v = 0
            if ([int]::TryParse($s.Text, [ref]$v)) {
                if ($v -lt 0) { $v = 0 }
                if ($v -gt 30) { $v = 30 }
                $c.SldDelay.Value = $v
                $s.Text = [string]$v
            } else {
                $s.Text = [string]([int]$c.SldDelay.Value)
            }
        }.GetNewClosure())

    # Hotkey-Felder bestuecken
    $hkPairs = @(
        @{ Box = $c.HkRegion; Clear = $c.HkRegionClear; Key = 'Region' },
        @{ Box = $c.HkActiveWindow; Clear = $c.HkActiveWindowClear; Key = 'ActiveWindow' },
        @{ Box = $c.HkMonitor; Clear = $c.HkMonitorClear; Key = 'Monitor' },
        @{ Box = $c.HkAllMonitors; Clear = $c.HkAllMonitorsClear; Key = 'AllMonitors' },
        @{ Box = $c.HkTrayMenu; Clear = $c.HkTrayMenuClear; Key = 'TrayMenu' }
    )
    foreach ($p in $hkPairs) {
        $hk = $null
        if ($Config.Hotkeys -is [hashtable] -and $Config.Hotkeys.ContainsKey($p.Key)) {
            $hk = $Config.Hotkeys[$p.Key]
        }
        _Update-HotkeyTextBox -Box $p.Box -Hotkey $hk
        _Wire-HotkeyCapture -Box $p.Box -ClearButton $p.Clear
    }

    # Browse
    $c.BtnBrowse.Add_Click({
            param($s, $e)
            $picked = _Pick-Folder -Initial $c.TxtOutputDir.Text
            if ($picked) { $c.TxtOutputDir.Text = $picked }
        }.GetNewClosure())

    # Speichern -> validieren -> bei OK DialogResult=true, Close
    $script:DialogResult = $null
    $c.BtnSave.Add_Click({
            param($s, $e)
            $candidate = _Build-ConfigFromDialog -Base $Config -Controls $c
            $val = Test-ConfigValid -Config $candidate
            if ($val.IsValid) {
                $script:DialogResult = $candidate
                $win.DialogResult = $true
                $win.Close()
            } else {
                _Set-Validation -Box $c.ValidationBox -Text $c.ValidationText -Messages $val.Errors
            }
        }.GetNewClosure())

    $c.BtnCancel.Add_Click({
            param($s, $e)
            $script:DialogResult = $null
            $win.DialogResult = $false
            $win.Close()
        }.GetNewClosure())

    [void]$win.ShowDialog()
    return $script:DialogResult
}

Export-ModuleMember -Function Show-ConfigDialog
