# mce_dynamic_factors.Tests.ps1 -- TDD para os 4 fatores dinamicos do MCE
# Pester 3.x. UTF-8 BOM.
# Fatores: fear_greed, funding_rate, etf_flow, dxy
# Fonte: knowledge/ONCHAIN_ANALYSIS.md, MACRO_CONTEXT.md, MARKET_TIMING_BRT.md

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_market_context_engine.ps1")

# ─── Get-FearGreedFactor ──────────────────────────────────────────────────────
Describe "Get-FearGreedFactor" {
    It "Extreme Fear (0-25) retorna 1.4 — oportunidade de compra historica" {
        (Get-FearGreedFactor -Score 15) | Should Be 1.4
        (Get-FearGreedFactor -Score 0)  | Should Be 1.4
        (Get-FearGreedFactor -Score 25) | Should Be 1.4
    }
    It "Fear (26-45) retorna 1.2 — favoravel para entrar" {
        (Get-FearGreedFactor -Score 26) | Should Be 1.2
        (Get-FearGreedFactor -Score 35) | Should Be 1.2
        (Get-FearGreedFactor -Score 45) | Should Be 1.2
    }
    It "Neutral (46-55) retorna 1.0 — sem ajuste" {
        (Get-FearGreedFactor -Score 46) | Should Be 1.0
        (Get-FearGreedFactor -Score 50) | Should Be 1.0
        (Get-FearGreedFactor -Score 55) | Should Be 1.0
    }
    It "Greed (56-75) retorna 0.8 — cautela" {
        (Get-FearGreedFactor -Score 56) | Should Be 0.8
        (Get-FearGreedFactor -Score 65) | Should Be 0.8
        (Get-FearGreedFactor -Score 75) | Should Be 0.8
    }
    It "Extreme Greed (76-100) retorna 0.5 — risco de topo" {
        (Get-FearGreedFactor -Score 76) | Should Be 0.5
        (Get-FearGreedFactor -Score 90) | Should Be 0.5
        (Get-FearGreedFactor -Score 100)| Should Be 0.5
    }
    It "Score null/invalido retorna 1.0 — fail-open (nao bloqueia sem dado)" {
        (Get-FearGreedFactor -Score $null) | Should Be 1.0
        (Get-FearGreedFactor -Score -1)    | Should Be 1.0
        (Get-FearGreedFactor -Score 101)   | Should Be 1.0
    }
}

# ─── Get-FundingRateFactor ────────────────────────────────────────────────────
Describe "Get-FundingRateFactor" {
    It "Funding muito negativo (abaixo de -0.05) retorna 1.3 — short squeeze iminente" {
        (Get-FundingRateFactor -Rate -0.06) | Should Be 1.3
        (Get-FundingRateFactor -Rate -0.10) | Should Be 1.3
        (Get-FundingRateFactor -Rate -0.05) | Should Be 1.3
    }
    It "Funding neutro (entre -0.05 e +0.05) retorna 1.0 — mercado equilibrado" {
        (Get-FundingRateFactor -Rate 0.0)   | Should Be 1.0
        (Get-FundingRateFactor -Rate 0.02)  | Should Be 1.0
        (Get-FundingRateFactor -Rate -0.02) | Should Be 1.0
        (Get-FundingRateFactor -Rate 0.049) | Should Be 1.0
    }
    It "Funding positivo (entre 0.05 e 0.10) retorna 0.8 — longs excessivos" {
        (Get-FundingRateFactor -Rate 0.051) | Should Be 0.8
        (Get-FundingRateFactor -Rate 0.08)  | Should Be 0.8
        (Get-FundingRateFactor -Rate 0.10)  | Should Be 0.8
    }
    It "Funding muito positivo (acima de 0.10) retorna 0.6 — risco de liquidacao" {
        (Get-FundingRateFactor -Rate 0.101) | Should Be 0.6
        (Get-FundingRateFactor -Rate 0.20)  | Should Be 0.6
    }
    It "Rate null retorna 1.0 — fail-open" {
        (Get-FundingRateFactor -Rate $null) | Should Be 1.0
    }
}

