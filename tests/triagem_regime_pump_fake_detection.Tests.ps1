# triagem_regime_pump_fake_detection.Tests.ps1
# TDD: Opção 1 — Detectar pump fake: BULL_STRONG só com confirmação técnica
# UTF-8 BOM. Pester 3.x.

. "$PSScriptRoot\..\agents\triagem_agent.ps1"

Describe "Regime pump fake detection - Tech confirmation required for BULL_STRONG" {

    Context "BULL_STRONG validation (change >= +15%)" {

        It "Change +112% SEM tech data (legacy) retorna BULL_STRONG (compat)" {
            # Legacy path: sem EMA/ADX, usa só change
            $r = _Compute-RegimeFromContext -Score 60 -MacroBias "BEARISH" -PairChange24h 112.0
            $r | Should Be "BULL_STRONG"
        }

        It "Change +112% COM tech: preco ACIMA EMA200 + ADX>25 + PDI>NDI retorna BULL_STRONG" {
            # Confirmação técnica: uptrend estrutural
            $r = _Compute-RegimeFromContext `
                -Score 60 `
                -MacroBias "BEARISH" `
                -PairChange24h 112.0 `
                -CurrentPrice 2.5 `
                -Ema200 2.0 `
                -Adx 35.0 `
                -Pdi 45.0 `
                -Ndi 20.0
            $r | Should Be "BULL_STRONG"
        }

        It "Change +112% COM tech: preco ABAIXO EMA200 retorna BEAR_WEAK (pump fake)" {
            # Pump fake: preço subiu mas ainda abaixo EMA200 = não é trend válido
            $r = _Compute-RegimeFromContext `
                -Score 60 `
                -MacroBias "BEARISH" `
                -PairChange24h 112.0 `
                -CurrentPrice 1.5 `
                -Ema200 2.0 `
                -Adx 35.0 `
                -Pdi 45.0 `
                -Ndi 20.0
            $r | Should Be "BEAR_WEAK"
        }

        It "Change +112% COM tech: preco ACIMA EMA200 MAS ADX<=25 (sem força) retorna BULL_WEAK" {
            # Preco recuperou mas sem força de trend (ADX baixo)
            $r = _Compute-RegimeFromContext `
                -Score 60 `
                -MacroBias "BEARISH" `
                -PairChange24h 112.0 `
                -CurrentPrice 2.5 `
                -Ema200 2.0 `
                -Adx 18.0 `
                -Pdi 45.0 `
                -Ndi 20.0
            $r | Should Be "BULL_WEAK"
        }

        It "Change +112% COM tech: preco ACIMA EMA200 MAS NDI>PDI (downtrend em ADX>25) retorna BEAR_STRONG" {
            # Pump em meio a downtrend estrutural
            $r = _Compute-RegimeFromContext `
                -Score 60 `
                -MacroBias "BEARISH" `
                -PairChange24h 112.0 `
                -CurrentPrice 2.5 `
                -Ema200 2.0 `
                -Adx 35.0 `
                -Pdi 20.0 `
                -Ndi 45.0
            $r | Should Be "BEAR_STRONG"
        }
    }

    Context "Change +5-15% range (ambiguo, requer confirmacao)" {

        It "Change +7% macro BEARISH + tech acima EMA200 + ADX>25 + PDI>NDI retorna BULL_STRONG" {
            $r = _Compute-RegimeFromContext `
                -Score 60 `
                -MacroBias "BEARISH" `
                -PairChange24h 7.0 `
                -CurrentPrice 2.5 `
                -Ema200 2.0 `
                -Adx 30.0 `
                -Pdi 40.0 `
                -Ndi 15.0
            $r | Should Be "BULL_STRONG"
        }

        It "Change +7% macro BEARISH + tech acima EMA200 MAS ADX<=25 retorna BULL_WEAK" {
            $r = _Compute-RegimeFromContext `
                -Score 60 `
                -MacroBias "BEARISH" `
                -PairChange24h 7.0 `
                -CurrentPrice 2.5 `
                -Ema200 2.0 `
                -Adx 15.0 `
                -Pdi 40.0 `
                -Ndi 15.0
            $r | Should Be "BULL_WEAK"
        }
    }

    Context "Backward compatibility: sem tech data usa legacy rules" {

        It "Change +112% SEM tech data (EMA200=$null) retorna BULL_STRONG (legacy)" {
            $r = _Compute-RegimeFromContext -Score 60 -MacroBias "BEARISH" -PairChange24h 112.0 -Ema200 $null
            $r | Should Be "BULL_STRONG"
        }

        It "Change +112% COM CurrentPrice=$null ignora tech (fallback legacy)" {
            $r = _Compute-RegimeFromContext `
                -Score 60 `
                -MacroBias "BEARISH" `
                -PairChange24h 112.0 `
                -CurrentPrice $null `
                -Ema200 2.0 `
                -Adx 35.0 `
                -Pdi 45.0 `
                -Ndi 20.0
            $r | Should Be "BULL_STRONG"
        }
    }

}

Describe "Invoke-Triagem respects pump fake detection (regime only)" {

    It "WLDUSDT score=112 +change=+112% macro=BEARISH + NO tech data retorna regime=BULL_STRONG (legacy)" {
        # Sem tech data, regime é direto baseado em change
        $ctx = [PSCustomObject]@{
            scanner = @{ score = 112; change = 112.0 }
            macro = @{ macro_bias = "BEARISH" }
            seasonal = @{ dayOfWeek = "Tuesday"; marketTier = "alt" }
        }
        $tri = Invoke-Triagem -Market "WLDUSDT" -Context $ctx
        $tri.regime | Should Be "BULL_STRONG"  # legacy: change >= +15% retorna BULL_STRONG sem tech
    }

    It "WLDUSDT score=112 +change=+112% + ABAIXO EMA200 detecta pump fake regime=BEAR_WEAK" {
        # Com tech: detecta pump fake BEAR_WEAK
        $ctx = [PSCustomObject]@{
            scanner = @{ score = 112; change = 112.0 }
            macro = @{ macro_bias = "BEARISH" }
            seasonal = @{ dayOfWeek = "Tuesday"; marketTier = "alt" }
            tech = @{ current_price = 1.5; ema200 = 2.0; adx = 35.0; pdi = 45.0; ndi = 20.0 }
        }
        $tri = Invoke-Triagem -Market "WLDUSDT" -Context $ctx
        $tri.regime | Should Be "BEAR_WEAK"  # pump fake detectado (preco < EMA200)
    }

    It "WLDUSDT +change=+112% ACIMA EMA200 + ADX>25 + uptrend detecta BULL_STRONG legitimo" {
        $ctx = [PSCustomObject]@{
            scanner = @{ score = 112; change = 112.0; current_price = 2.5 }
            macro = @{ macro_bias = "BEARISH" }
            seasonal = @{ dayOfWeek = "Tuesday"; marketTier = "btc" }
            tech = @{ ema200 = 2.0; adx = 35.0; pdi = 45.0; ndi = 20.0 }
        }
        $tri = Invoke-Triagem -Market "WLDUSDT" -Context $ctx
        $tri.regime | Should Be "BULL_STRONG"  # validado: acima EMA200 + ADX>25 + PDI>NDI
    }
}
