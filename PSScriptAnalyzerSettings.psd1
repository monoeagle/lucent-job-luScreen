@{
    # PSScriptAnalyzer-Konfiguration fuer LucentScreen.
    # Wird automatisch von tools/Invoke-PSSA.ps1 geladen.
    # Die hier ausgeschlossenen Regeln sind bewusst gesetzte Projekt-
    # Konventionen oder fuer den WPF/Tray-Kontext ungeeignet.

    Severity = @('Error','Warning','Information')

    ExcludeRules = @(
        # run.ps1, tools/ und Setup-Skripte verwenden Write-Host bewusst fuer
        # farbige, benutzergerichtete Konsolenausgabe. Kein Pipeline-Konsumer.
        # In src/core/ und src/ui/ bitte trotzdem das Logging-Modul nutzen.
        'PSAvoidUsingWriteHost',

        # WPF-UI-Code hat keine ShouldProcess-Semantik (kein -WhatIf-Use-Case
        # bei Show-Window, Set-Theme usw. -- die Wirkung ist immer
        # interaktiv vom User ausgeloest).
        'PSUseShouldProcessForStateChangingFunctions',

        # Domain-Funktionen wie Get-Screens, Register-Hotkeys, Get-Captures
        # operieren bewusst auf Mehrfach-Items. Singular waere semantisch
        # falsch.
        'PSUseSingularNouns',

        # Information-Level; XAML-Event-Handler haben oft ungenutzte
        # $sender / $eventArgs Parameter (das ist by-design fuer das
        # WPF-Event-Delegate).
        'PSReviewUnusedParameter',

        # Information-Level; idiomatischer PowerShell-Stil, vor allem in
        # Tests und Tools.
        'PSAvoidUsingPositionalParameters',

        # Information-Level; interne Helper (Funktionen mit _-Prefix)
        # brauchen kein Comment-Help.
        'PSProvideCommentHelp'
    )

    Rules = @{
        # Erzwingt einheitliche Whitespace-Regeln in den Modulen.
        PSUseConsistentWhitespace = @{
            Enable                                  = $true
            CheckOpenBrace                          = $true
            CheckOpenParen                          = $true
            CheckOperator                           = $true
            CheckSeparator                          = $true
            CheckPipe                               = $true
            IgnoreAssignmentOperatorInsideHashTable = $true
        }

        # 4-Spaces-Indentation, kein Tab.
        PSUseConsistentIndentation = @{
            Enable          = $true
            IndentationSize = 4
            Kind            = 'space'
        }
    }
}
