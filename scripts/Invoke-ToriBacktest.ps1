# Invoke-ToriBacktest.ps1 - Walk-forward backtesting engine for Tori Trades
#
# Backtests Tori methodology on 1 month of historical 1H data
# - Walks through each candle as it "arrives"
# - Runs Tori analysis (trendline, setup validation)
# - Checks enhanced confluence score (5 signals)
# - Enters trade if setup valid + confluence >= 75
# - Tracks entry, exit, PnL, hold time
#
# Performance: ~3-5 min for 10 pairs, ~15-25 min for 50+ pairs
#
# PS 5.1, UTF-8 BOM

param(
    [int]$NumPairs = 10,
    [int]$NumCandles = 1440,  # 1 hour * 1440 = 60 days
    [double]$MinConfluenceScore = 75.0,
    [double]$RiskReward = 5.0,
    [string]$OutputPath = "c:\Users\thiag\Coinex_AI_USER_API\backtest\tori_backtest_results.json"
)

# ============================================================================
# LOAD DEPENDENCIES
# ============================================================================

$agentsDir = "c:\Users\thiag\Coinex_AI_USER_API\agents"
$libCoinexPath = Join-Path $agentsDir "lib_coinex.ps1"
$libToriPath = Join-Path $agentsDir "lib_tori_trades_scanner.ps1"
$libConfluencePath = Join-Path $agentsDir "lib_tori_confluence_detector.ps1"

if (-not (Test-Path $libCoinexPath)) {
    throw "lib_coinex.ps1 not found at $libCoinexPath"
}
if (-not (Test-Path $libToriPath)) {
    throw "lib_tori_trades_scanner.ps1 not found at $libToriPath"
}
if (-not (Test-Path $libConfluencePath)) {
    throw "lib_tori_confluence_detector.ps1 not found at $libConfluencePath"
}

Write-Host "Loading dependencies..." -ForegroundColor Cyan
. $libCoinexPath
. $libToriPath
. $libConfluencePath

# ============================================================================
# CONFIGURATION
# ============================================================================

$COINEX_BASE_URL = "https://api.coinex.com"
$TIMEFRAME = "1h"
$MIN_CONFLUENCE = $MinConfluenceScore
$MIN_RR = $RiskReward
$ACCOUNT_SIZE = 3000  # Assume $3k account for PnL calculation
$RISK_PER_TRADE = 0.01  # 1% per trade

# Trendline gates (from lib_tori_trades_scanner)
$TRENDLINE_MIN_TOUCHES = 2
$TRENDLINE_TOUCH_TOL_PCT = 1.5
$TRENDLINE_SLOPE_MIN_DEG = 5.0
$TRENDLINE_SLOPE_MAX_DEG = 35.0

# Proximity gates
$PROXIMITY_MIN_PCT = -3.0
$PROXIMITY_MAX_PCT = 5.0

# ============================================================================
# HELPER: LINEAR REGRESSION
# ============================================================================

function _LinReg {
    param([double[]]$Y)
    $n = $Y.Length
    if ($n -lt 2) {
        $intercept = if ($n -eq 1) { $Y[0] } else { 0 }
        return @{ slope = 0; intercept = $intercept }
    }
    $sumX = 0; $sumY = 0; $sumXY = 0; $sumX2 = 0
    for ($i = 0; $i -lt $n; $i++) {
        $sumX  += $i
        $sumY  += $Y[$i]
        $sumXY += $i * $Y[$i]
        $sumX2 += $i * $i
    }
    $denom = ($n * $sumX2) - ($sumX * $sumX)
    if ($denom -eq 0) {
        return @{ slope = 0; intercept = ($sumY / $n) }
    }
    $slope = (($n * $sumXY) - ($sumX * $sumY)) / $denom
    $intercept = ($sumY - ($slope * $sumX)) / $n
    return @{ slope = $slope; intercept = $intercept }
}

# ============================================================================
# HELPER: TRENDLINE DETECTION
# ============================================================================

