# validate_capital_vs_bootstrap.ps1
# Compare real CoinEx balances vs bootstrap fallback values

Write-Host "`n📊 CAPITAL VALIDATION: Real vs Bootstrap" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray

# Real values from CoinEx (2026-06-08 11:44 BRT)
$real = @{
    spot_usdt = 2464.74
    spot_breakdown = @{
        usdt = 954.40
        btc = 345.80
        paxg = 1109.15
        xrp = 25.71
        others = 24.68
    }
    pnl_position = -171.72  # -6.51%
    pnl_today = -5.31       # -0.21%
}

# Bootstrap fallback (what scripts use if API fails)
$bootstrap = @{
    spot_capital = 1350.43
    futures_capital = 1350.42
    total_capital = 2700.85
}

# Analysis
$realTotal = $real.spot_usdt + ($null ?? 0)  # Add futures when known
$bootstrapTotal = $bootstrap.total_capital
$difference = $realTotal - $bootstrapTotal
$diffPct = ($difference / $bootstrapTotal) * 100

Write-Host "`n💰 SPOT BALANCE" -ForegroundColor Cyan
Write-Host "  Real Current: $($real.spot_usdt) USDT" -ForegroundColor Green
Write-Host "  Bootstrap Assumed: $($bootstrap.spot_capital) USDT" -ForegroundColor Yellow
Write-Host "  Difference: $difference USDT ($([Math]::Round($diffPct, 2))%)" -ForegroundColor $(if ($difference -lt 0) { "Red" } else { "Green" })

Write-Host "`n📈 BREAKDOWN (Real SPOT)" -ForegroundColor Cyan
foreach ($asset in $real.spot_breakdown.GetEnumerator()) {
    Write-Host "  $($asset.Key.ToUpper()): `$$($asset.Value)" -ForegroundColor Gray
}

Write-Host "`n📊 P&L" -ForegroundColor Cyan
Write-Host "  Position PnL: $($real.pnl_position) (-6.51%)" -ForegroundColor Red
Write-Host "  Today's PnL: $($real.pnl_today) (-0.21%)" -ForegroundColor Red

Write-Host "`n⚠️ RECOMMENDATION" -ForegroundColor Yellow
Write-Host "  1. Share FUTURES balance so we can calculate real 50/50 split" -ForegroundColor White
Write-Host "  2. Update bootstrap fallback from $($bootstrap.total_capital) to real total" -ForegroundColor White
Write-Host "  3. Recalculate position sizes (currently oversized by 8.75%)" -ForegroundColor White

Write-Host "`n💡 IMPACT ON LIVE" -ForegroundColor Cyan
Write-Host "  If 1% position cap is used:" -ForegroundColor Gray
Write-Host "    Bootstrap calc: 1% × \$2700.85 = \$27.01 per trade" -ForegroundColor Yellow
Write-Host "    Real calc: 1% × \$2464.74 = \$24.65 per trade" -ForegroundColor Green
Write-Host "    Difference: -\$2.36 safer (avoids over-leveraging)" -ForegroundColor Green

Write-Host "`n" -ForegroundColor Gray