# ─── Get-EtfFlowFactor ───────────────────────────────────────────────────────
Describe "Get-EtfFlowFactor" {
    It "Inflow forte (> 200M USD) retorna 1.3 — demanda institucional real" {
        (Get-EtfFlowFactor -FlowMillions 250)  | Should Be 1.3
        (Get-EtfFlowFactor -FlowMillions 1000) | Should Be 1.3
        (Get-EtfFlowFactor -FlowMillions 200)  | Should Be 1.3
    }
    It "Inflow moderado (0 a 200M) retorna 1.1 — neutro positivo" {
        (Get-EtfFlowFactor -FlowMillions 100) | Should Be 1.1
        (Get-EtfFlowFactor -FlowMillions 1)   | Should Be 1.1
        (Get-EtfFlowFactor -FlowMillions 0)   | Should Be 1.1
    }
    It "Outflow moderado (-200M a 0) retorna 0.8 — pressao vendedora" {
        (Get-EtfFlowFactor -FlowMillions -1)   | Should Be 0.8
        (Get-EtfFlowFactor -FlowMillions -100) | Should Be 0.8
        (Get-EtfFlowFactor -FlowMillions -200) | Should Be 0.8
    }
    It "Outflow forte (< -200M) retorna 0.5 — saida institucional significativa" {
        (Get-EtfFlowFactor -FlowMillions -201) | Should Be 0.5
        (Get-EtfFlowFactor -FlowMillions -500) | Should Be 0.5
    }
    It "FlowMillions null retorna 1.0 — fail-open (dado indisponivel)" {
        (Get-EtfFlowFactor -FlowMillions $null) | Should Be 1.0
    }
}

# ─── Get-DxyFactor ───────────────────────────────────────────────────────────
Describe "Get-DxyFactor" {
    It "DXY caindo (trend negativo) retorna 1.2 — dolar fraco = bullish crypto" {
        (Get-DxyFactor -Trend "DOWN") | Should Be 1.2
    }
    It "DXY lateral retorna 1.0 — sem ajuste" {
        (Get-DxyFactor -Trend "FLAT") | Should Be 1.0
    }
    It "DXY subindo retorna 0.8 — dolar forte = pressao em crypto" {
        (Get-DxyFactor -Trend "UP") | Should Be 0.8
    }
    It "DXY subindo acima de 105 retorna 0.6 — ambiente muito desfavoravel" {
        (Get-DxyFactor -Trend "UP_STRONG") | Should Be 0.6
    }
    It "Trend null retorna 1.0 — fail-open" {
        (Get-DxyFactor -Trend $null) | Should Be 1.0
    }
}

# ─── Get-DynamicContextScore (produto com fatores dinamicos) ─────────────────
Describe "Get-DynamicContextScore" {
    It "Retorna objeto com campo dynamic_score e fatores individuais" {
        $r = Get-DynamicContextScore -FearGreed 35 -FundingRate -0.03 -EtfFlowMillions 150 -DxyTrend "FLAT"
        $r.PSObject.Properties.Name -contains "dynamic_score" | Should Be $true
        $r.PSObject.Properties.Name -contains "fear_greed" | Should Be $true
        $r.PSObject.Properties.Name -contains "funding_rate" | Should Be $true
        $r.PSObject.Properties.Name -contains "etf_flow" | Should Be $true
        $r.PSObject.Properties.Name -contains "dxy" | Should Be $true
    }
    It "Cenario bullish: Fear=20, Funding=-0.06, ETF=+300M, DXY=DOWN -> dynamic_score > 1.0" {
        $r = Get-DynamicContextScore -FearGreed 20 -FundingRate -0.06 -EtfFlowMillions 300 -DxyTrend "DOWN"
        # 1.4 x 1.3 x 1.3 x 1.2 = 2.84 -> capped
        $r.dynamic_score | Should BeGreaterThan 1.0
    }
    It "Cenario bearish: Fear=85, Funding=+0.15, ETF=-300M, DXY=UP_STRONG retorna dynamic_score menor que 1.0" {
        $r = Get-DynamicContextScore -FearGreed 85 -FundingRate 0.15 -EtfFlowMillions -300 -DxyTrend "UP_STRONG"
        # 0.5 x 0.6 x 0.5 x 0.6 = 0.09
        $r.dynamic_score | Should BeLessThan 1.0
    }
    It "Todos nulls retorna dynamic_score = 1.0 (fail-open, nao bloqueia)" {
        $r = Get-DynamicContextScore -FearGreed $null -FundingRate $null -EtfFlowMillions $null -DxyTrend $null
        $r.dynamic_score | Should Be 1.0
    }
    It "dynamic_score e capped em 2.0 (nao amplifica demais)" {
        $r = Get-DynamicContextScore -FearGreed 5 -FundingRate -0.20 -EtfFlowMillions 2000 -DxyTrend "DOWN"
        $r.dynamic_score | Should BeLessThan 2.001
    }
}

