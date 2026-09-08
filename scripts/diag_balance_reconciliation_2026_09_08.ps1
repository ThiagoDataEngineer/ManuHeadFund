# diag_balance_reconciliation_2026_09_08.ps1 -- ONE-SHOT, so leitura
#
# Owner reportou saldo TOTAL caindo de ~$5500 para ~$5180 (~$320 real) nos
# ultimos 14 dias. Ja confirmamos nesta sessao que PnL de trade (futures
# realizado -$6.08, futures unrealized -$2.64, spot realizado +$31.78, spot
# unrealized +$0.08 = ~+$23 total) NAO explica essa queda.
#
# Este script cobre os 4 buracos que PnL de trade nao captura:
#   1) Saldo TOTAL atual (spot + futures) via API, pra confirmar o numero real
#   2) Funding rate PAGO/RECEBIDO em FUTURES (custo separado do PnL de posicao)
#   3) Fees de trading SPOT somados em TODOS os mercados com atividade (nao so
#      os que tem holding residual hoje -- mercados liquidados totalmente
#      tambem geraram fee e desapareceram dos holdings atuais)
#   4) Saques/depositos nos ultimos 14 dias
#
# NAO usa journal/trade_outcomes.jsonl nem Supabase (contaminados). So API CoinEx direta.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")

Write-Host "=== DIAG RECONCILIACAO DE SALDO TOTAL (READ-ONLY) ===" -ForegroundColor Cyan
Write-Host ""

$cutoffMs = [DateTimeOffset]::UtcNow.AddDays(-14).ToUnixTimeMilliseconds()
$cutoffSec = [DateTimeOffset]::UtcNow.AddDays(-14).ToUnixTimeSeconds()

function Get-TsMs($obj, [string[]]$fields) {
    foreach ($f in $fields) {
        if ($obj.PSObject.Properties.Name -contains $f -and $obj.$f) {
            $v = [long]$obj.$f
            return ($(if ($v -gt 999999999999) { $v } else { $v * 1000 }))
        }
    }
    return $null
}

# ============================================================
# [1] SALDO TOTAL ATUAL -- spot + futures
# ============================================================
Write-Host "[1] Saldo TOTAL atual (spot + futures)" -ForegroundColor Yellow
$spotUsdtValue = 0.0
$spotBreakdown = @()
try {
    $bal = CoinEx-Get "/v2/assets/spot/balance" -EA SilentlyContinue
    if ($bal.code -eq 0) {
        Write-Host "  RAW SHAPE spot/balance (1o registro):" -ForegroundColor DarkGray
        if ($bal.data.Count -gt 0) { Write-Host "    $($bal.data[0] | ConvertTo-Json -Compress -Depth 5)" }
        foreach ($h in $bal.data) {
            $qty = [double]$h.available + [double]$h.frozen
            if ($qty -le 0) { continue }
            if ($h.ccy -eq "USDT") {
                $spotUsdtValue += $qty
                $spotBreakdown += [PSCustomObject]@{ ccy = "USDT"; qty = $qty; usdtValue = $qty }
                continue
            }
            $px = $null
            try {
                $tk = CoinEx-Get "/v2/spot/ticker?market=$($h.ccy)USDT" -EA SilentlyContinue
                if ($tk.code -eq 0 -and $tk.data.Count -gt 0) { $px = [double]$tk.data[0].last }
            } catch {}
            $val = if ($px) { $qty * $px } else { 0.0 }
            $spotUsdtValue += $val
            $spotBreakdown += [PSCustomObject]@{ ccy = $h.ccy; qty = $qty; usdtValue = $val }
        }
        foreach ($s in $spotBreakdown) {
            Write-Host ("    {0}: qty={1:N6} ~USDT={2:N2}" -f $s.ccy, $s.qty, $s.usdtValue) -ForegroundColor White
        }
    } else {
        Write-Host "  ERRO API spot/balance: code=$($bal.code) message=$($bal.message)" -ForegroundColor Red
    }
} catch { Write-Host "  EXCECAO spot/balance: $_" -ForegroundColor Red }
Write-Host ("  TOTAL SPOT (~USDT): {0:N2}" -f $spotUsdtValue) -ForegroundColor Cyan
Write-Host ""

