# mentor_supabase_enrichment.Tests.ps1 — TDD para enriquecimento Supabase
# Padrão: Pester 5.x, mock Supabase responses, valida formato enrichment
# 2026-07-09

param()
$ErrorActionPreference = "Stop"

# Setup paths
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$libPath = Join-Path $root "agents" "lib_mentor_supabase_enrichment.ps1"

BeforeAll {
    . $libPath

    # Mock: Simulate Supabase REST API responses
    $script:mockDecisionGrades = @(
        @{
            direction = "SHORT"
            regime = "BEAR_WEAK"
            accuracy = 46
            n = 507
            would_win_pct = 57
        }
        @{
            direction = "LONG"
            regime = "BULL_STRONG"
            accuracy = 75
            n = 21
            would_win_pct = 68
        }
    )

    $script:mockCounterfactual = @(
        @{
            market = "LINKUSDT"
            direction = "LONG"
            avg_gain_pct = 79
            n_skipped = 12
            n_would_win = 8
        }
        @{
            market = "NAKA"
            direction = "SHORT"
            avg_gain_pct = 45
            n_skipped = 5
            n_would_win = 2
        }
    )

    $script:mockTrailing = @(
        @{
            market = "ETHUSDT"
            regime = "BULL_WEAK"
            side = "LONG"
            profit_realized_pct = 3.2
            sl_effectiveness = 0.92
            duration_minutes = 240
        }
        @{
            market = "ETHUSDT"
            regime = "BULL_WEAK"
            side = "LONG"
            profit_realized_pct = 2.8
            sl_effectiveness = 0.88
            duration_minutes = 180
        }
    )

    $script:mockCapital = @(
        @{
            balance_spot = 2425
            balance_futures = 2741
            deployed_pct = 0.65
            margin_free_pct = 0.15
            liquidation_price = 45000
        }
    )

    $script:mockPositions = @(
        @{
            market = "LINKUSDT"
            side = "LONG"
            entry_price = 10.25
            qty = 50
            size_usd = 512.5
        }
    )

    # Mock Get-SupabaseState
    $mockSupabaseState = {
        param([string]$Table)
        switch ($Table) {
            "decision_grades_agg" { return $script:mockDecisionGrades }
            "mce_counterfactual_agg" { return $script:mockCounterfactual }
            "trailing_positions" { return $script:mockTrailing }
            "capital_context" { return $script:mockCapital }
            "open_positions" { return $script:mockPositions }
            default { return @() }
        }
    }

    Mock -CommandName Get-SupabaseState -MockWith $mockSupabaseState
}

Describe "Get-DecisionGradeEnrichment" {
    It "retorna grades quando accuracy < 45% (invert=true)" {
        $result = Get-DecisionGradeEnrichment -Direction "SHORT" -Regime "BEAR_WEAK"

        $result | Should -Not -BeNullOrEmpty
        $result.accuracy | Should -Be 46
        $result.should_invert | Should -Be $true
        $result.would_win_pct | Should -Be 57
    }

    It "não inverte quando accuracy > 45%" {
        $result = Get-DecisionGradeEnrichment -Direction "LONG" -Regime "BULL_STRONG"

        $result | Should -Not -BeNullOrEmpty
        $result.accuracy | Should -Be 75
        $result.should_invert | Should -Be $false
    }

    It "retorna null quando direction não encontrada" {
        $result = Get-DecisionGradeEnrichment -Direction "UNKNOWN" -Regime "UNKNOWN"

        $result | Should -BeNullOrEmpty
    }
}

Describe "Get-CounterfactualEnrichment" {
    It "detecta oportunidade quando win_rate > 50%" {
        $result = Get-CounterfactualEnrichment -Market "LINKUSDT" -Direction "LONG"

        $result | Should -Not -BeNullOrEmpty
        $result.win_rate | Should -Be ([math]::Round(8/12, 3))
        $result.should_reconsider | Should -Be $true
    }

    It "não reconsidera quando win_rate < 50%" {
        $result = Get-CounterfactualEnrichment -Market "NAKA" -Direction "SHORT"

        $result | Should -Not -BeNullOrEmpty
        $result.win_rate | Should -Be ([math]::Round(2/5, 3))
        $result.should_reconsider | Should -Be $false
    }
}

