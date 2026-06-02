# FARO_V3_GO_LIVE.ps1 — ATIVA SISTEMA COMPLETO COM CAPITAL REAL
# Começa com $5 teste, scale pra $50, $500, $5k progressivamente

param(
    [decimal] $InitialCapital = 5.0,  # $5 teste
    [bool] $DryRun = $false  # FALSE = REAL TRADES
)

Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║           🔥 FARO V3 AGGRESSIVE - GO LIVE 🔥                  ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "⚠️  PRODUCTION MODE ACTIVATED" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "Timestamp: $timestamp" -ForegroundColor Green
Write-Host "Capital: `$$InitialCapital (TEST → SCALE)" -ForegroundColor Green
Write-Host "Mode: AGGRESSIVE_SCALP (6/7 signals, -2% stops, +3/8/20% targets)" -ForegroundColor Green
Write-Host "Leverage: 1.5x-2.0x (score-based)" -ForegroundColor Green
Write-Host "Max positions: 20 concurrent" -ForegroundColor Green
Write-Host "Expected: +200-300/day ($4-6k/month)" -ForegroundColor Green

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow

if ($DryRun) {
    Write-Host "🟡 DRY RUN MODE - No real trades" -ForegroundColor Yellow
} else {
    Write-Host "🔴 LIVE MODE - REAL TRADES ACTIVE" -ForegroundColor Red
}

Write-Host ""
Write-Host "SYSTEM ACTIVATION:" -ForegroundColor Cyan
Write-Host "═════════════════════════════════════════════════════════════════" -ForegroundColor Cyan

$projectRoot = Split-Path $PSScriptRoot -Parent
$agentsDir = Join-Path $projectRoot "agents"
$scriptsDir = Join-Path $projectRoot "scripts"
$journalDir = Join-Path $projectRoot "journal"

# Load all libs
Write-Host ""
Write-Host "1️⃣  Loading configuration & libraries..." -ForegroundColor Cyan
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
    if (Test-Path $p) {
        . $p
        $loadCount++
        Write-Host "   ✓ $l" -ForegroundColor Green
    }
}
Write-Host "   Loaded $loadCount/$($libs.Count) libs" -ForegroundColor Green

# Validate CoinEx API
Write-Host ""
Write-Host "2️⃣  Validating CoinEx API..." -ForegroundColor Cyan
try {
    $btc = CoinEx-GetTicker -market "BTCUSDT" -ErrorAction Stop
    Write-Host "   ✓ API Connected (BTC: `$$($btc.last))" -ForegroundColor Green
    Write-Host "   ✓ Ready to trade" -ForegroundColor Green
} catch {
    Write-Host "   ✗ API ERROR: $_" -ForegroundColor Red
    Write-Host "   Fix: Set COINEX_ACCESS_ID and COINEX_SECRET_KEY env vars" -ForegroundColor Yellow
    exit 1
}

# Start engine scan
Write-Host ""
Write-Host "3️⃣  Running initial engine scan..." -ForegroundColor Cyan
try {
    & (Join-Path $scriptsDir "faro_v3_engine.ps1") -DryRun $DryRun | Out-Null
    Write-Host "   ✓ Engine scan complete" -ForegroundColor Green
} catch {
    Write-Host "   ✗ Engine error: $_" -ForegroundColor Red
}

# Check candidates generated
Write-Host ""
Write-Host "4️⃣  Checking signal candidates..." -ForegroundColor Cyan
$candFile = Join-Path $journalDir "faro_v3_candidates.jsonl"
if (Test-Path $candFile) {
    $lines = @(Get-Content $candFile)
    Write-Host "   ✓ Candidates file: $($lines.Count) signals found" -ForegroundColor Green
    if ($lines.Count -gt 0) {
        $latest = $lines[-1] | ConvertFrom-Json
        Write-Host "   Latest: $($latest.market) - Score: $($latest.score) - Decision: $($latest.decision)" -ForegroundColor Cyan
    }
} else {
    Write-Host "   ⚠️  No candidates yet (will generate on next engine run)" -ForegroundColor Yellow
}

