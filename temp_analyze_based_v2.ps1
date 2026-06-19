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
Write-Host "  Capital: `$$('{0:F2}' -f $entry_usd)"
Write-Host ""

# Get current data
Write-Host "Fetching BASED data..." -ForegroundColor Gray
try {
    $daily = Invoke-RestMethod "https://api.coinex.com/v2/spot/kline?market=BASEDUSDT&period=1day&limit=20" -TimeoutSec 10

    if ($daily.data -and $daily.data.Count -gt 0) {
        $candles = @($daily.data | ForEach-Object {
            [PSCustomObject]@{
                idx = $_
                open = [double]$_.open
                high = [double]$_.high
                low = [double]$_.low
                close = [double]$_.close
                vol = [double]$_.volume
            }
        })

        $current = $candles[-1]
        $current_price = $current.close
        $pnl_pct = ($current_price - $entry_price) / $entry_price
        $pnl_usd = ($current_price - $entry_price) * $entry_qty

        Write-Host "CURRENT PRICE: $current_price USDT" -ForegroundColor Green
        Write-Host "PnL: $('{0:+$0.00}' -f $pnl_usd) ($('{0:+0.00%}' -f $pnl_pct))" -ForegroundColor $(if($pnl_usd -gt 0){"Green"}else{"Red"})
        Write-Host ""

        # Tech
        $closes = @($candles.close)
        $sma5 = ($closes[-5..-1] | Measure-Object -Average).Average
        $sma10 = ($closes[-10..-1] | Measure-Object -Average).Average
        $sma20 = ($closes | Measure-Object -Average).Average

        Write-Host "MOVING AVERAGES:" -ForegroundColor Cyan
        Write-Host "  SMA5:  $([Math]::Round($sma5, 6))"
        Write-Host "  SMA10: $([Math]::Round($sma10, 6))"
        Write-Host "  SMA20: $([Math]::Round($sma20, 6))"
        Write-Host ""

        # Support/Resistance
        $high20 = $candles.high | Measure-Object -Maximum | Select -ExpandProperty Maximum
        $low20 = $candles.low | Measure-Object -Minimum | Select -ExpandProperty Minimum

        Write-Host "SUPPORT/RESISTANCE (20d):" -ForegroundColor Cyan
        Write-Host "  Resistance: $high20"
        Write-Host "  Support: $low20"
        Write-Host "  Range: $('{0:F4}' -f ($high20 - $low20)) ($('{0:0.00%}' -f (($high20-$low20)/$low20)))"
        Write-Host ""

        # Last candles analysis
        Write-Host "LAST 5 CANDLES:" -ForegroundColor Gray
        $candles[-5..-1] | ForEach-Object {
            $bodysize = [Math]::Abs($_.close - $_.open) / $_.close * 100
            $wick_up = ($_.high - [Math]::Max($_.close, $_.open))
            $wick_down = [Math]::Min($_.close, $_.open) - $_.low
            $dir = if ($_.close -gt $_.open) { "🟢" } else { "🔴" }
            Write-Host "  $dir O:$('{0:F6}' -f $_.open) H:$('{0:F6}' -f $_.high) L:$('{0:F6}' -f $_.low) C:$('{0:F6}' -f $_.close) Body:$('{0:0.00%}' -f ($bodysize/100)) WickUp:$('{0:F6}' -f $wick_up) WickDn:$('{0:F6}' -f $wick_down)"
        }
        Write-Host ""

        # Pattern detection
        Write-Host "PATTERN ANALYSIS:" -ForegroundColor Cyan

        $prev = $candles[-2]
        $trend_hh = $current.high -gt $prev.high
        $trend_lh = $current.low -gt $prev.low
        $trend_ll = $current.low -lt $prev.low
        $trend_hl = $current.high -lt $prev.high

        if ($trend_hh -and $trend_lh) {
            Write-Host "  📈 HIGHER HIGH + HIGHER LOW = UPTREND CONTINUATION"
        } elseif ($trend_ll -and $trend_hl) {
            Write-Host "  📉 LOWER LOW + LOWER HIGH = DOWNTREND CONTINUATION"
        } elseif ($trend_hh -and $trend_ll) {
            Write-Host "  ⚠️  HIGHER HIGH + LOWER LOW = INDECISION / VOLATILITY EXPANSION"
            Write-Host "     Could be reversal setup or violent breakout coming"
        } elseif ($trend_hl -and $trend_lh) {
            Write-Host "  ➡️  LOWER HIGH + HIGHER LOW = CONSOLIDATION"
        }

        Write-Host ""

        # Trend direction
        $above_sma5 = $current_price -gt $sma5
        $above_sma10 = $current_price -gt $sma10
        $above_sma20 = $current_price -gt $sma20
        $sma_aligned = ($sma5 -gt $sma10) -and ($sma10 -gt $sma20)

        if ($above_sma20 -and $sma_aligned) {
            Write-Host "TREND: 🟢 BULLISH ALIGNED" -ForegroundColor Green
        } elseif (-not $above_sma20 -and -not $sma_aligned) {
            Write-Host "TREND: 🔴 BEARISH ALIGNED" -ForegroundColor Red
        } else {
            Write-Host "TREND: ⚠️  MIXED / CHOPPY" -ForegroundColor Yellow
        }

        Write-Host ""
        Write-Host "DECISION LOGIC:" -ForegroundColor Yellow

        if ($pnl_usd -gt 5) {
            Write-Host "✅ IN PROFIT: `$$('{0:F2}' -f $pnl_usd)" -ForegroundColor Green

            if ($trend_hh -and $trend_lh -and $above_sma20) {
                Write-Host "   HOLD - Uptrend strong, trailing should protect"
            } elseif ($trend_hh -and $trend_ll) {
                Write-Host "   ⚠️  CAUTION - Expansion could be reversal setup"
                Write-Host "   Consider tightening trailing SL or taking partial profits"
                Write-Host "   Watch for close below SMA5 or SMA10 as reversal signal"
            } elseif ($trend_ll -and $trend_hl) {
                Write-Host "   SELL or REDUCE - Downtrend formed"
                Write-Host "   Lock in profits, don't wait for trailing SL hit"
            } else {
                Write-Host "   HOLD - Consolidating but protecting gains"
            }
        } else {
            Write-Host "❌ BREAKEVEN/LOSS: `$$('{0:F2}' -f $pnl_usd)" -ForegroundColor Red
            Write-Host "   Wait for trend confirmation before taking profits"
        }

        Write-Host ""
        Write-Host "TRAILING SL STATUS:" -ForegroundColor Cyan
        $sl_original = 0.077485  # 2% below entry
        $sl_should_be = [Math]::Round($current_price * 0.98, 6)
        Write-Host "  Original SL: $sl_original"
        Write-Host "  Should be NOW: $sl_should_be"
        Write-Host "  Moved up by: `$$('{0:F6}' -f ($sl_should_be - $sl_original))"
        Write-Host ""

        # Volume analysis
        $avg_vol = ($candles.vol | Measure-Object -Average).Average
        $current_vol_ratio = $current.vol / $avg_vol
        Write-Host "VOLUME:" -ForegroundColor Gray
        Write-Host "  Current vs Avg: $('{0:0.00x}' -f $current_vol_ratio)"
        if ($current_vol_ratio -gt 1.5) {
            Write-Host "  📊 HIGH VOLUME - likely significant move"
        }

    } else {
        Write-Host "ERROR: No candle data" -ForegroundColor Red
    }
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
}
