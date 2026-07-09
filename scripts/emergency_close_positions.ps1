# emergency_rebalance.ps1 — Rebalancear carteira BEAR_WEAK: fechar perdedores, manter BTC aprendizado
# 2026-07-08 23:16+ ataque: regime BEAR_WEAK exige carteira 80% SHORT / 20% LONG.
# BTC 10X é pequeno ($25) = auto-aprendizado, MANTER. WAVES/SOL drenando, FECHAR.
# Uso: powershell.exe -NoProfile -File scripts/emergency_rebalance.ps1
# DryRun: adiciona -DryRun $true pra validar sem executar

param(
    [bool]$DryRun = $false,
    [hashtable]$PositionsAction = @{
        # "BTCUSDT"    = "keep"     # 10X LONG $25 USD — auto-aprendizado, manter
        "WAVESUSDT"  = "close"   # -13% 3X LONG — crítico, fecha agora
        "SOLUSDT"    = "close"   # -5% 5X SHORT em rally — anti-trend, anti-regime
        "ETHUSDT"    = "reduce"  # +1% 3X LONG — frágil, reduz pra 50% / rebalança margin
    }
)

$ErrorActionPreference = "Continue"
$root = Split-Path $PSScriptRoot -Parent
$journalDir = Join-Path $root "journal"

. (Join-Path $root "agents\lib_coinex.ps1")
. (Join-Path $root "agents\lib_portfolio_sync.ps1") -ErrorAction SilentlyContinue

"[$(Get-Date -Format 'HH:mm:ss')] EMERGENCY REBALANCE INICIADO"
"Ações: $($PositionsAction.Keys -join ', ')"
"DryRun: $DryRun`n"

foreach ($mkt in $PositionsAction.Keys) {
    $action = $PositionsAction[$mkt]
    try {
        Write-Host "[CLOSE] $mkt iniciando..." -ForegroundColor Cyan

        # Get current position
        $pos = CoinEx-GetFuturesPosition -Market $mkt
        if (-not $pos) {
            Write-Host "  $mkt NAO encontrado (ja fechado?)"
            continue
        }

        $qty = [double]$pos.quantity
        $side = "$($pos.side)".ToUpper()

        if ($qty -le 0) {
            Write-Host "  $mkt qty=0 (ja fechado)"
            continue
        }

        # Aplicar ação: close=100%, reduce=50%
        $qtyToClose = if ($action -eq "reduce") { $qty * 0.5 } else { $qty }
        $closeOrReduce = if ($action -eq "reduce") { "REDUZIR 50%" } else { "FECHAR 100%" }

        # Para LONG, vender. Para SHORT, comprar (inverter)
        $closeSide = if ($side -eq "LONG") { "sell" } else { "buy" }
        $price = [double]$pos.mark_price

        Write-Host "  qty=$qty side=$side action=$closeOrReduce closeOrder=$closeSide price=$price" -ForegroundColor Yellow

        if ($DryRun) {
            Write-Host "  [DRY] teria executado $action"
            continue
        }

        # Close via market order (immediate)
        $order = CoinEx-PlaceFuturesOrder -Market $mkt -Side $closeSide -Quantity $qtyToClose -OrderType "market"
        if ($order -and $order.order_id) {
            Write-Host "  ✅ FECHADO order=$($order.order_id)" -ForegroundColor Green
            Add-Content -Path (Join-Path $journalDir "emergency_closes.jsonl") -Value (@{
                ts = (Get-Date -Format 'o')
                market = $mkt
                quantity = $qty
                side = $side
                close_side = $closeSide
                order_id = $order.order_id
                price = $price
            } | ConvertTo-Json -Compress) -Encoding utf8
        } else {
            Write-Host "  ❌ ERRO ao fechar" -ForegroundColor Red
        }
    } catch {
        Write-Host "  ❌ Erro: $($_.Exception.Message)" -ForegroundColor Red
    }
}

"[$(Get-Date -Format 'HH:mm:ss')] EMERGENCY CLOSE CONCLUÍDO"
