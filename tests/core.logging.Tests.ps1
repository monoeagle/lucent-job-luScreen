#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../src/core/logging.psm1" -Force
}

Describe 'logging' {
    BeforeEach {
        $script:LogFile = Join-Path $TestDrive ("log_" + [guid]::NewGuid().ToString('N') + ".log")
    }

    AfterEach {
        Get-ChildItem $TestDrive -File -EA SilentlyContinue | Remove-Item -Force -EA SilentlyContinue
    }

    It 'initialisiert mit explizitem Pfad und liefert Success' {
        $r = Initialize-Logging -Path $script:LogFile -MinLevel 'Debug'
        $r.Success | Should -BeTrue
        $r.Status  | Should -Be 'OK'
        Test-Path -LiteralPath (Split-Path -Parent $script:LogFile) | Should -BeTrue
    }

    It 'schreibt eine Info-Zeile mit Timestamp und Source' {
        [void](Initialize-Logging -Path $script:LogFile -MinLevel 'Info')
        Write-LsLog -Level Info -Source 'test' -Message 'hallo welt'
        $content = Get-Content -LiteralPath $script:LogFile -Raw -Encoding UTF8
        $content | Should -Match '\[Info\]'
        $content | Should -Match '\[test\]'
        $content | Should -Match 'hallo welt'
        # ISO-Datum vorne
        $content | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}'
    }

    It 'filtert Debug-Eintraege wenn MinLevel=Info' {
        [void](Initialize-Logging -Path $script:LogFile -MinLevel 'Info')
        Write-LsLog -Level Debug -Source 'test' -Message 'sollte nicht erscheinen'
        Write-LsLog -Level Info  -Source 'test' -Message 'sollte erscheinen'
        $content = Get-Content -LiteralPath $script:LogFile -Raw -Encoding UTF8
        $content | Should -Not -Match 'sollte nicht erscheinen'
        $content | Should -Match     'sollte erscheinen'
    }

    It 'haelt sich an MinLevel=Debug und schreibt alle Levels' {
        [void](Initialize-Logging -Path $script:LogFile -MinLevel 'Debug')
        Write-LsLog -Level Debug -Source 't' -Message 'a-debug'
        Write-LsLog -Level Info  -Source 't' -Message 'a-info'
        Write-LsLog -Level Warn  -Source 't' -Message 'a-warn'
        Write-LsLog -Level Error -Source 't' -Message 'a-error'
        $content = Get-Content -LiteralPath $script:LogFile -Raw -Encoding UTF8
        ($content -split "`n").Count | Should -BeGreaterOrEqual 4
        $content | Should -Match 'a-debug'
        $content | Should -Match 'a-error'
    }

    It 'Get-LogPath liefert den konfigurierten Pfad' {
        [void](Initialize-Logging -Path $script:LogFile -MinLevel 'Info')
        Get-LogPath | Should -Be $script:LogFile
    }
}