function Get-Trendline-BT {
    param(
        [double[]]$Lows,
        [double[]]$Highs,
        [string]$TrendType
    )

    if ($Lows.Length -lt $TRENDLINE_MIN_TOUCHES) { return $null }

    $fitData = if ($TrendType -eq "LONG") { $Lows } else { $Highs }
    $lr = _LinReg -Y $fitData

    $touches = 0
    foreach ($i in 0..($fitData.Length - 1)) {
        $lineValue = $lr.intercept + ($lr.slope * $i)
        if ($lineValue -le 0) { continue }
        $diffPct = [Math]::Abs($fitData[$i] - $lineValue) / $lineValue * 100
        if ($diffPct -le $TRENDLINE_TOUCH_TOL_PCT) {
            $touches += 1
        }
    }

    if ($touches -lt $TRENDLINE_MIN_TOUCHES) { return $null }

    $slopeDeg = [Math]::Atan($lr.slope) * (180 / [Math]::PI)

    if ([Math]::Abs($slopeDeg) -lt $TRENDLINE_SLOPE_MIN_DEG -or
        [Math]::Abs($slopeDeg) -gt $TRENDLINE_SLOPE_MAX_DEG) {
        return $null
    }

    $startPrice = $lr.intercept
    $endPrice = $lr.intercept + ($lr.slope * ($fitData.Length - 1))

    return [PSCustomObject]@{
        slope_deg = $slopeDeg
        touches = $touches
        intercept = $lr.intercept
        slope_raw = $lr.slope
        start_price = $startPrice
        end_price = $endPrice
    }
}

# ============================================================================
# HELPER: RSI CALCULATION
# ============================================================================

function Get-RSI-BT {
    param([double[]]$Closes, [int]$Period = 14)

    if ($Closes.Length -lt ($Period + 1)) { return 50.0 }

    $gains = 0; $losses = 0
    for ($i = 1; $i -le $Period; $i++) {
        $delta = $Closes[$i] - $Closes[$i - 1]
        if ($delta -gt 0) { $gains += $delta }
        else { $losses += [Math]::Abs($delta) }
    }

    $avgGain = $gains / $Period
    $avgLoss = $losses / $Period

    for ($i = $Period + 1; $i -lt $Closes.Length; $i++) {
        $delta = $Closes[$i] - $Closes[$i - 1]
        if ($delta -gt 0) {
            $avgGain = ($avgGain * ($Period - 1) + $delta) / $Period
            $avgLoss = $avgLoss * ($Period - 1) / $Period
        } else {
            $avgGain = $avgGain * ($Period - 1) / $Period
            $avgLoss = ($avgLoss * ($Period - 1) + [Math]::Abs($delta)) / $Period
        }
    }

    if ($avgLoss -eq 0) { return 100.0 }
    $rs = $avgGain / $avgLoss
    return 100 - (100 / (1 + $rs))
}

# ============================================================================
# HELPER: FIBONACCI TARGET
# ============================================================================

function Get-FibonacciTarget-BT {
    param(
        [double]$Entry,
        [double]$Stop,
        [string]$TrendType,
        [double]$RatioTarget
    )

    $risk = [Math]::Abs($Entry - $Stop)

    if ($TrendType -eq "LONG") {
        return $Entry + ($risk * $RatioTarget)
    } else {
        return $Entry - ($risk * $RatioTarget)
    }
}

# ============================================================================
# WALK-FORWARD BACKTEST
# ============================================================================

