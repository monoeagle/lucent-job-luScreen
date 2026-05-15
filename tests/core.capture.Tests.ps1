#Requires -Version 5.1

BeforeAll {
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms

    Import-Module "$PSScriptRoot/../src/core/native.psm1"  -Force
    Import-Module "$PSScriptRoot/../src/core/capture.psm1" -Force
}

Describe 'capture: screen enumeration' {
    It 'Get-AllScreens liefert mindestens einen Screen' {
        $s = Get-AllScreens
        $s.Count | Should -BeGreaterOrEqual 1
        $s[0].Bounds.Width  | Should -BeGreaterThan 0
        $s[0].Bounds.Height | Should -BeGreaterThan 0
    }

    It 'Get-VirtualScreenBounds hat positive Dimensionen' {
        $vs = Get-VirtualScreenBounds
        $vs.Width  | Should -BeGreaterThan 0
        $vs.Height | Should -BeGreaterThan 0
    }

    It 'Get-ScreenUnderCursor liefert einen Screen' {
        $s = Get-ScreenUnderCursor
        $s | Should -Not -BeNullOrEmpty
        $s.Bounds.Width | Should -BeGreaterThan 0
    }
}

Describe 'capture: Capture-Rect' {
    It 'erzeugt ein Bitmap mit der angeforderten Groesse' {
        $bmp = Capture-Rect -Left 0 -Top 0 -Width 50 -Height 30
        try {
            $bmp           | Should -BeOfType [System.Drawing.Bitmap]
            $bmp.Width     | Should -Be 50
            $bmp.Height    | Should -Be 30
        } finally {
            $bmp.Dispose()
        }
    }

    It 'wirft bei Width<=0' {
        { Capture-Rect -Left 0 -Top 0 -Width 0 -Height 10 } | Should -Throw
    }

    It 'wirft bei Height<=0' {
        { Capture-Rect -Left 0 -Top 0 -Width 10 -Height -1 } | Should -Throw
    }
}

Describe 'capture: Format-CaptureFilename' {
    It 'ersetzt {mode} korrekt' {
        $fixed = [datetime]'2026-05-15 14:12:34'
        $r = Format-CaptureFilename -Template 'lsc_{mode}.png' -Mode 'Region' -Now $fixed
        $r | Should -Be 'lsc_Region.png'
    }

    It 'rendert Datums-Tokens korrekt' {
        $fixed = [datetime]'2026-05-15 14:12:34'
        $r = Format-CaptureFilename -Template 'yyyyMMdd-HHmmss_{mode}.png' -Mode 'Monitor' -Now $fixed
        $r | Should -Be '20260515-141234_Monitor.png'
    }

    It 'ActiveWindow-Mode darf trotz "d" und "M" im Namen nicht durch Date-Format zerlegt werden' {
        $fixed = [datetime]'2026-05-15 14:12:34'
        $r = Format-CaptureFilename -Template '{mode}_yyyy.png' -Mode 'ActiveWindow' -Now $fixed
        $r | Should -Be 'ActiveWindow_2026.png'
    }

    It '{postfix} wird ersetzt' {
        $fixed = [datetime]'2026-05-15 14:12:34'
        $r = Format-CaptureFilename -Template '{mode}{postfix}.png' -Mode 'Region' -Postfix '_edited' -Now $fixed
        $r | Should -Be 'Region_edited.png'
    }

    It 'leeres {postfix} bleibt leer' {
        $fixed = [datetime]'2026-05-15 14:12:34'
        $r = Format-CaptureFilename -Template '{mode}{postfix}.png' -Mode 'Region' -Now $fixed
        $r | Should -Be 'Region.png'
    }
}

Describe 'capture: Resolve-UniqueFilename' {
    BeforeEach {
        $script:Dir = Join-Path $TestDrive ("uniq_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $script:Dir | Out-Null
    }

    It 'liefert Original-Pfad wenn frei' {
        $p = Join-Path $script:Dir 'frei.png'
        Resolve-UniqueFilename -Path $p | Should -Be $p
    }

    It 'haengt -2 an wenn Original existiert' {
        $p = Join-Path $script:Dir 'kollision.png'
        New-Item -ItemType File -Path $p -Force | Out-Null
        $r = Resolve-UniqueFilename -Path $p
        $r | Should -Be (Join-Path $script:Dir 'kollision-2.png')
    }

    It 'zaehlt weiter bei -2, -3, -4' {
        $p = Join-Path $script:Dir 'spec.png'
        New-Item -ItemType File -Path $p -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $script:Dir 'spec-2.png') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $script:Dir 'spec-3.png') -Force | Out-Null
        $r = Resolve-UniqueFilename -Path $p
        $r | Should -Be (Join-Path $script:Dir 'spec-4.png')
    }
}

