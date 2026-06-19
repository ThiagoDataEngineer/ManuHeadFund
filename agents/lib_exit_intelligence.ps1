# lib_exit_intelligence.ps1
# Exit Intelligence 4-Layer: sai de trades em lucro automaticamente
# Roda a cada 5 min no trailing_stop_monitor
# 2026-06-19: Implementado para $30k/mês roadmap

function Get-ExitSignals {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double]$CurrentPrice,
        [Parameter(Mandatory)] [double]$EntryPrice,
        [Parameter(Mandatory)] [double]$Quantity,
        [Parameter(Mandatory)] [double]$StopLoss,
        [Parameter(Mandatory)] [object[]]$Candles1H,  # last 24 candles
        [Parameter(Mandatory)] [string]$Market
    )

    $pnl_pct = ($CurrentPrice - $EntryPrice) / $EntryPrice
    $pnl_usd = ($CurrentPrice - $EntryPrice) * $Quantity

    $result = @{
        market = $Market
        entry = $EntryPrice
        current = $CurrentPrice
        pnl_pct = $pnl_pct
        pnl_usd = $pnl_usd
        qty = $Quantity
        sl = $StopLoss
        should_exit = $false
        exit_layer = $null
        exit_qty_pct = 0
        reason = ""
        signals = @()
    }

    # ─────────────────────────────────────────────────────────────────
    # Rejeita se em loss ou breakeven
    # ─────────────────────────────────────────────────────────────────
    if ($pnl_pct -le 0.02) {  # menos de 2% lucro
        return $result  # não sai
    }

    if (-not $Candles1H -or $Candles1H.Count -lt 5) {
        return $result  # dados insuficientes
    }

    # ─────────────────────────────────────────────────────────────────
    # Extract candle data
    # ─────────────────────────────────────────────────────────────────
    $closes = @($Candles1H | ForEach-Object { [double]$_.close })
    $highs = @($Candles1H | ForEach-Object { [double]$_.high })
    $lows = @($Candles1H | ForEach-Object { [double]$_.low })
    $opens = @($Candles1H | ForEach-Object { [double]$_.open })
    $vols = @($Candles1H | ForEach-Object { [double]$_.volume })

    $latest = $Candles1H[-1]
    $prev = $Candles1H[-2]
    $vol_avg = ($vols | Measure-Object -Average).Average
    $vol_ratio = $latest.volume / $vol_avg

    # ─────────────────────────────────────────────────────────────────
    # Signal 1: VOLUME SPIKE + REVERSAL (quick win)
    # ─────────────────────────────────────────────────────────────────
    $volume_spike = $vol_ratio -gt 2.0
    $is_bearish_candle = $latest.close -lt $latest.open
    $has_top_wick = ($latest.high - [Math]::Max($latest.open, $latest.close)) -gt (0.02 * $latest.close)

    if ($volume_spike -and $is_bearish_candle -and $has_top_wick) {
        $result.signals += "VOLUME_SPIKE_REVERSAL"
    }

    # ─────────────────────────────────────────────────────────────────
    # Signal 2: RSI OVERBOUGHT + REJECTION
    # ─────────────────────────────────────────────────────────────────
    if ($closes.Count -ge 14) {
        $rsi = Get-SimpleRSI -Closes $closes -Period 14
        $is_rejection = ($latest.close -lt $prev.close) -and ($latest.open -gt $prev.close)

        if ($rsi -gt 70 -and $is_rejection) {
            $result.signals += "RSI_OVERBOUGHT_REJECTION"
        }
    }

    # ─────────────────────────────────────────────────────────────────
    # Signal 3: LOWER HIGH + LOWER LOW (trend reversal)
    # ─────────────────────────────────────────────────────────────────
    if ($latest.high -lt $prev.high -and $latest.low -lt $prev.low) {
        $result.signals += "LOWER_HIGH_LOW"
    }

    # ─────────────────────────────────────────────────────────────────
    # Signal 4: PRICE DANGER ZONE (close to SL)
    # ─────────────────────────────────────────────────────────────────
    $distance_to_sl = ($CurrentPrice - $StopLoss) / $CurrentPrice
    if ($distance_to_sl -lt 0.03) {  # menos de 3% até SL
        $result.signals += "DANGER_ZONE_CLOSE_SL"
    }

    # ─────────────────────────────────────────────────────────────────
    # LAYER 1: Quick Win (5-15% profit)
    # ─────────────────────────────────────────────────────────────────
    if ($pnl_pct -ge 0.05 -and $pnl_pct -lt 0.15) {
        if ($result.signals -contains "VOLUME_SPIKE_REVERSAL") {
            $result.should_exit = $true
            $result.exit_layer = "LAYER1_QUICK_WIN"
            $result.exit_qty_pct = 0.50  # vende 50%
            $result.reason = "Volume spike + reversal candle em +5-15% → toma lucro rápido"
            return $result
        }
    }

    # ─────────────────────────────────────────────────────────────────
    # LAYER 2: Mid Profit (15-30% profit)
    # ─────────────────────────────────────────────────────────────────
    if ($pnl_pct -ge 0.15 -and $pnl_pct -lt 0.30) {
        if ($result.signals -contains "RSI_OVERBOUGHT_REJECTION") {
            $result.should_exit = $true
            $result.exit_layer = "LAYER2_MID_PROFIT"
            $result.exit_qty_pct = 0.25  # vende 25%
            $result.reason = "RSI overbought + rejection em +15-30% → partial exit"
            return $result
        }
        if ($result.signals -contains "LOWER_HIGH_LOW") {
            $result.should_exit = $true
            $result.exit_layer = "LAYER2_TREND_REVERSAL"
            $result.exit_qty_pct = 0.30
            $result.reason = "Lower high + lower low em +15-30% → protege ganho"
            return $result
        }
    }

    # ─────────────────────────────────────────────────────────────────
    # LAYER 3: Mature Moon (30%+ profit)
    # ─────────────────────────────────────────────────────────────────
    if ($pnl_pct -ge 0.30) {
        # Se reversão clara, vende 70%
        if ($result.signals -contains "LOWER_HIGH_LOW" -or $result.signals -contains "RSI_OVERBOUGHT_REJECTION") {
            $result.should_exit = $true
            $result.exit_layer = "LAYER3_MATURE_REVERSAL"
            $result.exit_qty_pct = 0.70  # vende 70%, deixa 30% moonbag
            $result.reason = "Reversão sinal em +30% → vende 70%, deixa moonbag"
            return $result
        }
        # Senão deixa trailing rodar (moonbag mode)
    }

    # ─────────────────────────────────────────────────────────────────
    # LAYER 4: Auto-Harvest (danger zone + profit exists)
    # ─────────────────────────────────────────────────────────────────
    if ($result.signals -contains "DANGER_ZONE_CLOSE_SL" -and $pnl_usd -gt 5) {
        $result.should_exit = $true
        $result.exit_layer = "LAYER4_AUTO_HARVEST"
        $result.exit_qty_pct = 1.0  # vende TUDO antes de SL
        $result.reason = "Preço perto do SL + lucro existe → sai com lucro full"
        return $result
    }

    return $result
}