function Invoke-WalkForwardTest {
    param(
        [string]$Market,
        [PSObject[]]$AllCandles
    )

    Write-Verbose "Backtesting $Market with $($AllCandles.Count) candles..."

    $trades = @()
    $activePosition = $null

    # Walk through each candle
    for ($barIdx = 50; $barIdx -lt $AllCandles.Count; $barIdx++) {
        $currentCandle = $AllCandles[$barIdx]
        $historyCandles = $AllCandles[0..$barIdx]

        # Extract OHLCV for analysis
        $closes = @($historyCandles | ForEach-Object { [double]$_.close })
        $opens = @($historyCandles | ForEach-Object { [double]$_.open })
        $highs = @($historyCandles | ForEach-Object { [double]$_.high })
        $lows = @($historyCandles | ForEach-Object { [double]$_.low })
        $volumes = @($historyCandles | ForEach-Object { [double]$_.volume })

        $currentPrice = $closes[-1]

        # Check if active position hit target or stop
        if ($activePosition) {
            $closed = $false

            # Hit target?
            if ($activePosition.setup_type -eq "LONG" -and $currentPrice -ge $activePosition.target) {
                $exitPrice = $activePosition.target
                $closed = $true
            }
            elseif ($activePosition.setup_type -eq "SHORT" -and $currentPrice -le $activePosition.target) {
                $exitPrice = $activePosition.target
                $closed = $true
            }

            # Hit stop loss?
            if ($activePosition.setup_type -eq "LONG" -and $currentPrice -le $activePosition.stop_loss) {
                $exitPrice = $activePosition.stop_loss
                $closed = $true
            }
            elseif ($activePosition.setup_type -eq "SHORT" -and $currentPrice -ge $activePosition.stop_loss) {
                $exitPrice = $activePosition.stop_loss
                $closed = $true
            }

            if ($closed) {
                # Record trade
                $pnlUsdt = if ($activePosition.setup_type -eq "LONG") {
                    ($exitPrice - $activePosition.entry_price) * ($ACCOUNT_SIZE * $RISK_PER_TRADE / [Math]::Abs($activePosition.entry_price - $activePosition.stop_loss))
                } else {
                    ($activePosition.entry_price - $exitPrice) * ($ACCOUNT_SIZE * $RISK_PER_TRADE / [Math]::Abs($activePosition.stop_loss - $activePosition.entry_price))
                }

                $pnlPct = (($exitPrice - $activePosition.entry_price) / $activePosition.entry_price) * 100

                $holdCandles = $barIdx - $activePosition.entry_bar

                $trades += [PSCustomObject]@{
                    pair = $Market
                    timeframe = $TIMEFRAME
                    setup_type = $activePosition.setup_type
                    entry_ts = $activePosition.entry_ts
                    entry_price = [Math]::Round($activePosition.entry_price, 8)
                    stop_loss = [Math]::Round($activePosition.stop_loss, 8)
                    target = [Math]::Round($activePosition.target, 8)
                    exit_ts = $currentCandle.ts
                    exit_price = [Math]::Round($exitPrice, 8)
                    pnl_pct = [Math]::Round($pnlPct, 2)
                    pnl_usdt = [Math]::Round($pnlUsdt, 2)
                    hold_time_min = $holdCandles * 60  # 1H candles = 60 min each
                    confluence_signals_at_entry = $activePosition.confluence_signals -join ", "
                    confluence_score = $activePosition.confluence_score
                    result = if ($pnlUsdt -gt 0) { "WIN" } elseif ($pnlUsdt -lt 0) { "LOSS" } else { "BREAKEVEN" }
                }

                $activePosition = $null
            }
        }

        # Only look for new entries if no active position
        if (-not $activePosition -and $barIdx -lt ($AllCandles.Count - 1)) {
            # Try LONG setup
            $longTL = Get-Trendline-BT -Lows $lows -Highs $highs -TrendType "LONG"
            if ($longTL) {
                $proximity = (($currentPrice - $longTL.start_price) / $longTL.start_price) * 100

                if ($proximity -ge $PROXIMITY_MIN_PCT -and $proximity -le $PROXIMITY_MAX_PCT) {
                    # Calculate confluence score
                    $confluenceScore = Get-ConfluenceScoreEnhanced -Candles $historyCandles -SetupType "LONG" `
                        -TrendlineStartPrice $longTL.start_price -TrendlineTouches $longTL.touches

                    if ($confluenceScore.total_score -ge $MIN_CONFLUENCE) {
                        # Calculate risk and target
                        $stop = $longTL.start_price * 0.98
                        $risk = $currentPrice - $stop
                        $target = Get-FibonacciTarget-BT -Entry $currentPrice -Stop $stop -TrendType "LONG" -RatioTarget $MIN_RR
                        $reward = $target - $currentPrice
                        $ratio = if ($risk -ne 0) { $reward / $risk } else { 0 }

                        if ($ratio -ge $MIN_RR) {
                            $activePosition = @{
                                market = $Market
                                entry_ts = $currentCandle.ts
                                entry_bar = $barIdx
                                entry_price = $currentPrice
                                stop_loss = $stop
                                target = $target
                                setup_type = "LONG"
                                confluence_score = $confluenceScore.total_score
                                confluence_signals = $confluenceScore.signals_fired
                                ratio = $ratio
                            }
                        }
                    }
                }
            }

            # Try SHORT setup
            $shortTL = Get-Trendline-BT -Lows $lows -Highs $highs -TrendType "SHORT"
            if ($shortTL) {
                $proximity = (($shortTL.start_price - $currentPrice) / $shortTL.start_price) * 100

                if ($proximity -ge $PROXIMITY_MIN_PCT -and $proximity -le $PROXIMITY_MAX_PCT) {
                    # Calculate confluence score
                    $confluenceScore = Get-ConfluenceScoreEnhanced -Candles $historyCandles -SetupType "SHORT" `
                        -TrendlineStartPrice $shortTL.start_price -TrendlineTouches $shortTL.touches

                    if ($confluenceScore.total_score -ge $MIN_CONFLUENCE) {
                        # Calculate risk and target
                        $stop = $shortTL.start_price * 1.02
                        $risk = $stop - $currentPrice
                        $target = Get-FibonacciTarget-BT -Entry $currentPrice -Stop $stop -TrendType "SHORT" -RatioTarget $MIN_RR
                        $reward = $currentPrice - $target
                        $ratio = if ($risk -ne 0) { $reward / $risk } else { 0 }

                        if ($ratio -ge $MIN_RR) {
                            $activePosition = @{
                                market = $Market
                                entry_ts = $currentCandle.ts
                                entry_bar = $barIdx
                                entry_price = $currentPrice
                                stop_loss = $stop
                                target = $target
                                setup_type = "SHORT"
                                confluence_score = $confluenceScore.total_score
                                confluence_signals = $confluenceScore.signals_fired
                                ratio = $ratio
                            }
                        }
                    }
                }
            }
        }
    }

    return $trades
}

