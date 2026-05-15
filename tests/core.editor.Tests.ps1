#Requires -Version 5.1

BeforeAll {
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    Import-Module "$PSScriptRoot/../src/core/capture.psm1" -Force
    Import-Module "$PSScriptRoot/../src/core/editor.psm1"  -Force
}

Describe 'editor: Format-EditedFilename' {
    It 'haengt Postfix vor die Endung' {
        $r = Format-EditedFilename -OriginalPath 'C:\tmp\pic.png'
        $r | Should -Be 'C:\tmp\pic_edited.png'
    }
    It 'respektiert einen abweichenden Postfix' {
        $r = Format-EditedFilename -OriginalPath 'C:\tmp\pic.png' -Postfix '_v2'
        $r | Should -Be 'C:\tmp\pic_v2.png'
    }
    It 'haengt .png an, wenn das Original keine Endung hat' {
        $r = Format-EditedFilename -OriginalPath 'C:\tmp\pic' -Postfix '_x'
        $r | Should -Be 'C:\tmp\pic_x.png'
    }
}

Describe 'editor: Save-EditedImage' {
    BeforeEach {
        $script:EdDir = Join-Path $TestDrive ('ed-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:EdDir | Out-Null
        $script:Original = Join-Path $script:EdDir 'orig.png'

        # Eine minimale BitmapSource erzeugen, ohne dass das Original schon
        # auf Platte liegen muss -- Save-EditedImage liest nicht vom Original,
        # sondern speichert die Quelle in das Postfix-File.
        $bmp = New-Object System.Drawing.Bitmap(16, 8)
        try {
            $ms = New-Object System.IO.MemoryStream
            $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
            $ms.Position = 0
            $bi = New-Object System.Windows.Media.Imaging.BitmapImage
            $bi.BeginInit()
            $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bi.StreamSource = $ms
            $bi.EndInit()
            $bi.Freeze()
            $script:Source = $bi
            $ms.Dispose()
        } finally { $bmp.Dispose() }
    }

    It 'schreibt eine PNG-Datei mit erwartetem Pfad' {
        $r = Save-EditedImage -Source $script:Source -OriginalPath $script:Original
        $r.Success | Should -BeTrue
        $r.Status  | Should -Be 'OK'
        $r.Path    | Should -Be (Join-Path $script:EdDir 'orig_edited.png')
        Test-Path -LiteralPath $r.Path | Should -BeTrue
        # Erste Bytes muessen PNG-Magic sein
        $bytes = [System.IO.File]::ReadAllBytes($r.Path) | Select-Object -First 4
        ($bytes -join ',') | Should -Be '137,80,78,71'
    }

    It 'haengt -2/-3 an bei Kollision' {
        $first = Save-EditedImage -Source $script:Source -OriginalPath $script:Original
        $second = Save-EditedImage -Source $script:Source -OriginalPath $script:Original
        $third = Save-EditedImage -Source $script:Source -OriginalPath $script:Original

        $first.Path | Should -Be (Join-Path $script:EdDir 'orig_edited.png')
        $second.Path | Should -Be (Join-Path $script:EdDir 'orig_edited-2.png')
        $third.Path  | Should -Be (Join-Path $script:EdDir 'orig_edited-3.png')
        @(Get-ChildItem $script:EdDir -Filter '*.png').Count | Should -Be 3
    }

    It 'respektiert den Postfix-Parameter' {
        $r = Save-EditedImage -Source $script:Source -OriginalPath $script:Original -Postfix '_redacted'
        $r.Success | Should -BeTrue
        $r.Path    | Should -Be (Join-Path $script:EdDir 'orig_redacted.png')
    }
}
