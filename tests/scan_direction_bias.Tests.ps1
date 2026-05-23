# scan_direction_bias.Tests.ps1
# TDD strict: Get-DirectionBias detecta LONG/SHORT/NEUTRAL no pre-screen.
#
# Bug raiz (journal/cascade_diagnose_2026_05_15.md + log 2026-05-15):
# Hit-rate SHORT 0/10 capturado. Scanner top-20 dominado por LONG movers.
# Pre-screen passa candidatos direction-agnostic mas downstream nunca infere SHORT.
# Resultado: regra 5 da whitelist (SHORT->observe paper) eh letra morta.
#
# Fix: Get-DirectionBias retorna {LONG|SHORT|NEUTRAL} baseado em RSI + EMA + momentum.
# scan_master atta direction_bias a cada candidato. Orchestrator usa como hint
# para triagem.direction quando macroBias eh NEUTRAL/incerto.
#
# UTF-8 BOM. Pester 3.x. PS 5.1.

$scanMasterPath = "$PSScriptRoot\..\scripts\scan_master.ps1"
$content = Get-Content $scanMasterPath -Raw
if ($content -match '(?ms)(^function Get-DirectionBias\s*\{.*?^\})') {
    Invoke-Expression $matches[1]
}

Describe "Get-DirectionBias - inferencia LONG/SHORT/NEUTRAL no pre-screen" {

    Context "LONG bias - momentum positivo + EMA alinhada UP" {
        It "retorna LONG: RSI 55, EMA9>EMA21, momentum +5%" {
            $b = Get-DirectionBias -Rsi 55 -Ema9 100 -Ema21 95 -MomentumPct 5.0
            $b | Should Be "LONG"
        }
        It "retorna LONG: RSI 70, EMA9>EMA21, momentum +3%" {
            $b = Get-DirectionBias -Rsi 70 -Ema9 105 -Ema21 100 -MomentumPct 3.0
            $b | Should Be "LONG"
        }
        It "retorna LONG: RSI 25 (oversold rebound), EMA9<EMA21, momentum +2% (recovery)" {
            # Oversold bounce: RSI baixo + momentum virou positivo
            $b = Get-DirectionBias -Rsi 25 -Ema9 95 -Ema21 100 -MomentumPct 2.0
            $b | Should Be "LONG"
        }
    }

    Context "SHORT bias - exhaustion ou breakdown" {
        It "retorna SHORT: RSI 80 (parabolic), EMA9<EMA21, momentum -4%" {
            $b = Get-DirectionBias -Rsi 80 -Ema9 95 -Ema21 100 -MomentumPct -4.0
            $b | Should Be "SHORT"
        }
        It "retorna SHORT: RSI 90 (extreme overbought), EMA9>EMA21, momentum -1%" {
            # Parabolic exhaustion mesmo com EMA up: RSI muito alto + momentum virou neg
            $b = Get-DirectionBias -Rsi 90 -Ema9 105 -Ema21 100 -MomentumPct -1.0
            $b | Should Be "SHORT"
        }
        It "retorna SHORT: RSI 45, EMA9<EMA21 (downtrend), momentum -6%" {
            $b = Get-DirectionBias -Rsi 45 -Ema9 95 -Ema21 100 -MomentumPct -6.0
            $b | Should Be "SHORT"
        }
    }

    Context "NEUTRAL - sinal misto ou range" {
        It "retorna NEUTRAL: RSI 50, EMA9==EMA21, momentum 0%" {
            $b = Get-DirectionBias -Rsi 50 -Ema9 100 -Ema21 100 -MomentumPct 0.0
            $b | Should Be "NEUTRAL"
        }
        It "retorna NEUTRAL: RSI 60, EMA9>EMA21, momentum -1% (conflicting)" {
            # EMA up mas momentum levemente neg: indeciso
            $b = Get-DirectionBias -Rsi 60 -Ema9 101 -Ema21 100 -MomentumPct -1.0
            $b | Should Be "NEUTRAL"
        }
    }

    Context "Edge cases" {
        It "trata Ema21 = 0 (proteçao divisão) -> NEUTRAL" {
            $b = Get-DirectionBias -Rsi 50 -Ema9 100 -Ema21 0 -MomentumPct 0.0
            $b | Should Be "NEUTRAL"
        }
        It "trata momentum NaN/extremo: usa apenas RSI+EMA" {
            $b = Get-DirectionBias -Rsi 80 -Ema9 100 -Ema21 95 -MomentumPct 100
            # RSI 80 + EMA up + momentum extremo +: LONG (continuation)
            $b | Should Be "LONG"
        }
    }
}
