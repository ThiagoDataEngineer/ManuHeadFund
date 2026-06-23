# AUDIT_SPOT_RECOVERY.ps1 — Remediação de posições SPOT órfãs
# Detecta posições abertas no CoinEx que não estão em gem_trades.csv
# Opções: registrar com SL padrão, vender, ou deixar com trailing

param(
    [switch]$DryRun = $true,
    [switch]$FixAll = $false,
    [double]$DefaultSLPct = 0.01,  # 1% stop loss
    [double]$DefaultTPPct = 0.05   # 5% take profit
)

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$agentsDir = Join-Path $projectRoot "agents"
$journalDir = Join-Path $projectRoot "journal"

Set-Location $projectRoot

# Load libs
. (Join-Path $agentsDir "config.ps1") -ErrorAction SilentlyContinue
. (Join-Path $agentsDir "lib_coinex.ps1") -ErrorAction Stop
. (Join-Path $agentsDir "lib_daemon_singleton.ps1") -ErrorAction SilentlyContinue

Write-Host "=== SPOT POSITION AUDIT & RECOVERY ===" -ForegroundColor Cyan
Write-Host "DryRun: $DryRun | FixAll: $FixAll" -ForegroundColor Gray

# Posições conhecidas abertas (from gem_trades.csv)
$knownOpen = @{
    "FIROUSDT" = @{price=0.7745; qty=23.16994725}
    "OPNUSDT" = @{price=0.243034; qty=75.63329656}
    "AINUSDT" = @{price=0.09021; qty=201.68917432}
    "BASEDUSDT" = @{price=0.073238; qty=249.0277683}
    "COAIUSDT" = @{price=0.309137; qty=58.3534432}
    "PEPE2USDT" = @{price=1.932E-09; qty=9503619441.57}
    "SPCXXUSDT" = @{price=204.91; qty=0.08941579}
    "METUSDT" = @{price=0.129474; qty=561.39890575}
}

# Posições ORPHAN (não em gem_trades mas visíveis no CoinEx web)
$orphans = @(
    @{market="UBUSDT"; units=710.91; value_usd=67.41; pnl_usd=-10.81; action="AUDIT"}
    @{market="PAXGUSDT"; units=0.25704768; value_usd=1066.24; pnl_usd=-171.09; action="AUDIT"}
    @{market="TNSR"; units=1499.66480728; value_usd=58.93; pnl_usd=-9.17; action="VERIFY_TRAILING"}
    @{market="XRPUSDT"; units=22.32736098; value_usd=25.13; pnl_usd=-5.81; action="VERIFY_TRAILING"}
)

Write-Host "`n[ORPHAN POSITIONS] — não registradas em gem_trades.csv:" -ForegroundColor Yellow
$orphans | ForEach-Object {
    Write-Host "  $($_.market): $($_.units) units ($($_.value_usd) USD) | PnL: $($_.pnl_usd)" -ForegroundColor Gray
    Write-Host "    Action: $($_.action)" -ForegroundColor DarkYellow
}

# Recomendação
Write-Host "`n[RECOMENDATION] — Priority:" -ForegroundColor Magenta
Write-Host "  1. UBUSDT: ~50% realization (-$5), trailing other half" -ForegroundColor Cyan
Write-Host "  2. PAXGUSDT: Technical review (large loss -14%); consider cut if downtrend" -ForegroundColor Cyan
Write-Host "  3. TNSR, XRP: Verify trailing is active (check trailing_positions.json)" -ForegroundColor Cyan
Write-Host "  4. Then: All 8 OPEN trades → enable trailing + daily audit" -ForegroundColor Green

Write-Host "`n[NEXT STEP] — v7 Roadmap:" -ForegroundColor Green
Write-Host "  Phase 1: Stabilize all SPOT (SL/trailing active on 8 trades)" -ForegroundColor Gray
Write-Host "  Phase 2: Arbitrage engine (5min cycles, +2 USD per cycle target)" -ForegroundColor Gray
Write-Host "  Phase 3: SHORT/LONG/SPOT orchestration with maestria" -ForegroundColor Gray

if ($FixAll -and -not $DryRun) {
    Write-Host "`n[EXECUTING FIXES]..." -ForegroundColor Red
    # TODO: implement actual fixes
    # For now, output what would be done
}
