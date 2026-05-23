# triagem_regime_per_pair.Tests.ps1
# TDD: regime classifier per-pair (pair change_24h), nao macro-only.
# UTF-8 BOM. Pester 3.x.

. "$PSScriptRoot\..\agents\triagem_agent.ps1"

Describe "Regime per-pair v3 - PairChange24h dominates" {

    It "BUSDT change -13 percent retorna BEAR_STRONG" {
        $r = _Compute-RegimeFromContext -Score 50 -MacroBias "BULLISH" -PairChange24h -13.0
        $r | Should Be "BEAR_STRONG"
    }

    It "STORJ change plus 18 percent retorna BULL_STRONG" {
        $r = _Compute-RegimeFromContext -Score 50 -MacroBias "BEARISH" -PairChange24h 18.0
        $r | Should Be "BULL_STRONG"
    }

    It "Change -25 percent retorna CAPITULATION" {
        $r = _Compute-RegimeFromContext -Score 50 -MacroBias "BULLISH" -PairChange24h -25.0
        $r | Should Be "CAPITULATION"
    }

    It "Change -5 percent retorna BEAR_WEAK" {
        $r = _Compute-RegimeFromContext -Score 50 -MacroBias "BULLISH" -PairChange24h -5.0
        $r | Should Be "BEAR_WEAK"
    }

    It "Change plus 7 percent macro BULLISH retorna BULL_STRONG" {
        $r = _Compute-RegimeFromContext -Score 70 -MacroBias "BULLISH" -PairChange24h 7.0
        $r | Should Be "BULL_STRONG"
    }

    It "Change plus 7 percent macro NEUTRAL retorna BULL_WEAK" {
        $r = _Compute-RegimeFromContext -Score 60 -MacroBias "NEUTRAL" -PairChange24h 7.0
        $r | Should Be "BULL_WEAK"
    }

    It "Change plus 3 percent retorna TRANSITION_UP" {
        $r = _Compute-RegimeFromContext -Score 50 -MacroBias "NEUTRAL" -PairChange24h 3.0
        $r | Should Be "TRANSITION_UP"
    }

    It "Change zero macro NEUTRAL retorna SIDEWAYS" {
        $r = _Compute-RegimeFromContext -Score 50 -MacroBias "NEUTRAL" -PairChange24h 0.0
        $r | Should Be "SIDEWAYS"
    }

    It "Sem PairChange24h backward compat usa macro" {
        $r = _Compute-RegimeFromContext -Score 50 -MacroBias "BEARISH"
        $r | Should Be "BEAR_WEAK"
    }
}