$futuresBalUsdt = 0.0
try {
    $futBal = CoinEx-Get "/v2/assets/futures/balance" -EA SilentlyContinue
    if ($futBal.code -eq 0) {
        Write-Host "  RAW SHAPE futures/balance:" -ForegroundColor DarkGray
        Write-Host "    $($futBal.data | ConvertTo-Json -Compress -Depth 5)"
        foreach ($f in $futBal.data) {
            foreach ($field in @('available','equity','balance_total','margin_avbl')) {
                if ($f.PSObject.Properties.Name -contains $field) {
                    Write-Host ("    ccy={0} {1}={2}" -f $f.ccy, $field, $f.$field) -ForegroundColor White
                }
            }
            if ($f.ccy -eq "USDT") {
                foreach ($field in @('equity','available')) {
                    if ($f.PSObject.Properties.Name -contains $field) {
                        $futuresBalUsdt = [double]$f.$field
                        break
                    }
                }
            }
        }
    } else {
        Write-Host "  ERRO API futures/balance: code=$($futBal.code) message=$($futBal.message)" -ForegroundColor Red
    }
} catch { Write-Host "  EXCECAO futures/balance: $_" -ForegroundColor Red }
Write-Host ("  TOTAL FUTURES (equity/available, ~USDT): {0:N2}" -f $futuresBalUsdt) -ForegroundColor Cyan

# Soma unrealized das posicoes abertas pra ter equity real (caso o balance nao inclua)
$totalUnrealizedFutures = 0.0
$totalMarginUsed = 0.0
try {
    $futPos = CoinEx-Get "/v2/futures/pending-position?market_type=FUTURES&limit=100" -EA SilentlyContinue
    if ($futPos.code -eq 0) {
        foreach ($p in $futPos.data) {
            $upnl = $null
            foreach ($field in @('unrealized_pnl','profit_unreal','unrealized_profit','pnl_unrealized')) {
                if ($p.PSObject.Properties.Name -contains $field) { $upnl = [double]$p.$field; break }
            }
            if ($null -ne $upnl) { $totalUnrealizedFutures += $upnl }
            if ($p.PSObject.Properties.Name -contains 'margin_avbl') { $totalMarginUsed += [double]$p.margin_avbl }
        }
    }
} catch {}
Write-Host ("  (contexto) unrealized_pnl aberto agora: {0:N2} | margem em uso: {1:N2}" -f $totalUnrealizedFutures, $totalMarginUsed) -ForegroundColor DarkGray

$grandTotalBalance = $spotUsdtValue + $futuresBalUsdt
Write-Host ("  SALDO TOTAL ATUAL (spot + futures): {0:N2}" -f $grandTotalBalance) -ForegroundColor Magenta
Write-Host ""

# ============================================================
# [2] FUNDING RATE PAGO/RECEBIDO -- position-funding-history
# ============================================================
Write-Host "[2] FUTURES funding pago/recebido (14 dias) -- position-funding-history" -ForegroundColor Yellow
$totalFunding = 0.0
$fundingByMarket = @{}
try {
    # descobrir universo de mercados com atividade via finished-position (ja usado antes na sessao)
    $marketsWithActivity = @()
    $finPosAll = CoinEx-Get "/v2/futures/finished-position?market_type=FUTURES&page=1&limit=100" -EA SilentlyContinue
    if ($finPosAll.code -eq 0) {
        $marketsWithActivity = @($finPosAll.data | Where-Object { $_.market } | ForEach-Object { $_.market } | Select-Object -Unique)
    }
    # tambem incluir mercados abertos agora
    if ($futPos.code -eq 0) {
        $marketsWithActivity += @($futPos.data | ForEach-Object { $_.market })
        $marketsWithActivity = $marketsWithActivity | Select-Object -Unique
    }
    Write-Host "  Mercados FUTURES com atividade (14d + abertos): $($marketsWithActivity -join ', ')" -ForegroundColor DarkGray

    $shapePrinted = $false
    foreach ($mkt in $marketsWithActivity) {
        $page = 1
        $keepGoing = $true
        $mktFunding = 0.0
        while ($keepGoing) {
            $r = CoinEx-Get "/v2/futures/position-funding-history?market=$mkt&market_type=FUTURES&page=$page&limit=100" -EA SilentlyContinue
            if ($r.code -ne 0) {
                if (-not $shapePrinted) { Write-Host "  ERRO position-funding-history [$mkt]: code=$($r.code) message=$($r.message)" -ForegroundColor Red }
                break
            }
            if ($r.data.Count -eq 0) { break }
            if (-not $shapePrinted) {
                Write-Host "  RAW SHAPE position-funding-history (1o registro real):" -ForegroundColor DarkGray
                Write-Host "    $($r.data[0] | ConvertTo-Json -Compress -Depth 5)"
                $shapePrinted = $true
            }
            foreach ($f in $r.data) {
                $tsMs = Get-TsMs $f @('created_at','create_time','ctime','settle_time')
                if ($tsMs -and $tsMs -lt $cutoffMs) { continue }
                $amt = $null
                foreach ($field in @('funding','funding_value','amount','value')) {
                    if ($f.PSObject.Properties.Name -contains $field) { $amt = [double]$f.$field; break }
                }
                if ($null -ne $amt) { $mktFunding += $amt }
            }
            if ($r.data.Count -lt 100) { $keepGoing = $false }
            $page++
            if ($page -gt 5) { $keepGoing = $false }
        }
        if ($mktFunding -ne 0) {
            $fundingByMarket[$mkt] = $mktFunding
            $totalFunding += $mktFunding
            Write-Host ("    [{0}] funding 14d: {1:N4}" -f $mkt, $mktFunding) -ForegroundColor White
        }
    }
} catch { Write-Host "  EXCECAO funding history: $_" -ForegroundColor Red }
Write-Host ("  TOTAL FUNDING (14d, negativo=pago pela conta): {0:N4}" -f $totalFunding) -ForegroundColor Cyan
Write-Host ""

