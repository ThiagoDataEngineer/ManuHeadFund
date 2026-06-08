# Hybrid Orchestrator — Gerencia SPOT + FUTURES simultaneamente
# Objetivo: Executar o mesmo sinal em ambos mercados, mas com capital separado

<#
.SYNOPSIS
    Orquestra trades em SPOT e FUTURES em paralelo com capital allocation 50/50

.DESCRIPTION
    - Recebe um sinal (vol_climax + engulfing combo)
    - Aloca posição pra SPOT ($13.5) + FUTURES ($10.8)
    - Executa ambos simultânea ou sequencialmente
    - Monitora ambos até exit
    - Logs separados para análise por mercado

.NOTES
    Capital: $2,700.85
    SPOT: $1,350.43 (50%)
    FUTURES: $1,350.42 (50%)
#>

# ════════════════════════════════════════════════════════════
# INITIALIZATION
# ════════════════════════════════════════════════════════════

$script:HybridConfig = @{
    total_capital = $null  # Will be fetched ONCHAIN dynamically
    spot_pct = 0.50
    futures_pct = 0.50
    spot_capital = $null   # Will be calculated from onchain
    futures_capital = $null  # Will be calculated from onchain
    position_pct = 0.01  # 1% per trade in each market
    position_cap_usdt = 1.0  # Max USDT per market
    fallback_capital = 2700.85  # Only if onchain fetch fails
}

# ════════════════════════════════════════════════════════════
# INITIALIZATION — Fetch ONCHAIN capital
# ════════════════════════════════════════════════════════════

function Initialize-HybridConfig {
    Write-Host "💼 Initializing HybridConfig from ONCHAIN..." -ForegroundColor Cyan

    $spotBalance = 0
    $futuresBalance = 0

    # Fetch SPOT balance
    try {
        $spotUrl = "https://api.coinex.com/v2/spot/balance"
        $spotResp = Invoke-RestMethod -Uri $spotUrl -Method GET -TimeoutSec 5 -ErrorAction Stop
        if ($spotResp.code -eq 0 -and $spotResp.data) {
            foreach ($asset in $spotResp.data) {
                if ($asset.ccy -eq "USDT") {
                    $spotBalance = [double]($asset.available ?? 0)
                    break
                }
            }
        }
    } catch {
        Write-Host "⚠️ SPOT fetch failed, using fallback" -ForegroundColor Yellow
    }

    # Fetch FUTURES balance
    try {
        $futUrl = "https://api.coinex.com/v2/futures/balance"
        $futResp = Invoke-RestMethod -Uri $futUrl -Method GET -TimeoutSec 5 -ErrorAction Stop
        if ($futResp.code -eq 0 -and $futResp.data) {
            foreach ($asset in $futResp.data) {
                if ($asset.ccy -eq "USDT") {
                    $futuresBalance = [double]($asset.available ?? 0)
                    break
                }
            }
        }
    } catch {
        Write-Host "⚠️ FUTURES fetch failed, using fallback" -ForegroundColor Yellow
    }

    # Use real values or fallback
    if ($spotBalance -gt 0 -and $futuresBalance -gt 0) {
        $script:HybridConfig.spot_capital = $spotBalance
        $script:HybridConfig.futures_capital = $futuresBalance
        $script:HybridConfig.total_capital = $spotBalance + $futuresBalance
        Write-Host "✅ Loaded ONCHAIN: SPOT `$$([Math]::Round($spotBalance, 2)) + FUTURES `$$([Math]::Round($futuresBalance, 2))" -ForegroundColor Green
    } else {
        $script:HybridConfig.total_capital = $script:HybridConfig.fallback_capital
        $script:HybridConfig.spot_capital = $script:HybridConfig.fallback_capital * 0.50
        $script:HybridConfig.futures_capital = $script:HybridConfig.fallback_capital * 0.50
        Write-Host "⚠️ Using FALLBACK: `$$($script:HybridConfig.fallback_capital)" -ForegroundColor Yellow
    }
}

