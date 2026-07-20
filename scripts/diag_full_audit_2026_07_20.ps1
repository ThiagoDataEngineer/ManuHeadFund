# diag_full_audit_2026_07_20.ps1 -- auditoria one-shot ampla, so leitura.
#
# Cobre: posicoes reais (leverage/SL/TP), consistencia de exposicao, e
# confirmacao de que o gate estrutural novo (lib_token_structural_quality.ps1,
# commit 9b4c829) esta acessivel/funcional no ambiente real de producao.

$agentsDir = Join-Path $PSScriptRoot ".." "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_token_structural_quality.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

Write-Host "=== AUDITORIA AMPLA (READ-ONLY) 2026-07-20 ===" -ForegroundColor Cyan
Write-Host ""

# [1] Posicoes FUTURES reais -- leverage, SL, TP
Write-Host "[1] Posicoes FUTURES reais abertas -- leverage/SL/TP" -ForegroundColor Yellow
try {
    $pos = @(CoinEx-GetPendingPositions -ErrorAction Stop)
    Write-Host "  Total posicoes FUTURES: $($pos.Count)" -ForegroundColor White
    $overLev = 0
    $noSl = 0
    foreach ($p in $pos) {
        $lev = if ($p.leverage) { [double]$p.leverage } else { 0 }
        $hasSl = ($p.stop_loss_price -and "$($p.stop_loss_price)" -ne "0")
        $hasTp = ($p.take_profit_price -and "$($p.take_profit_price)" -ne "0")
        if ($lev -gt 5) { $overLev++ }
        if (-not $hasSl) { $noSl++ }
        $flag = if ($lev -gt 5 -or -not $hasSl) { "[!]" } else { "   " }
        Write-Host "  $flag $($p.market) side=$($p.side) leverage=${lev}x SL=$($p.stop_loss_price) TP=$($p.take_profit_price)"
    }
    if ($overLev -gt 0) { Write-Host "  [CRITICAL] $overLev posicao(oes) com leverage > 5x" -ForegroundColor Red }
    if ($noSl -gt 0) { Write-Host "  [CRITICAL] $noSl posicao(oes) SEM stop loss configurado na exchange" -ForegroundColor Red }
    if ($overLev -eq 0 -and $noSl -eq 0 -and $pos.Count -gt 0) { Write-Host "  [OK] todas as posicoes com leverage<=5x e SL configurado" -ForegroundColor Green }
} catch {
    Write-Host "  ERRO: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# [2] Holdings SPOT -- so contagem/contexto (ja auditado em detalhe ontem)
Write-Host "[2] Holdings SPOT (contexto)" -ForegroundColor Yellow
try {
    $bal = CoinEx-Get "/v2/assets/spot/balance" -EA Stop
    $holdings = @($bal.data | Where-Object { $_.ccy -ne "USDT" -and ([double]$_.available -gt 0 -or [double]$_.frozen -gt 0) })
    Write-Host "  Holdings nao-USDT: $($holdings.Count) ($($holdings.ccy -join ', '))" -ForegroundColor White
} catch {
    Write-Host "  ERRO: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# [3] Gate estrutural novo -- funcional no ambiente real?
Write-Host "[3] Gate estrutural (lib_token_structural_quality.ps1) -- smoke test real" -ForegroundColor Yellow
try {
    if (-not (Get-Command Test-TokenStructuralQuality -ErrorAction SilentlyContinue)) {
        Write-Host "  [CRITICAL] Test-TokenStructuralQuality NAO carregou" -ForegroundColor Red
    } else {
        # Testa com BTCUSDT real (deve dar PASS -- liquidez profunda, preco normal)
        $ticker = CoinEx-GetTicker "BTCUSDT"
        $btcPrice = [double]$ticker.last
        $r = Test-TokenStructuralQuality -Market "BTCUSDT" -CurrentPrice $btcPrice -IntendedSizeUsd 100
        Write-Host "  BTCUSDT (real): verdict=$($r.verdict) liquidity_usd=$($r.liquidity_usd) liquidity_multiple=$($r.liquidity_multiple)x price=$btcPrice" -ForegroundColor White
        if ($r.verdict -eq "PASS") {
            Write-Host "  [OK] gate funcional, BTCUSDT passa como esperado" -ForegroundColor Green
        } else {
            Write-Host "  [WARN] BTCUSDT deu $($r.verdict) -- inesperado pra uma major, investigar CoinEx-GetSpotDepth" -ForegroundColor Yellow
        }

        # Confirma CoinEx-GetSpotDepth funciona de verdade (endpoint novo)
        try {
            $depth = CoinEx-GetSpotDepth "BTCUSDT" 20
            Write-Host "  CoinEx-GetSpotDepth: OK, bids=$(@($depth.depth.bids).Count) asks=$(@($depth.depth.asks).Count)" -ForegroundColor Green
        } catch {
            Write-Host "  [CRITICAL] CoinEx-GetSpotDepth falhou: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "  ERRO: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# [4] trade_rejections -- o gate estrutural ja bloqueou algo desde o deploy?
Write-Host "[4] trade_rejections -- gate 'token_structural_quality_block' ja disparou?" -ForegroundColor Yellow
try {
    $rej = @(Get-StateRecords -Table "trade_rejections" -ErrorAction Stop)
    $structRej = @($rej | Where-Object { "$($_.gate)" -like "*token_structural_quality*" })
    Write-Host "  Total trade_rejections: $($rej.Count) | via gate estrutural: $($structRej.Count)" -ForegroundColor White
    foreach ($s in ($structRej | Sort-Object ts -Descending | Select-Object -First 10)) {
        Write-Host "    $($s.ts) | $($s.market) | $($s.gate)"
    }
} catch {
    Write-Host "  ERRO: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# [5] live_monitor_snapshots -- Fase 1 do monitor esta gravando de verdade?
Write-Host "[5] live_monitor_snapshots -- monitor Fase 1 gravando?" -ForegroundColor Yellow
try {
    $snaps = @(Get-StateRecords -Table "live_monitor_snapshots" -ErrorAction Stop)
    Write-Host "  Total snapshots: $($snaps.Count)" -ForegroundColor White
    if ($snaps.Count -gt 0) {
        $last = $snaps | Sort-Object ts -Descending | Select-Object -First 1
        Write-Host "  Ultimo: ts=$($last.ts) ok=$($last.ok_count) warn=$($last.warn_count) critical=$($last.critical_count)" -ForegroundColor White
    } else {
        Write-Host "  [WARN] 0 snapshots -- tabela pode nao ter sido criada (rodar SETUP_SUPABASE_LIVE_MONITOR_SNAPSHOTS) ou job nao passou pelo cron_guard ainda" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ERRO ou tabela ausente: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== FIM AUDITORIA ===" -ForegroundColor Cyan
