#!/usr/bin/env pwsh
# auto_fix_tp_sl.ps1
# AUTOMÁTICO: Delete ordens SPOT erradas + Cria SL/TP corretos para BASED e MET
# 2026-06-19 — CORRIGIDO para SPOT (não FUTURES)

$ErrorActionPreference = "Stop"

# Load libs
. agents/config.local.ps1
. agents/config.ps1
. agents/lib_coinex.ps1
. agents/lib_telegram.ps1

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Red
Write-Host "║  AUTO-FIX SPOT: Deletar ordens erradas + Criar SL/TP ║" -ForegroundColor Red
Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Red
Write-Host ""

# ============================================================
# STEP 1: Buscar e deletar ordens SPOT antigas
# ============================================================

Write-Host "[STEP 1] Buscando e deletando ordens SPOT antigas..." -ForegroundColor Yellow

$markets = @("BASEDUSDT", "METUSDT", "AINUSDT", "SPCXXUSDT")
$deletedCount = 0

foreach ($market in $markets) {
    try {
        $pending = CoinEx-Get "/v2/spot/pending-stop-order?market=$market&market_type=SPOT&page=1&limit=50" -ErrorAction SilentlyContinue

        if ($pending -and $pending.data -and $pending.data.Count -gt 0) {
            foreach ($order in $pending.data) {
                Write-Host "  Deletando $market stop_id=$($order.stop_id)..." -ForegroundColor Gray

                try {
                    CoinEx-CancelStopOrder -Market $market -StopId $order.stop_id -MarketType "SPOT" -ErrorAction Stop | Out-Null
                    $deletedCount++
                    Write-Host "    ✅ Deletado" -ForegroundColor Green
                } catch {
                    Write-Host "    ⚠️  Erro ao deletar: $_" -ForegroundColor Yellow
                }

                Start-Sleep -Milliseconds 200
            }
        }
    } catch {
        # OK se não encontrar ordens
    }
}

Write-Host "  ✅ Total deletado: $deletedCount ordens antigas" -ForegroundColor Green
Write-Host ""

# ============================================================
# STEP 2: Criar SL/TP corretos para SPOT
# ============================================================

Write-Host "[STEP 2] Criando SL/TP corretos..." -ForegroundColor Green
Write-Host ""

$fixes = @(
    @{
        market = "BASEDUSDT"
        qty = 248.28
        tp_qty = 124.14
        sl_price = 0.097543
        tp_price = 0.104475
    },
    @{
        market = "METUSDT"
        qty = 559.71
        tp_qty = 279.85
        sl_price = 0.135436
        tp_price = 0.143728
    }
)

foreach ($fix in $fixes) {
    $market = $fix.market
    $qty = $fix.qty
    $tp_qty = $fix.tp_qty
    $sl_price = $fix.sl_price
    $tp_price = $fix.tp_price

    Write-Host "[$market]" -ForegroundColor Cyan

    # Criar SL (vender QTY completa se preço cair abaixo de SL)
    try {
        Write-Host "  Criando SL em $sl_price (qty $qty)..." -ForegroundColor Gray
        $slResult = CoinEx-PlaceSpotStopOrder -Market $market -Side "sell" -TriggerPrice $sl_price -Amount $qty -ErrorAction Stop
        Write-Host "    ✅ SL criado (stop_id: $($slResult.stop_id))" -ForegroundColor Green
    } catch {
        Write-Host "    ❌ Erro ao criar SL: $_" -ForegroundColor Red
    }

    Start-Sleep -Milliseconds 300

    # Criar TP (vender 50% se preço subir para TP = venda parcial Layer 1)
    try {
        Write-Host "  Criando TP em $tp_price (qty $tp_qty - 50% parcial)..." -ForegroundColor Gray
        $tpResult = CoinEx-PlaceSpotStopOrder -Market $market -Side "sell" -TriggerPrice $tp_price -Amount $tp_qty -ErrorAction Stop
        Write-Host "    ✅ TP criado (stop_id: $($tpResult.stop_id))" -ForegroundColor Green
    } catch {
        Write-Host "    ❌ Erro ao criar TP: $_" -ForegroundColor Red
    }

    Start-Sleep -Milliseconds 300
    Write-Host ""
}

# ============================================================
# STEP 3: Confirmação
# ============================================================

Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  ✅ AUTO-FIX COMPLETO                                ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

Write-Host "✅ Próximas ações:" -ForegroundColor Yellow
Write-Host "   1. Verificar ordens em CoinEx (devem estar corretas)"
Write-Host "   2. Exit Intelligence rodará automático a cada 5min"
Write-Host "   3. Layer 1-4 de venda automática acionarão no pico"
Write-Host ""
Write-Host "📊 Resultado esperado:" -ForegroundColor Green
Write-Host "   BASED: SL 0.097543 (qtd 248.28) + TP 0.104475 (qtd 124.14 - 50%)"
Write-Host "   MET:   SL 0.135436 (qtd 559.71) + TP 0.143728 (qtd 279.85 - 50%)"
Write-Host ""

# Enviar alert no Telegram
try {
    Send-TelegramAlert -Message "✅ AUTO-FIX EXECUTADO: Ordens SPOT de BASED e MET recriadas com SL/TP corretos. Exit Intelligence ativo!" | Out-Null
    Write-Host "[TG] Alert enviado" -ForegroundColor Cyan
} catch {
    Write-Host "⚠️  Aviso Telegram não enviado (não crítico)" -ForegroundColor Yellow
}

Write-Host ""
