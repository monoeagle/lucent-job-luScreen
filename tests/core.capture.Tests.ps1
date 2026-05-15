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
