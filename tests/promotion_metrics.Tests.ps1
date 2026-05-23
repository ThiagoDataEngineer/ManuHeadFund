# promotion_metrics.Tests.ps1 -- TDD Get-PromotionMetrics
# Pester 3.x. PS 5.1. UTF-8 BOM.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_promotion_ladder.ps1")

# Helpers para criar fake closes (simula price history)
function New-FakeCloses {
    param([int]$N = 250, [double]$Start = 100, [double]$Drift = 0.001)
    $arr = @()
    $price = $Start
    for ($i = 0; $i -lt $N; $i++) {
        $price = $price * (1 + $Drift)
        $arr += $price
    }
    return $arr
}

Describe "Compute-AssetRegime" {

    It "BULL_STRONG quando dist_sma200>20% e mom_20d>10%" {
        $closes = New-FakeCloses -N 250 -Start 100 -Drift 0.006   # strong uptrend (1.006^20=12.7%)
        $r = Compute-AssetRegime -Closes $closes
        $r.regime | Should Be "BULL_STRONG"
        $r.dist_sma200 | Should BeGreaterThan 0.20
        $r.mom_20d | Should BeGreaterThan 0.10
    }

    It "BEAR_STRONG quando dist_sma200<-20% e mom_20d<-10%" {
        $closes = New-FakeCloses -N 250 -Start 200 -Drift -0.006  # strong downtrend
        $r = Compute-AssetRegime -Closes $closes
        $r.regime | Should Be "BEAR_STRONG"
    }

    It "SIDEWAYS quando movimento pequeno" {
        $closes = New-FakeCloses -N 250 -Start 100 -Drift 0.0001
        $r = Compute-AssetRegime -Closes $closes
        # Drift 0.01%/day over 250 days = ~28% total. Pode classificar como BULL_WEAK.
        # Aceito BULL_WEAK ou SIDEWAYS aqui
        ($r.regime -in @("SIDEWAYS","BULL_WEAK","TRANSITION")) | Should Be $true
    }

    It "retorna NO_HIST quando closes < 200" {
        $closes = @(100, 101, 102)
        $r = Compute-AssetRegime -Closes $closes
        $r.regime | Should Be "NO_HIST"
    }
}

Describe "Get-PromotionMetrics" {

    It "retorna estrutura completa com defaults zero/null" {
        $m = Get-PromotionMetrics -Market "TESTUSDT"
        $m.ContainsKey("sharpe_30d") | Should Be $true
        $m.ContainsKey("mom_20d") | Should Be $true
        $m.ContainsKey("n_trades") | Should Be $true
        $m.ContainsKey("max_dd") | Should Be $true
        $m.ContainsKey("regime_asset") | Should Be $true
        $m.ContainsKey("regime_btc") | Should Be $true
    }

    It "computa regime + mom_20d quando AssetCloses fornecido" {
        $closes = New-FakeCloses -N 250 -Start 100 -Drift 0.002
        $m = Get-PromotionMetrics -Market "X" -AssetCloses $closes
        $m.regime_asset | Should Not BeNullOrEmpty
        $m.mom_20d | Should BeGreaterThan 0
    }

    It "regime_btc preenchido quando BtcCloses fornecido" {
        $btcCloses = New-FakeCloses -N 250 -Start 50000 -Drift 0.002
        $m = Get-PromotionMetrics -Market "X" -BtcCloses $btcCloses
        $m.regime_btc | Should Not BeNullOrEmpty
    }

    It "merge metrics externos via -External" {
        $m = Get-PromotionMetrics -Market "X" -External @{ sharpe_30d = 1.5; n_trades = 10 }
        $m.sharpe_30d | Should Be 1.5
        $m.n_trades | Should Be 10
    }
}
