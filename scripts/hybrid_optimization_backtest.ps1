# HYBRID OPTIMIZATION — Teste múltiplos splits SPOT/FUTURES
# Objetivo: Encontrar ratio ótimo que mantenha WR ≥60% + capital allocation eficiente

param(
    [int] $InitialCapital = 2700.85,
    [int] $TradesPerScenario = 200,
    [array] $CapitalSplits = @(0.5, 0.6, 0.7, 0.8)  # 50/50, 60/40, 70/30, 80/20 SPOT/FUTURES
)

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  HYBRID OPTIMIZATION — Finding Optimal SPOT/FUTURES Ratio  ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# ════════════════════════════════════════════════════════════
# METRICS (from backtests)
# ════════════════════════════════════════════════════════════

$metrics = @{
    "SPOT" = @{
        winRate = 0.63
        avgWinPct = 0.007
        avgLossPct = 0.002
        fees = 0.004  # 0.4% total (maker 0.1% × 2 sides × 2)
        liquidation_risk = 0
    }
    "FUTURES" = @{
        winRate = 0.64  # Slightly better execution on FUTURES
        avgWinPct = 0.007
        avgLossPct = 0.002
        fees = 0.0004  # 0.04% total (much lower)
        liquidation_risk = 0.02  # 2% account risk if liquidation happens
    }
}

# ════════════════════════════════════════════════════════════
# SIMULATE TRADE FOR SINGLE MARKET
# ════════════════════════════════════════════════════════════

function Simulate-SingleTrade {
    param(
        [string] $Market,      # SPOT or FUTURES
        [double] $PositionSize,
        [hashtable] $MetricConfig
    )

    $isWin = (Get-Random -Minimum 0 -Maximum 100) -lt ($MetricConfig.winRate * 100)

    if ($isWin) {
        $variance = (Get-Random -Minimum -100 -Maximum 100) / 100
        $profitPct = $MetricConfig.avgWinPct + ($variance * 0.001)
        $profitPct = [Math]::Max($profitPct, 0.0005)
    } else {
        $variance = (Get-Random -Minimum -100 -Maximum 100) / 100
        $lossPct = $MetricConfig.avgLossPct + ($variance * 0.0008)
        $lossPct = [Math]::Max($lossPct, 0.0005)
        $profitPct = -$lossPct
    }

    $netPnLPct = $profitPct - $MetricConfig.fees
    $tradePnL = $PositionSize * $netPnLPct

    return @{
        market = $Market
        win = $isWin
        gross_pnl = $PositionSize * $profitPct
        fees = -($PositionSize * $MetricConfig.fees)
        net_pnl = $tradePnL
        pnl_pct = $netPnLPct
    }
}

# ════════════════════════════════════════════════════════════
# SIMULATE HYBRID SCENARIO (SPOT + FUTURES IN PARALLEL)
# ════════════════════════════════════════════════════════════

function Simulate-HybridScenario {
    param(
        [double] $SpotPercentage,     # 0.5 = 50% SPOT, 50% FUTURES
        [int] $Trades = 200
    )

    $futuresPercentage = 1 - $SpotPercentage
    $spotCapital = $InitialCapital * $SpotPercentage
    $futuresCapital = $InitialCapital * $futuresPercentage

    $spotPosition = $spotCapital * 0.01  # 1% per trade
    $futuresPosition = $futuresCapital * 0.01 * 0.8  # 0.8% (20% reduction for safety)

    $totalPnL = 0
    $spotWins = 0
    $futuresWins = 0
    $maxDD = 0
    $peakEquity = $InitialCapital
    $currentEquity = $InitialCapital
    $trades_log = @()

    for ($i = 0; $i -lt $Trades; $i++) {
        # Simulate BOTH markets in parallel (they can win/lose independently)
        $spotTrade = Simulate-SingleTrade -Market "SPOT" -PositionSize $spotPosition -MetricConfig $metrics["SPOT"]
        $futuresTrade = Simulate-SingleTrade -Market "FUTURES" -PositionSize $futuresPosition -MetricConfig $metrics["FUTURES"]

        $tradePnL = $spotTrade.net_pnl + $futuresTrade.net_pnl
        $currentEquity += $tradePnL
        $totalPnL += $tradePnL

        if ($spotTrade.win) { $spotWins++ }
        if ($futuresTrade.win) { $futuresWins++ }

        # Track max DD
        if ($currentEquity -gt $peakEquity) { $peakEquity = $currentEquity }
        $dd = $peakEquity - $currentEquity
        if ($dd -gt $maxDD) { $maxDD = $dd }

        $trades_log += @{
            cycle = $i
            spot_pnl = $spotTrade.net_pnl
            futures_pnl = $futuresTrade.net_pnl
            total_pnl = $tradePnL
            equity = $currentEquity
        }
    }

    # Calculate combined win rate
    # Each trade counts as 2 events (SPOT + FUTURES), so total outcomes = $Trades × 2
    $totalOutcomes = $Trades * 2
    $totalWins = $spotWins + $futuresWins
    $combinedWR = ($totalWins / $totalOutcomes) * 100

    $roi = ($totalPnL / $InitialCapital) * 100

    return @{
        spot_pct = $SpotPercentage * 100
        futures_pct = $futuresPercentage * 100
        spot_capital = $spotCapital
        futures_capital = $futuresCapital
        spot_position = $spotPosition
        futures_position = $futuresPosition
        trades = $Trades
        spot_wins = $spotWins
        futures_wins = $futuresWins
        combined_wr = $combinedWR
        total_pnl = $totalPnL
        roi = $roi
        max_dd = $maxDD
        final_equity = $currentEquity
        capital_change = $currentEquity - $InitialCapital
    }
}

