#Requires -Version 7.0
Set-StrictMode -Version Latest

# ---------------------------------------------------------------
#  LucentScreen.Native -- P/Invoke fuer Win32-Aufrufe.
#  Erweitert sich mit jedem AP; Stand AP 0: nur DPI-Awareness.
# ---------------------------------------------------------------

if (-not ('LucentScreen.Native' -as [Type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace LucentScreen {
    public static class Native {
        // DPI-Awareness-Kontexte (siehe SetProcessDpiAwarenessContext)
        public static readonly IntPtr DPI_AWARENESS_CONTEXT_UNAWARE             = new IntPtr(-1);
        public static readonly IntPtr DPI_AWARENESS_CONTEXT_SYSTEM_AWARE        = new IntPtr(-2);
        public static readonly IntPtr DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE   = new IntPtr(-3);
        public static readonly IntPtr DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = new IntPtr(-4);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool SetProcessDpiAwarenessContext(IntPtr dpiContext);

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
            public int Width  { get { return Right  - Left; } }
            public int Height { get { return Bottom - Top;  } }
        }
    }
}
'@
}

function Set-DpiAwareness {
    <#
    .SYNOPSIS
        Aktiviert PER_MONITOR_AWARE_V2 fuer den aktuellen Prozess.
    .DESCRIPTION
        Muss VOR der ersten UI-Instanziierung aufgerufen werden, sonst werden
        DPI-Skalierungen falsch angewandt und Screenshots schneiden falsch.
        Liefert ein Result-Hashtable zurueck.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    try {
        $ok = [LucentScreen.Native]::SetProcessDpiAwarenessContext(
            [LucentScreen.Native]::DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)
        if ($ok) {
            return @{ Success = $true; Status = 'OK'; Message = 'PER_MONITOR_AWARE_V2 aktiv' }
        }
        # Bereits gesetzt (z.B. via Manifest) -> kein Fehler
        $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        return @{
            Success = $true
            Status  = 'AlreadySet'
            Message = "DPI-Kontext schon gesetzt (Win32-Code $err)"
        }
    } catch {
        return @{
            Success = $false
            Status  = 'Error'
            Message = "DPI-Setup fehlgeschlagen: $($_.Exception.Message)"
        }
    }
}

Export-ModuleMember -Function Set-DpiAwareness