# ============================================================================
# MAIN BACKTEST ROUTINE
# ============================================================================

function Invoke-ToriBacktestMain {
    Write-Host "Tori Trades Backtest Engine" -ForegroundColor Green
    Write-Host "Parameters: $NumPairs pairs, $NumCandles candles ($($NumCandles/24) days), Min Confluence=$MinConfluenceScore" -ForegroundColor Cyan

    # Get futures markets
    Write-Host "Fetching CoinEx futures market list..." -ForegroundColor Cyan
    try {
        $allMarkets = CoinEx-GetFuturesMarkets | Where-Object { $_.market -match "USDT$" } | Select-Object -ExpandProperty market
    } catch {
        Write-Error "Failed to fetch markets: $_"
        return @()
    }

    if (-not $allMarkets) {
        Write-Error "No futures markets found"
        return @()
    }

    $allMarkets = @($allMarkets | Sort-Object)
    $pairsToTest = @($allMarkets | Select-Object -First $NumPairs)
    Write-Host "Backtesting $($pairsToTest.Count) pairs..." -ForegroundColor Yellow

    $allTrades = @()
    $tested = 0

    foreach ($pair in $pairsToTest) {
        $tested += 1
        $pct = [Math]::Round(($tested / $pairsToTest.Count) * 100)
        Write-Progress -Activity "Backtesting pairs" -Status "$pair ($tested/$($pairsToTest.Count))" -PercentComplete $pct

        try {
            # Fetch candles
            $candles = CoinEx-GetFuturesCandles -market $pair -period $TIMEFRAME -limit $NumCandles
            if (-not $candles -or $candles.Count -lt 100) {
                Write-Verbose "  [$pair] insufficient candles ($($candles.Count))"
                continue
            }

            # Run backtest
            $trades = Invoke-WalkForwardTest -Market $pair -AllCandles $candles
            $allTrades += @($trades)

            Write-Verbose "  [$pair] $($trades.Count) trades"
        } catch {
            Write-Verbose "  [$pair] error: $_"
        }

        Start-Sleep -Milliseconds 100
    }

    Write-Progress -Activity "Backtesting pairs" -Completed

    return $allTrades
}

# ============================================================================
# PERFORMANCE METRICS
# ============================================================================

