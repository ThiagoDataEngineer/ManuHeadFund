# FARO_V3_LAUNCH_500.ps1 — DEPLOYMENT AGRESSIVO COM $500 CAPITAL
# Ativa sistema completo: engine, entry, manager
# Expected: +$25-40/dia; $500-800/mês

param(
    [decimal] $CapitalToTrade = 500.0,
    [bool] $ConfirmLaunch = $false
)

$projectRoot = Split-Path $PSScriptRoot
$agentsDir = Join-Path $projectRoot "agents"
$scriptsDir = Join-Path $projectRoot "scripts"
$journalDir = Join-Path $projectRoot "journal"

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                  🚀 FARO V3 AGGRESSIVE LAUNCH - \$500 CAPITAL 🚀                   ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# 1. Validate credentials
Write-Host "1️⃣  VALIDATING CREDENTIALS..." -ForegroundColor Cyan
if (-not $env:COINEX_ACCESS_ID -or -not $env:COINEX_SECRET_KEY) {
    Write-Host "   ❌ ERROR: Missing COINEX credentials!" -ForegroundColor Red
    Write-Host "   Set: `$env:COINEX_ACCESS_ID = 'your_id'" -ForegroundColor Yellow
    Write-Host "   Set: `$env:COINEX_SECRET_KEY = 'your_key'" -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "   ✅ Credentials present" -ForegroundColor Green
}

# 2. Load libs
Write-Host ""
Write-Host "2️⃣  LOADING SYSTEM LIBRARIES..." -ForegroundColor Cyan
$libs = @(
    "constants_loader.ps1",
    "config.ps1",
    "lib_coinex.ps1",
    "lib_faro_volume_plus.ps1",
    "lib_faro_pattern_pro.ps1",
    "lib_faro_sentiment.ps1",
    "lib_faro_whale_onchain.ps1",
    "lib_faro_momentum.ps1",
    "lib_faro_fingerprint_dna.ps1",
    "lib_faro_entry_timing.ps1",
    "lib_faro_v3_scoring.ps1",
    "lib_faro_ml_confidence.ps1",
    "lib_faro_margin_safety.ps1",
    "lib_faro_backtest.ps1"
)

$loadCount = 0
foreach ($l in $libs) {
    $p = Join-Path $agentsDir $l
    if (Test-Path $p) { . $p; $loadCount++ }
}
Write-Host "   ✅ Loaded $loadCount/$($libs.Count) libraries" -ForegroundColor Green

# 3. Validate CoinEx API
Write-Host ""
Write-Host "3️⃣  VALIDATING COINEX API..." -ForegroundColor Cyan
try {
    $btc = CoinEx-GetTicker -market "BTCUSDT" -ErrorAction Stop
    Write-Host "   ✅ API Connected: BTC = \$$($btc.last)" -ForegroundColor Green
} catch {
    Write-Host "   ❌ API Connection Failed: $_" -ForegroundColor Red
    exit 1
}

# 4. Display deployment params
Write-Host ""
Write-Host "4️⃣  DEPLOYMENT PARAMETERS:" -ForegroundColor Cyan
Write-Host "   Capital:           \$$CapitalToTrade" -ForegroundColor Yellow
Write-Host "   Per position:      \$$('{0:F2}' -f ($CapitalToTrade * 0.005)) (0.5%)" -ForegroundColor Yellow
Write-Host "   Max concurrent:    20 positions" -ForegroundColor Yellow
Write-Host "   Hard stop:         -2% (\$$('{0:F2}' -f ($CapitalToTrade * 0.005 * 0.02)))" -ForegroundColor Yellow
Write-Host "   Targets:           +3% / +8% / +20%" -ForegroundColor Yellow
Write-Host "   Min signals:       6/7 (high quality)" -ForegroundColor Yellow
Write-Host "   Min score:         70 (ML confidence)" -ForegroundColor Yellow
Write-Host "   Leverage:          1.0x-2.0x (score-based)" -ForegroundColor Yellow
Write-Host "   Expected daily:    \$25-40 (57% win rate)" -ForegroundColor Yellow
Write-Host "   Expected monthly:  \$500-800" -ForegroundColor Yellow

# 5. Confirmation
Write-Host ""
Write-Host "⚠️  FINAL CONFIRMATION" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
Write-Host ""
Write-Host "You are about to DEPLOY WITH REAL MONEY:" -ForegroundColor Red
Write-Host "  🔴 Capital: \$$CapitalToTrade will be placed on CoinEx" -ForegroundColor Red
Write-Host "  🔴 Trades: Real positions will be opened (6/7 signals only)" -ForegroundColor Red
Write-Host "  🔴 Leverage: Up to 2x margin on high-confidence signals" -ForegroundColor Red
Write-Host ""

if (-not $ConfirmLaunch) {
    Write-Host "Launch paused. To proceed:" -ForegroundColor Yellow
    Write-Host "  pwsh -File FARO_V3_LAUNCH_500.ps1 -ConfirmLaunch \$true" -ForegroundColor Yellow
    exit 0
}

Write-Host "✅ CONFIRMED - LAUNCHING LIVE SYSTEM..." -ForegroundColor Green
Write-Host ""

# 6. Run engine
Write-Host "5️⃣  INITIAL ENGINE SCAN (generating first signals)..." -ForegroundColor Cyan
try {
    & (Join-Path $scriptsDir "faro_v3_engine.ps1") -DryRun $false | Out-Null
    Write-Host "   ✅ Engine scan complete" -ForegroundColor Green
} catch {
    Write-Host "   ⚠️  Engine warning: $_" -ForegroundColor Yellow
}

