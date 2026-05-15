#Requires -Version 5.1
Set-StrictMode -Version Latest

# ---------------------------------------------------------------
#  Globale Hotkeys
#
#  Architektur:
#    - LucentScreen.HotKey: P/Invoke-Wrapper (Add-Type) fuer
#      RegisterHotKey / UnregisterHotKey + Modifier-Konstanten.
#    - $script:HotkeyState: ID-Map { id -> Name } und Callback-Map.
#    - WM_HOTKEY-Dispatch erfolgt extern (LucentScreen.ps1 setzt
#      einen HwndSource-Hook und ruft Invoke-HotkeyById).
#
#  API:
#    Convert-ModifiersToFlags @('Control','Shift') -> 6
#    Convert-KeyNameToVirtualKey 'D1'              -> 49
#    Register-AllHotkeys -Hwnd $h -HotkeyMap $cfg.Hotkeys -Callbacks $cb
#      -> @{ Registered=@(...); Conflicts=@(...) }
#    Unregister-AllHotkeys -Hwnd $h
#    Invoke-HotkeyById -Id <int>     (vom WM_HOTKEY-Hook aufgerufen)
# ---------------------------------------------------------------

if (-not ('LucentScreen.HotKey' -as [Type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace LucentScreen {
    public static class HotKey {
        public const int MOD_ALT     = 0x1;
        public const int MOD_CONTROL = 0x2;
        public const int MOD_SHIFT   = 0x4;
        public const int MOD_WIN     = 0x8;
        public const int WM_HOTKEY   = 0x312;

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    }
}
'@
}

# State
$script:HotkeyState = @{
    NextId     = 1
    Registered = @{}    # id -> @{ Name; Callback; Modifiers; Key; Display }
}

# ---------------------------------------------------------------
#  Konvertierungs-Helfer
# ---------------------------------------------------------------

$script:ModifierFlag = @{
    'control' = [LucentScreen.HotKey]::MOD_CONTROL
    'ctrl'    = [LucentScreen.HotKey]::MOD_CONTROL
    'shift'   = [LucentScreen.HotKey]::MOD_SHIFT
    'alt'     = [LucentScreen.HotKey]::MOD_ALT
    'win'     = [LucentScreen.HotKey]::MOD_WIN
    'windows' = [LucentScreen.HotKey]::MOD_WIN
}

function Convert-ModifiersToFlags {
    [CmdletBinding()]
    [OutputType([uint32])]
    param([AllowEmptyCollection()][string[]]$Modifiers = @())
    $flags = 0
    foreach ($m in $Modifiers) {
        if (-not $m) { continue }
        $key = $m.ToLowerInvariant()
        if ($script:ModifierFlag.ContainsKey($key)) {
            $flags = $flags -bor $script:ModifierFlag[$key]
        }
    }
    return [uint32]$flags
}

function Convert-KeyNameToVirtualKey {
    <#
    .SYNOPSIS
        WPF-Key-Name (z.B. 'D1', 'F4', 'A') -> Win32 Virtual-Key-Code.
    .DESCRIPTION
        Nutzt System.Windows.Input.Key + KeyInterop.VirtualKeyFromKey.
        Liefert 0 bei unbekanntem Namen.
    #>
    [CmdletBinding()]
    [OutputType([uint32])]
    param([Parameter(Mandatory)][string]$KeyName)

    Add-Type -AssemblyName WindowsBase | Out-Null

    $wpfKey = $null
    try {
        $wpfKey = [Enum]::Parse([System.Windows.Input.Key], $KeyName, $true)
    } catch {
        return [uint32]0
    }
    return [uint32][System.Windows.Input.KeyInterop]::VirtualKeyFromKey($wpfKey)
}

# ---------------------------------------------------------------
#  Registrierung
# ---------------------------------------------------------------

function Register-AllHotkeys {
    <#
    .SYNOPSIS
        (Re-)Registriert alle Hotkeys aus einer Config-Map.
    .DESCRIPTION
        Entfernt zuvor registrierte Hotkeys, registriert dann jeden Eintrag
        in $HotkeyMap. Pro Eintrag: berechnet eine ID aus $script:HotkeyState.NextId,
        ruft RegisterHotKey. Bei Erfolg landet der Callback in der Registry,
        sonst in Conflicts.
    .OUTPUTS
        hashtable mit:
          Registered = Liste @{ Id; Name; Display }
          Conflicts  = Liste @{ Name; Display; Win32Error }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)][hashtable]$HotkeyMap,
        [Parameter(Mandatory)][hashtable]$Callbacks
    )

    # Alte Registrierungen freigeben
    Unregister-AllHotkeys -Hwnd $Hwnd

    $registered = New-Object System.Collections.Generic.List[hashtable]
    $conflicts = New-Object System.Collections.Generic.List[hashtable]

    foreach ($name in @($HotkeyMap.Keys)) {
        $hk = $HotkeyMap[$name]
        if (-not ($hk -is [hashtable]) -or -not $hk.Key) { continue }

        $mods = Convert-ModifiersToFlags -Modifiers @($hk.Modifiers)
        $vk = Convert-KeyNameToVirtualKey -KeyName $hk.Key
        if ($vk -eq 0) {
            $conflicts.Add(@{
                    Name       = $name
                    Display    = (Format-Hotkey $hk)
                    Win32Error = 0
                    Reason     = "Unbekannte Taste: $($hk.Key)"
                })
            continue
        }

        $id = $script:HotkeyState.NextId
        $script:HotkeyState.NextId++

        $ok = [LucentScreen.HotKey]::RegisterHotKey($Hwnd, $id, $mods, $vk)
        if ($ok) {
            $cb = if ($Callbacks.ContainsKey($name)) { $Callbacks[$name] } else { $null }
            $script:HotkeyState.Registered[$id] = @{
                Name      = $name
                Callback  = $cb
                Modifiers = @($hk.Modifiers)
                Key       = $hk.Key
                Display   = (Format-Hotkey $hk)
                Hwnd      = $Hwnd
            }
            $registered.Add(@{ Id = $id; Name = $name; Display = (Format-Hotkey $hk) })
        } else {
            $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            $conflicts.Add(@{
                    Name       = $name
                    Display    = (Format-Hotkey $hk)
                    Win32Error = $err
                    Reason     = "RegisterHotKey fehlgeschlagen (Win32 $err) -- vermutlich von anderer Anwendung belegt"
                })
        }
    }

    return @{
        Registered = @($registered)
        Conflicts  = @($conflicts)
    }
}

