# constants_loader.Tests.ps1
# TDD strict para constants_loader.ps1 e parity com backtest/constants.py
# UTF-8 BOM. Pester 3.x.

. "$PSScriptRoot\..\agents\constants_loader.ps1"

Describe "constants_loader - business rules base" {

    It "RR_DEFAULT = 5.0" {
        $global:CONST_RR_DEFAULT | Should Be 5.0
    }

    It "SCORE_THRESHOLD = 65.0" {
        $global:CONST_SCORE_THRESHOLD | Should Be 65.0
    }

    It "RISK_PCT_PER_TRADE = 0.01" {
        $global:CONST_RISK_PCT_PER_TRADE | Should Be 0.01
    }
}

Describe "constants_loader - regime params alinhados Python" {

    It "SMA200_PERIOD = 200 (matches backtest/constants.py)" {
        $global:CONST_SMA200_PERIOD | Should Be 200
    }

    It "SIDEWAYS_BAND = 0.02" {
        $global:CONST_SIDEWAYS_BAND | Should Be 0.02
    }

    It "ADX_STRONG_THRESHOLD = 25.0" {
        $global:CONST_ADX_STRONG_THRESHOLD | Should Be 25.0
    }
}

Describe "Get-Constant function" {

    It "retorna valor de constante existente" {
        Get-Constant -Name "RR_DEFAULT" | Should Be 5.0
    }

    It "retorna $null quando constante nao existe" {
        $r = Get-Constant -Name "INEXISTENTE_XYZ_ABC"
        $r | Should Be $null
    }

    It "retorna Default quando constante nao existe e Default fornecido" {
        Get-Constant -Name "INEXISTENTE_XYZ" -Default 999 | Should Be 999
    }
}

Describe "GO_CRITERION nomes desambiguados (pos DRIFT-2 fix)" {

    It "GO_POSITIVE_YEARS_PCT = 70 (long_14y semantic)" {
        $global:CONST_GO_POSITIVE_YEARS_PCT | Should Be 70.0
    }

    It "GO_POSITIVE_WINDOWS_PCT = 60 (walkforward semantic)" {
        $global:CONST_GO_POSITIVE_WINDOWS_PCT | Should Be 60.0
    }
}