# ============================================================
# [3] SPOT fees -- TODOS mercados com atividade (nao so holdings atuais)
# ============================================================
Write-Host "[3] SPOT trading fees (14 dias) -- todos os mercados com atividade" -ForegroundColor Yellow
# Descobrir universo: CoinEx v2 nao tem "list markets with activity" direto.
# Estrategia: puxar finished-order SEM filtro de market se suportado; senao,
# usar a lista conhecida de holdings atuais + mercados citados no journal local
# como fallback, e reportar explicitamente a limitacao.
$totalSpotFees = 0.0
$feesByMarket = @{}
$allOrdersNoMarketFilter = $null
try {
    $allOrdersNoMarketFilter = CoinEx-Get "/v2/spot/finished-order?market_type=SPOT&page=1&limit=100" -EA SilentlyContinue
} catch {}

if ($allOrdersNoMarketFilter -and $allOrdersNoMarketFilter.code -eq 0 -and $allOrdersNoMarketFilter.data.Count -gt 0) {
    Write-Host "  finished-order SEM filtro de market FUNCIONOU -- cobrindo universo completo" -ForegroundColor Green
    Write-Host "  RAW SHAPE: $($allOrdersNoMarketFilter.data[0] | ConvertTo-Json -Compress -Depth 5)" -ForegroundColor DarkGray
    $page = 1
    $keepGoing = $true
    while ($keepGoing) {
        $r = if ($page -eq 1) { $allOrdersNoMarketFilter } else { CoinEx-Get "/v2/spot/finished-order?market_type=SPOT&page=$page&limit=100" -EA SilentlyContinue }
        if ($r.code -ne 0 -or $r.data.Count -eq 0) { break }
        foreach ($o in $r.data) {
            $tsMs = Get-TsMs $o @('created_at','create_time','ctime')
            if ($tsMs -and $tsMs -lt $cutoffMs) { continue }
            $fee = 0.0
            if ($o.PSObject.Properties.Name -contains 'quote_fee') { $fee += [double]$o.quote_fee }
            if ($o.PSObject.Properties.Name -contains 'base_fee') { $fee += [double]$o.base_fee }
            $mkt = $o.market
            if (-not $feesByMarket.ContainsKey($mkt)) { $feesByMarket[$mkt] = 0.0 }
            $feesByMarket[$mkt] += $fee
            $totalSpotFees += $fee
        }
        if ($r.data.Count -lt 100) { $keepGoing = $false }
        $page++
        if ($page -gt 20) { $keepGoing = $false }
    }
} else {
    Write-Host "  finished-order SEM market NAO retornou dado util (code=$($allOrdersNoMarketFilter.code) message=$($allOrdersNoMarketFilter.message)) -- caindo pra estrategia por mercado" -ForegroundColor DarkYellow
    Write-Host "  LIMITACAO: so cobre mercados com holding atual + mercados conhecidos, pode SUBESTIMAR fees de mercados totalmente liquidados" -ForegroundColor DarkYellow

    $knownMarkets = @()
    try {
        $bal2 = CoinEx-Get "/v2/assets/spot/balance" -EA SilentlyContinue
        if ($bal2.code -eq 0) {
            $knownMarkets = @($bal2.data | Where-Object { $_.ccy -ne "USDT" } | ForEach-Object { "$($_.ccy)USDT" })
        }
    } catch {}
    # incluir mercados citados no achado do owner mesmo sem holding atual
    $knownMarkets += @("AKEUSDT", "CHIPUSDT", "USELESSUSDT")
    $knownMarkets = $knownMarkets | Select-Object -Unique

    foreach ($mkt in $knownMarkets) {
        $page = 1
        $keepGoing = $true
        $mktFee = 0.0
        while ($keepGoing) {
            $r = CoinEx-Get "/v2/spot/finished-order?market=$mkt&market_type=SPOT&page=$page&limit=100" -EA SilentlyContinue
            if ($r.code -ne 0 -or $r.data.Count -eq 0) { break }
            foreach ($o in $r.data) {
                $tsMs = Get-TsMs $o @('created_at','create_time','ctime')
                if ($tsMs -and $tsMs -lt $cutoffMs) { continue }
                $fee = 0.0
                if ($o.PSObject.Properties.Name -contains 'quote_fee') { $fee += [double]$o.quote_fee }
                if ($o.PSObject.Properties.Name -contains 'base_fee') { $fee += [double]$o.base_fee }
                $mktFee += $fee
            }
            if ($r.data.Count -lt 100) { $keepGoing = $false }
            $page++
            if ($page -gt 10) { $keepGoing = $false }
        }
        if ($mktFee -ne 0) {
            $feesByMarket[$mkt] = $mktFee
            $totalSpotFees += $mktFee
        }
    }
}
foreach ($k in $feesByMarket.Keys) {
    Write-Host ("    [{0}] fee 14d: {1:N4}" -f $k, $feesByMarket[$k]) -ForegroundColor White
}
Write-Host ("  TOTAL SPOT FEES (14d): {0:N4}" -f $totalSpotFees) -ForegroundColor Cyan
Write-Host ""

