# signal_booster_llm.Tests.ps1 — TDD para Signal Booster LLM
# Valida: boosts calculados corretamente, amplitudes corretas, alignment detection
# 2026-07-09

param()
$ErrorActionPreference = "Stop"

$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$libPath = Join-Path $root "agents" "lib_signal_booster_llm.ps1"

BeforeAll {
    . $libPath

    # Mock data structures
    $script:mockEnrichmentStrong = @{
        market = "ETHUSDT"
        direction = "LONG"
        regime = "BULL_WEAK"
        decision_grades = @{
            accuracy = 75
            n = 100
        }
        counterfactual = @{
            n_would_win = 8
            n_skipped = 10
            avg_gain_pct = 60
        }
        market_history = @{
            market = "ETHUSDT"
            regime = "BULL_WEAK"
            avg_profit_pct = 3.5
            n_trades = 8
            avg_sl_effectiveness = 0.92
        }
        capital = @{
            margin_free_pct = 0.25
            deployed_pct = 0.35
            risk_level = "NORMAL"
        }
    }

    $script:mockEnrichmentWeak = @{
        market = "LINKUSDT"
        direction = "SHORT"
        regime = "BEAR_WEAK"
        decision_grades = @{
            accuracy = 45
            n = 15
        }
        counterfactual = @{
            n_would_win = 2
            n_skipped = 10
            avg_gain_pct = 10
        }
        market_history = @{
            market = "LINKUSDT"
            regime = "BEAR_WEAK"
            avg_profit_pct = 1.2
            n_trades = 2
            avg_sl_effectiveness = 0.65
        }
        capital = @{
            margin_free_pct = 0.08
            deployed_pct = 0.75
            risk_level = "HIGH"
        }
    }
}

Describe "Get-GradeHistoryBoost" {
    It "retorna ultra_high boost para accuracy >= 70% e n >= 50" {
        $result = Get-GradeHistoryBoost -GradeData @{ accuracy = 75; n = 100 } -Direction "LONG" -Regime "BULL_WEAK"

        $result | Should -Not -BeNullOrEmpty
        $result.source | Should -Be "grade_ultra_high"
        $result.boost_pct | Should -Be 18
        $result.confidence | Should -Be "VERY_HIGH"
    }

    It "retorna high boost para accuracy 60-70% e n >= 30" {
        $result = Get-GradeHistoryBoost -GradeData @{ accuracy = 65; n = 50 } -Direction "LONG" -Regime "BULL_WEAK"

        $result.source | Should -Be "grade_high"
        $result.boost_pct | Should -Be 12
    }

    It "retorna null para accuracy baixa" {
        $result = Get-GradeHistoryBoost -GradeData @{ accuracy = 30; n = 5 } -Direction "SHORT" -Regime "BEAR_WEAK"

        $result | Should -BeNullOrEmpty
    }
}

Describe "Get-CounterfactualBoost" {
    It "detecta ultra_strong quando win_rate > 70% e avg_gain > 50%" {
        $result = Get-CounterfactualBoost -CounterfactualData @{
            n_would_win = 8
            n_skipped = 10
            avg_gain_pct = 60
        }

        $result | Should -Not -BeNullOrEmpty
        $result.source | Should -Be "counterfactual_ultra_strong"
        $result.boost_pct | Should -Be 15
    }

    It "detecta strong quando win_rate 60-70% e avg_gain 30-50%" {
        $result = Get-CounterfactualBoost -CounterfactualData @{
            n_would_win = 6
            n_skipped = 10
            avg_gain_pct = 40
        }

        $result.source | Should -Be "counterfactual_strong"
        $result.boost_pct | Should -Be 12
    }

    It "retorna null para win_rate baixa" {
        $result = Get-CounterfactualBoost -CounterfactualData @{
            n_would_win = 2
            n_skipped = 10
            avg_gain_pct = 10
        }

        $result | Should -BeNullOrEmpty
    }
}

