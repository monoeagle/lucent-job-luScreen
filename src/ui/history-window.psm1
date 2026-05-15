#Requires -Version 5.1
Set-StrictMode -Version Latest

# ---------------------------------------------------------------
#  Verlaufsfenster
#
#  Show-HistoryWindow -OutputDir <dir> [-Owner <Window>]
#    -> nichts (blockierender ShowDialog)
#
#  Verhalten:
#    - Listet *.png in $OutputDir (neueste zuerst)
#    - Thumbnails via BitmapImage(DecodePixelWidth=200, OnLoad, Freeze)
#      werden auf der UI in Chunks geladen, damit das Fenster sofort
#      sichtbar wird.
#    - Live-Update via DispatcherTimer-Polling (2 s) -- FileSystemWatcher
#      mit PowerShell-ScriptBlock-Handlern lief auf Worker-Threads und
#      konnte den Prozess silent killen.
#    - Tastatur: Enter/Doppelklick = Oeffnen, Strg+C = Clipboard,
#      Entf = Loeschen, F5 = Aktualisieren, Esc = Schliessen
#    - Buttons + Kontextmenue duplizieren die Aktionen
#
#  Voraussetzungen: STA, WPF + WinForms (NotifyIcon-Pfad bereits),
#  System.Drawing, core/xaml-loader.psm1, core/clipboard.psm1,
#  core/history.psm1
# ---------------------------------------------------------------

# Datenmodell mit INotifyPropertyChanged -- nur das Thumbnail
# aendert sich nachtraeglich, der Rest ist immutable nach Konstruktion.
if (-not ('LucentScreen.HistoryEntry' -as [type])) {
    Add-Type -ReferencedAssemblies PresentationCore, WindowsBase, System.Xaml -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Windows.Media.Imaging;

namespace LucentScreen {
    public class HistoryEntry : INotifyPropertyChanged {
        public string FullName { get; set; }
        public string FileName { get; set; }
        public long Size { get; set; }
        public string SizeDisplay { get; set; }
        public DateTime LastWriteTime { get; set; }
        public string TimeDisplay { get; set; }

        private BitmapSource _thumbnail;
        public BitmapSource Thumbnail {
            get { return _thumbnail; }
            set {
                if (_thumbnail != value) {
                    _thumbnail = value;
                    OnPropertyChanged("Thumbnail");
                }
            }
        }

        public event PropertyChangedEventHandler PropertyChanged;
        protected void OnPropertyChanged(string name) {
            PropertyChangedEventHandler h = PropertyChanged;
            if (h != null) h(this, new PropertyChangedEventArgs(name));
        }
    }
}
'@
}

