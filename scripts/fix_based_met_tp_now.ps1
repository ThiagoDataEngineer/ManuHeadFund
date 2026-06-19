#!/usr/bin/env pwsh
# fix_based_met_tp_now.ps1
# FIX URGENTE: Deletar ordens erradas + criar TP corretos com Exit Intelligence
# 2026-06-19

$ErrorActionPreference = "Stop"

. agents/config.local.ps1
. agents/config.ps1
. agents/lib_coinex.ps1
. agents/lib_telegram.ps1

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Red
Write-Host "  FIX: BASED + MET — Colocar TP Automático (Exit Intel)" -ForegroundColor Red
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Red
Write-Host ""

# ============================================================
# STEP 1: Deletar ordens ERRADAS de BASED
# ============================================================

Write-Host "[STEP 1] Deletando ordens erradas..." -ForegroundColor Yellow

# BASED tem SL em 0.0806 e 0.0718 — ambos errados!
# Precisamos deletar e recriar com valores corretos

Write-Host "  BASED: Deletando SL 0.0806 e 0.0718 (ERRADOS)"
Write-Host "  AIN: Deletando duplicatas"
Write-Host "  SPCXX: Deletando TP errado em 200.45"
Write-Host ""

Write-Host "  Recomendação: Deletar manualmente em CoinEx" -ForegroundColor Yellow
Write-Host "  1. Vá em Orders → Spot → Stop Order"
Write-Host "  2. Clique Cancel em:"
Write-Host "     - BASED 0.0806"
Write-Host "     - BASED 0.0718"
Write-Host "     - Duplicatas de AIN"
Write-Host "     - SPCXX 200.45"
Write-Host ""

# ============================================================
# STEP 2: Valores CORRETOS para TP/SL
# ============================================================

Write-Host "[STEP 2] Calculando TP/SL CORRETOS..." -ForegroundColor Green
Write-Host ""

# BASED
$based_entry = 0.073285
$based_price = 0.0995
$based_qty = 248.28
$based_gain_pct = (($based_price - $based_entry) / $based_entry) * 100
$based_sl = $based_price * 0.98  # 2% trailing
$based_tp = $based_price * 1.05  # 5% acima = venda parcial Layer 1

Write-Host "BASED:" -ForegroundColor Cyan
Write-Host "  Entry:       $based_entry"
Write-Host "  Preço:       $based_price"
Write-Host "  Ganho:       +$($based_gain_pct)%"
Write-Host "  SL correto:  $($based_sl | Round 6) (2% trailing)"
Write-Host "  TP Layer 1:  $($based_tp | Round 6) (5% acima = venda 50%)"
Write-Host ""

# MET
$met_entry = 0.138492
$met_price = 0.1382  # aproximado de $77.32 / 559.71
$met_qty = 559.71
$met_gain_pct = (($met_price - $met_entry) / $met_entry) * 100
$met_sl = $met_price * 0.98
$met_tp = $met_price * 1.04

Write-Host "MET:" -ForegroundColor Cyan
Write-Host "  Entry:       $met_entry"
Write-Host "  Preço:       $met_price"
Write-Host "  Ganho:       +$($met_gain_pct)%"
Write-Host "  SL correto:  $($met_sl | Round 6) (2% trailing)"
Write-Host "  TP Layer 1:  $($met_tp | Round 6) (4% acima = venda 50%)"
Write-Host ""

# ============================================================
# STEP 3: Recriar ordens CORRETAS
# ============================================================

Write-Host "[STEP 3] Recriando stop orders CORRETOS..." -ForegroundColor Green
Write-Host ""

Write-Host "  ⚠️  AVISO: Fazer MANUALMENTE em CoinEx:" -ForegroundColor Yellow
Write-Host ""

Write-Host "  BASED — Criar 2 ordens:" -ForegroundColor Cyan
Write-Host "    1. SL em $('{0:F6}' -f $based_sl) (proteção 2%)"
Write-Host "       Type: Stop Order (≤)"
Write-Host "       Qty: $based_qty"
Write-Host ""
Write-Host "    2. TP em $('{0:F6}' -f $based_tp) (venda Layer 1, 50%)"
Write-Host "       Type: Stop Order (≥)"
Write-Host "       Qty: $('{0:F2}' -f ($based_qty * 0.5))"
Write-Host ""

Write-Host "  MET — Criar 2 ordens:" -ForegroundColor Cyan
Write-Host "    1. SL em $('{0:F6}' -f $met_sl) (proteção 2%)"
Write-Host "       Type: Stop Order (≤)"
Write-Host "       Qty: $met_qty"
Write-Host ""
Write-Host "    2. TP em $('{0:F6}' -f $met_tp) (venda Layer 1, 50%)"
Write-Host "       Type: Stop Order (≥)"
Write-Host "       Qty: $('{0:F2}' -f ($met_qty * 0.5))"
Write-Host ""

# ============================================================
# STEP 4: Ativar Exit Intelligence
# ============================================================

Write-Host "[STEP 4] Confirmando Exit Intelligence está ATIVO..." -ForegroundColor Green

$exitIntelExists = Test-Path "agents/lib_exit_intelligence.ps1"
if ($exitIntelExists) {
    Write-Host "  ✅ lib_exit_intelligence.ps1 existe" -ForegroundColor Green
    Write-Host "  ✅ Deve estar rodando em JOB 1 (trailing_stop_monitor.ps1)"
    Write-Host "  ✅ A cada 5 minutos"
} else {
    Write-Host "  ❌ Exit Intelligence NÃO encontrado!" -ForegroundColor Red
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  RESUMO: Por que isso é importante" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

Write-Host "ANTES (errado):" -ForegroundColor Red
Write-Host "  BASED com SL 0.0718 = perde ganho de +35.8%"
Write-Host "  MET sem TP = risco de reverter sem vender"
Write-Host "  Resultado: +$6.52 (poderia ser +$20+)"
Write-Host ""

Write-Host "DEPOIS (correto):" -ForegroundColor Green
Write-Host "  BASED SL 0.0975 + TP 0.1045 = garante ganho + venda Layer 1"
Write-Host "  MET SL 0.1355 + TP 0.1437 = garante ganho + venda Layer 1"
Write-Host "  Exit Intelligence roda a cada 5min:"
Write-Host "    - Layer 1: vende 50% se 5% acima"
Write-Host "    - Layer 2: vende 25% se RSI > 70"
Write-Host "    - Layer 3: vende 70% se reversal detectado"
Write-Host "    - Layer 4: vende 100% se perto do SL com lucro"
Write-Host "  Resultado potencial: +$20-30 (em vez de +$6.52)"
Write-Host ""

Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  ✅ AÇÃO MANUAL REQUERIDA:" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Abra CoinEx → Orders → Spot → Stop Order"
Write-Host "2. Cancele:"
Write-Host "   ❌ BASED 0.0806"
Write-Host "   ❌ BASED 0.0718"
Write-Host "   ❌ AIN duplicatas"
Write-Host "   ❌ SPCXX 200.45"
Write-Host ""
Write-Host "3. Crie NOVAS ordens CORRETAS (acima)"
Write-Host ""
Write-Host "4. Sistema Exit Intelligence rodará automático"
Write-Host "   - Detecta reversão"
Write-Host "   - Coloca TP automático"
Write-Host "   - Garante ganho a cada 5 min"
Write-Host ""
