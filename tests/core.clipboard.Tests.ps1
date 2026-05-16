#Requires -Version 5.1

BeforeAll {
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    Import-Module "$PSScriptRoot/../src/core/capture.psm1"  -Force
    Import-Module "$PSScriptRoot/../src/core/clipboard.psm1" -Force
}

Describe 'clipboard: Convert-BitmapToBitmapSource' {
    It 'liefert BitmapSource mit den richtigen Dimensionen' {
        $bmp = New-Object System.Drawing.Bitmap(48, 32)
        try {
            $src = Convert-BitmapToBitmapSource -Bitmap $bmp
            $src             | Should -BeOfType [System.Windows.Media.Imaging.BitmapSource]
            $src.PixelWidth  | Should -Be 48
            $src.PixelHeight | Should -Be 32
        } finally {
            $bmp.Dispose()
        }
    }

    It 'liefert Frozen-Source (threadsafe, fuer Clipboard verwendbar)' {
        $bmp = New-Object System.Drawing.Bitmap(8, 8)
        try {
            $src = Convert-BitmapToBitmapSource -Bitmap $bmp
            $src.IsFrozen | Should -BeTrue
        } finally {
            $bmp.Dispose()
        }
    }
}

Describe 'clipboard: Set-ClipboardImage STA-Check' {
    # Pester selbst laeuft im MTA-Apartment (powershell.exe Default), deshalb
    # testen wir die Guard-Klausel statt das echte SetImage.

    It 'liefert NotSta-Status wenn Apartment != STA' {
        # Wir sind hier (in Pester) MTA -- Guard muss greifen
        $apt = [System.Threading.Thread]::CurrentThread.GetApartmentState()
        if ($apt -eq 'STA') {
            Set-ItResult -Skipped -Because 'Pester laeuft hier in STA, Guard nicht testbar.'
            return
        }
        $bmp = New-Object System.Drawing.Bitmap(4, 4)
        try {
            $r = Set-ClipboardImage -Bitmap $bmp -MaxAttempts 1
            $r.Success | Should -BeFalse
            $r.Status  | Should -Be 'NotSta'
        } finally {
            $bmp.Dispose()
        }
    }
}

Describe 'clipboard: Save-ClipboardImageAsPng STA-Check' {
    # Wie bei Set-ClipboardImage: STA-Guard ist die einzige Pfadkomponente,
    # die wir aus MTA testen koennen. ContainsImage/GetImage selbst werfen
    # ohne STA -- der Guard muss vorher greifen.

    It 'liefert NotSta-Status wenn Apartment != STA' {
        $apt = [System.Threading.Thread]::CurrentThread.GetApartmentState()
        if ($apt -eq 'STA') {
            Set-ItResult -Skipped -Because 'Pester laeuft hier in STA, Guard nicht testbar.'
            return
        }
        $target = Join-Path $TestDrive ('druck-{0}.png' -f ([guid]::NewGuid().ToString('N')))
        $r = Save-ClipboardImageAsPng -Path $target -MaxAttempts 1
        $r.Success  | Should -BeFalse
        $r.Status   | Should -Be 'NotSta'
        $r.Path     | Should -Be $null
        $r.Width    | Should -Be 0
        $r.Height   | Should -Be 0
        $r.Attempts | Should -Be 0
        Test-Path -LiteralPath $target | Should -BeFalse
    }
}
