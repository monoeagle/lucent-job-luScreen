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
    $iconDbl = [double]$Controls.SldIconSize.Value
    $h.HistoryIconSize = [int]$iconDbl

    $h.Hotkeys = @{
        Region       = (_Read-HotkeyFromBox $Controls.HkRegion)
        ActiveWindow = (_Read-HotkeyFromBox $Controls.HkActiveWindow)
        Monitor      = (_Read-HotkeyFromBox $Controls.HkMonitor)
        AllMonitors  = (_Read-HotkeyFromBox $Controls.HkAllMonitors)
        TrayMenu     = (_Read-HotkeyFromBox $Controls.HkTrayMenu)
        DelayReset   = (_Read-HotkeyFromBox $Controls.HkDelayReset)
        DelayPlus5   = (_Read-HotkeyFromBox $Controls.HkDelayPlus5)
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
    Set-AppWindowIcon -Window $win
    if ($Owner) { $win.Owner = $Owner }

    $names = @(
        'TxtOutputDir', 'BtnBrowse', 'TxtFileNameFormat', 'TxtEditPostfix',
        'SldDelay', 'TxtDelay',
        'SldIconSize', 'TxtIconSize',
        'HkRegion', 'HkRegionClear',
        'HkActiveWindow', 'HkActiveWindowClear',
        'HkMonitor', 'HkMonitorClear',
        'HkAllMonitors', 'HkAllMonitorsClear',
        'HkTrayMenu', 'HkTrayMenuClear',
        'HkDelayReset', 'HkDelayResetClear',
        'HkDelayPlus5', 'HkDelayPlus5Clear',
        'HkHistoryOpen', 'HkHistoryOpenClear',
        'BtnSave', 'BtnCancel',
        'ValidationBox', 'ValidationText'
    )
    $c = Get-XamlControls -Root $win -Names $names

    # --- Helper als lokale ScriptBlocks ---
    # WICHTIG: Modul-Funktionen mit `_`-Praefix sind aus den `.GetNewClosure()`-
    # Click-Handlern NICHT mehr aufrufbar -- die Closure verliert den Module-
    # Scope (siehe wpf-powershell-gotchas.md). Daher die Helper hier lokal als
    # ScriptBlock-Variablen, dann werden sie sauber durch die Closure gecaptured.
    $readHkBox = {
        param([System.Windows.Controls.TextBox]$Box)
        if ($Box.Tag -is [hashtable]) { return $Box.Tag }
        return $null
    }.GetNewClosure()

    $setValidation = {
        param([string[]]$Messages)
        if (-not $Messages -or $Messages.Count -eq 0) {
            $c.ValidationBox.Visibility = [System.Windows.Visibility]::Collapsed
            $c.ValidationText.Text = ''
            return
        }
        $c.ValidationText.Text = ($Messages -join "`n")
        $c.ValidationBox.Visibility = [System.Windows.Visibility]::Visible
    }.GetNewClosure()

    $pickFolder = {
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
    }.GetNewClosure()

    $buildCfg = {
        # Tiefe Kopie ueber JSON, damit Original-Config unangetastet bleibt
        $jsonClone = $Config | ConvertTo-Json -Depth 10
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

        $h.OutputDir = $c.TxtOutputDir.Text.Trim()
        $h.FileNameFormat = $c.TxtFileNameFormat.Text.Trim()
        $h.EditPostfix = $c.TxtEditPostfix.Text
        $h.DelaySeconds = [int]([double]$c.SldDelay.Value)
        $h.HistoryIconSize = [int]([double]$c.SldIconSize.Value)

        $h.Hotkeys = @{
            Region       = (& $readHkBox $c.HkRegion)
            ActiveWindow = (& $readHkBox $c.HkActiveWindow)
            Monitor      = (& $readHkBox $c.HkMonitor)
            AllMonitors  = (& $readHkBox $c.HkAllMonitors)
            TrayMenu     = (& $readHkBox $c.HkTrayMenu)
            DelayReset   = (& $readHkBox $c.HkDelayReset)
            DelayPlus5   = (& $readHkBox $c.HkDelayPlus5)
            HistoryOpen  = (& $readHkBox $c.HkHistoryOpen)
        }
        # $null-Eintraege rausfiltern -- Test-HotkeyConflict erwartet hashtable
        $cleanHk = @{}
        foreach ($k in $h.Hotkeys.Keys) {
            if ($h.Hotkeys[$k] -is [hashtable]) { $cleanHk[$k] = $h.Hotkeys[$k] }
        }
        $h.Hotkeys = $cleanHk

        return $h
    }.GetNewClosure()

    # --- Initial-Werte einsetzen ---
    $c.TxtOutputDir.Text = [string]$Config.OutputDir
    $c.TxtFileNameFormat.Text = [string]$Config.FileNameFormat
    $c.TxtEditPostfix.Text = [string]$Config.EditPostfix
    $c.SldDelay.Value = [double]([int]$Config.DelaySeconds)
    $c.TxtDelay.Text = [string]([int]$Config.DelaySeconds)

    $iconInit = if ($Config.ContainsKey('HistoryIconSize')) { [int]$Config.HistoryIconSize } else { 20 }
    if ($iconInit -lt 16) { $iconInit = 16 }
    if ($iconInit -gt 32) { $iconInit = 32 }
    $c.SldIconSize.Value = [double]$iconInit
    $c.TxtIconSize.Text = [string]$iconInit

    # Slider <-> TextBox koppeln (Verzoegerung)
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

    # Slider <-> TextBox koppeln (Icon-Groesse)
    $c.SldIconSize.Add_ValueChanged({
            param($s, $e)
            $c.TxtIconSize.Text = [string]([int]$s.Value)
        }.GetNewClosure())
    $c.TxtIconSize.Add_LostFocus({
            param($s, $e)
            $v = 0
            if ([int]::TryParse($s.Text, [ref]$v)) {
                if ($v -lt 16) { $v = 16 }
                if ($v -gt 32) { $v = 32 }
                $c.SldIconSize.Value = $v
                $s.Text = [string]$v
            } else {
                $s.Text = [string]([int]$c.SldIconSize.Value)
            }
        }.GetNewClosure())

    # Hotkey-Felder bestuecken
    $hkPairs = @(
        @{ Box = $c.HkRegion; Clear = $c.HkRegionClear; Key = 'Region' },
        @{ Box = $c.HkActiveWindow; Clear = $c.HkActiveWindowClear; Key = 'ActiveWindow' },
        @{ Box = $c.HkMonitor; Clear = $c.HkMonitorClear; Key = 'Monitor' },
        @{ Box = $c.HkAllMonitors; Clear = $c.HkAllMonitorsClear; Key = 'AllMonitors' },
        @{ Box = $c.HkTrayMenu; Clear = $c.HkTrayMenuClear; Key = 'TrayMenu' },
        @{ Box = $c.HkDelayReset; Clear = $c.HkDelayResetClear; Key = 'DelayReset' },
        @{ Box = $c.HkDelayPlus5; Clear = $c.HkDelayPlus5Clear; Key = 'DelayPlus5' },
        @{ Box = $c.HkHistoryOpen; Clear = $c.HkHistoryOpenClear; Key = 'HistoryOpen' }
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
            $picked = & $pickFolder $c.TxtOutputDir.Text
            if ($picked) { $c.TxtOutputDir.Text = $picked }
        }.GetNewClosure())

    # Speichern -> validieren -> bei OK DialogResult=true, Close
    # Hashtable-Slot statt $script: -- Closures aus .GetNewClosure() verlieren
    # den Module-Scope, schrieben dann in einen anderen Scope, und Show-ConfigDialog
    # las am Ende immer $null zurueck (selbes Phaenomen wie bei Underscore-Helpern).
    $state = @{ Result = $null }
    # Write-LsLog wird modulweit ueber LucentScreen.ps1 geladen. Wenn nicht
    # verfuegbar (z.B. im Pester-Kontext), Add-Content direkt als Fallback.
    $logSrc = 'config'
    $logIt = {
        param([string]$Lvl, [string]$Msg)
        if (Get-Command Write-LsLog -ErrorAction SilentlyContinue) {
            Write-LsLog -Level $Lvl -Source $logSrc -Message $Msg
        }
    }.GetNewClosure()
    $c.BtnSave.Add_Click({
            param($s, $e)
            & $logIt 'Info' 'BtnSave clicked'
            try {
                $candidate = & $buildCfg
                & $logIt 'Debug' ('candidate built: keys=' + (($candidate.Keys | Sort-Object) -join ','))
                $val = Test-ConfigValid -Config $candidate
                & $logIt 'Debug' ('validation: IsValid={0} Errors={1}' -f $val.IsValid, $val.Errors.Count)
                if ($val.IsValid) {
                    $state.Result = $candidate
                    $win.DialogResult = $true
                    $win.Close()
                    & $logIt 'Info' 'BtnSave: dialog closed with OK'
                    return
                }
                # Validation-Fehler: Inline-Box + MessageBox (Inline-Box kann
                # ausserhalb des sichtbaren ScrollView-Bereichs liegen).
                & $logIt 'Warning' ('validation failed: ' + ($val.Errors -join ' | '))
                & $setValidation $val.Errors
                [System.Windows.MessageBox]::Show(
                    "Konfiguration ist ungültig:`n`n" + ($val.Errors -join "`n"),
                    'LucentScreen -- Konfiguration',
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning) | Out-Null
            } catch {
                & $logIt 'Error' ('BtnSave EXCEPTION: {0} | {1} | at {2}' -f $_.Exception.GetType().FullName, $_.Exception.Message, $_.InvocationInfo.PositionMessage)
                [System.Windows.MessageBox]::Show(
                    ("Speichern fehlgeschlagen:`n`n{0}`n`nQuelle: {1}" -f $_.Exception.Message, $_.InvocationInfo.PositionMessage),
                    'LucentScreen -- Konfiguration',
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error) | Out-Null
            }
        }.GetNewClosure())

    $c.BtnCancel.Add_Click({
            param($s, $e)
            $state.Result = $null
            $win.DialogResult = $false
            $win.Close()
        }.GetNewClosure())

    [void]$win.ShowDialog()
    return $state.Result
}

Export-ModuleMember -Function Show-ConfigDialog