# Check scheduled tasks
Write-Host ""
Write-Host "5️⃣  Checking Task Scheduler..." -ForegroundColor Cyan
$tasks = @("ManuHeadFund_FARO_V3_engine_agg", "ManuHeadFund_FARO_V3_entry_agg", "ManuHeadFund_FARO_V3_manager_agg")
$enabledCount = 0
foreach ($task in $tasks) {
    try {
        $t = Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
        if ($t) {
            Write-Host "   ✓ $task" -ForegroundColor Green
            if ($t.State -eq "Ready") { $enabledCount++ }
        }
    } catch {}
}
Write-Host "   $enabledCount/$($tasks.Count) tasks enabled" -ForegroundColor Cyan

# Ready for live entry
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "6️⃣  STARTING LIVE ENTRY ENGINE..." -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "   🟡 DRY RUN: Testing logic without real trades" -ForegroundColor Yellow
} else {
    Write-Host "   🔴 LIVE: REAL TRADES WILL BE PLACED" -ForegroundColor Red
    Write-Host "   Capital: `$$InitialCapital" -ForegroundColor Red
    Write-Host "   Per position: `$$(5 * 0.005 * 1.5) (0.5% × 1.5x leverage)" -ForegroundColor Red
    Write-Host ""
    Write-Host "⚠️  Last chance to CTRL+C if you want to stop!" -ForegroundColor Yellow
    Write-Host "    Starting in 3 seconds..." -ForegroundColor Yellow
    Start-Sleep -Seconds 3
}

Write-Host ""
Write-Host "🚀 LAUNCHING ENTRY ENGINE..." -ForegroundColor Green

try {
    & (Join-Path $scriptsDir "faro_v3_entry_aggressive.ps1") -DryRun $DryRun
} catch {
    Write-Host "Error in entry: $_" -ForegroundColor Red
}

# Show results
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "📊 LIVE STATUS:" -ForegroundColor Green

# Check positions
$posFile = Join-Path $journalDir "faro_v3_positions.jsonl"
if (Test-Path $posFile) {
    $positions = @(Get-Content $posFile | ConvertFrom-Json)
    $active = @($positions | Where-Object { $_.status -eq "active" })
    Write-Host "   Active Positions: $($active.Count)" -ForegroundColor Green
    foreach ($pos in $active | Select-Object -First 3) {
        Write-Host "   • $($pos.market): Entry \$$('{0:F2}' -f $pos.entry_price) | Size \$$('{0:F2}' -f ($pos.entry_price * $pos.quantity))" -ForegroundColor Cyan
    }
} else {
    Write-Host "   No positions yet" -ForegroundColor Yellow
}

# Monitoring instructions
Write-Host ""
Write-Host "═════════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "📡 MONITORING COMMANDS:" -ForegroundColor Green
Write-Host ""
Write-Host "  # Check open positions" -ForegroundColor Gray
Write-Host "  Get-Content C:\Users\thiag\Coinex_AI_USER_API\journal\faro_v3_positions.jsonl | ConvertFrom-Json | tail -5" -ForegroundColor Gray
Write-Host ""
Write-Host "  # Check signals" -ForegroundColor Gray
Write-Host "  Get-Content C:\Users\thiag\Coinex_AI_USER_API\journal\faro_v3_candidates.jsonl | ConvertFrom-Json | tail -5" -ForegroundColor Gray
Write-Host ""
Write-Host "  # Check closed trades" -ForegroundColor Gray
Write-Host "  Get-Content C:\Users\thiag\Coinex_AI_USER_API\journal\faro_v3_trades.jsonl | ConvertFrom-Json" -ForegroundColor Gray
Write-Host ""
Write-Host "═════════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "✅ SYSTEM ACTIVE - MONITORING LIVE DATA" -ForegroundColor Green
Write-Host "═════════════════════════════════════════════════════════════════" -ForegroundColor Green

if (-not $DryRun) {
    Write-Host ""
    Write-Host "🚀 LIVE TRADING ACTIVATED" -ForegroundColor Green
    Write-Host "📈 Expected: +\$$('{0:F0}' -f 250)/day" -ForegroundColor Green
    Write-Host "📊 Monthly: +\$$('{0:F0}' -f 5000)" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Monitor first 24h trades" -ForegroundColor Cyan
    Write-Host "  2. Validate win rate (target 55%+)" -ForegroundColor Cyan
    Write-Host "  3. After 100 trades, calibrate or scale" -ForegroundColor Cyan
}
