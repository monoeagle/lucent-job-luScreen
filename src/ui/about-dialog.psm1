#Requires -Version 5.1
Set-StrictMode -Version Latest

# ---------------------------------------------------------------
#  About-Dialog
#  Voraussetzungen: STA + WPF-Assemblies + core/xaml-loader.psm1
# ---------------------------------------------------------------

function Show-AboutDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Version,
        [string]$IconPath,
        [System.Windows.Window]$Owner
    )

    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        throw 'Show-AboutDialog benoetigt ein STA-Apartment.'
    }

    $xamlPath = Join-Path $PSScriptRoot '..\views\about-dialog.xaml'
    $win = Load-Xaml -Path $xamlPath
    if ($Owner) { $win.Owner = $Owner }

    $map = Get-XamlControls -Root $win -Names 'ImgIcon', 'TxtVersion', 'BtnOk'
    $map.TxtVersion.Text = "Version $Version"

    if ($IconPath -and (Test-Path -LiteralPath $IconPath)) {
        try {
            $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
            $bmp.BeginInit()
            $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bmp.UriSource = New-Object System.Uri ($IconPath, [System.UriKind]::Absolute)
            $bmp.EndInit()
            $bmp.Freeze()
            $map.ImgIcon.Source = $bmp
            # Window-Icon
            try { $win.Icon = $bmp } catch { $null = $_ }
        } catch {
            # Icon ist Schmuck -- Fehler beim Laden ist nicht kritisch
            $null = $_
        }
    }

    $map.BtnOk.Add_Click({
            param($s, $e)
            $win.DialogResult = $true
            $win.Close()
        }.GetNewClosure())

    [void]$win.ShowDialog()
}

Export-ModuleMember -Function Show-AboutDialog