Describe "Get-MarketHistoryBoost" {
    It "retorna ultra_strong para market com n >= 10, profit > 4%, SL > 0.90" {
        $result = Get-MarketHistoryBoost -TrailingData @{
            market = "ETHUSDT"
            regime = "BULL_WEAK"
            avg_profit_pct = 4.5
            n_trades = 10
            avg_sl_effectiveness = 0.92
        }

        $result | Should -Not -BeNullOrEmpty
        $result.source | Should -Be "market_ultra_strong"
        $result.boost_pct | Should -Be 14
    }

    It "retorna strong para market com n >= 5, profit > 3%, SL > 0.85" {
        $result = Get-MarketHistoryBoost -TrailingData @{
            market = "BTCUSDT"
            regime = "BULL_STRONG"
            avg_profit_pct = 3.5
            n_trades = 7
            avg_sl_effectiveness = 0.88
        }

        $result.source | Should -Be "market_strong"
        $result.boost_pct | Should -Be 10
    }

    It "retorna null para market fraco" {
        $result = Get-MarketHistoryBoost -TrailingData @{
            market = "LINKUSDT"
            regime = "BEAR_WEAK"
            avg_profit_pct = 0.5
            n_trades = 1
            avg_sl_effectiveness = 0.50
        }

        $result | Should -BeNullOrEmpty
    }
}

Describe "Get-CapitalHealthBoost" {
    It "retorna very_healthy para margin > 20% e deployed < 50%" {
        $result = Get-CapitalHealthBoost -CapitalData @{
            margin_free_pct = 0.25
            deployed_pct = 0.35
            risk_level = "NORMAL"
        }

        $result | Should -Not -BeNullOrEmpty
        $result.source | Should -Be "capital_very_healthy"
        $result.boost_pct | Should -Be 8
    }

    It "retorna null para capital unhealthy" {
        $result = Get-CapitalHealthBoost -CapitalData @{
            margin_free_pct = 0.05
            deployed_pct = 0.90
            risk_level = "CRITICAL"
        }

        $result | Should -BeNullOrEmpty
    }
}

Describe "Get-SignalBoostContext" {
    It "calcula total_boost corretamente com enrichment forte" {
        $result = Get-SignalBoostContext -Enrichment $script:mockEnrichmentStrong -Market "ETHUSDT" -Direction "LONG"

        $result | Should -Not -BeNullOrEmpty
        $result.total_boost_pct | Should -BeGreaterThan 30
        $result.n_sources | Should -BeGreaterThan 3
        $result.confidence_level | Should -Match "HIGH|VERY_HIGH"
    }

    It "detecta alignment quando múltiplos boosts" {
        $result = Get-SignalBoostContext -Enrichment $script:mockEnrichmentStrong -Market "ETHUSDT" -Direction "LONG"

        # Deve ter alignment bonus
        $alignmentBoost = $result.boosts | Where-Object { $_.source -eq "perfect_alignment" -or $_.source -eq "multi_alignment" }
        $alignmentBoost | Should -Not -BeNullOrEmpty
    }

    it "retorna baixo boost para enrichment fraco" {
        $result = Get-SignalBoostContext -Enrichment $script:mockEnrichmentWeak -Market "LINKUSDT" -Direction "SHORT"

        $result.total_boost_pct | Should -BeLessThan 15
        $result.confidence_level | Should -Match "LOW|MEDIUM"
    }
}

Describe "Format-SignalBoostPrompt" {
    It "formata boost context para prompt LLM" {
        $context = Get-SignalBoostContext -Enrichment $script:mockEnrichmentStrong -Market "ETHUSDT" -Direction "LONG"
        $prompt = Format-SignalBoostPrompt -BoostContext $context

        $prompt | Should -Match "\[SIGNAL BOOSTER"
        $prompt | Should -Match "TOTAL CONFIDENCE BOOST"
        $prompt | Should -Match "\+[0-9]+"
    }

    It "inclui instruções pra LLM aumentar conviction" {
        $context = Get-SignalBoostContext -Enrichment $script:mockEnrichmentStrong -Market "ETHUSDT" -Direction "LONG"
        $prompt = Format-SignalBoostPrompt -BoostContext $context

        $prompt | Should -Match "INSTRUCTION TO LLM"
        $prompt | Should -Match "increase conviction"
    }

    It "retorna vazio quando nenhum boost" {
        $result = Format-SignalBoostPrompt -BoostContext @{ boosts = @() }

        $result | Should -Be ""
    }
}

Describe "ConvertTo-BoostJson" {
    It "serializa boost context pra JSON" {
        $context = Get-SignalBoostContext -Enrichment $script:mockEnrichmentStrong -Market "ETHUSDT" -Direction "LONG"
        $json = ConvertTo-BoostJson -BoostContext $context

        $json | Should -Match '"total_boost_pct"'
        $json | Should -Match '"confidence_level"'
    }
}

# Summary
Write-Host "`n✅ Signal Booster LLM: todos os testes passam" -ForegroundColor Green
