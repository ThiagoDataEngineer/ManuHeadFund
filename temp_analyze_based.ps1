. agents/config.local.ps1
. agents/config.ps1
. agents/lib_coinex.ps1

Write-Host "=== ANALYZING BASED POSITION ===" -ForegroundColor Cyan
Write-Host ""

# Entry data
$entry_price = 0.079148
$entry_qty = 248.280485
$entry_usd = $entry_price * $entry_qty

Write-Host "ENTRY:" -ForegroundColor Yellow
Write-Host "  Price: $entry_price USDT"
Write-Host "  Qty: $entry_qty BASED"
Write-Host "  USD: $entry_usd"
Write-Host ""

# Get current data
Write-Host "Fetching current BASED data..." -ForegroundColor Gray
try {
    # 1D candles (last 20 days)
    $daily = Invoke-RestMethod "https://api.coinex.com/v2/spot/kline?market=BASEDUSDT&period=1day&limit=20" -TimeoutSec 10
    if ($daily.data) {
        $candles_1d = @($daily.data | ForEach-Object {
            [PSCustomObject]@{
                ts = [datetime]::UnixEpoch.AddSeconds([double]$_.created_at)
                open = [double]$_.open
                high = [double]$_.high
                low = [double]$_.low
                close = [double]$_.close
                vol = [double]$_.volume
            }
        })

        $latest_1d = $candles_1d[-1]
        $current_price = $latest_1d.close

        Write-Host "CURRENT (1D):" -ForegroundColor Green
        Write-Host "  Price: $current_price USDT"
        Write-Host "  Change from entry: $('{0:+0.00%}' -f (($current_price - $entry_price) / $entry_price))"
        Write-Host "  PnL: $('{0:+$0.00}' -f (($current_price - $entry_price) * $entry_qty))"
        Write-Host "  Current USD Value: $($current_price * $entry_qty)"
        Write-Host ""

        # Technical analysis
        Write-Host "TECHNICAL (1D chart):" -ForegroundColor Cyan
        Write-Host "  High 20d: $($candles_1d.high | Measure-Object -Maximum | Select -ExpandProperty Maximum)"
        Write-Host "  Low 20d: $($candles_1d.low | Measure-Object -Minimum | Select -ExpandProperty Minimum)"
        Write-Host "  Avg Vol 20d: $('{0:F0}' -f ($candles_1d.vol | Measure-Object -Average | Select -ExpandProperty Average))"
        Write-Host ""

        # SMA
        $closes = @($candles_1d | ForEach-Object { $_.close })
        $sma5 = ($closes[-5..-1] | Measure-Object -Average).Average
        $sma10 = ($closes[-10..-1] | Measure-Object -Average).Average
        $sma20 = ($closes | Measure-Object -Average).Average

        Write-Host "MOVING AVERAGES:" -ForegroundColor Cyan
        Write-Host "  SMA5: $sma5"
        Write-Host "  SMA10: $sma10"
        Write-Host "  SMA20: $sma20"
        Write-Host ""

        # Trend
        $recent_trend = if ($current_price -gt $sma5) { "UP" } else { "DOWN" }
        Write-Host "TREND: $recent_trend" -ForegroundColor $(if($recent_trend -eq "UP"){"Green"}else{"Red"})
        Write-Host ""

        # Pattern analysis
        Write-Host "PATTERN ANALYSIS:" -ForegroundColor Cyan
        $higher_high = $latest_1d.high -gt $candles_1d[-2].high
        $lower_low = $latest_1d.low -lt $candles_1d[-2].low

        if ($higher_high -and -not $lower_low) {
            Write-Host "  📈 HIGHER HIGH - bullish continuation"
        } elseif ($lower_low -and -not $higher_high) {
            Write-Host "  📉 LOWER LOW - bearish signal"
        } elseif ($higher_high -and $lower_low) {
            Write-Host "  ⚠️  HIGHER HIGH + LOWER LOW - VOLATILITY / INDECISION"
            Write-Host "     COULD BE REVERSAL OR CONSOLIDATION BEFORE BREAKOUT"
        } else {
            Write-Host "  ➡️  CONSOLIDATION"
        }

        Write-Host ""
        Write-Host "CANDLES (last 5 days):" -ForegroundColor Gray
        $candles_1d[-5..-1] | ForEach-Object {
            $bodysize = [Math]::Abs($_.close - $_.open)
            $wicks = ($_.high - [Math]::Max($_.close, $_.open)) + ([Math]::Min($_.close, $_.open) - $_.low)
            $dir = if ($_.close -gt $_.open) { "🟢" } else { "🔴" }
            Write-Host "  $($_.ts.ToString('yyyy-MM-dd')) $dir O:$($_.open) H:$($_.high) L:$($_.low) C:$($_.close) BodySize:$bodysize Wicks:$wicks"
        }

        Write-Host ""
        Write-Host "RECOMMENDATION:" -ForegroundColor Yellow

        $pnl_pct = ($current_price - $entry_price) / $entry_price
        $pnl_usd = ($current_price - $entry_price) * $entry_qty

        if ($pnl_usd -gt 10) {
            Write-Host "✅ IN PROFIT: $($pnl_usd.ToString('+$0.00')) ($('{0:+0.00%}' -f $pnl_pct))"
            Write-Host "   Trailing SL should have moved UP"
            Write-Host "   Check if trailing moved from $0.079148 to higher level"
        } elseif ($pnl_usd -lt -5) {
            Write-Host "❌ IN LOSS: $($pnl_usd.ToString('+$0.00'))"
        } else {
            Write-Host "➡️  BREAKEVEN ZONE: $('{0:+$0.00}' -f $pnl_usd)"
        }

        Write-Host ""
        Write-Host "TRAILING STATUS:" -ForegroundColor Cyan
        Write-Host "  Entry SL was: 0.077485 (2% below entry)"
        Write-Host "  Should be moved to: ~$([Math]::Round($current_price * 0.98, 6)) now"
        Write-Host ""

    } else {
        Write-Host "ERROR: No data received" -ForegroundColor Red
    }
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
}
