# lib_faro_backtest.ps1 — Backtest simulation engine with metrics calculation

function Run-BacktestSimulation {
    param(
        [PSCustomObject[]] $Trades,
        [decimal] $InitialCapital = 5000,
        [decimal] $CommissionPercent = 0.001  # 0.1% trading fee
    )

    if (-not $Trades -or $Trades.Count -eq 0) {
        return [PSCustomObject]@{
            total_trades = 0
            winning_trades = 0
            losing_trades = 0
            win_rate = 0
            total_pnl = 0
            return_pct = 0
            avg_win = 0
            avg_loss = 0
            profit_factor = 0
            max_drawdown_pct = 0
            sharpe_ratio = 0
            status = "NO_TRADES"
        }
    }

    # Calculate P&L for each trade
    $tradeResults = @()
    $runningBalance = $InitialCapital
    $peakBalance = $InitialCapital

    foreach ($trade in $Trades) {
        $entryPrice = [decimal]$trade.entry_price
        $exitPrice = [decimal]$trade.exit_price
        $quantity = if ($null -ne $trade.quantity) { [decimal]$trade.quantity } else { 1 }

        # Calculate raw profit
        $rawPnL = ($exitPrice - $entryPrice) * $quantity

        # Apply commission on both entry and exit (based on trade value)
        $commission = $entryPrice * $quantity * $CommissionPercent * 2

        $netPnL = $rawPnL - $commission

        # Update balance
        $runningBalance += $netPnL

        # Track peak for drawdown calculation
        if ($runningBalance -gt $peakBalance) {
            $peakBalance = $runningBalance
        }

        $tradeResults += [PSCustomObject]@{
            entry_price = $entryPrice
            exit_price = $exitPrice
            quantity = $quantity
            gross_pnl = $rawPnL
            commission = $commission
            net_pnl = $netPnL
            running_balance = $runningBalance
            is_win = ($netPnL -gt 0)
            return_pct = ($netPnL / $InitialCapital) * 100
        }
    }

    # Calculate metrics
    $wins = @($tradeResults | Where-Object { $_.net_pnl -gt 0 })
    $losses = @($tradeResults | Where-Object { $_.net_pnl -le 0 })
    $totalTrades = $tradeResults.Count
    $winRate = if ($totalTrades -gt 0) { [decimal]($wins.Count) / [decimal]($totalTrades) } else { 0 }
    $totalPnL = ($tradeResults | Measure-Object -Property net_pnl -Sum).Sum
    if ($null -eq $totalPnL) { $totalPnL = 0 }
    $returnPct = ($totalPnL / $InitialCapital) * 100
    $avgWin = if ($wins.Count -gt 0) { ($wins | Measure-Object -Property net_pnl -Average).Average } else { 0 }
    $avgLoss = if ($losses.Count -gt 0) { ($losses | Measure-Object -Property net_pnl -Average).Average } else { 0 }

    # Profit factor (gross wins / gross losses)
    $profitFactor = 0
    if ($losses.Count -gt 0) {
        $winsSum   = ($wins   | Measure-Object -Property gross_pnl -Sum).Sum; if ($null -eq $winsSum)   { $winsSum   = 0 }
        $lossesSum = ($losses | Measure-Object -Property gross_pnl -Sum).Sum; if ($null -eq $lossesSum) { $lossesSum = 0 }
        $totalWins   = $winsSum
        $totalLosses = [Math]::Abs($lossesSum)
        if ($totalLosses -gt 0) {
            $profitFactor = $totalWins / $totalLosses
        }
    }

    # Max drawdown (peak-to-trough)
    $maxDrawdown = 0
    $lastPeak = $InitialCapital
    foreach ($result in $tradeResults) {
        if ($result.running_balance -gt $lastPeak) {
            $lastPeak = $result.running_balance
        }
        $drawdown = $lastPeak - $result.running_balance
        if ($drawdown -gt $maxDrawdown) {
            $maxDrawdown = $drawdown
        }
    }
    $maxDrawdownPct = if ($InitialCapital -gt 0) { ($maxDrawdown / $InitialCapital) * 100 } else { 0 }

    # Sharpe ratio (return / volatility)
    $returns = @($tradeResults | ForEach-Object { $_.return_pct })
    $sharpeRatio = 0
    if ($returns.Count -gt 1) {
        $mean = ($returns | Measure-Object -Average).Average
        $variance = $returns | ForEach-Object { [Math]::Pow($_ - $mean, 2) } | Measure-Object -Average | Select-Object -ExpandProperty Average
        $stdDev = [Math]::Sqrt($variance)
        if ($stdDev -gt 0) {
            # Annualized Sharpe (assuming 252 trading days)
            $sharpeRatio = ($mean * 252 / $stdDev)
        }
    }

    return [PSCustomObject]@{
        total_trades = $totalTrades
        winning_trades = $wins.Count
        losing_trades = $losses.Count
        win_rate = [Math]::Round($winRate, 4)
        total_pnl = [Math]::Round($totalPnL, 2)
        return_pct = [Math]::Round($returnPct, 2)
        avg_win = [Math]::Round($avgWin, 2)
        avg_loss = [Math]::Round($avgLoss, 2)
        profit_factor = [Math]::Round($profitFactor, 2)
        max_drawdown_pct = [Math]::Round($maxDrawdownPct, 2)
        sharpe_ratio = [Math]::Round($sharpeRatio, 2)
        final_capital = [Math]::Round($runningBalance, 2)
        status = "COMPLETE"
    }
}