# FUTURES fees tambem existem (taker/maker) -- ver se finished-order futures tem campo fee
Write-Host "[3b] FUTURES trading fees (14 dias)" -ForegroundColor Yellow
$totalFuturesFees = 0.0
try {
    $marketsForFee = if ($marketsWithActivity) { $marketsWithActivity } else { @() }
    $shapePrintedF = $false
    foreach ($mkt in $marketsForFee) {
        $page = 1
        $keepGoing = $true
        while ($keepGoing) {
            $r = CoinEx-Get "/v2/futures/finished-order?market=$mkt&market_type=FUTURES&page=$page&limit=100" -EA SilentlyContinue
            if ($r.code -ne 0 -or $r.data.Count -eq 0) { break }
            if (-not $shapePrintedF) {
                Write-Host "  RAW SHAPE futures finished-order: $($r.data[0] | ConvertTo-Json -Compress -Depth 5)" -ForegroundColor DarkGray
                $shapePrintedF = $true
            }
            foreach ($o in $r.data) {
                $tsMs = Get-TsMs $o @('created_at','create_time','ctime')
                if ($tsMs -and $tsMs -lt $cutoffMs) { continue }
                foreach ($field in @('fee','quote_fee')) {
                    if ($o.PSObject.Properties.Name -contains $field) { $totalFuturesFees += [double]$o.$field }
                }
            }
            if ($r.data.Count -lt 100) { $keepGoing = $false }
            $page++
            if ($page -gt 10) { $keepGoing = $false }
        }
    }
} catch { Write-Host "  EXCECAO futures fees: $_" -ForegroundColor Red }
Write-Host ("  TOTAL FUTURES FEES (14d): {0:N4}" -f $totalFuturesFees) -ForegroundColor Cyan
Write-Host ""

# ============================================================
# [4] Saques / Depositos
# ============================================================
Write-Host "[4] Saques e depositos (14 dias)" -ForegroundColor Yellow
$totalWithdraw = 0.0
$totalDeposit = 0.0
try {
    $wd = CoinEx-Get "/v2/assets/withdraw-history?page=1&limit=100" -EA SilentlyContinue
    if ($wd.code -eq 0) {
        if ($wd.data.Count -gt 0) { Write-Host "  RAW SHAPE withdraw-history: $($wd.data[0] | ConvertTo-Json -Compress -Depth 5)" -ForegroundColor DarkGray }
        foreach ($w in $wd.data) {
            $tsMs = Get-TsMs $w @('created_at','create_time','ctime')
            if ($tsMs -and $tsMs -lt $cutoffMs) { continue }
            $amt = $null
            foreach ($field in @('amount','actual_amount')) {
                if ($w.PSObject.Properties.Name -contains $field) { $amt = [double]$w.$field; break }
            }
            if ($null -ne $amt) {
                $totalWithdraw += $amt
                Write-Host ("    saque: ccy={0} amount={1} status={2}" -f $w.ccy, $amt, $w.status) -ForegroundColor White
            }
        }
    } else {
        Write-Host "  ERRO withdraw-history: code=$($wd.code) message=$($wd.message)" -ForegroundColor Red
    }
} catch { Write-Host "  EXCECAO withdraw-history: $_" -ForegroundColor Red }

