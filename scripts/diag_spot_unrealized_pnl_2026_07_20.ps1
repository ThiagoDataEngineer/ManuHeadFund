# diag_spot_unrealized_pnl_2026_07_20.ps1 -- diagnostico ONE-SHOT, so leitura
#
# CoinEx /v2/assets/spot/balance NAO retorna preco medio de custo (so
# available/frozen -- confirmado hoje). Estimativa: reconstroi o preco medio
# de COMPRA de cada holding SPOT atual a partir do historico real de ordens
# (/v2/spot/finished-order, ja confirmado ter side/price/filled_amount/
# filled_value -- mesmo endpoint usado em audit_coinex_state.ps1), compara
# com o preco atual via ticker. NAO e' PnL realizado exato (FIFO/LIFO real
# pode diferir, e taxas nao entram no calculo) -- e' estimativa de PnL NAO
# REALIZADO das posicoes SPOT que a conta tem HOJE.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")

Write-Host "=== DIAG SPOT UNREALIZED PNL (ESTIMATIVA, READ-ONLY) ===" -ForegroundColor Cyan
Write-Host ""

try {
    $bal = CoinEx-Get "/v2/assets/spot/balance" -EA Stop
    if ($bal.code -ne 0) { throw "balance code=$($bal.code) msg=$($bal.message)" }
    $holdings = @($bal.data | Where-Object { $_.ccy -ne "USDT" -and ([double]$_.available -gt 0 -or [double]$_.frozen -gt 0) })
} catch {
    Write-Host "ERRO ao puxar balance: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "Holdings SPOT nao-USDT: $($holdings.Count)" -ForegroundColor White
Write-Host ""

$totalCostBasis = 0.0
$totalCurrentValue = 0.0

foreach ($h in $holdings) {
    $mkt = "$($h.ccy)USDT"
    $qtyHeld = [double]$h.available + [double]$h.frozen

    try {
        # Historico de compras (side=buy) desse mercado -- ate 50 ordens mais recentes.
        $r = CoinEx-Get "/v2/spot/finished-order?market=$mkt&market_type=SPOT&page=1&limit=50" -EA SilentlyContinue
        if (-not $r -or $r.code -ne 0 -or $r.data.Count -eq 0) {
            Write-Host "  [$mkt] sem historico de ordens (par pode nao ser XXXUSDT, ou sem ordens recentes)" -ForegroundColor DarkYellow
            continue
        }

        $buys = @($r.data | Where-Object { $_.side -eq "buy" -and [double]$_.filled_amount -gt 0 })
        if ($buys.Count -eq 0) {
            Write-Host "  [$mkt] holding=$qtyHeld mas sem ordens de compra no historico consultado (pode ter sido comprado ha mais tempo que o limit=50 cobre)" -ForegroundColor DarkYellow
            continue
        }

        $totalBoughtQty = ($buys | ForEach-Object { [double]$_.filled_amount } | Measure-Object -Sum).Sum
        $totalBoughtValue = ($buys | ForEach-Object { [double]$_.filled_value } | Measure-Object -Sum).Sum
        $avgBuyPrice = if ($totalBoughtQty -gt 0) { $totalBoughtValue / $totalBoughtQty } else { 0 }

        $currentPrice = 0
        try {
            $ticker = CoinEx-GetTicker $mkt
            if ($ticker -and $ticker.last) { $currentPrice = [double]$ticker.last }
        } catch {}

        if ($avgBuyPrice -gt 0 -and $currentPrice -gt 0) {
            $costBasis = $qtyHeld * $avgBuyPrice
            $currentValue = $qtyHeld * $currentPrice
            $unrealizedPnl = $currentValue - $costBasis
            $unrealizedPct = if ($costBasis -gt 0) { ($unrealizedPnl / $costBasis) * 100 } else { 0 }

            $totalCostBasis += $costBasis
            $totalCurrentValue += $currentValue

            $color = if ($unrealizedPnl -ge 0) { "Green" } else { "Red" }
            Write-Host "  [$mkt] qty=$qtyHeld avg_buy=`$$([Math]::Round($avgBuyPrice,6)) atual=`$$([Math]::Round($currentPrice,6)) | custo=`$$([Math]::Round($costBasis,2)) valor_atual=`$$([Math]::Round($currentValue,2)) | PnL_nao_realizado=`$$([Math]::Round($unrealizedPnl,2)) ($([Math]::Round($unrealizedPct,1))%)" -ForegroundColor $color
        } else {
            Write-Host "  [$mkt] nao foi possivel calcular (avg_buy=$avgBuyPrice atual=$currentPrice)" -ForegroundColor DarkYellow
        }
    } catch {
        Write-Host "  [$mkt] erro: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== TOTAL (holdings com calculo possivel) ===" -ForegroundColor Cyan
$totalUnrealized = $totalCurrentValue - $totalCostBasis
$totalColor = if ($totalUnrealized -ge 0) { "Green" } else { "Red" }
Write-Host "Custo total estimado: `$$([Math]::Round($totalCostBasis,2))" -ForegroundColor White
Write-Host "Valor atual estimado: `$$([Math]::Round($totalCurrentValue,2))" -ForegroundColor White
Write-Host "PnL nao-realizado estimado: `$$([Math]::Round($totalUnrealized,2))" -ForegroundColor $totalColor
Write-Host ""
Write-Host "AVISO: estimativa (media simples de compras no historico consultado, sem" -ForegroundColor DarkYellow
Write-Host "descontar taxas, sem considerar vendas parciais anteriores via FIFO/LIFO" -ForegroundColor DarkYellow
Write-Host "real). Nao substitui PnL realizado real -- e' so um proxy do que a conta" -ForegroundColor DarkYellow
Write-Host "teria hoje se liquidasse os holdings atuais ao preco de mercado." -ForegroundColor DarkYellow
Write-Host ""
Write-Host "=== FIM DIAG ===" -ForegroundColor Cyan
