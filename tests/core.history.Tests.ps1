#Requires -Version 5.1

BeforeAll {
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    Import-Module "$PSScriptRoot/../src/core/clipboard.psm1" -Force
    Import-Module "$PSScriptRoot/../src/core/history.psm1"   -Force
}

Describe 'history: Format-FileSize' {
    It 'unter 1 KB -> Bytes' {
        Format-FileSize -Bytes 512 | Should -Be '512 B'
    }
    It 'zwischen 1 KB und 1 MB -> KB' {
        (Format-FileSize -Bytes 2048) | Should -Match 'KB$'
    }
    It 'zwischen 1 MB und 1 GB -> MB' {
        (Format-FileSize -Bytes (3 * 1024 * 1024)) | Should -Match 'MB$'
    }
    It 'ueber 1 GB -> GB' {
        (Format-FileSize -Bytes (2 * 1024 * 1024 * 1024)) | Should -Match 'GB$'
    }
}

Describe 'history: Get-HistoryFiles' {
    BeforeEach {
        $script:HistDir = Join-Path $TestDrive ("hist-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:HistDir | Out-Null
    }

    It 'liefert leer wenn Ordner nicht existiert' {
        $missing = Join-Path $TestDrive ('missing-' + [guid]::NewGuid().ToString('N'))
        $r = Get-HistoryFiles -Path $missing
        @($r).Count | Should -Be 0
    }

    It 'sortiert neueste zuerst' {
        $f1 = Join-Path $script:HistDir 'a.png'
        $f2 = Join-Path $script:HistDir 'b.png'
        $f3 = Join-Path $script:HistDir 'c.png'
        Set-Content -LiteralPath $f1 -Value 'x'
        (Get-Item -LiteralPath $f1).LastWriteTime = (Get-Date).AddMinutes(-30)
        Set-Content -LiteralPath $f2 -Value 'y'
        (Get-Item -LiteralPath $f2).LastWriteTime = (Get-Date).AddMinutes(-10)
        Set-Content -LiteralPath $f3 -Value 'z'
        (Get-Item -LiteralPath $f3).LastWriteTime = (Get-Date)

        $r = Get-HistoryFiles -Path $script:HistDir
        @($r).Count | Should -Be 3
        $r[0].Name | Should -Be 'c.png'
        $r[1].Name | Should -Be 'b.png'
        $r[2].Name | Should -Be 'a.png'
    }

    It 'filtert per Wildcard' {
        Set-Content -LiteralPath (Join-Path $script:HistDir 'pic.png') -Value 'x'
        Set-Content -LiteralPath (Join-Path $script:HistDir 'note.txt') -Value 'x'

        $r = Get-HistoryFiles -Path $script:HistDir -Filter '*.png'
        @($r).Count | Should -Be 1
        $r[0].Name | Should -Be 'pic.png'
    }
}

Describe 'history: New-HistoryItem' {
    It 'mappt alle erwarteten Felder' {
        $p = Join-Path $TestDrive ('item-' + [guid]::NewGuid().ToString('N') + '.png')
        Set-Content -LiteralPath $p -Value 'abc'
        $fi = Get-Item -LiteralPath $p

        $h = New-HistoryItem -File $fi
        $h.FullName      | Should -Be $fi.FullName
        $h.FileName      | Should -Be $fi.Name
        $h.Size          | Should -BeGreaterThan 0
        $h.SizeDisplay   | Should -Not -BeNullOrEmpty
        $h.LastWriteTime | Should -Be $fi.LastWriteTime
        $h.TimeDisplay   | Should -Match '^\d{4}-\d{2}-\d{2}'
    }
}

Describe 'history: Get-HistoryItems' {
    It 'liefert Items in absteigender Reihenfolge' {
        $d = Join-Path $TestDrive ('items-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $d | Out-Null

        $a = Join-Path $d 'a.png'; Set-Content -LiteralPath $a -Value 'a'
        (Get-Item -LiteralPath $a).LastWriteTime = (Get-Date).AddHours(-2)
        $b = Join-Path $d 'b.png'; Set-Content -LiteralPath $b -Value 'b'
        (Get-Item -LiteralPath $b).LastWriteTime = (Get-Date)

        $items = Get-HistoryItems -Path $d
        @($items).Count | Should -Be 2
        $items[0].FileName | Should -Be 'b.png'
        $items[1].FileName | Should -Be 'a.png'
    }
}

Describe 'history: Remove-HistoryItem' {
    It 'meldet NotFound bei fehlender Datei' {
        $r = Remove-HistoryItem -Path (Join-Path $TestDrive 'kaputt.png')
        $r.Success | Should -BeFalse
        $r.Status  | Should -Be 'NotFound'
    }

    It 'loescht endgueltig mit -Permanent' {
        $p = Join-Path $TestDrive ('perm-' + [guid]::NewGuid().ToString('N') + '.png')
        Set-Content -LiteralPath $p -Value 'x'
        $r = Remove-HistoryItem -Path $p -Permanent
        $r.Success | Should -BeTrue
        Test-Path -LiteralPath $p | Should -BeFalse
    }
}

Describe 'history: Show-HistoryInFolder / Open-HistoryFile NotFound-Guard' {
    It 'Show-HistoryInFolder meldet NotFound' {
        $r = Show-HistoryInFolder -Path (Join-Path $TestDrive 'gibt-es-nicht.png')
        $r.Success | Should -BeFalse
        $r.Status  | Should -Be 'NotFound'
    }
    It 'Open-HistoryFile meldet NotFound' {
        $r = Open-HistoryFile -Path (Join-Path $TestDrive 'gibt-es-nicht.png')
        $r.Success | Should -BeFalse
        $r.Status  | Should -Be 'NotFound'
    }
    It 'Copy-HistoryFileToClipboard meldet NotFound' {
        $r = Copy-HistoryFileToClipboard -Path (Join-Path $TestDrive 'gibt-es-nicht.png')
        $r.Success | Should -BeFalse
        $r.Status  | Should -Be 'NotFound'
    }
}

Describe 'history: Rename-HistoryItem' {
    BeforeEach {
        $script:RenDir = Join-Path $TestDrive ("ren-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:RenDir | Out-Null
        $script:RenFile = Join-Path $script:RenDir 'shot.png'
        [System.IO.File]::WriteAllBytes($script:RenFile, [byte[]](1, 2, 3))
    }

    It 'meldet NotFound bei fehlender Datei' {
        $r = Rename-HistoryItem -Path (Join-Path $script:RenDir 'gibt-es-nicht.png') -NewName 'neu.png'
        $r.Success | Should -BeFalse
        $r.Status  | Should -Be 'NotFound'
    }

    It 'meldet InvalidName bei leerem Namen' {
        $r = Rename-HistoryItem -Path $script:RenFile -NewName '   '
        $r.Success | Should -BeFalse
        $r.Status  | Should -Be 'InvalidName'
    }

    It 'meldet InvalidName bei Pfad-Separator im Namen' {
        $r = Rename-HistoryItem -Path $script:RenFile -NewName 'sub\new.png'
        $r.Success | Should -BeFalse
        $r.Status  | Should -Be 'InvalidName'
    }

    It 'meldet InvalidName wenn neuer Name == alter' {
        $r = Rename-HistoryItem -Path $script:RenFile -NewName 'shot.png'
        $r.Success | Should -BeFalse
        $r.Status  | Should -Be 'InvalidName'
    }

    It 'meldet TargetExists wenn Ziel schon existiert' {
        $occupied = Join-Path $script:RenDir 'occupied.png'
        [System.IO.File]::WriteAllBytes($occupied, [byte[]](9, 9))
        $r = Rename-HistoryItem -Path $script:RenFile -NewName 'occupied.png'
        $r.Success | Should -BeFalse
        $r.Status  | Should -Be 'TargetExists'
        Test-Path -LiteralPath $script:RenFile | Should -BeTrue   # alte Datei unangetastet
    }

    It 'benennt erfolgreich um, alte Datei weg, neue da' {
        $r = Rename-HistoryItem -Path $script:RenFile -NewName 'umbenannt.png'
        $r.Success | Should -BeTrue
        $r.Status  | Should -Be 'OK'
        $r.Path    | Should -Be (Join-Path $script:RenDir 'umbenannt.png')
        Test-Path -LiteralPath $script:RenFile | Should -BeFalse
        Test-Path -LiteralPath $r.Path         | Should -BeTrue
    }

    It '-KeepExtension haengt Original-Extension an, wenn neuer Name keine hat' {
        $r = Rename-HistoryItem -Path $script:RenFile -NewName 'ohne-ext' -KeepExtension
        $r.Success | Should -BeTrue
        $r.Path    | Should -Be (Join-Path $script:RenDir 'ohne-ext.png')
    }

    It '-KeepExtension ueberschreibt nicht, wenn neuer Name schon eine Ext hat' {
        $r = Rename-HistoryItem -Path $script:RenFile -NewName 'neu.jpg' -KeepExtension
        $r.Success | Should -BeTrue
        $r.Path    | Should -Be (Join-Path $script:RenDir 'neu.jpg')
    }
}