# Auto-initialize on first load
Initialize-HybridConfig

# ════════════════════════════════════════════════════════════
# MAIN ENTRY POINT
# ════════════════════════════════════════════════════════════

<#
.SYNOPSIS
    Execute-HybridSignal [-Signal <PSObject>] [-Regime <string>]

.EXAMPLE
    $signal = @{
        market = "BTCUSDT"
        type = "VOL_CLIMAX_ENGULFING"
        confidence = 0.42
        direction = "LONG"
        stop_loss_pct = 0.01
    }
    Execute-HybridSignal -Signal $signal -Regime "BEAR_WEAK"
#>

function Execute-HybridSignal {
    param(
        [Parameter(Mandatory=$true)]
        [PSObject] $Signal,

        [Parameter(Mandatory=$true)]
        [string] $Regime
    )

    # Validate signal
    if (-not $Signal.market -or -not $Signal.type) {
        Write-Error "Invalid signal: missing market or type"
        return $null
    }

    # Calculate positions
    $positions = Get-HybridPositionSizes -Regime $Regime

    Write-Host "`n🌐 HYBRID EXECUTION: $($Signal.market) — $($Signal.type)" -ForegroundColor Cyan
    Write-Host "  Regime: $Regime" -ForegroundColor Gray
    Write-Host "  Confidence: $($Signal.confidence)" -ForegroundColor Gray
    Write-Host "  SPOT position: `$$($positions.spot_usdt) | FUTURES position: `$$($positions.futures_usdt)" -ForegroundColor Cyan

    # Execute both markets
    $spotTrade = Execute-SpotTrade -Signal $Signal -PositionSizeUSDT $positions.spot_usdt -Regime $Regime
    $futuresTrade = Execute-FuturesTrade -Signal $Signal -PositionSizeUSDT $positions.futures_usdt -Regime $Regime

    return @{
        timestamp = Get-Date
        signal_type = $Signal.type
        market = $Signal.market
        regime = $Regime
        spot_trade = $spotTrade
        futures_trade = $futuresTrade
        combined_risk = $spotTrade.risk_usd + $futuresTrade.risk_usd
    }
}

# ════════════════════════════════════════════════════════════
# POSITION SIZING
# ════════════════════════════════════════════════════════════

function Get-HybridPositionSizes {
    param(
        [Parameter(Mandatory=$true)]
        [string] $Regime
    )

    # Regime multipliers (same as SPOT sizing)
    $multipliers = @{
        "BULL_STRONG" = 1.0
        "BULL_WEAK" = 1.0
        "BEAR_WEAK" = 1.0
        "BEAR_STRONG" = 0.5
    }

    $multiplier = $multipliers[$Regime] ?? 1.0

    # Base positions (1% of respective capital)
    $spotBaseUSdt = $script:HybridConfig.spot_capital * 0.01
    $futuresBaseUSDT = $script:HybridConfig.futures_capital * 0.01 * 0.8  # 0.8% for safety

    # Apply regime multiplier
    $spotPosition = $spotBaseUSdt * $multiplier
    $futuresPosition = $futuresBaseUSDT * $multiplier

    # Hard cap at 1% of total capital per market
    $spotMaxCap = $script:HybridConfig.spot_capital * 0.01
    $futuresMaxCap = $script:HybridConfig.futures_capital * 0.01

    $spotPosition = [Math]::Min($spotPosition, $spotMaxCap)
    $futuresPosition = [Math]::Min($futuresPosition, $futuresMaxCap)

    return @{
        spot_usdt = $spotPosition
        futures_usdt = $futuresPosition
        spot_pct = ($spotPosition / $script:HybridConfig.spot_capital) * 100
        futures_pct = ($futuresPosition / $script:HybridConfig.futures_capital) * 100
        regime = $Regime
    }
}

# ════════════════════════════════════════════════════════════
# SPOT EXECUTION
# ════════════════════════════════════════════════════════════