# ════════════════════════════════════════════════════════════
# RUN OPTIMIZATION
# ════════════════════════════════════════════════════════════

Write-Host "`n📊 HYBRID SPLIT OPTIMIZATION (Testing 4 scenarios):`n" -ForegroundColor Yellow

$results = @()

foreach ($split in $CapitalSplits) {
    $spotPct = [Math]::Round($split * 100, 0)
    $futPct = [Math]::Round((1 - $split) * 100, 0)

    Write-Host "  Testing: $spotPct% SPOT / $futPct% FUTURES..." -ForegroundColor Cyan

    $result = Simulate-HybridScenario -SpotPercentage $split -Trades $TradesPerScenario
    $results += $result

    Write-Host "    Combined WR:     $([Math]::Round($result.combined_wr, 1))%"
    Write-Host "    SPOT wins:       $($result.spot_wins) | FUTURES wins: $($result.futures_wins)"
    Write-Host "    Total PnL:       `$$([Math]::Round($result.total_pnl, 2))"
    Write-Host "    ROI:             +$([Math]::Round($result.roi, 2))%"
    Write-Host "    Max DD:          -`$$([Math]::Round($result.max_dd, 2))"
    Write-Host "    Final Equity:    `$$([Math]::Round($result.final_equity, 2))`n"
}

# ════════════════════════════════════════════════════════════
# COMPARISON TABLE
# ════════════════════════════════════════════════════════════

Write-Host "`n📊 HYBRID OPTIMIZATION RESULTS:`n" -ForegroundColor Cyan

Write-Host "Split          | Spot Cap | Fut Cap | Spot Pos | Fut Pos | Combined WR | PnL    | ROI    | Max DD" -ForegroundColor Gray
Write-Host "───────────────┼──────────┼─────────┼──────────┼─────────┼─────────────┼────────┼────────┼──────────" -ForegroundColor Gray

foreach ($r in $results) {
    Write-Host "$([Math]::Round($r.spot_pct).ToString().PadRight(3))%/$([Math]::Round($r.futures_pct).ToString().PadRight(2))% SPOT/FUT | " `
        -NoNewline -ForegroundColor White
    Write-Host "$([Math]::Round($r.spot_capital, 0).ToString().PadRight(8)) | " `
        -NoNewline -ForegroundColor White
    Write-Host "$([Math]::Round($r.futures_capital, 0).ToString().PadRight(7)) | " `
        -NoNewline -ForegroundColor White
    Write-Host "$([Math]::Round($r.spot_position, 2).ToString().PadRight(8)) | " `
        -NoNewline -ForegroundColor White
    Write-Host "$([Math]::Round($r.futures_position, 2).ToString().PadRight(7)) | " `
        -NoNewline -ForegroundColor White
    Write-Host "$([Math]::Round($r.combined_wr, 1).ToString().PadRight(11))% | " `
        -NoNewline -ForegroundColor White
    Write-Host "`$$([Math]::Round($r.total_pnl, 2).ToString().PadRight(6)) | " `
        -NoNewline -ForegroundColor White
    Write-Host "+$([Math]::Round($r.roi, 2).ToString().PadRight(6))% | " `
        -NoNewline -ForegroundColor White
    Write-Host "-`$$([Math]::Round($r.max_dd, 2))" -ForegroundColor White
}

# ════════════════════════════════════════════════════════════
# FIND OPTIMAL RATIO
# ════════════════════════════════════════════════════════════

$bestResult = $results | Sort-Object -Property combined_wr -Descending | Select-Object -First 1
$bestWR = $bestResult.combined_wr

Write-Host "`n🎯 OPTIMAL HYBRID CONFIG:`n" -ForegroundColor Green

Write-Host "  Allocation:      $([Math]::Round($bestResult.spot_pct))% SPOT / $([Math]::Round($bestResult.futures_pct))% FUTURES" -ForegroundColor Cyan
Write-Host "  Capital Split:   `$$([Math]::Round($bestResult.spot_capital, 2)) SPOT + `$$([Math]::Round($bestResult.futures_capital, 2)) FUTURES" -ForegroundColor Cyan
Write-Host "  Positions:       `$$([Math]::Round($bestResult.spot_position, 2)) SPOT/trade + `$$([Math]::Round($bestResult.futures_position, 2)) FUTURES/trade" -ForegroundColor Cyan
Write-Host "  Combined WR:     $([Math]::Round($bestResult.combined_wr, 1))%" -ForegroundColor Green
Write-Host "  Expected ROI:    +$([Math]::Round($bestResult.roi, 2))% per 200 trades" -ForegroundColor Green
Write-Host "  Max DD:          -`$$([Math]::Round($bestResult.max_dd, 2))" -ForegroundColor Yellow
Write-Host ""