function Unregister-AllHotkeys {
    [CmdletBinding()]
    param([Parameter(Mandatory)][IntPtr]$Hwnd)

    foreach ($id in @($script:HotkeyState.Registered.Keys)) {
        try {
            [void][LucentScreen.HotKey]::UnregisterHotKey($Hwnd, [int]$id)
        } catch {
            $null = $_
        }
    }
    $script:HotkeyState.Registered = @{}
}

function Invoke-HotkeyById {
    <#
    .SYNOPSIS
        Wird vom WM_HOTKEY-Hook aufgerufen, fuehrt den Callback aus.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$Id)

    if (-not $script:HotkeyState.Registered.ContainsKey($Id)) { return }
    $entry = $script:HotkeyState.Registered[$Id]
    if (-not $entry.Callback) { return }
    try {
        $entry.Callback.Invoke()
    } catch {
        # Hotkey-Callback darf die App nicht killen
        Write-Warning ("Hotkey-Callback '{0}' fehlgeschlagen: {1}" -f $entry.Name, $_.Exception.Message)
    }
}

function Get-RegisteredHotkeys {
    <#
    .SYNOPSIS
        Diagnostik: gibt die aktuell registrierten Hotkeys zurueck.
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param()
    $out = @()
    foreach ($id in @($script:HotkeyState.Registered.Keys)) {
        $e = $script:HotkeyState.Registered[$id]
        $out += @{ Id = $id; Name = $e.Name; Display = $e.Display }
    }
    return , $out
}

Export-ModuleMember -Function Convert-ModifiersToFlags, Convert-KeyNameToVirtualKey, Register-AllHotkeys, Unregister-AllHotkeys, Invoke-HotkeyById, Get-RegisteredHotkeys
