# diag_spot_holdings_readonly_2026_08_24.ps1 -- ONE-SHOT, so leitura.
#
# Owner reportou (extrato real CoinEx): 18 moedas SPOT com valor relevante
# (SUI $137, XAUT $85, SC $65, SUPER $65, AERO $63, VIRTUAL $63, STX $52,
# FF $51, DOG $44, PAXG $3.58, COAI $2.93, SKL $2.17, PUMP/LDO/USDC/ZRO/
# ETHFI/TUT/DGB residuais) SEM ordem de venda/stop configurada. O log real
# do trailing_stop_monitor (2026-08-23 06:24) mostrou "SPOT STOPS: 1 holdings
# cobertas" -- so 1 das 18+ chegou a Get-SpotHoldingsForStop. Investigar por
# que (endpoint /v2/assets/spot/balance nao retorna tudo? filtro descarta
# indevidamente? MinUsd=5 corta mais do que deveria?).

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_spot_stop_guard.ps1")

Write-Host "=== DIAG: SPOT holdings sem stop (READ-ONLY) ===" -ForegroundColor Cyan

Write-Host "`n--- [1] Saldo REAL via /v2/assets/spot/balance ---" -ForegroundColor Yellow
try {
    $bal = CoinEx-Get "/v2/assets/spot/balance"
    Write-Host "code=$($bal.code) | total de linhas retornadas: $(@($bal.data).Count)"
    $stable = @("USDT","USDC","USD","DAI","TUSD","BUSD")
    foreach ($c in @($bal.data)) {
        $ccy = "$($c.ccy)".ToUpper()
        $qty = ([double]$c.available) + ([double]$c.frozen)
        $isStable = ($ccy -in $stable)
        Write-Host "  ${ccy}: available=$($c.available) frozen=$($c.frozen) qty_total=$qty stable=$isStable"
    }
} catch {
    Write-Host "ERRO ao buscar saldo: $_" -ForegroundColor Red
}

Write-Host "`n--- [2] Get-SpotHoldingsForStop -MinUsd 5 (funcao real usada em producao) ---" -ForegroundColor Yellow
try {
    $targets = Get-SpotHoldingsForStop -MinUsd 5
    Write-Host "Total holdings elegiveis: $(@($targets).Count)"
    foreach ($t in @($targets)) {
        Write-Host "  $($t.market): qty=$($t.qty) stop_price=$($t.stop_price)"
    }
} catch {
    Write-Host "ERRO em Get-SpotHoldingsForStop: $_" -ForegroundColor Red
}

Write-Host "`n--- [3a] Ordens SPOT NORMAIS pendentes (pending-order) ---" -ForegroundColor Yellow
try {
    $pending = CoinEx-Get "/v2/spot/pending-order?market_type=SPOT"
    Write-Host "code=$($pending.code) | total pendentes: $(@($pending.data).Count)"
    foreach ($o in @($pending.data)) {
        Write-Host "  $($o.market) side=$($o.side) type=$($o.type) price=$($o.price) amount=$($o.amount)"
    }
} catch {
    Write-Host "ERRO ao buscar ordens pendentes: $_" -ForegroundColor Red
}

Write-Host "`n--- [3b] Ordens de STOP SPOT pendentes (pending-stop-order -- o que Sync-SpotStopsToExchange realmente consulta) ---" -ForegroundColor Yellow
try {
    $markets = @("FFUSDT","STXUSDT","SUPERUSDT","VIRTUALUSDT","DOGUSDT","AEROUSDT","SCUSDT","SUIUSDT","XAUTUSDT")
    foreach ($mkt in $markets) {
        try {
            $so = CoinEx-Get "/v2/spot/pending-stop-order?market=$mkt&market_type=SPOT&page=1&limit=100"
            $n = @($so.data).Count
            Write-Host "  ${mkt}: code=$($so.code) stop-orders=$n"
            foreach ($s in @($so.data)) {
                Write-Host "    side=$($s.side) trigger=$($s.trigger_price) price=$($s.price) amount=$($s.amount)"
            }
        } catch {
            Write-Host "  ${mkt}: ERRO $_" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "ERRO ao buscar stop-orders: $_" -ForegroundColor Red
}

Write-Host "`n=== FIM DIAG (so leitura -- Sync-SpotStopsToExchange NAO executado) ===" -ForegroundColor Cyan
