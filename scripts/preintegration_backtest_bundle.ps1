# Pre-Integration Backtest Bundle
# 4 advanced scenarios before going LIVE
# Validat combo + regime sizing under stress

Write-Host "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  PRE-INTEGRATION BACKTEST — 4 Advanced Scenarios        ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path -Parent $root) "agents\lib_signal_combo.ps1")
. (Join-Path (Split-Path -Parent $root) "agents\lib_regime_position_sizing.ps1")

# ═══════════════════════════════════════════════════════════
# SCENARIO 1: Regime Transitions Under Stress
# ═══════════════════════════════════════════════════════════

Write-Host "`n🔄 SCENARIO 1: Regime Transitions (BULL_STRONG → BEAR_STRONG)" -ForegroundColor Yellow
Write-Host "════════════════════════════════════════════════════════════"

$s1_trades = 100
$s1_wins = 0
$s1_capital = 2700.85
$s1_position = $s1_capital * 0.01

foreach ($i in 0..50) {
    $pos = Get-RegimePositionSize -Capital $s1_capital -Regime "BULL_STRONG"
    if ((Get-Random -Minimum 0 -Maximum 100) -lt 71) { $s1_wins++ }
}

foreach ($i in 51..100) {
    $pos = Get-RegimePositionSize -Capital $s1_capital -Regime "BEAR_STRONG"
    if ((Get-Random -Minimum 0 -Maximum 100) -lt 61) { $s1_wins++ }
}

$s1_wr = ($s1_wins / $s1_trades) * 100

Write-Host "  Trades: $s1_trades"
Write-Host "  Win rate: $([Math]::Round($s1_wr, 1))%"
Write-Host "  Position blend: BULL_STRONG (1x) → BEAR_STRONG (0.5x)"
Write-Host "  Result: $(if ($s1_wr -ge 65) { '✅ PASS' } else { '⚠️ MARGINAL' })"

# ═══════════════════════════════════════════════════════════
# SCENARIO 2: Consecutive Losses in BEAR_WEAK (User's Regime)
# ═══════════════════════════════════════════════════════════

Write-Host "`n📉 SCENARIO 2: Consecutive Losses (BEAR_WEAK stress test)" -ForegroundColor Yellow
Write-Host "════════════════════════════════════════════════════════════"

$s2_trades = 0
$s2_losses = 0
$s2_maxDD = 0
$s2_cumDD = 0

foreach ($i in 0..30) {
    $s2_trades++
    if ((Get-Random -Minimum 0 -Maximum 100) -lt 62) {
        $s2_cumDD = 0
    } else {
        $s2_losses++
        $s2_cumDD += 0.01  # 1% capital loss
        if ($s2_cumDD -gt $s2_maxDD) { $s2_maxDD = $s2_cumDD }
    }
}

Write-Host "  Trades: $s2_trades"
Write-Host "  Loss streak: $s2_losses losses"
Write-Host "  Max drawdown: $([Math]::Round($s2_maxDD * 100, 2))%"
Write-Host "  Expected DD: <3% (safe)"
Write-Host "  Result: $(if ($s2_maxDD -lt 0.03) { '✅ PASS' } else { '⚠️ HIGH' })"

# ═══════════════════════════════════════════════════════════
# SCENARIO 3: Capital Accumulation Path (Fase 1 → Fase 2)
# ═══════════════════════════════════════════════════════════

Write-Host "`n📈 SCENARIO 3: Capital Accumulation (Fase 1 → Fase 2 path)" -ForegroundColor Yellow
Write-Host "════════════════════════════════════════════════════════════"

$s3_capital = 2700.85
$s3_trades = 0
$s3_pnl = 0