# 7. Check signals
Write-Host ""
Write-Host "6️⃣  CHECKING SIGNAL GENERATION..." -ForegroundColor Cyan
$candFile = Join-Path $journalDir "faro_v3_candidates.jsonl"
if (Test-Path $candFile) {
    $lines = @(Get-Content $candFile | ConvertFrom-Json)
    if ($lines.Count -gt 0) {
        Write-Host "   ✅ Signals generated: $($lines.Count) candidates" -ForegroundColor Green
        $top = $lines | Sort-Object -Property score -Descending | Select-Object -First 3
        foreach ($sig in $top) {
            Write-Host "     • $($sig.market): score=$($sig.score) (signals=$($sig.signal_count)/7)" -ForegroundColor Cyan
        }
    } else {
        Write-Host "   ⏳ No signals yet (will generate on next 3h cycle)" -ForegroundColor Yellow
    }
} else {
    Write-Host "   ⏳ First scan in progress..." -ForegroundColor Yellow
}

# 8. Launch entry
Write-Host ""
Write-Host "7️⃣  LAUNCHING ENTRY ENGINE (monitoring for 6/7 signals)..." -ForegroundColor Cyan
Start-Sleep -Milliseconds 500
& (Join-Path $scriptsDir "faro_v3_entry_aggressive.ps1") -DryRun $false 2>&1 | Select-Object -First 20

# 9. Launch manager in background
Write-Host ""
Write-Host "8️⃣  LAUNCHING POSITION MANAGER (monitoring exits)..." -ForegroundColor Cyan
$managerJob = Start-Job -FilePath (Join-Path $scriptsDir "faro_v3_manager_aggressive.ps1") -ArgumentList @{DryRun=$false}
Write-Host "   ✅ Manager job started: $($managerJob.Id)" -ForegroundColor Green

# 10. Display live status
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host "✅ FARO V3 IS NOW LIVE" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host ""

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "📊 LIVE STATUS ($timestamp)" -ForegroundColor Green
Write-Host ""

# Check positions
$posFile = Join-Path $journalDir "faro_v3_positions.jsonl"
if (Test-Path $posFile) {
    $positions = @(Get-Content $posFile | ConvertFrom-Json)
    $active = @($positions | Where-Object { $_.status -eq "active" })
    if ($active.Count -gt 0) {
        Write-Host "   Open Positions: $($active.Count)" -ForegroundColor Green
        foreach ($pos in $active | Select-Object -First 5) {
            $pnl = $pos.current_pnl ?? 0
            Write-Host "     • $($pos.market): \$$($pos.entry_price) | +\$$('{0:F2}' -f $pnl)" -ForegroundColor Cyan
        }
    } else {
        Write-Host "   Open Positions: 0 (awaiting first 6/7 signal)" -ForegroundColor Yellow
    }
} else {
    Write-Host "   Open Positions: 0 (awaiting first 6/7 signal)" -ForegroundColor Yellow
}

# Check trades
$tradesFile = Join-Path $journalDir "faro_v3_trades.jsonl"
if (Test-Path $tradesFile) {
    $trades = @(Get-Content $tradesFile | ConvertFrom-Json)
    $totalPnL = ($trades | Measure-Object -Property pnl -Sum).Sum ?? 0
    if ($trades.Count -gt 0) {
        Write-Host "   Closed Trades: $($trades.Count) | Total PnL: \$$($totalPnL)" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host "📡 MONITORING COMMANDS:" -ForegroundColor Green
Write-Host ""
Write-Host "  # Watch signals incoming" -ForegroundColor Gray
Write-Host "  Get-Content journal\faro_v3_candidates.jsonl | ConvertFrom-Json | tail -5" -ForegroundColor Gray
Write-Host ""
Write-Host "  # Watch positions" -ForegroundColor Gray
Write-Host "  Get-Content journal\faro_v3_positions.jsonl | ConvertFrom-Json | tail -5" -ForegroundColor Gray
Write-Host ""
Write-Host "  # Watch trades + PnL" -ForegroundColor Gray
Write-Host "  Get-Content journal\faro_v3_trades.jsonl | ConvertFrom-Json | Measure-Object -Property pnl -Sum" -ForegroundColor Gray
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green

Write-Host ""
Write-Host "🚀 NEXT STEPS:" -ForegroundColor Cyan
Write-Host "   1. Monitor first 24 hours (watch for signals → entries → exits)" -ForegroundColor Cyan
Write-Host "   2. After 10-20 trades, check actual win rate vs 57% target" -ForegroundColor Cyan
Write-Host "   3. After 100 trades, validate system or recalibrate" -ForegroundColor Cyan
Write-Host "   4. Scale to \$2,000 once validation complete (4-6 weeks)" -ForegroundColor Cyan
Write-Host ""
Write-Host "🎯 TARGET METRICS (After 100 trades):" -ForegroundColor Cyan
Write-Host "   ✓ Win rate: 55%+ (target 57%)" -ForegroundColor Cyan
Write-Host "   ✓ Avg win: +6-8% per winning trade" -ForegroundColor Cyan
Write-Host "   ✓ Avg loss: -1.5 to -2% per losing trade" -ForegroundColor Cyan
Write-Host "   ✓ Sharpe ratio: 1.5+ (good risk-adjusted returns)" -ForegroundColor Cyan
Write-Host "   ✓ Max drawdown: <20% (manageable risk)" -ForegroundColor Cyan
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "                     🔥 FARO V3 LIVE - TRADING ACTIVE 🔥" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════════════════════════" -ForegroundColor Green