function Calculate-OptimalPositionSize {
    param(
        [decimal] $AccountSize = 5000,
        [int] $WinRate = 55,  # percentage
        [decimal] $AvgWinRatio = 0.05,  # +5% win
        [decimal] $AvgLossRatio = 0.02  # -2% loss
    )

    # Kelly Criterion: f* = (p*b - q) / b
    # f* = optimal fraction of account to risk
    # p = win probability, q = 1-p, b = win/loss ratio

    $pWin = $WinRate / 100
    $qLoss = 1 - $pWin
    $bRatio = $AvgWinRatio / $AvgLossRatio

    $kellyFraction = ($pWin * $bRatio - $qLoss) / $bRatio

    # Conservative: use half Kelly (lower variance)
    $conservativeRisk = $kellyFraction / 2

    # Cap at reasonable levels
    $recommendedRisk = [Math]::Max(0.01, [Math]::Min($conservativeRisk, 0.10))

    $positionSize = $AccountSize * $recommendedRisk

    return [PSCustomObject]@{
        kelly_fraction = [Math]::Round($kellyFraction, 4)
        conservative_kelly = [Math]::Round($conservativeRisk, 4)
        recommended_risk_pct = [Math]::Round($recommendedRisk * 100, 2)
        position_size = [Math]::Round($positionSize, 2)
        account_size = $AccountSize
        expected_daily_return = [Math]::Round($AccountSize * $recommendedRisk * 0.5, 2)
    }
}

function Get-BacktestMetricsInterpretation {
    param(
        [PSCustomObject] $BacktestResult
    )

    $interpretation = @()

    # Win rate interpretation
    if ($BacktestResult.win_rate -lt 0.40) {
        $interpretation += "❌ Win rate too low (<40%); strategy needs refinement"
    }
    elseif ($BacktestResult.win_rate -lt 0.50) {
        $interpretation += "⚠️  Win rate below 50%; needs positive expectancy (high R:R)"
    }
    elseif ($BacktestResult.win_rate -lt 0.55) {
        $interpretation += "✓ Win rate acceptable (50-55%); decent strategy"
    }
    else {
        $interpretation += "✅ Win rate excellent (55%+); strong edge"
    }

    # Sharpe ratio interpretation
    if ($BacktestResult.sharpe_ratio -lt 0.5) {
        $interpretation += "❌ Sharpe too low; inconsistent returns"
    }
    elseif ($BacktestResult.sharpe_ratio -lt 1.0) {
        $interpretation += "⚠️  Sharpe marginal; need better risk management"
    }
    elseif ($BacktestResult.sharpe_ratio -lt 2.0) {
        $interpretation += "✓ Sharpe reasonable (1-2); good risk-adjusted return"
    }
    else {
        $interpretation += "✅ Sharpe excellent (2+); excellent risk management"
    }

    # Profit factor interpretation
    if ($BacktestResult.profit_factor -lt 1.0) {
        $interpretation += "❌ Losing money; strategy not viable"
    }
    elseif ($BacktestResult.profit_factor -lt 1.5) {
        $interpretation += "⚠️  Profit factor weak; barely profitable"
    }
    elseif ($BacktestResult.profit_factor -lt 2.5) {
        $interpretation += "✓ Profit factor good (1.5-2.5); solid strategy"
    }
    else {
        $interpretation += "✅ Profit factor excellent (2.5+); strong profitability"
    }

    # Drawdown interpretation
    if ($BacktestResult.max_drawdown_pct -gt 30) {
        $interpretation += "❌ Drawdown too high (>30%); too risky"
    }
    elseif ($BacktestResult.max_drawdown_pct -gt 20) {
        $interpretation += "⚠️  Drawdown significant (20-30%); monitor closely"
    }
    else {
        $interpretation += "✓ Drawdown acceptable (<20%); manageable risk"
    }

    return $interpretation -join " | "
}