try {
    $dp = CoinEx-Get "/v2/assets/deposit-history?page=1&limit=100" -EA SilentlyContinue
    if ($dp.code -eq 0) {
        if ($dp.data.Count -gt 0) { Write-Host "  RAW SHAPE deposit-history: $($dp.data[0] | ConvertTo-Json -Compress -Depth 5)" -ForegroundColor DarkGray }
        foreach ($d in $dp.data) {
            $tsMs = Get-TsMs $d @('created_at','create_time','ctime')
            if ($tsMs -and $tsMs -lt $cutoffMs) { continue }
            $amt = $null
            foreach ($field in @('amount','actual_amount')) {
                if ($d.PSObject.Properties.Name -contains $field) { $amt = [double]$d.$field; break }
            }
            if ($null -ne $amt) {
                $totalDeposit += $amt
                Write-Host ("    deposito: ccy={0} amount={1} status={2}" -f $d.ccy, $amt, $d.status) -ForegroundColor White
            }
        }
    } else {
        Write-Host "  ERRO deposit-history: code=$($dp.code) message=$($dp.message)" -ForegroundColor Red
    }
} catch { Write-Host "  EXCECAO deposit-history: $_" -ForegroundColor Red }
Write-Host ("  TOTAL SAQUES (14d): {0:N2} | TOTAL DEPOSITOS (14d): {1:N2}" -f $totalWithdraw, $totalDeposit) -ForegroundColor Cyan
Write-Host ""

# ============================================================
# RESUMO FINAL
# ============================================================
Write-Host "=== RESUMO FINAL -- RECONCILIACAO ===" -ForegroundColor Cyan
$knownTradePnl = -6.08 - 2.64 + 31.78 + 0.08   # ja confirmado nesta sessao
Write-Host ("  Trade PnL ja confirmado (fut realizado -6.08 + fut unrealized -2.64 + spot realizado 31.78 + spot unrealized 0.08): {0:N2}" -f $knownTradePnl) -ForegroundColor White
Write-Host ("  Funding pago/recebido (14d): {0:N4}" -f $totalFunding) -ForegroundColor White
Write-Host ("  Spot fees (14d): {0:N4} (NEGATIVO no calculo)" -f $totalSpotFees) -ForegroundColor White
Write-Host ("  Futures fees (14d): {0:N4} (NEGATIVO no calculo)" -f $totalFuturesFees) -ForegroundColor White
Write-Host ("  Saques (14d): {0:N2} (NEGATIVO no calculo, saiu da conta)" -f $totalWithdraw) -ForegroundColor White
Write-Host ("  Depositos (14d): {0:N2} (POSITIVO no calculo, entrou na conta)" -f $totalDeposit) -ForegroundColor White
Write-Host ""

# nota: quote_fee em finished-order da CoinEx normalmente ja vem como valor
# positivo representando custo cobrado (nao like sinal). Tratamos como custo.
$feesAsNegative = -1 * [Math]::Abs($totalSpotFees) - [Math]::Abs($totalFuturesFees)
$explainedDelta = $knownTradePnl + $totalFunding + $feesAsNegative - $totalWithdraw + $totalDeposit
Write-Host ("  DELTA EXPLICADO TOTAL: {0:N2}" -f $explainedDelta) -ForegroundColor Magenta
Write-Host ("  DELTA REPORTADO PELO OWNER: ~-320.00 (5500 -> 5180)") -ForegroundColor Magenta
Write-Host ("  DIFERENCA NAO EXPLICADA: {0:N2}" -f (-320 - $explainedDelta)) -ForegroundColor Red
Write-Host ""
Write-Host ("  SALDO TOTAL ATUAL MEDIDO AGORA (spot+futures): {0:N2}" -f $grandTotalBalance) -ForegroundColor Magenta
Write-Host ""
Write-Host "=== FIM DIAG ===" -ForegroundColor Cyan
