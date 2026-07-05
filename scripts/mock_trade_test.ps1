# mock_trade_test.ps1 — Mock Trade Test (30min simulação)
# 2026-07-05: Validar pipeline entrada→histórico→dashboard SEM trade real
# Simula: gem_executor processa candidate → registra outcome → dashboard atualiza

param([int]$MockTradeCount = 3, [int]$DelaySeconds = 30)

Write-Host "🧪 MOCK TRADE TEST — 30min Simulação" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "Simulando $MockTradeCount trades de ENTRADA até histórico atualizar" -ForegroundColor Yellow
Write-Host "Delay entre trades: ${DelaySeconds}sec" -ForegroundColor Yellow

$root = Split-Path $PSScriptRoot -Parent
$outcomeFile = Join-Path $root "journal\trade_outcomes.jsonl"
$historyFile = Join-Path $root "journal\trade_history_extended.json"

# Trades simulados (MOCK)
$mockTrades = @(
    @{
        trade_id = "MOCK-TEST-001"
        market = "MOCKUSDT"
        direction = "LONG"
        entry_price = 1.50
        exit_price = 1.65
        entry_date = (Get-Date).AddMinutes(-15).ToString("yyyy-MM-dd")
        exit_date = (Get-Date).ToString("yyyy-MM-dd")
        size_usd = 100
        pnl_pct = 10.0
        pnl_usd = 10.00
        win = $true
        alpha_vs_btc = 8.5
        close_reason = "mock_test_tp"
        notes = "Mock trade #1 — TP atingido"
        source = "mock_trade_test"
        registered_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    },
    @{
        trade_id = "MOCK-TEST-002"
        market = "MOCKUSDT"
        direction = "SHORT"
        entry_price = 1.65
        exit_price = 1.58
        entry_date = (Get-Date).AddMinutes(-10).ToString("yyyy-MM-dd")
        exit_date = (Get-Date).ToString("yyyy-MM-dd")
        size_usd = 80
        pnl_pct = 4.24
        pnl_usd = 3.40
        win = $true
        alpha_vs_btc = 2.3
        close_reason = "mock_test_tp"
        notes = "Mock trade #2 — TP atingido"
        source = "mock_trade_test"
        registered_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    },
    @{
        trade_id = "MOCK-TEST-003"
        market = "MOCKUSDT"
        direction = "LONG"
        entry_price = 1.58
        exit_price = 1.55
        entry_date = (Get-Date).AddMinutes(-5).ToString("yyyy-MM-dd")
        exit_date = (Get-Date).ToString("yyyy-MM-dd")
        size_usd = 120
        pnl_pct = -1.90
        pnl_usd = -2.28
        win = $false
        alpha_vs_btc = -4.2
        close_reason = "mock_test_sl"
        notes = "Mock trade #3 — SL atingido"
        source = "mock_trade_test"
        registered_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    }
)

Write-Host "`n[PASSO 1] Estado INICIAL do histórico" -ForegroundColor Yellow
if (Test-Path $historyFile) {
    $before = Get-Content $historyFile -Raw | ConvertFrom-Json
    Write-Host "  Trades antes: $($before.stats.totalTrades)" -ForegroundColor Gray
    Write-Host "  Win rate: $($before.stats.winRate)%" -ForegroundColor Gray
} else {
    Write-Host "  ⚠️  Histórico ainda não criado" -ForegroundColor Gray
}

Write-Host "`n[PASSO 2] Adicionar trades MOCK ao JSONL" -ForegroundColor Yellow
for ($i = 0; $i -lt $MockTradeCount; $i++) {
    $trade = $mockTrades[$i]
    $json = $trade | ConvertTo-Json -Compress

    # Append ao arquivo JSONL
    Add-Content $outcomeFile -Value $json -Encoding UTF8

    Write-Host "  ✅ Trade #$($i+1) adicionado: $($trade.trade_id) | $($trade.direction) $($trade.market) | PnL=$($trade.pnl_usd)" -ForegroundColor Green

    # Simular latência
    if ($i -lt ($MockTradeCount - 1)) {
        Write-Host "     Aguardando ${DelaySeconds}sec antes do próximo..." -ForegroundColor Gray
        Start-Sleep -Seconds $DelaySeconds
    }
}

Write-Host "`n[PASSO 3] Executar populate_trade_history.ps1" -ForegroundColor Yellow
$populateScript = Join-Path $root "scripts\populate_trade_history.ps1"
if (Test-Path $populateScript) {
    & $populateScript | Out-Null
    Write-Host "  ✅ Populador executado" -ForegroundColor Green
} else {
    Write-Host "  ❌ ERRO: populate_trade_history.ps1 não encontrado" -ForegroundColor Red
    exit 1
}

Write-Host "`n[PASSO 4] Verificar histórico APÓS trades" -ForegroundColor Yellow
if (Test-Path $historyFile) {
    $after = Get-Content $historyFile -Raw | ConvertFrom-Json
    Write-Host "  ✅ Trades após: $($after.stats.totalTrades) (era $(if ($before) { $before.stats.totalTrades } else { 0 }))" -ForegroundColor Green
    Write-Host "     Wins: $($after.stats.wins)" -ForegroundColor Green
    Write-Host "     Losses: $($after.stats.losses)" -ForegroundColor Green
    Write-Host "     PnL: $$($after.stats.totalPnL)" -ForegroundColor Green
    Write-Host "     Profit Factor: $($after.stats.profitFactor)" -ForegroundColor Green
    Write-Host "     Win Rate: $($after.stats.winRate)%" -ForegroundColor Green
} else {
    Write-Host "  ❌ ERRO: Histórico não foi atualizado" -ForegroundColor Red
    exit 1
}

Write-Host "`n[PASSO 5] Validar JSONL integridade" -ForegroundColor Yellow
$lines = @(Get-Content $outcomeFile -Encoding UTF8)
$validCount = 0
$invalidCount = 0

foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try {
        $obj = $line | ConvertFrom-Json
        if ($obj.market -and $obj.direction) { $validCount++ }
    } catch {
        $invalidCount++
    }
}

Write-Host "  ✅ JSONL válidas: $validCount linhas" -ForegroundColor Green
if ($invalidCount -gt 0) {
    Write-Host "  ⚠️  Linhas inválidas: $invalidCount" -ForegroundColor Yellow
}

Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "✅ MOCK TRADE TEST COMPLETO" -ForegroundColor Green
Write-Host "`nProximos passos:" -ForegroundColor Green
Write-Host "  1. Abra dashboard no navegador (F5 pra refresh)" -ForegroundColor Cyan
Write-Host "  2. TAB 3: Histórico deve mostrar trades anteriores + $MockTradeCount mock trades" -ForegroundColor Cyan
Write-Host "  3. Stats devem estar atualizadas (totalTrades = $($after.stats.totalTrades))" -ForegroundColor Cyan
Write-Host "`nSe tudo verde acima, GO-LIVE APROVADO! 🚀" -ForegroundColor Green