Describe 'capture: Save-Capture' {
    BeforeEach {
        $script:OutDir = Join-Path $TestDrive ("out_" + [guid]::NewGuid().ToString('N'))
    }

    It 'speichert PNG, legt fehlenden Zielordner an, liefert Success' {
        $bmp = Capture-Rect -Left 0 -Top 0 -Width 32 -Height 32
        try {
            $r = Save-Capture -Bitmap $bmp -Mode 'TestMode' -OutputDir $script:OutDir
            $r.Success | Should -BeTrue
            $r.Status  | Should -Be 'OK'
            Test-Path -LiteralPath $r.Path | Should -BeTrue
            (Get-Item $r.Path).Length | Should -BeGreaterThan 0
            # Dateiname enthaelt den Mode
            ([IO.Path]::GetFileName($r.Path)) | Should -Match '_TestMode\.png$'
        } finally {
            $bmp.Dispose()
        }
    }

    It 'haengt -2 an bei zweitem Save in derselben Sekunde' {
        $bmp = Capture-Rect -Left 0 -Top 0 -Width 16 -Height 16
        try {
            # Festes Template ohne Datums-Tokens, damit garantiert kollidiert
            $tmpl = 'fix_{mode}.png'
            $r1 = Save-Capture -Bitmap $bmp -Mode 'X' -OutputDir $script:OutDir -Template $tmpl
            $r2 = Save-Capture -Bitmap $bmp -Mode 'X' -OutputDir $script:OutDir -Template $tmpl
            $r1.Success | Should -BeTrue
            $r2.Success | Should -BeTrue
            ([IO.Path]::GetFileName($r1.Path)) | Should -Be 'fix_X.png'
            ([IO.Path]::GetFileName($r2.Path)) | Should -Be 'fix_X-2.png'
        } finally {
            $bmp.Dispose()
        }
    }

    It 'nutzt {postfix} wenn im Template' {
        $bmp = Capture-Rect -Left 0 -Top 0 -Width 16 -Height 16
        try {
            $r = Save-Capture -Bitmap $bmp -Mode 'Region' -OutputDir $script:OutDir `
                -Template '{mode}{postfix}.png' -Postfix '_edit'
            ([IO.Path]::GetFileName($r.Path)) | Should -Be 'Region_edit.png'
        } finally {
            $bmp.Dispose()
        }
    }
}

Describe 'capture: Invoke-Capture' {
    It 'Mode=Monitor liefert Bitmap mit positiver Groesse' {
        $r = Invoke-Capture -Mode Monitor
        try {
            $r.Success | Should -BeTrue
            $r.Mode    | Should -Be 'Monitor'
            $r.Width   | Should -BeGreaterThan 0
            $r.Height  | Should -BeGreaterThan 0
            $r.Bitmap  | Should -BeOfType [System.Drawing.Bitmap]
        } finally {
            if ($r.Bitmap) { $r.Bitmap.Dispose() }
        }
    }

    It 'Mode=AllMonitors liefert Bitmap in VirtualScreen-Groesse' {
        $r = Invoke-Capture -Mode AllMonitors
        try {
            $vs = Get-VirtualScreenBounds
            $r.Success | Should -BeTrue
            $r.Width   | Should -Be $vs.Width
            $r.Height  | Should -Be $vs.Height
        } finally {
            if ($r.Bitmap) { $r.Bitmap.Dispose() }
        }
    }

    It 'Mode=Region ohne RegionRect liefert Success=$false' {
        $r = Invoke-Capture -Mode Region
        $r.Success | Should -BeFalse
        $r.Message | Should -Match 'RegionRect'
    }

    It 'Mode=Region mit RegionRect liefert Bitmap mit dieser Groesse' {
        $r = Invoke-Capture -Mode Region -RegionRect @{ Left = 0; Top = 0; Width = 40; Height = 20 }
        try {
            $r.Success | Should -BeTrue
            $r.Width   | Should -Be 40
            $r.Height  | Should -Be 20
        } finally {
            if ($r.Bitmap) { $r.Bitmap.Dispose() }
        }
    }
}