function Calculate-BacktestMetrics {
    param([PSObject[]]$Trades)

    if ($Trades.Count -eq 0) {
        return [PSCustomObject]@{
            total_trades = 0
            wins = 0
            losses = 0
            breakeven = 0
            win_rate_pct = 0.0
            avg_win_usdt = 0.0
            avg_loss_usdt = 0.0
            profit_factor = 0.0
            max_consecutive_losses = 0
            total_pnl = 0.0
            avg_hold_min = 0.0
            expectancy = 0.0
        }
    }

    $wins = @($Trades | Where-Object { $_.result -eq "WIN" })
    $losses = @($Trades | Where-Object { $_.result -eq "LOSS" })
    $breakeven = @($Trades | Where-Object { $_.result -eq "BREAKEVEN" })

    $winRate = if ($Trades.Count -gt 0) { ($wins.Count / $Trades.Count) * 100 } else { 0 }

    $totalWins = ($wins | Measure-Object -Property pnl_usdt -Sum).Sum
    $totalLosses = ($losses | Measure-Object -Property pnl_usdt -Sum).Sum
    $totalPnL = $totalWins + $totalLosses

    $avgWin = if ($wins.Count -gt 0) { $totalWins / $wins.Count } else { 0 }
    $avgLoss = if ($losses.Count -gt 0) { $totalLosses / $losses.Count } else { 0 }

    $profitFactor = if ($totalLosses -ne 0) { -$totalWins / $totalLosses } else { 0 }

    $maxConsecutiveLosses = 0
    $currentStreak = 0
    foreach ($trade in $Trades) {
        if ($trade.result -eq "LOSS") {
            $currentStreak += 1
            if ($currentStreak -gt $maxConsecutiveLosses) {
                $maxConsecutiveLosses = $currentStreak
            }
        } else {
            $currentStreak = 0
        }
    }

    $avgHold = ($Trades | Measure-Object -Property hold_time_min -Average).Average
    $expectancy = if ($Trades.Count -gt 0) { $totalPnL / $Trades.Count } else { 0 }

    return [PSCustomObject]@{
        total_trades = $Trades.Count
        wins = $wins.Count
        losses = $losses.Count
        breakeven = $breakeven.Count
        win_rate_pct = [Math]::Round($winRate, 2)
        avg_win_usdt = [Math]::Round($avgWin, 2)
        avg_loss_usdt = [Math]::Round($avgLoss, 2)
        profit_factor = [Math]::Round($profitFactor, 2)
        max_consecutive_losses = $maxConsecutiveLosses
        total_pnl = [Math]::Round($totalPnL, 2)
        avg_hold_min = [Math]::Round($avgHold, 0)
        expectancy = [Math]::Round($expectancy, 2)
    }
}

# ============================================================================
# EXECUTION
# ============================================================================

try {
    $trades = Invoke-ToriBacktestMain
    $metrics = Calculate-BacktestMetrics -Trades $trades

    Write-Host "`n=== BACKTEST RESULTS ===" -ForegroundColor Green
    Write-Host "Total trades: $($metrics.total_trades)" -ForegroundColor Cyan
    Write-Host "Wins: $($metrics.wins) | Losses: $($metrics.losses) | Breakeven: $($metrics.breakeven)"
    Write-Host "Win rate: $($metrics.win_rate_pct)%"
    Write-Host "Avg win: `$$($metrics.avg_win_usdt) | Avg loss: `$$($metrics.avg_loss_usdt)"
    Write-Host "Profit factor: $($metrics.profit_factor)"
    Write-Host "Total PnL: `$$($metrics.total_pnl)"
    Write-Host "Expectancy: `$$($metrics.expectancy) per trade"
    Write-Host "Max consecutive losses: $($metrics.max_consecutive_losses)"

    # Export results
    if ($trades.Count -gt 0) {
        $export = @{
            metadata = @{
                num_pairs = $NumPairs
                num_candles = $NumCandles
                min_confluence_score = $MinConfluenceScore
                risk_reward = $RiskReward
                backtest_date = (Get-Date -Format "o")
            }
            metrics = $metrics
            trades = $trades
        }

        $json = $export | ConvertTo-Json -Depth 10
        Set-Content -Path $OutputPath -Value $json -Encoding UTF8
        Write-Host "`nResults exported to: $OutputPath" -ForegroundColor Green
    }
}
catch {
    Write-Error "Backtest failed: $_"
    exit 1
}
