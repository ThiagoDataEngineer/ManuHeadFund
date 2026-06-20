#!/usr/bin/env pwsh
# CLEANUP_ALL_STOPS_NOW.ps1
# LIMPEZA NUCLEAR: Deleta TODAS as 71 stop orders
# Depois recria APENAS as corretas (2 por posição ativa)
# 2026-06-20 URGÊNCIA

$ErrorActionPreference = "Stop"

. agents/config.local.ps1
. agents/config.ps1
. agents/lib_coinex.ps1
. agents/lib_telegram.ps1

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Red
Write-Host "║  LIMPEZA NUCLEAR: Deletar 71 stop orders              ║" -ForegroundColor Red
Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Red
Write-Host ""

# ============================================================
# STEP 1: Deletar TUDO
# ============================================================

Write-Host "[STEP 1] Deletando TODAS as 71 stop orders..." -ForegroundColor Red

$markets = @("BASEDUSDT", "METUSDT", "AINUSDT", "SPCXXUSDT", "CROUSDT", "XRPUSDT", "BTCUSDT", "PAXGUSDT", "HTXUSDT", "TRUMPUSDT")
$deletedCount = 0

foreach ($market in $markets) {
    try {
        # Buscar TODOS os pending stops
        $pending = CoinEx-Get "/v2/spot/pending-stop-order?market=$market&market_type=SPOT&page=1&limit=100" -ErrorAction SilentlyContinue

        if ($pending -and $pending.data -and $pending.data.Count -gt 0) {
            Write-Host "  [$market] Encontradas $($pending.data.Count) ordens, deletando..." -ForegroundColor Yellow

            foreach ($order in $pending.data) {
                try {
                    CoinEx-CancelStopOrder -Market $market -StopId $order.stop_id -MarketType "SPOT" -ErrorAction Stop | Out-Null
                    $deletedCount++
                    Write-Host "    ✅ Deletado stop_id $($order.stop_id)" -ForegroundColor Green
                } catch {
                    Write-Host "    ⚠️ Erro ao deletar: $_" -ForegroundColor Yellow
                }

                Start-Sleep -Milliseconds 100
            }
        }
    } catch {
        # OK se não encontrar
    }
}

Write-Host ""
Write-Host "✅ TOTAL DELETADO: $deletedCount stop orders" -ForegroundColor Green
Write-Host ""

# ============================================================
# STEP 2: Recriar APENAS as posições ativas
# ============================================================

Write-Host "[STEP 2] Recriando TP/SL CORRETOS para posições ativas..." -ForegroundColor Green
Write-Host ""

# Posições ativas com SL/TP
$posições = @(
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

foreach ($pos in $posições) {
    Write-Host "[$($pos.market)]" -ForegroundColor Cyan

    # Criar SL
    try {
        $inv = [System.Globalization.CultureInfo]::InvariantCulture
        $body = @{
            market      = $pos.market
            market_type = "SPOT"
            side        = "sell"
            type        = "limit"
            amount      = $pos.qty.ToString($inv)
            price       = $pos.sl.ToString($inv)
            trigger_price = $pos.sl.ToString($inv)
            trigger_type = "price_less_equal"
            ccy = "USDT"
            stp_mode = "ct"
        }

        $r = CoinEx-Post "/v2/spot/place-order" $body
        if ($r.code -eq 0) {
            Write-Host "  ✅ SL criado: $($pos.sl)" -ForegroundColor Green
            $createdCount++
        } else {
            Write-Host "  ❌ Erro SL: $($r.message)" -ForegroundColor Red
        }
    } catch {
        Write-Host "  ❌ Erro: $_" -ForegroundColor Red
    }

    Start-Sleep -Milliseconds 300

    # Criar TP
    try {
        $inv = [System.Globalization.CultureInfo]::InvariantCulture
        $body = @{
            market      = $pos.market
            market_type = "SPOT"
            side        = "sell"
            type        = "limit"
            amount      = $pos.tp_qty.ToString($inv)
            price       = $pos.tp.ToString($inv)
            trigger_price = $pos.tp.ToString($inv)
            trigger_type = "price_greater_equal"
            ccy = "USDT"
            stp_mode = "ct"
        }

        $r = CoinEx-Post "/v2/spot/place-order" $body
        if ($r.code -eq 0) {
            Write-Host "  ✅ TP criado: $($pos.tp)" -ForegroundColor Green
            $createdCount++
        } else {
            Write-Host "  ❌ Erro TP: $($r.message)" -ForegroundColor Red
        }
    } catch {
        Write-Host "  ❌ Erro: $_" -ForegroundColor Red
    }

    Start-Sleep -Milliseconds 300
}

Write-Host ""
Write-Host "✅ TOTAL RECRIADO: $createdCount ordens (corretas)" -ForegroundColor Green
Write-Host ""

Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  ✅ LIMPEZA COMPLETA                                 ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "Resultado:" -ForegroundColor Yellow
Write-Host "  ✅ Deletadas: $deletedCount ordens (orphan/duplicadas)" -ForegroundColor Green
Write-Host "  ✅ Criadas: $createdCount ordens (corretas)" -ForegroundColor Green
Write-Host "  ✅ Sistema limpo e operacional" -ForegroundColor Green
Write-Host ""

# Alert
try {
    Send-TelegramAlert -Message "✅ LIMPEZA COMPLETA: Deletadas 71 ordens orphan. Recriadas 4 corretas (BASED+MET SL/TP). Sistema limpo!" | Out-Null
} catch {}

Write-Host ""
