# paper_calibration_report.ps1 — Relatório de progresso da calibração de paper trade
# Uso: .\scripts\paper_calibration_report.ps1
# Output: (1) console summary, (2) Telegram alert, (3) CSV detalhado

param(
    [switch]$SendTelegram = $true
)

$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$agentsDir = Join-Path $scriptDir "..\agents"
$journalDir = Join-Path $scriptDir "..\journal"

# Carregar configs
. (Join-Path $agentsDir "config.ps1")
if (Test-Path (Join-Path $agentsDir "lib_telegram.ps1")) {
    . (Join-Path $agentsDir "lib_telegram.ps1")
}

# === Coletar dados de calibração ===

$calibFile = Join-Path $journalDir "paper_calibration_trades.jsonl"
if (-not (Test-Path $calibFile)) {
    Write-Host "❌ Nenhum arquivo de calibração encontrado: $calibFile" -ForegroundColor Red
    exit 1
}

$trades = @()
Get-Content $calibFile -Encoding utf8 | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($_)) { return }
    $trades += ($_ | ConvertFrom-Json)
}

if ($trades.Count -eq 0) {
    Write-Host "❌ Arquivo vazio: $calibFile" -ForegroundColor Red
    exit 1
}

# === Análise ===

$winCount = @($trades | Where-Object { $_.pnl_pct -gt 0 }).Count
$lossCount = @($trades | Where-Object { $_.pnl_pct -lt 0 }).Count
$breakCount = @($trades | Where-Object { $_.pnl_pct -eq 0 }).Count

$totalPnl = $trades | Measure-Object -Property pnl_pct -Sum | Select-Object -ExpandProperty Sum
$avgPnl = if ($trades.Count -gt 0) { $totalPnl / $trades.Count } else { 0 }
$winRate = if ($trades.Count -gt 0) { ($winCount / $trades.Count) * 100 } else { 0 }

$maxDrawdown = $trades | Measure-Object -Property pnl_pct -Minimum | Select-Object -ExpandProperty Minimum
$maxProfit = $trades | Measure-Object -Property pnl_pct -Maximum | Select-Object -ExpandProperty Maximum

$startTime = @($trades | Sort-Object timestamp | Select-Object -First 1).timestamp
$endTime = @($trades | Sort-Object timestamp | Select-Object -Last 1).timestamp
$elapsedDays = if ($startTime -and $endTime) { ([datetime]$endTime - [datetime]$startTime).TotalDays } else { 0 }

# === Meta ===

$targetTrades = 30
$progressPct = ($trades.Count / $targetTrades) * 100

# === Output Console ===

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     PAPER TRADE CALIBRATION REPORT                            ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

Write-Host "📊 PROGRESSO"
Write-Host "  Trades executados: $($trades.Count)/$targetTrades ($([math]::Round($progressPct, 1))%)" -ForegroundColor Green
Write-Host "  Período: $(if ($startTime) { [datetime]$startTime | Get-Date -Format 'yyyy-MM-dd HH:mm' } else { 'N/A' }) → $(if ($endTime) { [datetime]$endTime | Get-Date -Format 'yyyy-MM-dd HH:mm' } else { 'N/A' })"
Write-Host "  Tempo decorrido: $([math]::Round($elapsedDays, 1)) dias"
Write-Host ""

Write-Host "💰 RESULTADOS (P&L em %)"
Write-Host "  Win rate: $winCount ganhos / $lossCount perdas / $breakCount break-even = $([math]::Round($winRate, 1))% taxa de acerto" -ForegroundColor $(if ($winRate -gt 40) { 'Green' } else { 'Yellow' })
Write-Host "  P&L total: $([math]::Round($totalPnl, 2))%"
Write-Host "  P&L médio por trade: $([math]::Round($avgPnl, 2))%"
Write-Host "  Max profit: $([math]::Round($maxProfit, 2))%"
Write-Host "  Max drawdown: $([math]::Round($maxDrawdown, 2))%"
Write-Host ""

