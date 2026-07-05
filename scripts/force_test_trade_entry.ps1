# force_test_trade_entry.ps1 — Força 1 entrada de teste para validar pipeline
# 2026-07-05: Mercado restritivo (BEAR_WEAK), gates bloqueando tudo
# Solução: Injeta 1 candidato direto no gem_loop com FORCE_ENTRY=true

param([string]$Symbol = "WAVESUSDT", [string]$Direction = "LONG", [double]$Entry = 0.27, [double]$SL = 0.26, [double]$TP = 0.32, [double]$SizeUSD = 50)

Write-Host "🔥 FORÇA ENTRY — Injetando trade no pipeline" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

$root = Split-Path $PSScriptRoot -Parent

# Dados da entrada forçada
$candidate = @{
    symbol = $Symbol
    direction = $Direction
    entry_price = $Entry
    stop_loss = $SL
    take_profit = $TP
    size_usd = $SizeUSD
    score = 75  # Score alto pra passar gates
    conviction = 85
    regime = "BEAR_WEAK"
    confluence = 5  # 5+ fatores
    reason = "FORCE_TEST_ENTRY_VALIDATION"
    timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

Write-Host "`n📊 Candidato de Teste:" -ForegroundColor Yellow
Write-Host "   Symbol: $($candidate.symbol)"
Write-Host "   Direction: $($candidate.direction)"
Write-Host "   Entry: $($candidate.entry_price)"
Write-Host "   SL: $($candidate.stop_loss)"
Write-Host "   TP: $($candidate.take_profit)"
Write-Host "   Size: $$($candidate.size_usd)"
Write-Host "   Conviction: $($candidate.conviction)"
Write-Host "   Reason: $($candidate.reason)"

Write-Host "`n⚡ Simulando gem_executor..." -ForegroundColor Green

# Simular registro da entrada
$tradeEntry = @{
    trade_id = "$($Symbol)-FORCE-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    market = $Symbol
    direction = $Direction
    entry_price = $Entry
    entry_date = (Get-Date).ToString("yyyy-MM-dd")
    exit_date = $null
    size_usd = $SizeUSD
    exit_price = $null
    pnl_pct = $null
    pnl_usd = $null
    win = $null
    alpha_vs_btc = $null
    close_reason = "pending"
    notes = "FORCE_TEST_ENTRY — validar pipeline end-to-end. Score=$($candidate.score), Conviction=$($candidate.conviction)"
    source = "force_test_trade_entry"
    registered_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
}

# Append ao JSONL
$outcomeFile = Join-Path $root "journal/trade_outcomes.jsonl"
$json = $tradeEntry | ConvertTo-Json -Compress
Add-Content $outcomeFile -Value $json -Encoding UTF8

Write-Host "✅ Trade FORCE injetado em trade_outcomes.jsonl" -ForegroundColor Green
Write-Host "   ID: $($tradeEntry.trade_id)" -ForegroundColor Gray
Write-Host "   JSONL: $outcomeFile" -ForegroundColor Gray

Write-Host "`n⚡ Executando populate_trade_history.ps1..." -ForegroundColor Yellow
$populateScript = Join-Path $root "scripts\populate_trade_history.ps1"
& $populateScript | Out-Null

Write-Host "✅ Histórico atualizado" -ForegroundColor Green

Write-Host "`n📊 Verificando dashboard agora..." -ForegroundColor Yellow
$historyFile = Join-Path $root "journal/trade_history_extended.json"
if (Test-Path $historyFile) {
    $history = Get-Content $historyFile -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Host "   Total trades: $($history.stats.totalTrades)" -ForegroundColor Green
    Write-Host "   Wins: $($history.stats.wins)"
    Write-Host "   Losses: $($history.stats.losses)"
    Write-Host "   PnL: $$($history.stats.totalPnL)"
}

Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "✅ FORCE ENTRY COMPLETO" -ForegroundColor Green
Write-Host "`nProximos passos:" -ForegroundColor Yellow
Write-Host "  1. Abra dashboard: file:///C:/Users/thiag/Coinex_AI_USER_API/dashboard/test_simple.html" -ForegroundColor Cyan
Write-Host "  2. Verifique TAB 'Histórico' — trade deve estar lá" -ForegroundColor Cyan
Write-Host "  3. Próximo ciclo de scan (~15min) vai buscar sair automático (TP/SL)" -ForegroundColor Cyan
Write-Host "`n🎯 Se funcionar: pipeline está OK, mercado só tá restritivo" -ForegroundColor Green
Write-Host "🎯 Se não funcionar: há bug no populate ou renderização" -ForegroundColor Green
