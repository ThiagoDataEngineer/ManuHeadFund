#!/usr/bin/env pwsh
# sync_and_fix_tp.ps1
# Sincroniza posições da CoinEx e adiciona TP onde falta

param(
    [string[]]$Markets = @('BASEDUSDT', 'SPCXXUSDT', 'AINUSDT')
)

. agents/config.local.ps1
. agents/lib_coinex.ps1

Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  SINCRONIZAR E FIXAR TP — POSIÇÕES ABERTAS              ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

Write-Host "[STEP 1] Buscando posições abertas na CoinEx..." -ForegroundColor Yellow

try {
    $openOrders = CoinEx-GetOpenOrders -ErrorAction Stop

    if ($openOrders) {
        Write-Host "  ✓ Encontradas $($openOrders.Count) posições abertas" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Nenhuma posição aberta" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "  ✗ Erro ao buscar: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Filter for markets of interest
Write-Host "[STEP 2] Verificando BASED, SPCXX, AIN..." -ForegroundColor Yellow
Write-Host ""

foreach ($market in $Markets) {
    $pos = $openOrders | Where-Object { $_.market -eq $market }

    if ($pos) {
        $size = $pos.amount ?? $pos.quantity ?? $pos.size  # CoinEx returns 'amount' field
        $entry = $pos.price ?? $pos.entry_price  # CoinEx returns 'price' field for SPOT
        $hasSL = $pos.stop_loss_price -or $pos.sl_order_id
        $hasTP = $pos.take_profit_price -or $pos.tp_order_id

        # Check and create SL (Stop Loss)
        if ($hasSL) {
            Write-Host "✓ ${market}: SL ja configurada" -ForegroundColor Green
        } else {
            Write-Host "✗ ${market}: SEM SL — será adicionada" -ForegroundColor Red

            # Calculate SL (2% loss)
            $sl = [math]::Round($entry * 0.98, 4)

            # Place SL order
            Write-Host "  Adicionando SL: $sl..." -ForegroundColor Yellow

            try {
                # Create STOP ORDER (sell at SL price when triggered)
                $slOrder = CoinEx-PlaceSpotStopOrder `
                    -Market $market `
                    -Side "sell" `
                    -TriggerPrice $sl `
                    -Amount $size `
                    -ErrorAction Stop

                Write-Host "    ✓ SL STOP ORDER CREATED" -ForegroundColor Green
            } catch {
                Write-Host "    ✗ Erro ao criar SL stop order: $_" -ForegroundColor Red
            }
        }

        # Check and create TP (Take Profit)
        if ($hasTP) {
            Write-Host "✓ ${market}: TP ja configurada" -ForegroundColor Green
        } else {
            Write-Host "✗ ${market}: SEM TP — será adicionada" -ForegroundColor Red

            # Calculate TP (10% gain)
            $tp = [math]::Round($entry * 1.10, 4)

            # Place TP order
            Write-Host "  Adicionando TP: $tp..." -ForegroundColor Yellow

            try {
                # Create STOP ORDER (sell at TP price when triggered)
                $tpOrder = CoinEx-PlaceSpotStopOrder `
                    -Market $market `
                    -Side "sell" `
                    -TriggerPrice $tp `
                    -Amount $size `
                    -ErrorAction Stop

                Write-Host "    ✓ TP STOP ORDER CREATED" -ForegroundColor Green
            } catch {
                Write-Host "    ✗ Erro ao criar TP stop order: $_" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "⚠ ${market}: Não encontrado em posições abertas" -ForegroundColor Yellow
    }

    Write-Host ""
}

Write-Host "✓ Sincronização concluída" -ForegroundColor Green
