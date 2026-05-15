#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    Add-Type -AssemblyName System.Xaml

    Import-Module "$PSScriptRoot/../src/core/xaml-loader.psm1" -Force
}

Describe 'xaml-loader' {
    BeforeEach {
        $script:XamlFile = Join-Path $TestDrive ("ui_" + [guid]::NewGuid().ToString('N') + '.xaml')
    }

    AfterEach {
        Get-ChildItem $TestDrive -File -EA SilentlyContinue | Remove-Item -Force -EA SilentlyContinue
    }

    Context 'Load-Xaml' {
        It 'wirft, wenn die Datei nicht existiert' {
            { Load-Xaml -Path (Join-Path $TestDrive 'fehlt.xaml') } |
                Should -Throw -ExpectedMessage '*nicht gefunden*'
        }

        It 'wirft bei kaputtem XML' {
            Set-Content -LiteralPath $script:XamlFile -Value 'kein-xml' -Encoding UTF8
            { Load-Xaml -Path $script:XamlFile } | Should -Throw
        }

        It 'laedt ein gueltiges Window-XAML' {
            $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Test" Width="300" Height="200">
  <Grid>
    <Button x:Name="BtnOk" Content="OK"/>
  </Grid>
</Window>
'@
            Set-Content -LiteralPath $script:XamlFile -Value $xaml -Encoding UTF8
            $win = Load-Xaml -Path $script:XamlFile
            $win | Should -Not -BeNullOrEmpty
            $win.Title | Should -Be 'Test'
        }

        It 'entfernt x:Class-Attribut vor dem Parsen' {
            $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        x:Class="Designer.MainWindow" Title="Mit Code-Behind" Width="200" Height="100">
  <Grid/>
</Window>
'@
            Set-Content -LiteralPath $script:XamlFile -Value $xaml -Encoding UTF8
            $win = Load-Xaml -Path $script:XamlFile
            $win.Title | Should -Be 'Mit Code-Behind'
        }
    }

    Context 'Get-XamlControls' {
        It 'mappt vorhandene Names auf Controls' {
            $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Width="100" Height="80">
  <StackPanel>
    <Button x:Name="BtnOk"/>
    <TextBox x:Name="TxtPath"/>
  </StackPanel>
</Window>
'@
            Set-Content -LiteralPath $script:XamlFile -Value $xaml -Encoding UTF8
            $win = Load-Xaml -Path $script:XamlFile
            $map = Get-XamlControls -Root $win -Names 'BtnOk', 'TxtPath', 'DoesNotExist'
            $map.ContainsKey('BtnOk')        | Should -BeTrue
            $map.ContainsKey('TxtPath')      | Should -BeTrue
            $map.ContainsKey('DoesNotExist') | Should -BeFalse
        }
    }
}