function Execute-SpotTrade {
    param(
        [PSObject] $Signal,
        [double] $PositionSizeUSDT,
        [string] $Regime
    )

    $entryPrice = $Signal.entry_price ?? 100  # Placeholder
    $stopLossPrice = $entryPrice * (1 - $Signal.stop_loss_pct)
    $riskUSD = $PositionSizeUSDT * $Signal.stop_loss_pct

    $trade = @{
        market = "SPOT"
        pair = $Signal.market
        position_size_usd = $PositionSizeUSDT
        entry_price = $entryPrice
        stop_loss = $stopLossPrice
        risk_usd = $riskUSD
        signal_type = $Signal.type
        confidence = $Signal.confidence
        regime = $Regime
        timestamp = Get-Date
        status = "EXECUTED"
        liquidation_risk = "NONE"
    }

    Write-Host "    SPOT trade queued: $PositionSizeUSDT USDT @ $entryPrice (risk: `$$riskUSD)" -ForegroundColor Green

    return $trade
}

# ════════════════════════════════════════════════════════════
# FUTURES EXECUTION
# ════════════════════════════════════════════════════════════

function Execute-FuturesTrade {
    param(
        [PSObject] $Signal,
        [double] $PositionSizeUSDT,
        [string] $Regime
    )

    $entryPrice = $Signal.entry_price ?? 100
    $stopLossPrice = $entryPrice * (1 - $Signal.stop_loss_pct)
    $riskUSD = $PositionSizeUSDT * $Signal.stop_loss_pct

    # Calculate liquidation price (assuming 1x leverage, minimum 2x collateral)
    $collateralRatio = 2.0  # Conservative: 2x collateral needed
    $liquidationPrice = $entryPrice * (1 - (1 / $collateralRatio))

    $trade = @{
        market = "FUTURES"
        pair = $Signal.market
        position_size_usd = $PositionSizeUSDT
        entry_price = $entryPrice
        stop_loss = $stopLossPrice
        liquidation_price = $liquidationPrice
        collateral_ratio = $collateralRatio
        risk_usd = $riskUSD
        signal_type = $Signal.type
        confidence = $Signal.confidence
        regime = $Regime
        timestamp = Get-Date
        status = "EXECUTED"
        liquidation_risk = "MONITOR"  # Always monitor futures
    }

    Write-Host "    FUTURES trade queued: $PositionSizeUSDT USDT @ $entryPrice (liq: $liquidationPrice, risk: `$$riskUSD)" -ForegroundColor Yellow

    return $trade
}

# ════════════════════════════════════════════════════════════
# MONITORING & RISK MANAGEMENT
# ════════════════════════════════════════════════════════════

function Monitor-HybridPositions {
    param(
        [PSObject] $HybridTrade,
        [hashtable] $MarketData  # Current prices
    )

    Write-Host "`n📊 HYBRID POSITION MONITORING" -ForegroundColor Cyan

    # Monitor SPOT
    $spotTrade = $HybridTrade.spot_trade
    $spotCurrentPrice = $MarketData[$spotTrade.pair]
    $spotPnL = ($spotCurrentPrice - $spotTrade.entry_price) / $spotTrade.entry_price * $spotTrade.position_size_usd
    $spotStatus = if ($spotCurrentPrice -lt $spotTrade.stop_loss) { "🔴 STOP HIT" } else { "🟢 ACTIVE" }

    Write-Host "  SPOT:" -ForegroundColor Gray
    Write-Host "    Entry: $($spotTrade.entry_price) | Current: $spotCurrentPrice | Stop: $($spotTrade.stop_loss)"
    Write-Host "    P&L: `$$([Math]::Round($spotPnL, 2)) | Status: $spotStatus"

    # Monitor FUTURES
    $futuresTrade = $HybridTrade.futures_trade
    $futuresCurrentPrice = $MarketData[$futuresTrade.pair]
    $futuresPnL = ($futuresCurrentPrice - $futuresTrade.entry_price) / $futuresTrade.entry_price * $futuresTrade.position_size_usd
    $liqRisk = if ($futuresCurrentPrice -lt $futuresTrade.liquidation_price) { "🔴 LIQUIDATION RISK" } else { "🟡 MONITOR" }
    $futuresStatus = if ($futuresCurrentPrice -lt $futuresTrade.stop_loss) { "🔴 STOP HIT" } else { $liqRisk }

    Write-Host "  FUTURES:" -ForegroundColor Gray
    Write-Host "    Entry: $($futuresTrade.entry_price) | Current: $futuresCurrentPrice | Liq: $($futuresTrade.liquidation_price)"
    Write-Host "    P&L: `$$([Math]::Round($futuresPnL, 2)) | Status: $futuresStatus"

    Write-Host "  Combined P&L: `$$([Math]::Round($spotPnL + $futuresPnL, 2))" -ForegroundColor Green
}