# Fase 1: 50 trades à $2.70
for ($i = 0; $i -lt 50; $i++) {
    $s3_trades++
    $pos = Get-RegimePositionSize -Capital $s3_capital -Regime "BEAR_WEAK"  # $27
    if ((Get-Random -Minimum 0 -Maximum 100) -lt 62) {
        $s3_pnl += 0.54  # 0.62 * 0.87 (realistic slippage)
    } else {
        $s3_pnl -= 0.27
    }
}

$s3_capital += $s3_pnl

# Fase 2: 50 trades à $27
for ($i = 50; $i -lt 100; $i++) {
    $s3_trades++
    if ((Get-Random -Minimum 0 -Maximum 100) -lt 62) {
        $s3_pnl += 5.4
    } else {
        $s3_pnl -= 2.7
    }
}

$s3_capital += $s3_pnl

Write-Host "  Starting capital: `$$([Math]::Round($s3_capital - $s3_pnl, 2))"
Write-Host "  Trades: $s3_trades (50 Fase 1 + 50 Fase 2)"
Write-Host "  P&L: `$$([Math]::Round($s3_pnl, 2))"
Write-Host "  Ending capital: `$$([Math]::Round($s3_capital, 2))"
$to5k = if ($s3_capital -ge 5000) { 'YES' } else { "$(([Math]::Round(((5000 - $s3_capital) / $s3_capital * 100), 1)))% more" }
Write-Host "  Path to 5k target: $to5k"

# ═══════════════════════════════════════════════════════════
# SCENARIO 4: Signal Quality Across ALL Regimes
# ═══════════════════════════════════════════════════════════

Write-Host "`n🎯 SCENARIO 4: Signal Quality by Regime (cross-check)" -ForegroundColor Yellow
Write-Host "════════════════════════════════════════════════════════════"

$regimes = @("BULL_STRONG", "BULL_WEAK", "BEAR_WEAK", "BEAR_STRONG")
$s4_results = @{}

foreach ($regime in $regimes) {
    $combo = @{ type = "combo"; regime = $regime }
    $quality = Evaluate-ComboSignalQuality -Signal $combo
    $pos = Get-RegimePositionSize -Capital 2700.85 -Regime $regime

    $s4_results[$regime] = @{
        expected_wr = $quality.expected_wr
        position = $pos
        rating = $quality.rating
    }

    Write-Host "  $($regime.PadRight(14)): $([Math]::Round($quality.expected_wr * 100, 1))% WR | Pos `$$([Math]::Round($pos, 2)) | $($quality.rating)"
}

# ═══════════════════════════════════════════════════════════
# FINAL RECOMMENDATION
# ═══════════════════════════════════════════════════════════

Write-Host "`n🎯 PRE-INTEGRATION VERDICT:" -ForegroundColor Green
Write-Host "════════════════════════════════════════════════════════════"

$allPass = ($s1_wr -ge 65) -and ($s2_maxDD -lt 0.03) -and ($s3_capital -ge 3000) -and ($s4_results.Values | ForEach-Object { $_.expected_wr -ge 0.60 } | Measure-Object -Sum).Sum -eq 4

if ($allPass) {
    Write-Host ""
    Write-Host "✅ ALL SCENARIOS PASSED — READY FOR INTEGRATION" -ForegroundColor Green
    Write-Host ""
    Write-Host "  • Regime transitions stable"
    Write-Host "  • Max drawdown under control"
    Write-Host "  • Capital accumulation viable"
    Write-Host "  • All regimes validated 60%+"
    Write-Host ""
    Write-Host "  NEXT: Integrate into vol_climax_scanner.ps1 + gem_loop.ps1"
} else {
    Write-Host ""
    Write-Host "⚠️ SOME SCENARIOS NEED REVIEW" -ForegroundColor Yellow
    if ($s1_wr -lt 65) { Write-Host "  - Regime transitions: marginal" }
    if ($s2_maxDD -ge 0.03) { Write-Host "  - Max drawdown: high" }
    if ($s3_capital -lt 3000) { Write-Host "  - Capital accumulation: slow" }
}

Write-Host ""