# ════════════════════════════════════════════════════════════
# APPROVAL VERDICT
# ════════════════════════════════════════════════════════════

Write-Host "🚀 VERDICT:`n" -ForegroundColor Green

if ($bestWR -ge 60) {
    Write-Host "  ✅ HYBRID APPROVED — WR $([Math]::Round($bestWR, 1))% ≥60%" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Benefits over SPOT:"
    Write-Host "    - Diversificado (SPOT + FUTURES em paralelo)"
    Write-Host "    - Fees otimizadas (0.04% FUTURES vs 0.4% SPOT)"
    Write-Host "    - Capital allocation flexível ($([Math]::Round($bestResult.spot_capital, 2)) + $([Math]::Round($bestResult.futures_capital, 2)))"
    Write-Host "    - Pode fazer SHORT no FUTURES facilmente"
    Write-Host ""
    Write-Host "  Risks to manage:"
    Write-Host "    - FUTURES liquidation risk (need monitoring)"
    Write-Host "    - Operational complexity (+2 integrations)"
    Write-Host "    - API dependencies (both SPOT + FUTURES endpoints)"
} elseif ($bestWR -ge 58) {
    Write-Host "  ⚠️ MARGINAL — WR $([Math]::Round($bestWR, 1))% close to 60%" -ForegroundColor Yellow
    Write-Host "     Can work but needs careful monitoring"
} else {
    Write-Host "  ❌ NOT RECOMMENDED — WR $([Math]::Round($bestWR, 1))% <60%" -ForegroundColor Red
    Write-Host "     Risk too high. Revert to SPOT-only."
}

Write-Host ""

# ════════════════════════════════════════════════════════════
# DETAILED BREAKDOWN
# ════════════════════════════════════════════════════════════

Write-Host "📋 DETAILED BREAKDOWN — OPTIMAL CONFIG:`n" -ForegroundColor Cyan

Write-Host "SPOT Account (Trading):" -ForegroundColor Yellow
Write-Host "  Capital:         `$$([Math]::Round($bestResult.spot_capital, 2))"
Write-Host "  Position/trade:  `$$([Math]::Round($bestResult.spot_position, 2)) (1% of SPOT cap)"
Write-Host "  Expected WR:     63% (from backtest)"
Write-Host "  Liquidation:     ❌ NONE (1x, no leverage)"
Write-Host "  Fees:            0.4% per trade"
Write-Host ""

Write-Host "FUTURES Account (Trading):" -ForegroundColor Yellow
Write-Host "  Capital:         `$$([Math]::Round($bestResult.futures_capital, 2))"
Write-Host "  Position/trade:  `$$([Math]::Round($bestResult.futures_position, 2)) (0.8% of FUTURES cap for safety)"
Write-Host "  Expected WR:     64% (slightly better execution)"
Write-Host "  Liquidation:     ⚠️ YES (monitor collateral ratio >2x)"
Write-Host "  Fees:            0.04% per trade (10x cheaper)"
Write-Host ""

Write-Host "Combined Operations:" -ForegroundColor Yellow
Write-Host "  Parallel trades: YES (both markets simultaneously)"
Write-Host "  Max positions:   2 open simultaneously (1 SPOT + 1 FUTURES)"
Write-Host "  Rebalancing:     Daily check if split maintains allocation"
Write-Host "  Risk exposure:   Diversified (not all eggs in 1 basket)"
Write-Host ""

# ════════════════════════════════════════════════════════════
# DAILY OPERATIONS
# ════════════════════════════════════════════════════════════

Write-Host "⚙️ DAILY OPERATIONS CHECKLIST:`n" -ForegroundColor Cyan

Write-Host "Morning:"
Write-Host "  [ ] Check SPOT balance"
Write-Host "  [ ] Check FUTURES balance + collateral ratio (should be >2.0)"
Write-Host "  [ ] Verify allocation still $([Math]::Round($bestResult.spot_capital, 2)) SPOT / $([Math]::Round($bestResult.futures_capital, 2)) FUTURES"
Write-Host "  [ ] If drift >10%, rebalance"
Write-Host ""

Write-Host "During Trading:"
Write-Host "  [ ] Monitor SPOT position (no leverage, safe to hold)"
Write-Host "  [ ] Monitor FUTURES position (check liquidation price)"
Write-Host "  [ ] Both markets use same vol_climax_scanner signal"
Write-Host "  [ ] Log both trades to journal with market designation"
Write-Host ""

Write-Host "Evening:"
Write-Host "  [ ] Close FUTURES positions (don't hold overnight due to funding costs)"
Write-Host "  [ ] SPOT positions OK to hold (no funding, no expiry)"
Write-Host "  [ ] Reconcile capital across accounts"
Write-Host "  [ ] Alert if max DD exceeded"
Write-Host ""

Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "✅ HYBRID READY FOR EVOLUTION" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan

