# lib_market_scenario.Tests.ps1 -- Pester 3.x
# TDD 2026-06-24: motor de CENARIO (identifica regime -> estrategia com edge).
# "Sempre ganhar" = sempre escolher a estrategia certa pro cenario:
#   CAPITULACAO -> comprar fundo (LONG) | BEAR -> SHORT/caixa | BULL -> LONG | NEUTRO -> esperar.
# Capitulacao (BEAR_MARKET.md Fase 3 / Weinstein): RSI extremo + volume climatico + queda profunda.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_market_scenario.ps1")

Describe "Test-Capitulation - detecta o fundo (Fase 3)" {
    It "RSI extremo + volume climatico + abaixo da 200 -> CAPITULACAO" {
        (Test-Capitulation -Rsi 24 -VolRatio 2.2 -Price 52000 -Ema200 77000).is_capitulation | Should Be $true
    }
    It "RSI baixo mas SEM volume climatico -> NAO e capitulacao (so queda)" {
        (Test-Capitulation -Rsi 28 -VolRatio 1.0 -Price 52000 -Ema200 77000).is_capitulation | Should Be $false
    }
    It "Volume alto mas RSI nao extremo -> NAO" {
        (Test-Capitulation -Rsi 42 -VolRatio 2.5 -Price 60000 -Ema200 77000).is_capitulation | Should Be $false
    }
    It "Acima da 200 (nao e bear profundo) -> NAO" {
        (Test-Capitulation -Rsi 25 -VolRatio 2.0 -Price 80000 -Ema200 77000).is_capitulation | Should Be $false
    }
}

Describe "Resolve-MarketScenario - cenario -> estrategia com edge" {
    It "Capitulacao -> ACUMULA LONG (compra o fundo)" {
        $r = Resolve-MarketScenario -Price 52000 -Ema20 64000 -Ema50 68000 -Ema200 77000 -Rsi 24 -Momentum30dPct -28 -VolRatio 2.2
        $r.scenario | Should Be "CAPITULACAO"
        $r.allow_long | Should Be $true
        $r.allow_short | Should Be $false
    }
    It "Bear sem capitulacao -> SHORT/caixa (bloqueia LONG)" {
        $r = Resolve-MarketScenario -Price 60800 -Ema20 64300 -Ema50 68200 -Ema200 77000 -Rsi 38 -Momentum30dPct -19.9 -VolRatio 1.0
        $r.scenario | Should Be "BEAR"
        $r.allow_long | Should Be $false
        $r.allow_short | Should Be $true
    }
    It "Bull -> LONG (sem short)" {
        $r = Resolve-MarketScenario -Price 72000 -Ema20 68000 -Ema50 66000 -Ema200 64000 -Rsi 58 -Momentum30dPct 12 -VolRatio 1.1
        $r.scenario | Should Be "BULL"
        $r.allow_long | Should Be $true
        $r.allow_short | Should Be $false
    }
    It "Neutro/chop -> ESPERA (nem long nem short)" {
        $r = Resolve-MarketScenario -Price 65000 -Ema20 65100 -Ema50 64900 -Ema200 66000 -Rsi 50 -Momentum30dPct 1 -VolRatio 1.0
        $r.scenario | Should Be "NEUTRO"
        $r.allow_long | Should Be $false
        $r.allow_short | Should Be $false
    }
    It "Dados invalidos -> UNKNOWN fail-safe (nao bloqueia por dado ruim)" {
        $r = Resolve-MarketScenario -Price 0 -Ema20 0 -Ema50 0 -Ema200 0 -Rsi 0 -Momentum30dPct 0 -VolRatio 0
        $r.scenario | Should Be "UNKNOWN"
        $r.allow_long | Should Be $true
    }
}
