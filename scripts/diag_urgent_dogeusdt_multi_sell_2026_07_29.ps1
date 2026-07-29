# diag_urgent_dogeusdt_multi_sell_2026_07_29.ps1 -- diagnostico ONE-SHOT,
# so leitura, URGENTE. Owner reportou: DOGEUSDT SHORT autonomo sem TP/SL,
# "vendendo varias vezes", ja em -$822. Precisa confirmar: (1) posicao real
# na CoinEx agora (side/size/stop_loss real/pnl), (2) trailing_state (o que
# o journal acha), (3) historico de ordens FUTURES recentes (quantas vezes
# abriu/fechou de fato) pra distinguir "multiplas entradas reais" de
# "1 posicao so, trailing tentando mexer repetidamente" (ou dashboard/log
# mostrando o mesmo evento formatado de forma confusa).

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"
$MKT = "DOGEUSDT"

Write-Host "=== DIAG URGENTE: $MKT -- multiplas vendas / sem TP-SL ===" -ForegroundColor Cyan

Write-Host "`n--- [1] Posicao REAL na CoinEx agora ---" -ForegroundColor Yellow
try {
    $pos = CoinEx-GetPosition -market $MKT
    if ($pos) {
        Write-Host ($pos | ConvertTo-Json -Depth 5)
    } else {
        Write-Host "Sem posicao ativa retornada (pode ja ter fechado)." -ForegroundColor DarkYellow
    }
} catch { Write-Host "ERRO CoinEx-GetPosition: $_" -ForegroundColor Red }

Write-Host "`n--- [2] trailing_state (journal) ---" -ForegroundColor Yellow
try {
    $rows = @(Get-StateRecords -Table "trailing_state" -Filter @{ market = $MKT })
    foreach ($r in $rows) {
        Write-Host ("pk_id={0} active={1} side={2} entry={3} stop={4} stopCurrent={5} target={6} phase={7} openedAt={8} closedAt={9} closeReason={10}" -f `
            $r.pk_id, $r.active, $r.side, $r.entry, $r.stop, $r.stopCurrent, $r.target, $r.phase, $r.openedAt, $r.closedAt, $r.closeReason)
    }
    if ($rows.Count -eq 0) { Write-Host "Nenhum registro em trailing_state para $MKT." -ForegroundColor DarkYellow }
} catch { Write-Host "ERRO trailing_state: $_" -ForegroundColor Red }

Write-Host "`n--- [3] Ordens FUTURES finalizadas recentes ($MKT) ---" -ForegroundColor Yellow
try {
    $fo = CoinEx-Get "/v2/futures/finished-order?market=$MKT&market_type=FUTURES&page=1&limit=20"
    if ($fo.code -eq 0 -and $fo.data) {
        foreach ($o in @($fo.data)) {
            Write-Host ("order_id={0} side={1} type={2} amount={3} price={4} deal_amount={5} deal_value={6} status={7} created_at={8}" -f `
                $o.order_id, $o.side, $o.type, $o.amount, $o.price, $o.deal_amount, $o.deal_value, $o.status, $o.created_at)
        }
        Write-Host "Total ordens finalizadas retornadas: $($fo.data.Count)"
    } else {
        Write-Host "Sem dado ou erro: code=$($fo.code) message=$($fo.message)" -ForegroundColor DarkYellow
    }
} catch { Write-Host "ERRO finished-order: $_" -ForegroundColor Red }

Write-Host "`n--- [4] Ordens FUTURES pendentes (abertas agora) ($MKT) ---" -ForegroundColor Yellow
try {
    $po = CoinEx-Get "/v2/futures/pending-order?market=$MKT&market_type=FUTURES&page=1&limit=20"
    if ($po.code -eq 0 -and $po.data) {
        foreach ($o in @($po.data)) {
            Write-Host ("order_id={0} side={1} type={2} amount={3} price={4} status={5} created_at={6}" -f `
                $o.order_id, $o.side, $o.type, $o.amount, $o.price, $o.status, $o.created_at)
        }
        Write-Host "Total ordens pendentes: $($po.data.Count)"
    } else {
        Write-Host "Sem ordens pendentes ou erro: code=$($po.code) message=$($po.message)" -ForegroundColor DarkYellow
    }
} catch { Write-Host "ERRO pending-order: $_" -ForegroundColor Red }

Write-Host "`n--- [5] trade_outcomes recentes ($MKT) ---" -ForegroundColor Yellow
try {
    $outcomes = @(Get-StateRecords -Table "trade_outcomes" -Filter @{ symbol = $MKT })
    foreach ($o in $outcomes) {
        Write-Host ("id={0} direction={1} entry_price={2} exit_price={3} pnl_realized={4} pnl_percent={5} status={6} entry_ts={7}" -f `
            $o.id, $o.direction, $o.entry_price, $o.exit_price, $o.pnl_realized, $o.pnl_percent, $o.status, $o.entry_ts)
    }
    if ($outcomes.Count -eq 0) { Write-Host "Nenhum outcome para $MKT em trade_outcomes." -ForegroundColor DarkYellow }
} catch { Write-Host "ERRO trade_outcomes: $_" -ForegroundColor Red }

Write-Host "`n=== FIM ===" -ForegroundColor Cyan
