. agents/config.local.ps1
. agents/config.ps1
. agents/lib_coinex.ps1

Write-Host "=== ANALYZING METUSDT ENTRY ===" -ForegroundColor Cyan
Write-Host ""

# Entry data
$entry_price = 0.129587
$entry_qty = 561.39890575
$entry_usd = $entry_price * $entry_qty

Write-Host "ENTRY METUSDT:" -ForegroundColor Yellow
Write-Host "  Price: $entry_price"
Write-Host "  Qty: $entry_qty"
Write-Host "  Capital: `$$([math]::Round($entry_usd, 2))"
Write-Host ""

# Get 1D candles (20 dias)
Write-Host "Fetching 1D candles..." -ForegroundColor Gray
try {
    $daily = Invoke-RestMethod "https://api.coinex.com/v2/spot/kline?market=METUSDT&period=1day&limit=20" -TimeoutSec 10

    if ($daily.data) {
        $candles = @($daily.data | ForEach-Object {
            [PSCustomObject]@{
                open = [double]$_.open
                high = [double]$_.high
                low = [double]$_.low
                close = [double]$_.close
                vol = [double]$_.volume
            }
        })

        $current = $candles[-1].close
        $pnl_pct = ($current - $entry_price) / $entry_price
        $pnl_usd = ($current - $entry_price) * $entry_qty

        Write-Host "CURRENT PRICE: $current" -ForegroundColor Green
        Write-Host "PnL: $('{0:+$0.00}' -f $pnl_usd) ($('{0:+0.00%}' -f $pnl_pct))" -ForegroundColor $(if($pnl_usd -gt 0){"Green"}else{"Red"})
        Write-Host ""

        # Entry point analysis
        $low_20d = $candles.low | Measure-Object -Minimum | Select -ExpandProperty Minimum
        $high_20d = $candles.high | Measure-Object -Maximum | Select -ExpandProperty Maximum
        $range_20d = $high_20d - $low_20d

        Write-Host "20-DAY RANGE:" -ForegroundColor Cyan
        Write-Host "  Low: $low_20d"
        Write-Host "  High: $high_20d"
        Write-Host "  Range: $('{0:F6}' -f $range_20d) ($('{0:0.00%}' -f ($range_20d / $low_20d)))"
        Write-Host ""

        # Where did we enter in the range?
        $pct_into_range = ($entry_price - $low_20d) / $range_20d
        Write-Host "ENTRY POSITION IN RANGE:" -ForegroundColor Yellow
        Write-Host "  Entered at: $('{0:0.00%}' -f $pct_into_range) of range"

        if ($pct_into_range -lt 0.25) {
            Write-Host "  ✅ EARLY ENTRY - bottom 25% of range (EXCELLENT)"
        } elseif ($pct_into_range -lt 0.50) {
            Write-Host "  ✅ GOOD ENTRY - lower half of range (GOOD)"
        } elseif ($pct_into_range -lt 0.75) {
            Write-Host "  ⚠️  MID ENTRY - upper-middle (OKAY but risky)"
        } else {
            Write-Host "  ❌ LATE ENTRY - top 25% of range (RISKY)"
        }
        Write-Host ""

        # Trend at entry time
        $closes = @($candles.close)
        $sma5 = ($closes[-5..-1] | Measure-Object -Average).Average
        $sma10 = ($closes[-10..-1] | Measure-Object -Average).Average
        $sma20 = ($closes | Measure-Object -Average).Average

        Write-Host "MOVING AVERAGES:" -ForegroundColor Cyan
        Write-Host "  SMA5:  $('{0:F6}' -f $sma5)"
        Write-Host "  SMA10: $('{0:F6}' -f $sma10)"
        Write-Host "  SMA20: $('{0:F6}' -f $sma20)"
        Write-Host "  Entry: $entry_price"
        Write-Host ""

        # Momentum
        if ($entry_price -gt $sma5 -and $sma5 -gt $sma10 -and $sma10 -gt $sma20) {
            Write-Host "MOMENTUM: 🟢 STRONG UPTREND (perfect entry timing)" -ForegroundColor Green
        } elseif ($entry_price -gt $sma20) {
            Write-Host "MOMENTUM: 🟡 MILD UPTREND (okay entry)" -ForegroundColor Yellow
        } else {
            Write-Host "MOMENTUM: 🔴 DOWNTREND or REVERSAL (risky)" -ForegroundColor Red
        }
        Write-Host ""

        # Candles analysis
        Write-Host "LAST 5 CANDLES:" -ForegroundColor Gray
        $candles[-5..-1] | ForEach-Object {
            $dir = if ($_.close -gt $_.open) { "🟢" } else { "🔴" }
            $body_pct = ([Math]::Abs($_.close - $_.open) / $_.close) * 100
            Write-Host "  $dir O:$('{0:F6}' -f $_.open) C:$('{0:F6}' -f $_.close) BodySize:$('{0:0.00%}' -f ($body_pct/100))"
        }
        Write-Host ""

        # Verdict
        Write-Host "ENTRY VERDICT:" -ForegroundColor Yellow
        if ($pct_into_range -lt 0.50 -and $entry_price -gt $sma20) {
            Write-Host "✅ GOOD ENTRY - entered during uptrend, lower half of range"
            Write-Host "   Action: HOLD, let trailing SL protect"
        } elseif ($pct_into_range -lt 0.50) {
            Write-Host "✅ EARLY ENTRY - but trend unclear"
            Write-Host "   Action: Monitor closely for reversal"
        } else {
            Write-Host "⚠️  LATE ENTRY - entered upper half of range"
            Write-Host "   Risk: Vulnerable to pullback"
            Write-Host "   Action: Tighten SL or take partial profit if +10%+ appears"
        }

    } else {
        Write-Host "ERROR: No candle data" -ForegroundColor Red
    }
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
}
