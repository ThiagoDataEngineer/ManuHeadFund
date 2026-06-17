# run_feedback_loop_test.ps1 -- Teste integrado do feedback loop
# Roda: stats → calibra → ativa trailing → sizing → relatorio

$ErrorActionPreference = "Continue"
$projectRoot = Split-Path -Parent $PSScriptRoot
$agentsDir = Join-Path $projectRoot "agents"
$journalDir = Join-Path $projectRoot "journal"

. (Join-Path $agentsDir "lib_sizing_dynamics.ps1")
. (Join-Path $agentsDir "lib_trailing_auto_activate.ps1")
. (Join-Path $agentsDir "lib_feedback_calibrator.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")

Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║         FEEDBACK LOOP TEST — Sizing + Calibration             ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

# 1) Capital atual
$spot = 925.07
$futures = 2714.02
Write-Host "1️⃣  CAPITAL" -ForegroundColor Cyan
Write-Host "   SPOT: `$$spot | FUTURES: `$$futures | TOTAL: `$$(spot+futures)" -ForegroundColor Gray

# 2) Regime atual (BEAR_WEAK = SHORT favorecido)
$regime = "BEAR_WEAK"
$alloc = Get-DynamicCapitalAllocation -SpotUsdt $spot -FuturesUsdt $futures -Regime $regime
Write-Host ""
Write-Host "2️⃣  ALOCAÇÃO (regime=$regime)" -ForegroundColor Cyan
Write-Host "   SHORT (futures 20x): `$$([math]::Round($alloc.short_alloc,2)) ($($alloc.short_pct*100)%)" -ForegroundColor Yellow
Write-Host "   LONG (spot 1x):      `$$([math]::Round($alloc.long_alloc,2)) ($($alloc.long_pct*100)%)" -ForegroundColor Blue

# 3) Size por trade
$size_short = Get-SizePerTrade -AllocatedCapital $alloc.short_alloc -MaxConcurrentTrades 5 -StopLossPct 0.015
$size_long = Get-SizePerTrade -AllocatedCapital $alloc.long_alloc -MaxConcurrentTrades 5 -StopLossPct 0.02
Write-Host ""
Write-Host "3️⃣  SIZING POR TRADE (risco 1% do capital total)" -ForegroundColor Cyan
Write-Host "   SHORT: `$$([math]::Round($size_short,2)) com leverage 20x" -ForegroundColor Yellow
Write-Host "   LONG:  `$$([math]::Round($size_long,2)) com leverage 1x" -ForegroundColor Blue

# 4) Outcomes dos últimos 7 dias
Write-Host ""
Write-Host "4️⃣  OUTCOMES 7D (feedback)" -ForegroundColor Cyan
$outcomesFile = Join-Path $journalDir "trade_outcomes.jsonl"
$stats = Get-OutcomesStats -OutcomesFile $outcomesFile -Days 7

if ($stats) {
    Write-Host "   Trades:        $($stats.trades)"
    Write-Host "   Wins/Losses:   $($stats.wins)/$($stats.losses)"
    Write-Host "   Win Rate:      $([math]::Round($stats.win_rate*100,1))%"
    Write-Host "   PnL Total:     `$$($stats.pnl_total_usd)"
    Write-Host "   PnL Médio:     `$$($stats.pnl_avg_usd)/trade" -ForegroundColor $(if($stats.pnl_avg_usd -ge 0){'Green'}else{'Red'})
    Write-Host "   Melhor/Pior:   `$$($stats.best_pnl) / `$$($stats.worst_pnl)"
    Write-Host "   Avg Loss:      $([math]::Abs($stats.avg_loss_pct))%"
} else {
    Write-Host "   ⚠️  Sem dados de outcomes (primeiros trades)" -ForegroundColor Yellow
    $stats = @{ trades=0; win_rate=0.40; pnl_total_usd=0 }
}

# 5) Calibração automática
Write-Host ""
Write-Host "5️⃣  CALIBRAÇÃO (auto-feedback)" -ForegroundColor Cyan

$currentParams = @{
    THRESHOLD_ENTRADA   = 70
    STOP_LOSS_PCT       = 2.0
    TARGET_PROFIT_PCT   = 10.0
    SHORT_RATIO         = 0.80
}

$calibration = Get-CalibratedParams -Stats $stats -CurrentParams $currentParams

Write-Host "   📊 Antes:"
$currentParams.GetEnumerator() | ForEach-Object {
    Write-Host "      $($_.Name): $($_.Value)" -ForegroundColor Gray
}

Write-Host "   📊 Depois:"
$calibration.calibrated.GetEnumerator() | ForEach-Object {
    $changed = $currentParams[$_.Name] -ne $_.Value
    $col = if ($changed) { 'Green' } else { 'Gray' }
    $mark = if ($changed) { ' ✓' } else { '' }
    Write-Host "      $($_.Name): $($_.Value)$mark" -ForegroundColor $col
}

if ($calibration.changes.Count -gt 0) {
    Write-Host "   🔧 Ajustes:"
    $calibration.changes | ForEach-Object {
        Write-Host "      $($_.param): $($_.old) → $($_.new) ($($_.reason))" -ForegroundColor Yellow
    }
}

# 6) Trailing automático
Write-Host ""
Write-Host "6️⃣  TRAILING AUTOMÁTICO" -ForegroundColor Cyan
$trailFile = Join-Path $journalDir "trailing_positions.json"
$trailingStatus = Get-TrailingStatus -TrailFile $trailFile
if ($trailingStatus.Count -gt 0) {
    $trailingStatus | ForEach-Object {
        $status = if ($_.trailing) { "✓ ATIVO" } else { "✗ INATIVO" }
        Write-Host "   $($_.market): $status (trailing $($_.trailing_pct*100)%, phase $($_.phase))"
    }
} else {
    Write-Host "   ℹ️  Nenhuma posição aberta com trailing" -ForegroundColor Gray
}

# 7) Resumo executivo
Write-Host ""
Write-Host "7️⃣  META: \$10/DIA TESTAVEL" -ForegroundColor Cyan
$target_daily = 10
$capital_total = $spot + $futures
$daily_pct = ($target_daily / $capital_total) * 100
$trades_needed_month = 25
$wins_needed = [math]::Round($trades_needed_month * 0.45)
$losses_allowed = $trades_needed_month - $wins_needed
$expected_pnl = ($wins_needed * 1.5) + ($losses_allowed * -0.30)

Write-Host "   Capital:       `$$capital_total"
Write-Host "   Target/dia:    `$$target_daily ($([math]::Round($daily_pct,2))%/dia)"
Write-Host "   Trades/mês:    $trades_needed_month (~1.19/dia)"
Write-Host "   Win rate:      45% esperado (modelo com +20 threshold_entrada, -0.5% stop)"
Write-Host "   Expected PnL:  `$$([math]::Round($expected_pnl,2))/mês (vs $([math]::Round($target_daily*21,0))/mês target)" -ForegroundColor $(if($expected_pnl -gt 200){'Green'}else{'Yellow'})

Write-Host ""
Write-Host "✅ Feedback loop completo. Dados prontos pra próximo ciclo gem_loop." -ForegroundColor Green
Write-Host ""

# Salvar relatório
$reportFile = Join-Path $journalDir "calibration_report_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
Write-CalibrationReport -Calibration $calibration -OutputFile $reportFile
Write-Host "📄 Relatório: $reportFile" -ForegroundColor Gray
