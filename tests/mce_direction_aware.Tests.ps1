# mce_direction_aware.Tests.ps1 -- TDD Evolucao A+B 2026-07-06
# MCE direction-aware: SHORT nao pode ser bloqueado por fatores LONG-framed.
# Pester 3.x. UTF-8 BOM.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_market_context_engine.ps1")

Describe "Get-RegimeFactor direction-aware" {
    It "LONG default inalterado: BEAR_WEAK = 0.2" {
        (Get-RegimeFactor -Regime "BEAR_WEAK") | Should Be 0.2
    }
    It "LONG default inalterado: BEAR_STRONG = 0.0" {
        (Get-RegimeFactor -Regime "BEAR_STRONG") | Should Be 0.0
    }
    It "SHORT em BEAR_STRONG = 1.4 (pro-tendencia)" {
        (Get-RegimeFactor -Regime "BEAR_STRONG" -Direction "SHORT") | Should Be 1.4
    }
    It "SHORT em BEAR_WEAK = 1.3" {
        (Get-RegimeFactor -Regime "BEAR_WEAK" -Direction "SHORT") | Should Be 1.3
    }
    It "SHORT em BULL_STRONG = 0.3 (anti-trend penalizado)" {
        (Get-RegimeFactor -Regime "BULL_STRONG" -Direction "SHORT") | Should Be 0.3
    }
    It "SHORT em CAPITULATION = 1.1 (squeeze risk, nao 1.4)" {
        (Get-RegimeFactor -Regime "CAPITULATION" -Direction "SHORT") | Should Be 1.1
    }
    It "SHORT sem zeros na tabela (whitelist e a autoridade de skip)" {
        $regimes = @('BULL_STRONG','BULL_WEAK','SIDEWAYS','TRANSITION_UP','TRANSITION_DOWN','BEAR_WEAK','BEAR_STRONG','CAPITULATION')
        foreach ($r in $regimes) {
            (Get-RegimeFactor -Regime $r -Direction "SHORT") | Should BeGreaterThan 0
        }
    }
}

Describe "Get-ContextScore direction-aware" {
    It "SHORT neutraliza halving factor (1.0)" {
        $dt = [datetime]"2026-07-06 11:00"   # halving month 27 -> LONG 0.3
        $r = Get-ContextScore -DateBrt $dt -Regime "BEAR_WEAK" -Direction "SHORT"
        $r.halving | Should Be 1.0
    }
    It "LONG mantem halving factor do ciclo (0.3 em jul/2026)" {
        $dt = [datetime]"2026-07-06 11:00"
        $r = Get-ContextScore -DateBrt $dt -Regime "BEAR_WEAK"
        $r.halving | Should Be 0.3
    }
    It "FOMC bloqueia AMBAS as direcoes (macro 0.0 e evento binario)" {
        $dt = [datetime]"2026-07-29 11:00"   # FOMC
        $r = Get-ContextScore -DateBrt $dt -Regime "BEAR_WEAK" -Direction "SHORT"
        $r.score | Should Be 0.0
    }
}

Describe "Test-ContextAllowsTrade direction-aware" {
    It "SHORT em BEAR_WEAK segunda 11h NAO e BLOCK (era impossivel passar antes)" {
        $dt = [datetime]"2026-07-06 11:00"   # Monday golden hour
        $r = Test-ContextAllowsTrade -DateBrt $dt -Regime "BEAR_WEAK" -Direction "SHORT"
        $r.action | Should Not Be "BLOCK"
    }
    It "SHORT em BEAR_STRONG segunda 11h chega a LIVE_FULL" {
        $dt = [datetime]"2026-07-06 11:00"
        # dow 1.2 x season 1.1 x halving 1.0 x session 1.0 x macro 1.0 x regime 1.4 = 1.848
        $r = Test-ContextAllowsTrade -DateBrt $dt -Regime "BEAR_STRONG" -Direction "SHORT"
        $r.action | Should Be "LIVE_FULL"
    }
    It "LONG em BEAR_WEAK mantem comportamento original (BLOCK/PAPER)" {
        $dt = [datetime]"2026-07-06 11:00"
        $r = Test-ContextAllowsTrade -DateBrt $dt -Regime "BEAR_WEAK"
        $r.action -in @("BLOCK","PAPER_ONLY") | Should Be $true
    }
    It "resultado carrega direction pra auditoria" {
        $dt = [datetime]"2026-07-06 11:00"
        $r = Test-ContextAllowsTrade -DateBrt $dt -Regime "BEAR_WEAK" -Direction "SHORT"
        $r.direction | Should Be "SHORT"
    }
}

Describe "Fatores dinamicos direction-aware" {
    It "FearGreed 85 (Extreme Greed): LONG 0.5, SHORT 1.4" {
        (Get-FearGreedFactor -Score 85) | Should Be 0.5
        (Get-FearGreedFactor -Score 85 -Direction "SHORT") | Should Be 1.4
    }
    It "FearGreed 15 (Extreme Fear): LONG 1.4, SHORT 0.6 (squeeze risk)" {
        (Get-FearGreedFactor -Score 15) | Should Be 1.4
        (Get-FearGreedFactor -Score 15 -Direction "SHORT") | Should Be 0.6
    }
    It "Funding 0.12 (longs excessivos): LONG 0.6, SHORT 1.3" {
        (Get-FundingRateFactor -Rate 0.12) | Should Be 0.6
        (Get-FundingRateFactor -Rate 0.12 -Direction "SHORT") | Should Be 1.3
    }
    It "Funding -0.08 (shorts crowded): LONG 1.3, SHORT 0.6" {
        (Get-FundingRateFactor -Rate -0.08) | Should Be 1.3
        (Get-FundingRateFactor -Rate -0.08 -Direction "SHORT") | Should Be 0.6
    }
    It "ETF outflow forte -300M: LONG 0.5, SHORT 1.3" {
        (Get-EtfFlowFactor -FlowMillions -300) | Should Be 0.5
        (Get-EtfFlowFactor -FlowMillions -300 -Direction "SHORT") | Should Be 1.3
    }
    It "DXY UP_STRONG: LONG 0.6, SHORT 1.3" {
        (Get-DxyFactor -Trend "UP_STRONG") | Should Be 0.6
        (Get-DxyFactor -Trend "UP_STRONG" -Direction "SHORT") | Should Be 1.3
    }
    It "dado ausente = fail-open 1.0 em ambas direcoes" {
        (Get-FearGreedFactor -Score $null -Direction "SHORT") | Should Be 1.0
        (Get-FundingRateFactor -Rate $null -Direction "SHORT") | Should Be 1.0
        (Get-EtfFlowFactor -FlowMillions $null -Direction "SHORT") | Should Be 1.0
        (Get-DxyFactor -Trend "" -Direction "SHORT") | Should Be 1.0
    }
    It "Get-DynamicContextScore propaga Direction" {
        $long  = Get-DynamicContextScore -FearGreed 85 -FundingRate 0.12
        $short = Get-DynamicContextScore -FearGreed 85 -FundingRate 0.12 -Direction "SHORT"
        $short.dynamic_score | Should BeGreaterThan $long.dynamic_score
    }
}