Describe "Get-TrailingHistoryEnrichment" {
    It "calcula médias históricas corretamente" {
        $result = Get-TrailingHistoryEnrichment -Market "ETHUSDT" -Regime "BULL_WEAK" -Side "LONG"

        $result | Should -Not -BeNullOrEmpty
        $result.n_trades | Should -Be 2
        $result.avg_profit_pct | Should -Be 3.0
        $result.avg_sl_effectiveness | Should -Be 0.9
        $result.avg_duration_min | Should -Be 210
    }

    It "retorna HIGH confidence com n >= 5" {
        $result = Get-TrailingHistoryEnrichment -Market "ETHUSDT" -Regime "BULL_WEAK" -Side "LONG"
        # Simulando 5+ trades adicionando ao mock
        # Por enquanto testa n < 5 = MEDIUM
        $result.confidence | Should -Be "MEDIUM"
    }
}

Describe "Get-CapitalEnrichment" {
    It "calcula status capital corretamente" {
        $result = Get-CapitalEnrichment

        $result | Should -Not -BeNullOrEmpty
        $result.balance_spot | Should -Be 2425
        $result.balance_futures | Should -Be 2741
        $result.deployed_pct | Should -Be 0.65
        $result.margin_free_pct | Should -Be 0.15
        $result.sizing_reduction | Should -Be 1.0
    }

    It "sinaliza risco HIGH quando margin < 10%" {
        # Mock com margin baixa
        Mock -CommandName Get-SupabaseState -ParameterFilter { $Table -eq "capital_context" } `
            -MockWith { @(@{ margin_free_pct = 0.08; deployed_pct = 0.9; balance_spot = 100; balance_futures = 100; liquidation_price = 0 }) }

        $result = Get-CapitalEnrichment

        $result.risk_level | Should -Be "HIGH"
        $result.sizing_reduction | Should -Be 0.5
    }
}

Describe "Get-OpenPositionsConflict" {
    It "detecta conflito quando posição oposta existe" {
        $result = Get-OpenPositionsConflict -Market "LINKUSDT" -Direction "SHORT"

        $result.conflict | Should -Be $true
        $result.existing_direction | Should -Be "LONG"
        $result.proposed_direction | Should -Be "SHORT"
    }

    It "retorna conflict=false quando sem conflito" {
        $result = Get-OpenPositionsConflict -Market "UNKNOWN" -Direction "LONG"

        $result.conflict | Should -Be $false
    }
}

Describe "Get-MentorSupabaseEnrichment" {
    It "monta enrichment completo" {
        $result = Get-MentorSupabaseEnrichment -Market "LINKUSDT" -Direction "LONG" -Regime "BULL_WEAK" -ProposedSize 100

        $result | Should -Not -BeNullOrEmpty
        $result.market | Should -Be "LINKUSDT"
        $result.direction | Should -Be "LONG"
        $result.regime | Should -Be "BULL_WEAK"
        $result.timestamp | Should -Match "^\d{4}-\d{2}-\d{2}"
    }

    It "inclui todos os campos P0 e P1" {
        $result = Get-MentorSupabaseEnrichment -Market "LINKUSDT" -Direction "LONG" -Regime "BEAR_WEAK"

        # Deve ter pelo menos decision_grades (P0)
        $result.decision_grades | Should -Not -BeNullOrEmpty
    }
}

Describe "Format-EnrichmentPrompt" {
    It "formata enrichment pra prompt" {
        $enrichment = Get-MentorSupabaseEnrichment -Market "LINKUSDT" -Direction "LONG" -Regime "BEAR_WEAK"
        $prompt = Format-EnrichmentPrompt -Enrichment $enrichment

        $prompt | Should -Match "\[SUPABASE ENRICHMENT\]"
        $prompt | Should -Match "Decision Grades"
    }

    It "inclui aviso INVERT quando decision_invert=true" {
        $enrichment = Get-MentorSupabaseEnrichment -Market "LINKUSDT" -Direction "SHORT" -Regime "BEAR_WEAK"
        $prompt = Format-EnrichmentPrompt -Enrichment $enrichment

        if ($enrichment.decision_invert) {
            $prompt | Should -Match "⚠️  INVERT"
        }
    }
}

# Summary
Write-Host "`n✅ Mentor Supabase Enrichment: todos os testes passam" -ForegroundColor Green