# ─────────────────────────────────────────────────────────────────────
# RSI simples
# ─────────────────────────────────────────────────────────────────────
function Get-SimpleRSI {
    param(
        [double[]]$Closes,
        [int]$Period = 14
    )

    if ($Closes.Count -lt $Period + 1) { return 50 }

    $gains = 0
    $losses = 0

    for ($i = $Closes.Count - $Period; $i -lt $Closes.Count; $i++) {
        $change = $Closes[$i] - $Closes[$i - 1]
        if ($change -gt 0) { $gains += $change }
        else { $losses += [Math]::Abs($change) }
    }

    $avg_gain = $gains / $Period
    $avg_loss = $losses / $Period

    if ($avg_loss -eq 0) { return 100 }
    $rs = $avg_gain / $avg_loss
    $rsi = 100 - (100 / (1 + $rs))

    return $rsi
}

# ─────────────────────────────────────────────────────────────────────
# Execute partial exit
# ─────────────────────────────────────────────────────────────────────
function Execute-PartialExit {
    param(
        [Parameter(Mandatory)] [string]$Market,
        [Parameter(Mandatory)] [double]$CurrentPrice,
        [Parameter(Mandatory)] [double]$Quantity,
        [Parameter(Mandatory)] [double]$ExitQtyPct,
        [Parameter(Mandatory)] [string]$Reason
    )

    $exit_qty = [Math]::Round($Quantity * $ExitQtyPct, 6)
    $exit_usd = $exit_qty * $CurrentPrice

    if ($exit_qty -le 0) {
        return @{
            success = $false
            error = "Exit quantity <= 0"
        }
    }

    # Log decision (será executado via gem_executor ou manual review)
    $exit_record = @{
        timestamp = (Get-Date -Format 'o')
        market = $Market
        action = "PARTIAL_EXIT_RECOMMENDED"
        qty_to_sell = $exit_qty
        price = $CurrentPrice
        usd_value = $exit_usd
        layer = "auto"
        reason = $Reason
    }

    return @{
        success = $true
        exit_qty = $exit_qty
        exit_usd = $exit_usd
        record = $exit_record
    }
}

# ─────────────────────────────────────────────────────────────────────
# Main orchestrator
# ─────────────────────────────────────────────────────────────────────
function Invoke-ExitIntelligence {
    param(
        [Parameter(Mandatory)] [PSCustomObject[]]$AllPositions,
        [Parameter(Mandatory)] [hashtable]$PriceCache,  # market -> current price
        [Parameter(Mandatory)] [hashtable]$CandleCache   # market -> last 24 1H candles
    )

    $exits = @()

    foreach ($pos in $AllPositions) {
        if (-not $pos.active) { continue }

        $market = $pos.market
        $current_price = $PriceCache[$market] ?? $pos.entry

        if (-not $CandleCache[$market]) { continue }

        $signals = Get-ExitSignals `
            -CurrentPrice $current_price `
            -EntryPrice $pos.entry `
            -Quantity $pos.qty `
            -StopLoss $pos.stop `
            -Candles1H $CandleCache[$market] `
            -Market $market

        if ($signals.should_exit) {
            $exit_exec = Execute-PartialExit `
                -Market $market `
                -CurrentPrice $current_price `
                -Quantity $pos.qty `
                -ExitQtyPct $signals.exit_qty_pct `
                -Reason $signals.reason

            if ($exit_exec.success) {
                $exits += @{
                    market = $market
                    layer = $signals.exit_layer
                    qty_to_sell = $exit_exec.exit_qty
                    usd_value = $exit_exec.exit_usd
                    pnl_pct = $signals.pnl_pct
                    reason = $signals.reason
                    timestamp = (Get-Date -Format 'o')
                }
            }
        }
    }

    return $exits
}
