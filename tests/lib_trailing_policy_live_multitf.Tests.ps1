# tests/lib_trailing_policy_live_multitf.Tests.ps1
# TDD (2026-07-07): trailing multi-timeframe opt-in.
# Invoke-TrailingPolicyLive/Get-PositionExitDecision aceitam HtfTrend {t1D;t4H;t1H}.
# Quando fornecido, trend_up vem da CONFLUENCIA direcao-aware (Get-MultiTimeframeConviction),
# nao mais do binario single-TF. Invariante: ratchet-only (nunca afrouxa stop).
#
# Pester 3.4 compativel.

$ErrorActionPreference = "Stop"

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_trailing_baseline.ps1")
. (Join-Path $agentsDir "lib_trailing_policy.ps1")
. (Join-Path $agentsDir "lib_multiframe_analysis.ps1")
. (Join-Path $agentsDir "lib_trailing_policy_live.ps1")

# Gera N candles de close ascendente (uptrend) ou descendente, com high/low simples.
function New-Candles {
    param([double]$Start, [double]$Step, [int]$N)
    $arr = @()
    $px = $Start
    for ($i = 0; $i -lt $N; $i++) {
        $arr += [PSCustomObject]@{ open = $px; high = $px * 1.01; low = $px * 0.99; close = $px; volume = 1000 }
        $px = $px + $Step
    }
    return $arr
}

Describe "Get-PositionExitDecision multi-TF (HtfTrend)" {

    # Posicao LONG em lucro (r_now alto) para que a politica queira mover o stop.
    $longPos = [PSCustomObject]@{
        market = "AAAUSDT"; side = "LONG"; entry = 100.0; stop = 95.0
        stopCurrent = 95.0; peak = 130.0; openedAt = (Get-Date).AddDays(-3).ToString("o")
    }
    # candles em uptrend -> lastClose > sma -> single-TF trend_up = TRUE
    $upCandles = New-Candles -Start 100 -Step 1 -N 30

    Context "Backward-compat: sem HtfTrend, comportamento identico ao single-TF" {
        It "trend_up reflete o single-TF (uptrend) e trend_up_stf == trend_up" {
            $dec = Get-PositionExitDecision -Position $longPos -Candles $upCandles -Regime "BULL_WEAK"
            $dec.trend_up | Should Be $true
            $dec.trend_up_stf | Should Be $true
            $dec.htf_conviction | Should BeNullOrEmpty
        }
    }

    Context "HtfTrend alinhado (todos UP, LONG)" {
        It "conviccao alta -> trend_up TRUE" {
            $htf = @{ t1D = "STRONG_UP"; t4H = "UP"; t1H = "UP" }
            $dec = Get-PositionExitDecision -Position $longPos -Candles $upCandles -Regime "BULL_WEAK" -HtfTrend $htf
            $dec.trend_up | Should Be $true
            ($dec.htf_conviction -ge 40) | Should Be $true
        }
    }

    Context "HtfTrend contra a posicao (1D/4H DOWN, LONG)" {
        It "conviccao baixa -> trend_up FALSE (politica mais apertada)" {
            $htf = @{ t1D = "STRONG_DOWN"; t4H = "DOWN"; t1H = "DOWN" }
            $dec = Get-PositionExitDecision -Position $longPos -Candles $upCandles -Regime "BULL_WEAK" -HtfTrend $htf
            $dec.trend_up | Should Be $false
            ($dec.htf_conviction -lt 40) | Should Be $true
        }
    }

    Context "SHORT: confluencia usa a direcao (nao inverte)" {
        It "SHORT com HTFs DOWN -> conviccao alta -> trend_up TRUE" {
            $shortPos = [PSCustomObject]@{
                market = "BBBUSDT"; side = "SHORT"; entry = 100.0; stop = 105.0
                stopCurrent = 105.0; peak = 80.0; openedAt = (Get-Date).AddDays(-3).ToString("o")
            }
            $downCandles = New-Candles -Start 100 -Step -1 -N 30
            $htf = @{ t1D = "STRONG_DOWN"; t4H = "DOWN"; t1H = "DOWN" }
            $dec = Get-PositionExitDecision -Position $shortPos -Candles $downCandles -Regime "BEAR_WEAK" -HtfTrend $htf
            ($dec.htf_conviction -ge 40) | Should Be $true
            $dec.trend_up | Should Be $true
        }
    }
}

Describe "Invoke-TrailingPolicyLive ratchet-only com multi-TF" {

    It "nunca afrouxa o stop: HtfTrend contra nao pode BAIXAR o stopCurrent (LONG)" {
        $pos = [PSCustomObject]@{
            market = "CCCUSDT"; side = "LONG"; entry = 100.0; stop = 95.0
            stopCurrent = 120.0; peak = 130.0; openedAt = (Get-Date).AddDays(-3).ToString("o")
        }
        $map = @{ "CCCUSDT" = (New-Candles -Start 100 -Step 1 -N 30) }
        $htf = @{ "CCCUSDT" = @{ t1D = "STRONG_DOWN"; t4H = "DOWN"; t1H = "DOWN" } }

        $before = [double]$pos.stopCurrent
        $res = Invoke-TrailingPolicyLive -Positions @($pos) -CandleMap $map -Regime "BULL_WEAK" -HtfTrendMap $htf
        # Ratchet-only: o stop resultante nunca fica ABAIXO do anterior num LONG.
        ([double]$res.positions[0].stopCurrent -ge $before) | Should Be $true
    }

    It "HtfTrendMap=null -> caminho single-TF (sem erro, backward-compat)" {
        $pos = [PSCustomObject]@{
            market = "DDDUSDT"; side = "LONG"; entry = 100.0; stop = 95.0
            stopCurrent = 95.0; peak = 130.0; openedAt = (Get-Date).AddDays(-3).ToString("o")
        }
        $map = @{ "DDDUSDT" = (New-Candles -Start 100 -Step 1 -N 30) }
        $res = Invoke-TrailingPolicyLive -Positions @($pos) -CandleMap $map -Regime "BULL_WEAK"
        $res.PSObject.Properties['changes'] | Should Not BeNullOrEmpty
    }
}
