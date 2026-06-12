# trailing_macro.Tests.ps1
# TDD para Camada 5: Macro pressure (BTC correlation, DXY, eventos)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$libPath = Join-Path (Join-Path $projectRoot "agents") "lib_trailing_macro.ps1"
if (Test-Path $libPath) { . $libPath }

Describe "Trailing Macro - Camada 5" {

    Context "Get-BtcCorrelationPressure - BTC dump pressiona alts" {
        It "BTC -3% em 1h aplica pressao alta para alts em LONG" {
            Get-BtcCorrelationPressure -BtcChange1hPct -3.0 -Side "LONG" | Should BeGreaterThan 60
        }
        It "BTC -1% e moderado (LONG)" {
            $r = Get-BtcCorrelationPressure -BtcChange1hPct -1.0 -Side "LONG"
            $r | Should BeGreaterThan 0
            $r | Should BeLessThan 50
        }
        It "BTC +0.5% nao pressiona LONG" {
            Get-BtcCorrelationPressure -BtcChange1hPct 0.5 -Side "LONG" | Should Be 0
        }
        It "BTC +3% pressiona SHORT (correlacao inversa)" {
            Get-BtcCorrelationPressure -BtcChange1hPct 3.0 -Side "SHORT" | Should BeGreaterThan 60
        }
        It "Para BTC mesmo: nao auto-correlaciona" {
            Get-BtcCorrelationPressure -BtcChange1hPct -3.0 -Side "LONG" -IsBtc $true | Should Be 0
        }
    }

    Context "Test-MacroEventWindow - eventos importantes proximos" {
        It "Janela FOMC (1h antes a 4h depois) retorna true" {
            $now = Get-Date "2026-05-25 14:00"
            $fomc = Get-Date "2026-05-25 14:30"
            Test-MacroEventWindow -EventTime $fomc -CurrentTime $now -PreHours 1 -PostHours 4 | Should Be $true
        }
        It "Fora da janela retorna false" {
            $now = Get-Date "2026-05-25 09:00"
            $fomc = Get-Date "2026-05-25 14:30"
            Test-MacroEventWindow -EventTime $fomc -CurrentTime $now -PreHours 1 -PostHours 4 | Should Be $false
        }
        It "Pos-evento dentro da janela retorna true" {
            $now = Get-Date "2026-05-25 17:00"
            $fomc = Get-Date "2026-05-25 14:30"
            Test-MacroEventWindow -EventTime $fomc -CurrentTime $now -PreHours 1 -PostHours 4 | Should Be $true
        }
    }

    Context "Get-MacroPressureScore - score combinado" {
        It "BTC dump + evento ativo = score alto" {
            $now = Get-Date "2026-05-25 14:00"
            $event_ = Get-Date "2026-05-25 14:30"
            $r = Get-MacroPressureScore -BtcChange1hPct -2.5 -Side "LONG" `
                -EventTime $event_ -CurrentTime $now
            $r | Should BeGreaterThan 50
        }
        It "Sem stress macro retorna baixo" {
            $now = Get-Date "2026-05-25 09:00"
            $event_ = Get-Date "2026-05-25 14:30"
            $r = Get-MacroPressureScore -BtcChange1hPct 0.2 -Side "LONG" `
                -EventTime $event_ -CurrentTime $now
            $r | Should BeLessThan 20
        }
    }
}