# ════════════════════════════════════════════════════════════
# DAILY REBALANCING
# ════════════════════════════════════════════════════════════

function Rebalance-HybridCapital {
    param(
        [double] $CurrentSpotBalance,
        [double] $CurrentFuturesBalance
    )

    $totalBalance = $CurrentSpotBalance + $CurrentFuturesBalance
    $targetSpotBalance = $totalBalance * $script:HybridConfig.spot_pct
    $targetFuturesBalance = $totalBalance * $script:HybridConfig.futures_pct

    $spotDrift = [Math]::Abs($CurrentSpotBalance - $targetSpotBalance)
    $futuresDrift = [Math]::Abs($CurrentFuturesBalance - $targetFuturesBalance)
    $driftPct = ($spotDrift / $totalBalance) * 100

    Write-Host "`n💰 HYBRID REBALANCING CHECK" -ForegroundColor Cyan
    Write-Host "  Total balance: `$$totalBalance" -ForegroundColor Gray
    Write-Host "  SPOT: `$$CurrentSpotBalance (target: `$$targetSpotBalance, drift: $([Math]::Round($driftPct, 1))%)" -ForegroundColor Gray
    Write-Host "  FUTURES: `$$CurrentFuturesBalance (target: `$$targetFuturesBalance, drift: $([Math]::Round($driftPct, 1))%)" -ForegroundColor Gray

    if ($driftPct -gt 10) {
        Write-Host "  ⚠️ Drift >10% detected! Rebalancing needed." -ForegroundColor Yellow
        Write-Host "    Transfer `$$([Math]::Round($spotDrift, 2)) to rebalance" -ForegroundColor Yellow
        return @{
            rebalance_needed = $true
            from_market = if ($CurrentSpotBalance -gt $targetSpotBalance) { "SPOT" } else { "FUTURES" }
            amount = $spotDrift
        }
    } else {
        Write-Host "  ✅ Balanced (drift <10%)" -ForegroundColor Green
        return @{ rebalance_needed = $false }
    }
}

# ════════════════════════════════════════════════════════════
# LOGGING & AUDIT
# ════════════════════════════════════════════════════════════

function Log-HybridTrade {
    param(
        [PSObject] $HybridTrade,
        [string] $JournalPath = "journal/hybrid_trades.jsonl"
    )

    $entry = @{
        timestamp = $HybridTrade.timestamp
        signal_type = $HybridTrade.signal_type
        market = $HybridTrade.market
        regime = $HybridTrade.regime
        spot_position = $HybridTrade.spot_trade.position_size_usd
        futures_position = $HybridTrade.futures_trade.position_size_usd
        combined_risk = $HybridTrade.combined_risk
        spot_entry = $HybridTrade.spot_trade.entry_price
        futures_entry = $HybridTrade.futures_trade.entry_price
        status = "LOGGED"
    }

    $entry | ConvertTo-Json | Add-Content -Path $JournalPath
    Write-Host "  📝 Logged to $JournalPath" -ForegroundColor Gray
}

# ════════════════════════════════════════════════════════════
# NOTE: Functions automatically available via dot-sourcing in PS 5.1
# No Export-ModuleMember needed for *.ps1 scripts
# ════════════════════════════════════════════════════════════

