# fix_tp_via_cancel_place.ps1 — Cancela TP/SL antigos e cria novos via PlaceOrder
# BREVUSDT: 0.0633 → 0.092721
# RAYUSDT: 0.473 → 0.69311

param([switch]$DryRun = $false)

$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path $PSScriptRoot -Parent) "agents\config.ps1")
. (Join-Path (Split-Path $PSScriptRoot -Parent) "agents\lib_coinex.ps1")
. (Join-Path (Split-Path $PSScriptRoot -Parent) "agents\lib_coinex_position_management.ps1")

$fixes = @(
    @{
        market = "BREVUSDT"
        side = "sell"  # SHORT
        oldTP = 0.0633
        oldSL = 0.100500
        newTP = 0.092721
        newSL = 0.092959  # Breakeven
        entry = 0.093052
        stop = 0.092959
        leverage = 20
        marginMode = "isolated"
    },
    @{
        market = "RAYUSDT"
        side = "sell"  # SHORT
        oldTP = 0.473
        oldSL = 0.7512
        newTP = 0.69311
        newSL = 0.6948
        entry = 0.6955
        stop = 0.6948
        leverage = 3
        marginMode = "cross"
    }
)

Write-Host "🔴 CORRIGINDO TPs ERRADOS (ESTRATÉGIA: CANCEL + PLACE)" -ForegroundColor Red
Write-Host ""

foreach ($fix in $fixes) {
    $mkt = $fix.market
    $oldTP = $fix.oldTP
    $oldSL = $fix.oldSL
    $newTP = $fix.newTP
    $newSL = $fix.newSL
    $entry = $fix.entry
    $stop = $fix.stop
    $leverage = $fix.leverage
    $marginMode = $fix.marginMode
    $risk = $entry - $stop

    Write-Host "📊 $mkt (leverage: ${leverage}x, mode: $marginMode)" -ForegroundColor Yellow
    Write-Host "   Entry:     $entry" -ForegroundColor Gray
    Write-Host "   Stop:      $stop (risk: $('{0:N6}' -f $risk))" -ForegroundColor Yellow
    Write-Host "   TP Atual:  $oldTP ❌ (ERRADO)" -ForegroundColor Red
    Write-Host "   TP Novo:   $newTP ✅ (R:R 1:3)" -ForegroundColor Green
    Write-Host "   SL Atual:  $oldSL" -ForegroundColor Gray
    Write-Host "   SL Novo:   $newSL (breakeven)" -ForegroundColor Gray
    Write-Host ""

    if (-not $DryRun) {
        try {
            # Step 1: Cancelar TP existente
            Write-Host "   → Step 1: Cancelando TP antigo..." -ForegroundColor Cyan
            $cancelTP = CoinEx-CancelPositionTakeProfit -Market $mkt -ErrorAction SilentlyContinue
            if ($?) {
                Write-Host "     ✅ TP antigo cancelado" -ForegroundColor Green
            } else {
                Write-Host "     ⚠️  Falha ao cancelar TP (pode estar já cancelado)" -ForegroundColor Yellow
            }

            # Step 2: Cancelar SL existente (para refazer)
            Write-Host "   → Step 2: Cancelando SL antigo..." -ForegroundColor Cyan
            $cancelSL = CoinEx-CancelPositionStopLoss -Market $mkt -ErrorAction SilentlyContinue
            if ($?) {
                Write-Host "     ✅ SL antigo cancelado" -ForegroundColor Green
            } else {
                Write-Host "     ⚠️  Falha ao cancelar SL (pode estar já cancelado)" -ForegroundColor Yellow
            }

            # Step 3: Recriar AMBOS TP + SL com valores corretos
            # CoinEx-ModifyPositionTakeProfit requer: market, price, triggerType
            # CoinEx-ModifyPositionStopLoss requer: market, price, triggerType
            Write-Host "   → Step 3: Criando novo TP + SL..." -ForegroundColor Cyan

            # Tentar modificar TP primeiro
            $newTPResult = CoinEx-ModifyPositionTakeProfit -Market $mkt -Price ([decimal]$newTP) -TriggerType "mark_price"
            if ($newTPResult.success) {
                Write-Host "     ✅ TP novo colocado: $newTP" -ForegroundColor Green
            } else {
                Write-Host "     ❌ FALHA TP: $($newTPResult.error_msg)" -ForegroundColor Red
            }

            # Tentar modificar SL
            $newSLResult = CoinEx-ModifyPositionStopLoss -Market $mkt -Price ([decimal]$newSL) -TriggerType "mark_price"
            if ($newSLResult.success) {
                Write-Host "     ✅ SL novo colocado: $newSL" -ForegroundColor Green
            } else {
                Write-Host "     ❌ FALHA SL: $($newSLResult.error_msg)" -ForegroundColor Red
            }

        } catch {
            Write-Host "   ❌ Erro: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "   [DRY RUN] Seria cancelado e recolocado" -ForegroundColor Gray
    }
    Write-Host ""
}

Write-Host "════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "✅ TPs corrigidos para R:R 1:3 automático" -ForegroundColor Green
