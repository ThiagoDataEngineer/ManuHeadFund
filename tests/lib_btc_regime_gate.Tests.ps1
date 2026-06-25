# lib_btc_regime_gate.Tests.ps1 -- Pester 3.x
# TDD 2026-06-24: BTC-core gate. Causa real das perdas: sistema comprou alt LONG
# durante BTC -20%/mes (alt sangra 2-4x BTC em bear). Bloqueia LONG de alt quando
# BTC em downtrend confirmado. SHORT liberado (bear favorece short).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_btc_regime_gate.ps1")

Describe "Test-BtcRegimeGate" {
    It "LONG alt + BTC bear confirmado (abaixo EMA20+EMA50, mom<0) -> BLOQUEIA" {
        $r = Test-BtcRegimeGate -Direction "LONG" -Price 60800 -Ema20 64300 -Ema50 68200 -Momentum30dPct -19.9
        $r.allowed | Should Be $false
        $r.reason | Should Be "btc_bear_blocks_long_alt"
    }
    It "SHORT alt + BTC bear -> LIBERA (bear favorece short)" {
        (Test-BtcRegimeGate -Direction "SHORT" -Price 60800 -Ema20 64300 -Ema50 68200 -Momentum30dPct -19.9).allowed | Should Be $true
    }
    It "LONG alt + BTC acima da EMA20 (nao bear) -> LIBERA" {
        (Test-BtcRegimeGate -Direction "LONG" -Price 70000 -Ema20 68000 -Ema50 66000 -Momentum30dPct 5).allowed | Should Be $true
    }
    It "LONG + abaixo EMA20 MAS momentum positivo -> LIBERA (nao e bear pleno)" {
        (Test-BtcRegimeGate -Direction "LONG" -Price 63000 -Ema20 64000 -Ema50 62000 -Momentum30dPct 8).allowed | Should Be $true
    }
    It "Dados invalidos (EMA<=0) -> LIBERA (fail-safe, nao trava por dado ruim)" {
        (Test-BtcRegimeGate -Direction "LONG" -Price 60000 -Ema20 0 -Ema50 0 -Momentum30dPct -19).allowed | Should Be $true
    }
}
