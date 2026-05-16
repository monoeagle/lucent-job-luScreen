#Requires -Version 5.1
Set-StrictMode -Version Latest

# ---------------------------------------------------------------
#  About-Dialog (Layout angelehnt an CodeSigningCommander)
#
#  Show-AboutDialog -Version <s> [-IconPath <p>] [-Owner <Window>]
#
#  Header:    Icon-Bild (PNG) + Titel + Version + Untertitel
#  Tab Info:  System (PowerShell/OS/DPI) + Projekt (Entwickler/E-Mail/
#             Repository/App-Pfad) + Komponenten-Liste
#  Tab Changelog: liest CHANGELOG.md aus dem Repo-Root
#
#  Voraussetzungen: STA, WPF, core/xaml-loader.psm1
# ---------------------------------------------------------------

function _AboutDlg-GetGitConfig {
    param([string]$Key)
    try {
        $val = & git config --get $Key 2>$null
        if ($LASTEXITCODE -eq 0 -and $val) { return [string]$val.Trim() }
    } catch { $null = $_ }
    return $null
}

function _AboutDlg-FindRepoRoot {
    param([string]$StartDir)
    $cur = $StartDir
    while ($cur -and (Test-Path -LiteralPath $cur)) {
        if (Test-Path -LiteralPath (Join-Path $cur '.git')) { return $cur }
        $parent = Split-Path -Parent $cur
        if ($parent -eq $cur) { break }
        $cur = $parent
    }
    return $null
}

function _AboutDlg-LoadChangelog {
    param([string]$RepoRoot, [int]$MaxBytes = 200000)
    if (-not $RepoRoot) { return '(Repository-Root nicht gefunden)' }
    $path = Join-Path $RepoRoot 'CHANGELOG.md'
    if (-not (Test-Path -LiteralPath $path)) {
        return "(CHANGELOG.md nicht gefunden in $RepoRoot)"
    }
    try {
        $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        if ($content.Length -gt $MaxBytes) {
            $content = $content.Substring(0, $MaxBytes) + "`n`n... (gekürzt -- siehe CHANGELOG.md für vollständigen Text)"
        }
        return $content
    } catch {
        return "(CHANGELOG.md konnte nicht gelesen werden: $($_.Exception.Message))"
    }
}

function Show-AboutDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Version,
        [string]$IconPath,
        [string]$WindowIconPath,
        [System.Windows.Window]$Owner
    )

    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        throw 'Show-AboutDialog benoetigt ein STA-Apartment.'
    }

    $xamlPath = Join-Path $PSScriptRoot '..\views\about-dialog.xaml'
    $win = Load-Xaml -Path $xamlPath
    # Window-Titelleisten-Icon: -WindowIconPath schlaegt den App-Default,
    # sonst greift Set-AppDefaultIcon aus dem Bootstrap.
    Set-AppWindowIcon -Window $win -Path $WindowIconPath
    if ($Owner) { $win.Owner = $Owner }

    $names = @(
        'ImgHeader', 'LblVersion',
        'LblPwsh', 'LblOs', 'LblDpi',
        'LblDeveloper', 'LblEmail', 'LblRepo', 'LblAppPath',
        'LblChangelog', 'BtnOk'
    )
    $c = Get-XamlControls -Root $win -Names $names

    $c.LblVersion.Text = "Version $Version"

    # --- Header-Icon (PNG bevorzugt -- gross + alpha)
    if ($IconPath -and (Test-Path -LiteralPath $IconPath)) {
        try {
            $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
            $bmp.BeginInit()
            $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bmp.UriSource = New-Object System.Uri ($IconPath, [System.UriKind]::Absolute)
            $bmp.EndInit()
            $bmp.Freeze()
            $c.ImgHeader.Source = $bmp
        } catch { $null = $_ }
    }

    # --- System ---
    $edition = [string]$PSVersionTable.PSEdition
    if ([string]::IsNullOrWhiteSpace($edition)) { $edition = 'Desktop' }
    $c.LblPwsh.Text = "$($PSVersionTable.PSVersion) ($edition)"

    try {
        $os = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Caption
    } catch {
        $os = [string][System.Environment]::OSVersion.VersionString
    }
    $c.LblOs.Text = $os

    $dpi = 'unbekannt'
    try {
        $dpiAware = [LucentScreen.Native]::GetThreadDpiAwarenessContext()
        if ($dpiAware) { $dpi = "PER_MONITOR_AWARE_V2 (Context $dpiAware)" }
    } catch {
        $dpi = 'PER_MONITOR_AWARE_V2 (Bootstrap)'
    }
    $c.LblDpi.Text = $dpi

    # --- Projekt ---
    $appDir = Split-Path -Parent $PSScriptRoot   # ui/ -> src/
    $repoRoot = _AboutDlg-FindRepoRoot -StartDir $appDir
    $devName = _AboutDlg-GetGitConfig -Key 'user.name'
    $devEmail = _AboutDlg-GetGitConfig -Key 'user.email'
    if (-not $devName) { $devName = 'Tobias Philipp' }
    if (-not $devEmail) { $devEmail = '—' }

    $c.LblDeveloper.Text = $devName
    $c.LblEmail.Text = $devEmail
    $c.LblRepo.Text = if ($repoRoot) { $repoRoot } else { '(nicht gefunden)' }
    $c.LblAppPath.Text = $appDir

    # --- Changelog ---
    $c.LblChangelog.Text = _AboutDlg-LoadChangelog -RepoRoot $repoRoot

    $c.BtnOk.Add_Click({ param($s, $e); $win.DialogResult = $true; $win.Close() }.GetNewClosure())

    [void]$win.ShowDialog()
}

Export-ModuleMember -Function Show-AboutDialog
