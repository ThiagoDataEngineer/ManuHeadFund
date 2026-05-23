# triagem_regime_hybrid.Tests.ps1 -- HYBRID fix 2026-05-21.
# Pester 3.x.
#
# Bug: triagem usa change_24h + macro fallback, mas backtest STRUCTURAL_BREAK
# foi calculado com SMA200+ADX semantics. Sistema vetava BTC consolidando
# intraday como BULL_WEAK (-1%a+2% range, macro=BULLISH fallback) ativando
# blacklist baseada em regime DIFERENTE.
#
# Fix: quando EMA200+ADX disponiveis, usar backtest semantics. Senao fallback.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "triagem_agent.ps1")


Describe "_Compute-RegimeFromContext - HYBRID (backtest semantics)" {

    It "Sem tech data + change<+2% +BULLISH = BULL_WEAK (legacy fallback preservado)" {
        $r = _Compute-RegimeFromContext -Score 50 -MacroBias "BULLISH" -PairChange24h 1.0
        $r | Should Be "BULL_WEAK"
    }

    It "Com tech data: price>ema200 + ADX>25 + PDI>NDI = BULL_STRONG" {
        $r = _Compute-RegimeFromContext -Score 50 -MacroBias "BULLISH" -PairChange24h 1.0 `
            -CurrentPrice 100 -Ema200 90 -Adx 30 -Pdi 28 -Ndi 18
        $r | Should Be "BULL_STRONG"
    }

    It "Com tech data: price>ema200 + ADX<=25 = BULL_WEAK (backtest condition)" {
        $r = _Compute-RegimeFromContext -Score 50 -MacroBias "BULLISH" -PairChange24h 1.0 `
            -CurrentPrice 100 -Ema200 90 -Adx 20 -Pdi 18 -Ndi 16
        $r | Should Be "BULL_WEAK"
    }

    It "Com tech data: price<ema200 + ADX<=25 = BEAR_WEAK (override macro BULLISH)" {
        # Cenario critico: macro BULLISH mas asset abaixo EMA200 -> respeitar SMA structural
        $r = _Compute-RegimeFromContext -Score 50 -MacroBias "BULLISH" -PairChange24h 1.0 `
            -CurrentPrice 80 -Ema200 90 -Adx 15 -Pdi 12 -Ndi 14
        $r | Should Be "BEAR_WEAK"
    }

    It "Com tech data: price<ema200 + ADX>25 + NDI>PDI = BEAR_STRONG" {
        $r = _Compute-RegimeFromContext -Score 50 -MacroBias "BULLISH" -PairChange24h 1.0 `
            -CurrentPrice 80 -Ema200 90 -Adx 35 -Pdi 15 -Ndi 28
        $r | Should Be "BEAR_STRONG"
    }

    It "Change >= +15% sempre BULL_STRONG (pump forte, ignora tech)" {
        # Pumps fortes nao precisam de SMA200 check
        $r = _Compute-RegimeFromContext -Score 50 -MacroBias "BEARISH" -PairChange24h 20 `
            -CurrentPrice 50 -Ema200 100 -Adx 10
        $r | Should Be "BULL_STRONG"
    }

    It "Change <= -8% sempre BEAR_STRONG (crash forte, ignora tech)" {
        $r = _Compute-RegimeFromContext -Score 50 -MacroBias "BULLISH" -PairChange24h -10 `
            -CurrentPrice 200 -Ema200 100 -Adx 30 -Pdi 28 -Ndi 16
        $r | Should Be "BEAR_STRONG"
    }
}


Describe "_Compute-RegimeFromContext - Anti-regression BTC 2026-05-21" {

    It "BTC consolidando intraday + EMA200 abaixo do price + ADX fraco -> BULL_WEAK valido" {
        # Cenario real BTC hoje: change 24h ~ +1% intraday consolidando
        # Se BTC EMA200 daily < price atual (BTC ~$77k > ema200 ~$70k em recovery)
        # e ADX baixo (consolidacao), BULL_WEAK eh classification VALIDA.
        $r = _Compute-RegimeFromContext -Score 70 -MacroBias "BULLISH" -PairChange24h 1.5 `
            -CurrentPrice 77000 -Ema200 70000 -Adx 18 -Pdi 17 -Ndi 16
        $r | Should Be "BULL_WEAK"
    }

    It "BTC abaixo de EMA200 + macro BULLISH -> BEAR_WEAK (corrige veto incorreto)" {
        # Se BTC realmente esta abaixo EMA200, sistema NAO deve dizer BULL_WEAK pura
        # macro fallback. Era a fonte do bug: vetava como BULL_WEAK mesmo BTC bear.
        $r = _Compute-RegimeFromContext -Score 70 -MacroBias "BULLISH" -PairChange24h 0.8 `
            -CurrentPrice 65000 -Ema200 75000 -Adx 18 -Pdi 16 -Ndi 17
        $r | Should Be "BEAR_WEAK"
    }
}