function Show-HistoryWindow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OutputDir,
        [System.Windows.Window]$Owner,
        [string]$EditPostfix = '_edited',
        [int]$IconSize = 20    # Toolbar-Icon-Groesse, 16-32 pt (Config.HistoryIconSize)
    )

    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        throw 'Show-HistoryWindow benoetigt ein STA-Apartment.'
    }

    $xamlPath = Join-Path $PSScriptRoot '..\views\history-window.xaml'
    $win = Load-Xaml -Path $xamlPath
    Set-AppWindowIcon -Window $win
    if ($Owner) { $win.Owner = $Owner }

    # Wunschgroesse: 5 Spalten x 5 Zeilen (Item ~212x212 inkl. Margin),
    # plus Toolbar/Statusbar/Chrome. Falls Workarea kleiner -> herunterclampen.
    $cursor = [System.Windows.Forms.Cursor]::Position
    $screen = [System.Windows.Forms.Screen]::FromPoint($cursor)
    $wa = $screen.WorkingArea
    $desiredW = 1110
    $desiredH = 1080
    $win.Width = [math]::Min($desiredW, [int]($wa.Width - 40))
    $win.Height = [math]::Min($desiredH, [int]($wa.Height - 40))

    $names = @('LstItems', 'TxtFolder', 'TxtStatus', 'TxtSelection',
        'BtnView', 'BtnEdit', 'BtnDelete', 'BtnReveal', 'BtnCopy', 'BtnCopyMulti', 'BtnRefresh',
        'MiEdit', 'MiOpen', 'MiReveal', 'MiCopy', 'MiDelete')
    $c = Get-XamlControls -Root $win -Names $names

    # Toolbar-Icon-Groesse aus Config (clamped auf 16-32 pt). Buttons sind
    # quadratisch: Width = Height = FontSize + 14 (passt zu MDL2-Glyphen).
    $is = $IconSize
    if ($is -lt 16) { $is = 16 }
    if ($is -gt 32) { $is = 32 }
    $btnDim = [double]($is + 14)
    foreach ($btn in @($c.BtnView, $c.BtnEdit, $c.BtnDelete, $c.BtnReveal, $c.BtnCopy, $c.BtnCopyMulti, $c.BtnRefresh)) {
        $btn.FontSize = [double]$is
        $btn.Width = $btnDim
        $btn.Height = $btnDim
    }

    $c.TxtFolder.Text = "Ordner: $OutputDir"

    # Helper als ScriptBlock-Variablen -- werden ueber Closure-Capture in
    # die Event-Handler weitergereicht. Modul-Funktionen mit `_`-Praefix
    # liessen sich aus den ScriptBlocks zur Laufzeit nicht aufloesen.
    $mkEntry = {
        param([hashtable]$Item)
        $e = New-Object LucentScreen.HistoryEntry
        $e.FullName = $Item.FullName
        $e.FileName = $Item.FileName
        $e.Size = $Item.Size
        $e.SizeDisplay = $Item.SizeDisplay
        $e.LastWriteTime = $Item.LastWriteTime
        $e.TimeDisplay = $Item.TimeDisplay
        return $e
    }

    $loadThumb = {
        param([string]$Path, [int]$TargetWidth = 200)
        # BitmapFrame.Create laedt das PNG ueber URI mit OnLoad-Cache --
        # File-Handle wird sofort freigegeben. Bei groesseren Bildern
        # liefert TransformedBitmap einen RAM-sparenden Downscale.
        # (BitmapImage+DecodePixelWidth zeigte leere/weisse Tiles -- der
        # BitmapFrame-Pfad ist robuster.)
        try {
            $uri = New-Object System.Uri ($Path, [System.UriKind]::Absolute)
            $frame = [System.Windows.Media.Imaging.BitmapFrame]::Create(
                $uri,
                [System.Windows.Media.Imaging.BitmapCreateOptions]::IgnoreColorProfile,
                [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
            if ($frame.PixelWidth -le $TargetWidth) {
                $frame.Freeze()
                return $frame
            }
            $scale = [double]$TargetWidth / [double]$frame.PixelWidth
            $tx = New-Object System.Windows.Media.ScaleTransform $scale, $scale
            $tb = New-Object System.Windows.Media.Imaging.TransformedBitmap $frame, $tx
            $tb.Freeze()
            return $tb
        } catch {
            return $null
        }
    }

    # Sammlung + State werden via Hashtable referenziert, damit Closures
    # die gleiche Instanz sehen.
    $state = @{
        Items         = New-Object System.Collections.ObjectModel.ObservableCollection[LucentScreen.HistoryEntry]
        DebounceTimer = $null
        OutputDir     = $OutputDir
        Closing       = $false
        LastSig       = ''
    }
    $c.LstItems.ItemsSource = $state.Items

    $updateStatus = {
        $count = $state.Items.Count
        $sel = $c.LstItems.SelectedItems.Count
        $c.TxtStatus.Text = ("{0} Bilder" -f $count)
        if ($sel -gt 0) {
            $c.TxtSelection.Text = ("{0} ausgewaehlt" -f $sel)
        } else {
            $c.TxtSelection.Text = ''
        }
    }.GetNewClosure()

    $refresh = {
        if ($state.Closing) { return }
        $items = Get-HistoryItems -Path $state.OutputDir
        # Selektion merken (per FullName)
        $selectedPaths = @{}
        foreach ($sel in $c.LstItems.SelectedItems) { $selectedPaths[$sel.FullName] = $true }

        $state.Items.Clear()
        foreach ($it in $items) {
            $entry = & $mkEntry $it
            # Synchroner Thumbnail-Load: bei DecodePixelWidth-Pfad zeigten
            # sich leere Tiles, BitmapFrame+TransformedBitmap ist schnell
            # genug fuer typische Verlaeufe (<= einige hundert Bilder).
            $bmp = & $loadThumb $entry.FullName
            if ($null -ne $bmp) { $entry.Thumbnail = $bmp }
            $state.Items.Add($entry) | Out-Null
        }

        # Selektion wiederherstellen, soweit moeglich
        foreach ($entry in $state.Items) {
            if ($selectedPaths.ContainsKey($entry.FullName)) {
                $c.LstItems.SelectedItems.Add($entry) | Out-Null
            }
        }

        & $updateStatus
    }.GetNewClosure()

    # Live-Update via DispatcherTimer-Polling. FileSystemWatcher mit
    # PowerShell-ScriptBlock-Handlern lief auf einem Worker-Thread und
    # killte den Prozess silent (kein Dispatcher- oder AppDomain-Exception)
    # nach Datei-Operationen. Polling laeuft komplett im UI-Thread und
    # ist mit 2s-Intervall billig genug fuer einen Verlaufsordner.
    $state.LastSnapshot = (Get-Date 0)
    $poll = {
        if ($state.Closing) { return }
        $files = Get-HistoryFiles -Path $state.OutputDir
        $latest = if (@($files).Count -gt 0) { $files[0].LastWriteTime } else { (Get-Date 0) }
        # Snapshot-Signatur: Anzahl + neueste Zeit -- aendert sich bei
        # Add/Delete/Rename. Bei Modifikationen der Top-Datei greift
        # LastWriteTime sofort, bei Modifikationen tieferer Dateien
        # ziehen wir die Anzahl mit ran (Default sortiert nach Zeit, also
        # rutscht eine modifizierte Datei eh nach oben).
        $sigCount = @($files).Count
        $sig = "{0}|{1}" -f $sigCount, $latest.Ticks
        if ($state.LastSig -ne $sig) {
            $state.LastSig = $sig
            & $refresh
        }
    }.GetNewClosure()

    $poller = New-Object System.Windows.Threading.DispatcherTimer
    $poller.Interval = [TimeSpan]::FromSeconds(2)
    $poller.Add_Tick({ param($s, $e); & $poll }.GetNewClosure())
    $state.DebounceTimer = $poller

    # Kommando-Handler
    $cmdEdit = {
        $sel = @($c.LstItems.SelectedItems)
        if ($sel.Count -eq 0) { return }
        # Editor blockt mit ShowDialog -- bei Mehrfachauswahl sequentiell.
        foreach ($entry in $sel) {
            [void](Show-EditorWindow -ImagePath $entry.FullName -Owner $win -Postfix $EditPostfix)
        }
        # Falls neue _edited-Dateien entstanden, Refresh anstossen.
        & $refresh
    }.GetNewClosure()

    $cmdOpen = {
        $sel = @($c.LstItems.SelectedItems)
        if ($sel.Count -eq 0) { return }
        foreach ($entry in $sel) {
            [void](Open-HistoryFile -Path $entry.FullName)
        }
    }.GetNewClosure()

    $cmdReveal = {
        $sel = @($c.LstItems.SelectedItems)
        if ($sel.Count -eq 0) { return }
        # Bei Mehrfachauswahl nur das erste Item zeigen -- Explorer kann nur eines markieren
        [void](Show-HistoryInFolder -Path $sel[0].FullName)
    }.GetNewClosure()

    $cmdCopy = {
        $sel = @($c.LstItems.SelectedItems)
        if ($sel.Count -eq 0) { return }
        # Bei Mehrfachauswahl: nur erstes Bild ins Clipboard (Clipboard kann
        # nur ein Bild halten)
        $r = Copy-HistoryFileToClipboard -Path $sel[0].FullName
        if (-not $r.Success) {
            [System.Windows.MessageBox]::Show(
                ("In Zwischenablage fehlgeschlagen:`n" + $r.Message),
                'LucentScreen',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }
        # Toast mit Copy-Glyph (Segoe MDL2 0xE8C8) -- gleicher Look wie nach
        # Editor-Save. Show-CaptureToast ist modulweit ueber LucentScreen.ps1
        # importiert.
        if (Get-Command Show-CaptureToast -ErrorAction SilentlyContinue) {
            $copyGlyph = "$([char]0xE8C8)"
            Show-CaptureToast -Title 'In Zwischenablage kopiert' -Subtitle $sel[0].FileName -Glyph $copyGlyph
        }
    }.GetNewClosure()

    $cmdDelete = {
        $sel = @($c.LstItems.SelectedItems)
        if ($sel.Count -eq 0) { return }
        $msg = if ($sel.Count -eq 1) {
            "Datei '$($sel[0].FileName)' in den Papierkorb verschieben?"
        } else {
            "$($sel.Count) Dateien in den Papierkorb verschieben?"
        }
        $r = [System.Windows.MessageBox]::Show(
            $msg, 'LucentScreen -- Loeschen',
            [System.Windows.MessageBoxButton]::OKCancel,
            [System.Windows.MessageBoxImage]::Question)
        if ($r -ne [System.Windows.MessageBoxResult]::OK) { return }

        foreach ($entry in $sel) {
            $del = Remove-HistoryItem -Path $entry.FullName
            if (-not $del.Success) {
                [System.Windows.MessageBox]::Show(
                    ("Loeschen fehlgeschlagen ($($entry.FileName)):`n" + $del.Message),
                    'LucentScreen',
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning) | Out-Null
            }
        }
        # Sofortiger Refresh -- Poller braucht sonst bis zu 2s.
        & $refresh
    }.GetNewClosure()

    $cmdRefresh = { & $refresh }.GetNewClosure()

    # Multi-Copy: Datei-Liste als FileDropList ins Clipboard. Word/Outlook/Mail-
    # Programme fuegen so alle Bilder ein, Explorer behandelt es als 'Kopieren'.
    $cmdCopyMulti = {
        $sel = @($c.LstItems.SelectedItems)
        if ($sel.Count -eq 0) { return }
        try {
            $files = New-Object System.Collections.Specialized.StringCollection
            foreach ($entry in $sel) { [void]$files.Add($entry.FullName) }
            [System.Windows.Clipboard]::SetFileDropList($files)
        } catch {
            [System.Windows.MessageBox]::Show(
                ("Datei-Liste in Zwischenablage fehlgeschlagen:`n" + $_.Exception.Message),
                'LucentScreen',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }
        if (Get-Command Show-CaptureToast -ErrorAction SilentlyContinue) {
            $copyGlyph = "$([char]0xE8C8)"
            $sub = if ($sel.Count -eq 1) { $sel[0].FileName } else { ("{0} Dateien" -f $sel.Count) }
            Show-CaptureToast -Title 'Datei-Liste kopiert' -Subtitle $sub -Glyph $copyGlyph
        }
    }.GetNewClosure()

    $c.BtnView.Add_Click($cmdOpen)
    $c.BtnEdit.Add_Click($cmdEdit)
    $c.BtnDelete.Add_Click($cmdDelete)
    $c.BtnReveal.Add_Click($cmdReveal)
    $c.BtnCopy.Add_Click($cmdCopy)
    $c.BtnCopyMulti.Add_Click($cmdCopyMulti)
    $c.BtnRefresh.Add_Click($cmdRefresh)
    $c.MiEdit.Add_Click($cmdEdit)
    $c.MiOpen.Add_Click($cmdOpen)
    $c.MiReveal.Add_Click($cmdReveal)
    $c.MiCopy.Add_Click($cmdCopy)
    $c.MiDelete.Add_Click($cmdDelete)

    # Doppelklick auf ListBoxItem -> Editor (primaere Aktion)
    $c.LstItems.add_MouseDoubleClick({
            param($s, $e)
            & $cmdEdit
        }.GetNewClosure())

    $c.LstItems.add_SelectionChanged({
            param($s, $e)
            & $updateStatus
        }.GetNewClosure())

    # Tastatur am Window-Level (greift unabhaengig vom Fokus innerhalb)
    $win.add_PreviewKeyDown({
            param($s, $e)
            $ctrl = ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) -ne 0
            switch ($e.Key) {
                'Escape' { $win.Close(); $e.Handled = $true; break }
                'F5' { & $cmdRefresh; $e.Handled = $true; break }
                'Delete' { & $cmdDelete; $e.Handled = $true; break }
                'Enter' { & $cmdEdit; $e.Handled = $true; break }
                'Return' { & $cmdEdit; $e.Handled = $true; break }
                default {
                    if ($ctrl -and ($e.Key -eq [System.Windows.Input.Key]::C)) {
                        & $cmdCopy
                        $e.Handled = $true
                    }
                }
            }
        }.GetNewClosure())

    # Cleanup beim Schliessen
    $win.add_Closed({
            param($s, $e)
            $state.Closing = $true
            if ($state.DebounceTimer) { try { $state.DebounceTimer.Stop() } catch { $null = $_ } }
        }.GetNewClosure())

    # Erstbefuellung + Poller starten + Show
    & $refresh
    $poller.Start()
    [void]$win.ShowDialog()
}

Export-ModuleMember -Function Show-HistoryWindow