# ─── Get-DynamicContextData (fetch real das APIs) ────────────────────────────
Describe "Get-DynamicContextData" {
    It "Retorna objeto com campos esperados (mesmo sem API keys)" {
        $r = Get-DynamicContextData
        $r.PSObject.Properties.Name -contains "fear_greed_score" | Should Be $true
        $r.PSObject.Properties.Name -contains "funding_rate" | Should Be $true
        $r.PSObject.Properties.Name -contains "etf_flow_millions" | Should Be $true
        $r.PSObject.Properties.Name -contains "dxy_trend" | Should Be $true
        $r.PSObject.Properties.Name -contains "source" | Should Be $true
        $r.PSObject.Properties.Name -contains "fetched_at" | Should Be $true
    }
    It "fear_greed_score e null ou inteiro 0-100" {
        $r = Get-DynamicContextData
        if ($null -ne $r.fear_greed_score) {
            $r.fear_greed_score | Should BeGreaterThan -1
            $r.fear_greed_score | Should BeLessThan 101
        }
    }
    It "dxy_trend e um dos valores validos ou null" {
        $r = Get-DynamicContextData
        if ($null -ne $r.dxy_trend) {
            $r.dxy_trend -in @("UP","UP_STRONG","FLAT","DOWN") | Should Be $true
        }
    }
}

# ─── Integracao: Test-ContextAllowsTrade com fatores dinamicos ───────────────
Describe "Test-ContextAllowsTrade com DynamicData" {
    It "Aceita parametro DynamicData opcional sem quebrar" {
        $dt = [datetime]"2026-05-27 11:00"
        $dynData = [PSCustomObject]@{
            fear_greed_score  = 35
            funding_rate      = -0.03
            etf_flow_millions = 150
            dxy_trend         = "FLAT"
        }
        $r = Test-ContextAllowsTrade -DateBrt $dt -Regime "BULL_WEAK" -DynamicData $dynData
        $r.PSObject.Properties.Name -contains "action" | Should Be $true
        $r.PSObject.Properties.Name -contains "score" | Should Be $true
        $r.PSObject.Properties.Name -contains "dynamic_score" | Should Be $true
    }
    It "Sem DynamicData funciona igual ao comportamento anterior (backward compat)" {
        $dt = [datetime]"2026-05-27 11:00"
        $r = Test-ContextAllowsTrade -DateBrt $dt -Regime "BULL_WEAK"
        $r.PSObject.Properties.Name -contains "action" | Should Be $true
        $r.PSObject.Properties.Name -contains "score" | Should Be $true
    }
    It "Fear=20 + Funding=-0.06 melhora score vs sem dados dinamicos" {
        $dt = [datetime]"2026-05-27 11:00"
        $rBase = Test-ContextAllowsTrade -DateBrt $dt -Regime "BULL_WEAK"
        $dynData = [PSCustomObject]@{
            fear_greed_score  = 20
            funding_rate      = -0.06
            etf_flow_millions = 300
            dxy_trend         = "DOWN"
        }
        $rDyn = Test-ContextAllowsTrade -DateBrt $dt -Regime "BULL_WEAK" -DynamicData $dynData
        $rDyn.score | Should BeGreaterThan $rBase.score
    }
}
