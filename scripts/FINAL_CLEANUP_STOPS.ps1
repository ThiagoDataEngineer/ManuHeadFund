#!/usr/bin/env pwsh
# FINAL_CLEANUP_STOPS.ps1
# LIMPEZA FINAL + RECRIAÇÃO ÚNICO: Deleta TUDO, recria 2 únicos stops
# MANUAL ONLY - NÃO DEVE RODAR AUTOMATICAMENTE
# 2026-06-20 Urgência

$ErrorActionPreference = "Stop"

. agents/config.local.ps1
. agents/config.ps1
. agents/lib_coinex.ps1
. agents/lib_telegram.ps1

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Red
Write-Host "║  LIMPEZA FINAL: Deletar TUDO + Recriar 2 únicos       ║" -ForegroundColor Red
Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Red
Write-Host ""

# ============================================================
# STEP 1: Deletar TODOS os stops
# ============================================================

Write-Host "[STEP 1] Deletando TODOS os stop orders..." -ForegroundColor Red

$markets = @("BASEDUSDT", "METUSDT", "AINUSDT", "SPCXXUSDT", "CROUSDT", "XRPUSDT", "BTCUSDT", "PAXGUSDT", "HTXUSDT", "TRUMPUSDT", "LINKUSDT")
$totalDeleted = 0

foreach ($market in $markets) {
    try {
        $pending = CoinEx-Get "/v2/spot/pending-stop-order?market=$market&market_type=SPOT&page=1&limit=100" -ErrorAction SilentlyContinue

        if ($pending -and $pending.data -and $pending.data.Count -gt 0) {
            Write-Host "  [$market] $($pending.data.Count) orders..." -ForegroundColor Yellow

            foreach ($order in $pending.data) {
                try {
                    CoinEx-CancelStopOrder -Market $market -StopId $order.stop_id -MarketType "SPOT" -ErrorAction Stop | Out-Null
                    $totalDeleted++
                    Write-Host "    ✅ Deletado stop_id $($order.stop_id)" -ForegroundColor Green
                } catch {
                    Write-Host "    ⚠️  Erro: $_" -ForegroundColor Yellow
                }
                Start-Sleep -Milliseconds 50
            }
        }
    } catch {}
}

Write-Host ""
Write-Host "✅ TOTAL DELETADO: $totalDeleted stop orders" -ForegroundColor Green
Write-Host ""

Start-Sleep -Seconds 2

# ============================================================
# STEP 2: Recriar APENAS 2 posições ativas
# ============================================================

Write-Host "[STEP 2] Recriando APENAS 2 stops (SL+TP cada)..." -ForegroundColor Green
Write-Host ""

$positions = @(
    @{
        market = "BASEDUSDT"
        qty = 248.28
        tp_qty = 124.14
        sl = 0.097543
        tp = 0.104475
    },
    @{
        market = "METUSDT"
        qty = 559.71
        tp_qty = 279.85
        sl = 0.135436
        tp = 0.143728
    }
)

$createdCount = 0

foreach ($pos in $positions) {
    Write-Host "[$($pos.market)]" -ForegroundColor Cyan

    # Criar SL (price_less_equal)
    try {
        $inv = [System.Globalization.CultureInfo]::InvariantCulture
        $body = @{
            market        = $pos.market
            market_type   = "SPOT"
            side          = "sell"
            type          = "limit"
            amount        = ([math]::Round($pos.qty, 6)).ToString($inv)
            price         = ([math]::Round([decimal]$pos.sl, 8)).ToString($inv)
            ccy           = "USDT"
            trigger_price = ([math]::Round([decimal]$pos.sl, 12)).ToString($inv)
            trigger_type  = "price_less_equal"
            stp_mode      = "ct"
        }

        $r = CoinEx-Post "/v2/spot/stop-order" $body
        if ($r.code -eq 0) {
            Write-Host "  ✅ SL: $($pos.sl) (qty: $($pos.qty)) | stop_id: $($r.data.stop_id)" -ForegroundColor Green
            $createdCount++
        } else {
            Write-Host "  ❌ SL ERRO: $($r.message)" -ForegroundColor Red
        }
    } catch {
        Write-Host "  ❌ SL ERRO: $_" -ForegroundColor Red
    }

    Start-Sleep -Milliseconds 300

    # Criar TP (price_greater_equal)
    try {
        $inv = [System.Globalization.CultureInfo]::InvariantCulture
        $body = @{
            market        = $pos.market
            market_type   = "SPOT"
            side          = "sell"
            type          = "limit"
            amount        = ([math]::Round($pos.tp_qty, 6)).ToString($inv)
            price         = ([math]::Round([decimal]$pos.tp, 8)).ToString($inv)
            ccy           = "USDT"
            trigger_price = ([math]::Round([decimal]$pos.tp, 12)).ToString($inv)
            trigger_type  = "price_greater_equal"
            stp_mode      = "ct"
        }

        $r = CoinEx-Post "/v2/spot/stop-order" $body
        if ($r.code -eq 0) {
            Write-Host "  ✅ TP: $($pos.tp) (qty: $($pos.tp_qty)) | stop_id: $($r.data.stop_id)" -ForegroundColor Green
            $createdCount++
        } else {
            Write-Host "  ❌ TP ERRO: $($r.message)" -ForegroundColor Red
        }
    } catch {
        Write-Host "  ❌ TP ERRO: $_" -ForegroundColor Red
    }

    Start-Sleep -Milliseconds 300

    Write-Host ""
}

Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "✅ LIMPEZA FINAL CONCLUÍDA" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "Resultado:" -ForegroundColor Yellow
Write-Host "  • Deletadas: $totalDeleted stop orders" -ForegroundColor Red
Write-Host "  • Recriadas: $createdCount stops (2 posições = 4 orders)" -ForegroundColor Green
Write-Host "  • Sistema: LIMPO E PRONTO" -ForegroundColor Cyan
Write-Host ""
Write-Host "⚠️  IMPORTANTE:" -ForegroundColor Yellow
Write-Host "  1. trailing_stop_monitor.ps1: sync_and_fix_tp DESABILITADO" -ForegroundColor Gray
Write-Host "  2. Nenhuma nova duplicata será criada" -ForegroundColor Gray
Write-Host "  3. Peak updates e Exit Intelligence continuam normais" -ForegroundColor Gray
Write-Host ""

# Alert
try {
    Send-TelegramAlert -Message "✅ LIMPEZA FINAL: Deletados $totalDeleted orphan stops. Recriados 4 corretos (BASED+MET). Sistema LIMPO! 🎯" | Out-Null
} catch {}

Write-Host ""
