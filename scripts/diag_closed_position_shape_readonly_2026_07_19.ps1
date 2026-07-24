# diag_closed_position_shape_readonly_2026_07_19.ps1 -- diagnostico ONE-SHOT, so leitura
#
# Achado investigando por que Reconcile-AppToJournal (lib_position_sync_live.ps1)
# sempre falha silencioso: CoinEx-GetClosedPositions nunca existiu, e a funcao
# de conversao (_Convert-ClosedTradeToOutcome) foi escrita esperando campos
# (entryPrice, exitPrice, quantity, orderId) que nunca foram confirmados contra
# a API real -- parecem inventados (camelCase nao bate com o padrao snake_case
# ja confirmado em uso real no resto de lib_coinex.ps1, ex: finished-position
# so tem uso confirmado com pos.side/pos.realized_pnl/pos.close_avbl em
# audit_coinex_state.ps1).
#
# Este script NAO tenta consertar nada -- so imprime o shape bruto de
# /v2/futures/finished-position e /v2/spot/finished-order pra mercados REAIS
# (descobertos via holding/posicao atual, mesmo padrao ja validado em
# audit_coinex_state.ps1), pra confirmar os nomes de campo certos antes de
# implementar CoinEx-GetClosedPositions de verdade.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")

Write-Host "=== DIAG CLOSED POSITION SHAPE (READ-ONLY) ===" -ForegroundColor Cyan
Write-Host ""

# === FUTURES: mercados com posicao aberta agora (mesmo padrao de audit_coinex_state.ps1) ===
Write-Host "[1] Descobrindo mercados FUTURES via pending-position..." -ForegroundColor Yellow
$futMarkets = @()
try {
    $futPos = CoinEx-Get "/v2/futures/pending-position?market_type=FUTURES" -EA SilentlyContinue
    if ($futPos.code -eq 0) {
        $futMarkets = @($futPos.data | ForEach-Object { $_.market } | Select-Object -Unique)
    }
} catch {
    Write-Host "  ERRO: $_" -ForegroundColor Red
}
Write-Host "  Mercados encontrados: $($futMarkets -join ', ')" -ForegroundColor White

if ($futMarkets.Count -gt 0) {
    Write-Host ""
    Write-Host "[2] Shape bruto de /v2/futures/finished-position (ate 3 mercados, 1 registro cada)" -ForegroundColor Yellow
    foreach ($mkt in ($futMarkets | Select-Object -First 3)) {
        try {
            $r = CoinEx-Get "/v2/futures/finished-position?market=$mkt&market_type=FUTURES&page=1&limit=1" -EA SilentlyContinue
            if ($r.code -eq 0 -and $r.data.Count -gt 0) {
                Write-Host "  [$mkt] SHAPE COMPLETO:" -ForegroundColor Green
                Write-Host "    $($r.data[0] | ConvertTo-Json -Compress -Depth 4)"
            } elseif ($r.code -eq 0) {
                Write-Host "  [$mkt] sem posicoes fechadas historicas" -ForegroundColor DarkYellow
            } else {
                Write-Host "  [$mkt] erro: $($r.message)" -ForegroundColor Red
            }
        } catch {
            Write-Host "  [$mkt] excecao: $_" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "[3] Shape bruto de /v2/futures/finished-order (mesmo mercado, 1 registro)" -ForegroundColor Yellow
    foreach ($mkt in ($futMarkets | Select-Object -First 3)) {
        try {
            $r = CoinEx-Get "/v2/futures/finished-order?market=$mkt&market_type=FUTURES&page=1&limit=1" -EA SilentlyContinue
            if ($r.code -eq 0 -and $r.data.Count -gt 0) {
                Write-Host "  [$mkt] SHAPE COMPLETO:" -ForegroundColor Green
                Write-Host "    $($r.data[0] | ConvertTo-Json -Compress -Depth 4)"
            }
        } catch {
            Write-Host "  [$mkt] excecao: $_" -ForegroundColor Red
        }
    }
} else {
    Write-Host "  (nenhuma posicao FUTURES aberta agora -- sem mercado pra testar finished-position/finished-order)" -ForegroundColor DarkYellow
}

Write-Host ""

# === SPOT: mercados com holding real ===
Write-Host "[4] Descobrindo mercados SPOT via balance..." -ForegroundColor Yellow
$spotMarkets = @()
try {
    $bal = CoinEx-Get "/v2/assets/spot/balance" -EA SilentlyContinue
    if ($bal.code -eq 0) {
        $spotMarkets = @($bal.data | Where-Object { $_.ccy -ne "USDT" -and ([double]$_.available -gt 0 -or [double]$_.frozen -gt 0) } | ForEach-Object { "$($_.ccy)USDT" })
    }
} catch {
    Write-Host "  ERRO: $_" -ForegroundColor Red
}
Write-Host "  Mercados encontrados: $($spotMarkets -join ', ')" -ForegroundColor White

if ($spotMarkets.Count -gt 0) {
    Write-Host ""
    Write-Host "[5] Shape bruto de /v2/spot/finished-order (ate 3 mercados, 1 registro cada)" -ForegroundColor Yellow
    foreach ($mkt in ($spotMarkets | Select-Object -First 3)) {
        try {
            $r = CoinEx-Get "/v2/spot/finished-order?market=$mkt&market_type=SPOT&page=1&limit=1" -EA SilentlyContinue
            if ($r.code -eq 0 -and $r.data.Count -gt 0) {
                Write-Host "  [$mkt] SHAPE COMPLETO:" -ForegroundColor Green
                Write-Host "    $($r.data[0] | ConvertTo-Json -Compress -Depth 4)"
            } elseif ($r.code -eq 0) {
                Write-Host "  [$mkt] sem ordens fechadas historicas" -ForegroundColor DarkYellow
            } else {
                Write-Host "  [$mkt] erro: $($r.message)" -ForegroundColor Red
            }
        } catch {
            Write-Host "  [$mkt] excecao: $_" -ForegroundColor Red
        }
    }
} else {
    Write-Host "  (nenhum holding SPOT real agora -- sem mercado pra testar finished-order)" -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "=== FIM DIAG -- use o shape acima pra implementar CoinEx-GetClosedPositions sem adivinhar ===" -ForegroundColor Cyan
