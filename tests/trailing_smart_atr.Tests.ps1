# trailing_smart_atr.Tests.ps1
# TDD para Camada 2: ATR Adaptativo no trailing
# RED phase: testes definem comportamento esperado

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$libPath = Join-Path (Join-Path $projectRoot "agents") "lib_trailing_smart.ps1"

# Carregar lib se existir (criada na fase GREEN)
if (Test-Path $libPath) { . $libPath }

Describe "Trailing Smart - Camada 2: ATR Adaptativo" {

    Context "Get-AtrStopMultiple - retorna multiplo de ATR baseado em volatilidade" {
        It "LOW_VOL (ATR <2%) retorna 2.5 ATRs (stop mais largo, par estavel)" {
            Get-AtrStopMultiple -AtrPct 1.5 | Should Be 2.5
        }
        It "MEDIUM_VOL (2-4%) retorna 2.0 ATRs (padrao)" {
            Get-AtrStopMultiple -AtrPct 3.0 | Should Be 2.0
        }
        It "HIGH_VOL (4-6%) retorna 1.5 ATRs (stop mais perto, evitar whipsaw)" {
            Get-AtrStopMultiple -AtrPct 5.0 | Should Be 1.5
        }
        It "EXTREME_VOL (>6%) retorna 1.2 ATRs (stop apertado)" {
            Get-AtrStopMultiple -AtrPct 8.0 | Should Be 1.2
        }
    }

    Context "Calculate-AdaptiveStopPrice - calcula preco do stop baseado em ATR" {
        It "LONG entry=100 ATR=2.0 multiple=2.5 retorna stop=95.0" {
            $r = Calculate-AdaptiveStopPrice -Side "LONG" -Entry 100.0 -AtrAbs 2.0 -AtrMultiple 2.5
            $r | Should Be 95.0
        }
        It "SHORT entry=100 ATR=2.0 multiple=2.5 retorna stop=105.0" {
            $r = Calculate-AdaptiveStopPrice -Side "SHORT" -Entry 100.0 -AtrAbs 2.0 -AtrMultiple 2.5
            $r | Should Be 105.0
        }
        It "LONG com par sub-dollar (BNB 0.05 ATR) preserva precisao" {
            $r = Calculate-AdaptiveStopPrice -Side "LONG" -Entry 0.5 -AtrAbs 0.005 -AtrMultiple 2.0
            $r | Should Be 0.49
        }
    }

    Context "Get-VolatilityClass - classifica volatilidade" {
        It "Retorna LOW_VOL para ATR < 2%" {
            Get-VolatilityClass -AtrPct 1.0 | Should Be "LOW_VOL"
        }
        It "Retorna MEDIUM_VOL para ATR 2-4%" {
            Get-VolatilityClass -AtrPct 3.0 | Should Be "MEDIUM_VOL"
        }
        It "Retorna HIGH_VOL para ATR 4-6%" {
            Get-VolatilityClass -AtrPct 5.0 | Should Be "HIGH_VOL"
        }
        It "Retorna EXTREME_VOL para ATR > 6%" {
            Get-VolatilityClass -AtrPct 8.0 | Should Be "EXTREME_VOL"
        }
    }

    Context "Calculate-AtrFromCandles - calcula ATR de array de candles" {
        It "Calcula ATR(14) corretamente" {
            $candles = 1..20 | ForEach-Object {
                [PSCustomObject]@{
                    high = 100 + $_
                    low = 99 + $_
                    close = 99.5 + $_
                }
            }
            $atr = Calculate-AtrFromCandles -Candles $candles -Period 14
            $atr | Should BeGreaterThan 0
            $atr | Should BeLessThan 5
        }
        It "Retorna 0 se menos candles que Period" {
            $candles = 1..5 | ForEach-Object {
                [PSCustomObject]@{ high=100; low=99; close=99.5 }
            }
            Calculate-AtrFromCandles -Candles $candles -Period 14 | Should Be 0
        }
    }
}
