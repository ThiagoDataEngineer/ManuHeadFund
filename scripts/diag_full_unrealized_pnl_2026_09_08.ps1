# diag_full_unrealized_pnl_2026_09_08.ps1 -- diagnostico ONE-SHOT, so leitura
#
# Owner sente perda de $200+ nas ultimas 2 semanas. Ja confirmado via extrato
# real CoinEx que FUTURES realizado (finished-position, 10-14 dias) e so -$6.08,
# praticamente neutro. Este script cobre os 2 lugares que faltam:
#   1) FUTURES abertas AGORA com unrealized PnL (pending-position)
#   2) SPOT: reconstrucao aproximada de realizado via finished-order + holdings
#      atuais com prejuizo latente (preco medio de compra vs preco atual)
#
# NAO usa journal/trade_outcomes.jsonl nem Supabase trade_outcomes (contaminados,
# ja confirmado nesta sessao). So dado direto da API CoinEx.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")

Write-Host "=== DIAG FULL UNREALIZED PNL (READ-ONLY) ===" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# [1] FUTURES: posicoes abertas agora, PnL nao realizado
# ============================================================
Write-Host "[1] FUTURES pending-position -- PnL nao realizado" -ForegroundColor Yellow
$totalUnrealizedFutures = 0.0
$futCount = 0
try {
    $futPos = CoinEx-Get "/v2/futures/pending-position?market_type=FUTURES" -EA SilentlyContinue
    if ($futPos.code -eq 0) {
        Write-Host "  RAW SHAPE (1o registro, se houver):" -ForegroundColor DarkGray
        if ($futPos.data.Count -gt 0) {
            Write-Host "    $($futPos.data[0] | ConvertTo-Json -Compress -Depth 5)"
        }
        Write-Host ""
        foreach ($p in $futPos.data) {
            $futCount++
            # campos candidatos pro PnL nao realizado -- CoinEx v2 costuma usar 'unrealized_pnl'
            $upnl = $null
            foreach ($field in @('unrealized_pnl','profit_unreal','unrealized_profit','pnl_unrealized')) {
                if ($p.PSObject.Properties.Name -contains $field) {
                    $upnl = [double]$p.$field
                    break
                }
            }
            $market = $p.market
            $side = $p.side
            $margin = $p.margin
            $openTime = $p.open_time
            if ($null -ne $upnl) {
                $totalUnrealizedFutures += $upnl
            }
            $openTimeStr = "?"
            if ($openTime) {
                try {
                    $openTimeStr = ([DateTimeOffset]::FromUnixTimeSeconds([long]$openTime)).ToString("yyyy-MM-dd HH:mm")
                } catch {
                    try { $openTimeStr = ([DateTimeOffset]::FromUnixTimeMilliseconds([long]$openTime)).ToString("yyyy-MM-dd HH:mm") } catch {}
                }
            }
            Write-Host ("  [{0}] side={1} margin={2} unrealized_pnl={3} aberta_desde={4}" -f $market, $side, $margin, $upnl, $openTimeStr) -ForegroundColor White
        }
        Write-Host ""
        Write-Host ("  TOTAL FUTURES unrealized_pnl ({0} posicoes): {1}" -f $futCount, $totalUnrealizedFutures) -ForegroundColor Cyan
    } else {
        Write-Host "  ERRO API: code=$($futPos.code) message=$($futPos.message)" -ForegroundColor Red
    }
} catch {
    Write-Host "  EXCECAO: $_" -ForegroundColor Red
}

Write-Host ""

# ============================================================
# [2] SPOT: holdings atuais
# ============================================================
Write-Host "[2] SPOT balance -- holdings atuais nao-USDT" -ForegroundColor Yellow
$spotHoldings = @()
try {
    $bal = CoinEx-Get "/v2/assets/spot/balance" -EA SilentlyContinue
    if ($bal.code -eq 0) {
        $spotHoldings = @($bal.data | Where-Object { $_.ccy -ne "USDT" -and ([double]$_.available + [double]$_.frozen) -gt 0 })
        foreach ($h in $spotHoldings) {
            $qty = [double]$h.available + [double]$h.frozen
            Write-Host ("  {0}: qty={1}" -f $h.ccy, $qty) -ForegroundColor White
        }
    } else {
        Write-Host "  ERRO API: code=$($bal.code) message=$($bal.message)" -ForegroundColor Red
    }
} catch {
    Write-Host "  EXCECAO: $_" -ForegroundColor Red
}

Write-Host ""

# ============================================================
# [3] SPOT: finished-order ultimos 14 dias por mercado com holding
#     + reconstrucao de custo medio e comparacao com preco atual
# ============================================================
Write-Host "[3] SPOT finished-order (14 dias) -- custo medio vs preco atual" -ForegroundColor Yellow
$cutoffMs = [DateTimeOffset]::UtcNow.AddDays(-14).ToUnixTimeMilliseconds()
$totalRealizedSpotApprox = 0.0
$totalUnrealizedSpotLatent = 0.0
$spotSummary = @()
$shapePrinted = $false

