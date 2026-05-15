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

Describe 'editor: Get-ArrowGeometry' {
    It 'liefert 5 Punkte fuer einen normalen Pfeil' {
        $r = Get-ArrowGeometry -X1 0 -Y1 0 -X2 100 -Y2 0
        $r.IsDegenerate    | Should -BeFalse
        @($r.Points).Count | Should -Be 5
    }

    It 'Punkt[0] = Start, Punkt[1] = Ende' {
        $r = Get-ArrowGeometry -X1 10 -Y1 20 -X2 110 -Y2 220
        $r.Points[0].X | Should -Be 10
        $r.Points[0].Y | Should -Be 20
        $r.Points[1].X | Should -Be 110
        $r.Points[1].Y | Should -Be 220
    }

    It 'Spitzen-Schenkel zeigen nach hinten (X < End.X bei waagrechtem Pfeil)' {
        $r = Get-ArrowGeometry -X1 0 -Y1 0 -X2 100 -Y2 0 -HeadSize 20
        # Schenkel-Endpunkte sind Index 2 und 4
        $r.Points[2].X | Should -BeLessThan 100
        $r.Points[4].X | Should -BeLessThan 100
        # Symmetrie um die Y-Achse: einer ueber 0, einer drunter
        ($r.Points[2].Y * $r.Points[4].Y) | Should -BeLessThan 0
    }

    It 'meldet IsDegenerate bei Start == End' {
        $r = Get-ArrowGeometry -X1 50 -Y1 50 -X2 50 -Y2 50
        $r.IsDegenerate | Should -BeTrue
        @($r.Points).Count | Should -Be 1
    }

    It 'HeadSize skaliert die Schenkel-Laenge' {
        $small = Get-ArrowGeometry -X1 0 -Y1 0 -X2 100 -Y2 0 -HeadSize 10
        $big = Get-ArrowGeometry -X1 0 -Y1 0 -X2 100 -Y2 0 -HeadSize 40
        # Abstand des Schenkel-Endpunkts vom End (100,0)
        $dxSmall = 100 - $small.Points[2].X
        $dxBig = 100 - $big.Points[2].X
        $dxBig | Should -BeGreaterThan $dxSmall
    }
}
