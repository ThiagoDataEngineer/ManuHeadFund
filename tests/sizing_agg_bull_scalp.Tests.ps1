# tests/sizing_agg_bull_scalp.Tests.ps1
# TDD (2026-07-07): estrategia de sizing agressivo — 3% em BULL_STRONG e scalps
# Pester 3.4 compativel.

$ErrorActionPreference = "Stop"
$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_hybrid_orchestrator.ps1")

Describe "Get-PositionSize: estrategia 3% em BULL_STRONG / scalps" {

    BeforeEach {
        # Mock capital setup
        $script:HybridConfig = @{
            spot_capital = 2425.33
            futures_capital = 2718.49
            total_capital = 5143.82
            last_updated = Get-Date
        }
        # Mock Get-DynamicCapital pra nao fazer chamada API
        Set-Item function:Get-DynamicCapital -Value { $global:HybridConfig }
    }

    AfterEach {
        Remove-Item function:Get-DynamicCapital -ErrorAction SilentlyContinue
    }

    It "1% default em BEAR_WEAK (conservador)" {
        $pos = Get-PositionSize -Market FUTURES -Regime BEAR_WEAK -IsScalp $false
        $expected = 2718.49 * 0.01  # 27.18 USDT
        $pos.position_usdt | Should Be ([Math]::Round($expected, 2))
        $pos.sizing_aggressive | Should Be $false
    }

    It "3% em BULL_STRONG (agressivo confianca alta)" {
        $pos = Get-PositionSize -Market FUTURES -Regime BULL_STRONG -IsScalp $false
        $expected = 2718.49 * 0.03  # 81.55 USDT
        $pos.position_usdt | Should Be ([Math]::Round($expected, 2))
        $pos.sizing_aggressive | Should Be $true
    }

    It "3% em scalp <5min mesmo em BEAR_WEAK (risco temporal)" {
        $pos = Get-PositionSize -Market FUTURES -Regime BEAR_WEAK -IsScalp $true
        $expected = 2718.49 * 0.03  # 81.55 USDT
        $pos.position_usdt | Should Be ([Math]::Round($expected, 2))
        $pos.is_scalp | Should Be $true
    }

    It "1% em BULL_WEAK (sem agressividade, nem scalp)" {
        $pos = Get-PositionSize -Market FUTURES -Regime BULL_WEAK -IsScalp $false
        $expected = 2718.49 * 0.01  # 27.18 USDT
        $pos.position_usdt | Should Be ([Math]::Round($expected, 2))
        $pos.sizing_aggressive | Should Be $false
    }

    It "0.5% em BEAR_STRONG (half-risk, mais conservador que o padrao)" {
        $pos = Get-PositionSize -Market FUTURES -Regime BEAR_STRONG -IsScalp $false
        # BEAR_STRONG = 1% base * 0.5 multiplier
        $expected = 2718.49 * 0.01 * 0.5  # 13.59 USDT
        $pos.position_usdt | Should Be ([Math]::Round($expected, 2))
    }
}

Describe "Test-IsScalp: deteccao de trade curto" {

    It "scalp strategy SCALP ou INTRADAY_5M => true" {
        Test-IsScalp -Strategy "SCALP_PUMP" -PlannedDurationMinutes 0 | Should Be $true
        Test-IsScalp -Strategy "INTRADAY_5M" -PlannedDurationMinutes 0 | Should Be $true
    }

    It "duracao <5min => scalp" {
        Test-IsScalp -Strategy "TREND_FOLLOW" -PlannedDurationMinutes 3 | Should Be $true
    }

    It "duracao >5min e sem SCALP no nome => nao scalp" {
        Test-IsScalp -Strategy "REVERSAL" -PlannedDurationMinutes 15 | Should Be $false
    }

    It "default (0 min, nao scalp strategy) => false" {
        Test-IsScalp -Strategy "STANDARD" -PlannedDurationMinutes 0 | Should Be $false
    }
}