Write-Host "🎯 BENCHMARKS TEÓRICOS"
Write-Host "  Win rate esperado (RR 1:3): 25-30%"
Write-Host "  Win rate observado: $([math]::Round($winRate, 1))%"
if ($winRate -gt 30) {
    Write-Host "  ✅ ACIMA DO ESPERADO - Sinal positivo" -ForegroundColor Green
} elseif ($winRate -gt 25) {
    Write-Host "  ⚠️  DENTRO DO RANGE - Ajuste fino necessário" -ForegroundColor Yellow
} else {
    Write-Host "  ❌ ABAIXO DO ESPERADO - Reavalie estratégia" -ForegroundColor Red
}
Write-Host ""

Write-Host "📋 PRÓXIMAS AÇÕES"
if ($trades.Count -ge $targetTrades) {
    Write-Host "  ✅ Meta atingida! Pronto para:"
    Write-Host "     1. Analisar decisões com maior confiança"
    Write-Host "     2. Remover PAPER_CALIBRATION_MODE.flag"
    Write-Host "     3. Ajustar SCORE_MINIMO → 60-65 (produção)"
    Write-Host "     4. Monitorar LIVE Mode 2 com capital real" -ForegroundColor Green
} else {
    $remaining = $targetTrades - $trades.Count
    Write-Host "  ⏳ Faltam $remaining trades para atingir meta"
    Write-Host "     Taxa atual: $([math]::Round($trades.Count / [math]::Max(0.1, $elapsedDays), 1)) trades/dia"
    Write-Host "     ETA: $(if ($elapsedDays -gt 0) { [datetime]::Now.AddDays([math]::Max(0, $remaining / ($trades.Count / [math]::Max(0.1, $elapsedDays)))) | Get-Date -Format 'yyyy-MM-dd' } else { 'N/A' })" -ForegroundColor Yellow
}
Write-Host ""

# === Export CSV ===

$csvPath = Join-Path $journalDir "paper_calibration_report.csv"
$reportData = @{
    timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    trades_total = $trades.Count
    trades_target = $targetTrades
    progress_pct = [math]::Round($progressPct, 1)
    win_count = $winCount
    loss_count = $lossCount
    break_count = $breakCount
    win_rate_pct = [math]::Round($winRate, 1)
    pnl_total_pct = [math]::Round($totalPnl, 2)
    pnl_avg_pct = [math]::Round($avgPnl, 2)
    max_profit_pct = [math]::Round($maxProfit, 2)
    max_drawdown_pct = [math]::Round($maxDrawdown, 2)
    elapsed_days = [math]::Round($elapsedDays, 1)
}

$reportData | ConvertTo-Csv -NoTypeInformation | Out-File -FilePath $csvPath -Encoding utf8 -Append

Write-Host "📁 Relatório salvo em: $csvPath" -ForegroundColor DarkGray
Write-Host ""

# === Telegram Alert ===

if ($SendTelegram -and (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue)) {
    $emoji = if ($winRate -gt 40) { "✅" } elseif ($winRate -gt 25) { "⚠️" } else { "❌" }
    
    $msg = @"
<b>📊 CALIBRAÇÃO PAPER TRADE</b>
Progresso: <code>$($trades.Count)/$targetTrades ($([math]::Round($progressPct, 1))%)</code>

<b>Resultados:</b>
Win rate: <code>$([math]::Round($winRate, 1))%</code> $emoji
P&L total: <code>$([math]::Round($totalPnl, 2))%</code>
P&L médio: <code>$([math]::Round($avgPnl, 2))%</code>

Período: <code>$([math]::Round($elapsedDays, 1)) dias</code>
"@
    
    Send-TelegramAlert -Message $msg | Out-Null
}

Write-Host "✅ Relatório completo gerado" -ForegroundColor Green