foreach ($h in $spotHoldings) {
    $ccy = $h.ccy
    $mkt = "${ccy}USDT"
    $qtyNow = [double]$h.available + [double]$h.frozen

    $buyQty = 0.0; $buyCost = 0.0
    $sellQty = 0.0; $sellRevenue = 0.0
    $feeTotal = 0.0
    $orderCount = 0

    try {
        $page = 1
        $keepGoing = $true
        while ($keepGoing) {
            $r = CoinEx-Get "/v2/spot/finished-order?market=$mkt&market_type=SPOT&page=$page&limit=100" -EA SilentlyContinue
            if ($r.code -ne 0 -or $r.data.Count -eq 0) { break }
            if (-not $shapePrinted) {
                Write-Host "  RAW SHAPE spot finished-order (1o registro real encontrado):" -ForegroundColor DarkGray
                Write-Host "    $($r.data[0] | ConvertTo-Json -Compress -Depth 5)"
                $shapePrinted = $true
            }
            foreach ($o in $r.data) {
                $ts = $null
                foreach ($tf in @('created_at','create_time','ctime')) {
                    if ($o.PSObject.Properties.Name -contains $tf) { $ts = [long]$o.$tf; break }
                }
                if ($ts) {
                    $tsMs = if ($ts -gt 999999999999) { $ts } else { $ts * 1000 }
                    if ($tsMs -lt $cutoffMs) { continue }
                }
                $orderCount++
                $side = $o.side
                $dealAmount = 0.0; $dealValue = 0.0; $fee = 0.0
                foreach ($f in @('deal_amount','filled_amount','base_amount','amount')) {
                    if ($o.PSObject.Properties.Name -contains $f) { $dealAmount = [double]$o.$f; break }
                }
                foreach ($f in @('deal_money','filled_value','quote_amount','deal_value')) {
                    if ($o.PSObject.Properties.Name -contains $f) { $dealValue = [double]$o.$f; break }
                }
                if ($o.PSObject.Properties.Name -contains 'quote_fee') { $fee += [double]$o.quote_fee }
                if ($o.PSObject.Properties.Name -contains 'base_fee') { $fee += [double]$o.base_fee }

                if ($side -eq 'buy') {
                    $buyQty += $dealAmount
                    $buyCost += $dealValue
                } elseif ($side -eq 'sell') {
                    $sellQty += $dealAmount
                    $sellRevenue += $dealValue
                }
                $feeTotal += $fee
            }
            if ($r.data.Count -lt 100) { $keepGoing = $false }
            $page++
            if ($page -gt 10) { $keepGoing = $false }
        }
    } catch {
        Write-Host "  [$mkt] EXCECAO finished-order: $_" -ForegroundColor Red
        continue
    }

    if ($orderCount -eq 0) {
        Write-Host "  [$mkt] sem ordens preenchidas nos ultimos 14 dias" -ForegroundColor DarkYellow
        continue
    }

    # Preco atual
    $curPrice = $null
    try {
        $tk = CoinEx-Get "/v2/spot/ticker?market=$mkt" -EA SilentlyContinue
        if ($tk.code -eq 0 -and $tk.data.Count -gt 0) {
            $curPrice = [double]$tk.data[0].last
        }
    } catch {}

    $avgBuyPrice = if ($buyQty -gt 0) { $buyCost / $buyQty } else { $null }
    $avgSellPrice = if ($sellQty -gt 0) { $sellRevenue / $sellQty } else { $null }

    $netQtyChange = $buyQty - $sellQty
    $realizedApprox = $null
    if ($sellQty -gt 0 -and $avgBuyPrice) {
        # realizado aproximado = qty vendida * (preco medio venda - preco medio compra), fees ja deduzidas no deal_money reportado se vier liquido
        $realizedApprox = $sellRevenue - ($sellQty * $avgBuyPrice)
        $totalRealizedSpotApprox += $realizedApprox
    }

    $unrealizedLatent = $null
    if ($qtyNow -gt 0 -and $avgBuyPrice -and $curPrice) {
        $unrealizedLatent = $qtyNow * ($curPrice - $avgBuyPrice)
        $totalUnrealizedSpotLatent += $unrealizedLatent
    }

    Write-Host ("  [{0}] orders={1} buyQty={2:N4} buyCost={3:N2} sellQty={4:N4} sellRev={5:N2} feeTotal={6:N4} avgBuy={7} curPrice={8} qtyNow={9:N4} realizadoApprox={10} unrealizedLatente={11}" -f `
        $mkt, $orderCount, $buyQty, $buyCost, $sellQty, $sellRevenue, $feeTotal, $avgBuyPrice, $curPrice, $qtyNow, $realizedApprox, $unrealizedLatent) -ForegroundColor White

    $spotSummary += [PSCustomObject]@{
        market = $mkt
        realizedApprox = $realizedApprox
        unrealizedLatent = $unrealizedLatent
    }
}

Write-Host ""
Write-Host ("  TOTAL SPOT realizado aproximado (14d, so mercados com venda): {0:N2}" -f $totalRealizedSpotApprox) -ForegroundColor Cyan
Write-Host ("  TOTAL SPOT unrealized latente (holdings atuais vs custo medio): {0:N2}" -f $totalUnrealizedSpotLatent) -ForegroundColor Cyan

Write-Host ""
Write-Host "=== RESUMO FINAL ===" -ForegroundColor Cyan
Write-Host ("  FUTURES unrealized agora: {0:N2}" -f $totalUnrealizedFutures) -ForegroundColor White
Write-Host ("  SPOT realizado aproximado (14d): {0:N2}" -f $totalRealizedSpotApprox) -ForegroundColor White
Write-Host ("  SPOT unrealized latente (holdings atuais): {0:N2}" -f $totalUnrealizedSpotLatent) -ForegroundColor White
$grandTotal = $totalUnrealizedFutures + $totalRealizedSpotApprox + $totalUnrealizedSpotLatent
Write-Host ("  GRAND TOTAL (futures unrealized + spot realizado approx + spot unrealized latente): {0:N2}" -f $grandTotal) -ForegroundColor Magenta
Write-Host ""
Write-Host "=== FIM DIAG ===" -ForegroundColor Cyan
