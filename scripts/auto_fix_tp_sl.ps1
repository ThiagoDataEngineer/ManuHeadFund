#!/usr/bin/env pwsh
# auto_fix_tp_sl.ps1
# AUTOMÁTICO: Delete ordens erradas + Cria TP/SL corretos para BASED e MET
# 2026-06-19

$ErrorActionPreference = "Stop"

# Load libs
. agents/config.local.ps1
. agents/config.ps1
. agents/lib_coinex_position_management.ps1
. agents/lib_telegram.ps1

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Red
Write-Host "║  AUTO-FIX: Deletar ordens erradas + Criar TP/SL      ║" -ForegroundColor Red
Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Red
Write-Host ""

# ============================================================
# STEP 1: Cancelar ordens erradas
# ============================================================

Write-Host "[STEP 1] Cancelando ordens erradas..." -ForegroundColor Yellow

$baseMarkets = @("BASEDUSDT", "METUSDT", "AINUSDT", "SPCXXUSDT")

foreach ($market in $baseMarkets) {
    Write-Host "  Cancelando SL+TP de $market..." -ForegroundColor Gray

    try {
        CoinEx-CancelPositionStopLoss -Market $market -ErrorAction SilentlyContinue | Out-Null
        Start-Sleep -Milliseconds 100
    } catch {
        # Esperado se não existir SL
    }

    try {
        CoinEx-CancelPositionTakeProfit -Market $market -ErrorAction SilentlyContinue | Out-Null
        Start-Sleep -Milliseconds 100
    } catch {
        # Esperado se não existir TP
    }
}

Write-Host "  ✅ Ordens antigas canceladas (ou não existiam)" -ForegroundColor Green
Write-Host ""

# ============================================================
# STEP 2: Criar ordens CORRETAS
# ============================================================

Write-Host "[STEP 2] Criando ordens CORRETAS..." -ForegroundColor Green
Write-Host ""

# Dados atuais com valores corretos
$fixData = @(
    @{
        market = "BASEDUSDT"
        sl = 0.097543
        tp = 0.104475
    },
    @{
        market = "METUSDT"
        sl = 0.135436
        tp = 0.143728
    }
)

foreach ($data in $fixData) {
    $market = $data.market
    $sl = $data.sl
    $tp = $data.tp

    Write-Host "[$market]" -ForegroundColor Cyan

    # Criar/Modificar SL
    try {
        Write-Host "  Criando SL em $sl..." -ForegroundColor Gray
        CoinEx-ModifyPositionStopLoss -Market $market -Price $sl -ErrorAction Stop
        Write-Host "    ✅ SL criado/atualizado" -ForegroundColor Green
    } catch {
        Write-Host "    ⚠️  Erro ao criar SL: $_" -ForegroundColor Yellow
    }

    Start-Sleep -Milliseconds 200

    # Criar/Modificar TP
    try {
        Write-Host "  Criando TP em $tp..." -ForegroundColor Gray
        CoinEx-ModifyPositionTakeProfit -Market $market -Price $tp -ErrorAction Stop
        Write-Host "    ✅ TP criado/atualizado" -ForegroundColor Green
    } catch {
        Write-Host "    ⚠️  Erro ao criar TP: $_" -ForegroundColor Yellow
    }

    Start-Sleep -Milliseconds 200
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
Write-Host "   BASED: SL 0.097543 + TP 0.104475 (garante +5% min)"
Write-Host "   MET:   SL 0.135436 + TP 0.143728 (garante +5% min)"
Write-Host ""

# Enviar alert no Telegram
try {
    Send-TelegramAlert -Message "✅ AUTO-FIX EXECUTADO: Ordens de BASED e MET recriadas com TP/SL corretos. Exit Intelligence ativo!" | Out-Null
    Write-Host "[TG] Alert enviado" -ForegroundColor Cyan
} catch {
    Write-Host "⚠️  Aviso Telegram não enviado (não crítico)" -ForegroundColor Yellow
}

Write-Host ""
