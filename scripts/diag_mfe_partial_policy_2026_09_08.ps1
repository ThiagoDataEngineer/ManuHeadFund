# diag_mfe_partial_policy_2026_09_08.ps1 -- ONE-SHOT, so leitura
#
# Owner quer decidir com dado real se o piso de partial exit (hoje: aperta em
# 0.1R, realiza 50% em 1R, 25% em 2R -- lib_trailing_baseline.ps1) esta
# deixando dinheiro na mesa comparado a deixar o trade "correr" mais perto do
# alvo de R:R 1:5 (regra de ouro do projeto).
#
# Abordagem (limitacao ja conhecida: trailing_unified_shadow nao grava o TP
# alvo por ciclo, entao nao da pra reconstruir SL/TP exato por trade) --
# em vez disso mede MFE (maximum favorable excursion) real via candles 1min
# entre entry e exit de cada trade fechado, expresso em multiplos do risco
# realizado (proxy de R, ja que o R exato nao e recuperavel): quanto do
# movimento favoravel real o trade teve, vs quanto foi de fato capturado
# (pnl_realizado / mfe_em_valor). Isso mostra se ha upside real sendo perdido
# por sair cedo (mfe >> pnl realizado) ou se o trade reverteu rapido demais
# pra qualquer politica de partial ter feito diferenca (mfe ~ pnl realizado).

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_candle_fetcher.ps1")

Write-Host "=== DIAG MFE vs PNL REALIZADO -- trades reais 21d ===" -ForegroundColor Cyan
Write-Host ""

$windowDays = 21
$windowStart = (Get-Date).AddDays(-$windowDays)

# 1) Descobrir universo de mercados (mesma tecnica ja validada nesta sessao)
$allMarkets = [System.Collections.Generic.HashSet[string]]::new()
try {
    $futPos = CoinEx-Get "/v2/futures/pending-position?market_type=FUTURES" -EA SilentlyContinue
    if ($futPos.code -eq 0) { foreach ($p in $futPos.data) { [void]$allMarkets.Add($p.market) } }
} catch {}
try {
    $page = 1
    do {
        $ord = CoinEx-Get "/v2/futures/finished-order?market_type=FUTURES&page=$page&limit=100" -EA SilentlyContinue
        if ($ord.code -ne 0 -or -not $ord.data -or $ord.data.Count -eq 0) { break }
        foreach ($o in $ord.data) {
            $ts = try { [datetimeoffset]::FromUnixTimeMilliseconds([long]$o.updated_at).UtcDateTime } catch { $null }
            if ($ts -and $ts -ge $windowStart) { [void]$allMarkets.Add($o.market) }
        }
        $hasMore = $ord.pagination.has_next
        $page++
    } while ($hasMore -and $page -le 20)
} catch {}
Write-Host "[1] Universo de mercados (21d): $($allMarkets.Count) -> $($allMarkets -join ', ')"
Write-Host ""

# 2) Puxar trades fechados reais (finished-position) com side/pnl/finished_type/timestamps
$trades = @()
foreach ($mkt in $allMarkets) {
    try {
        $page = 1
        do {
            $r = CoinEx-Get "/v2/futures/finished-position?market=$mkt&market_type=FUTURES&page=$page&limit=50" -EA SilentlyContinue
            if ($r.code -ne 0 -or -not $r.data -or $r.data.Count -eq 0) { break }
            foreach ($p in $r.data) {
                $updatedAt = try { [datetimeoffset]::FromUnixTimeMilliseconds([long]$p.updated_at).UtcDateTime } catch { $null }
                $createdAt = try { [datetimeoffset]::FromUnixTimeMilliseconds([long]$p.created_at).UtcDateTime } catch { $null }
                if ($updatedAt -and $updatedAt -ge $windowStart -and $createdAt) {
                    $trades += [PSCustomObject]@{
                        market = $mkt; side = $p.side; pnl = [double]$p.realized_pnl
                        finished_type = $p.finished_type
                        entry = [double]$p.avg_entry_price
                        settle = [double]$p.settle_price
                        opened_at = $createdAt; closed_at = $updatedAt
                    }
                }
            }
            $hasMore = $r.pagination.has_next
            $page++
        } while ($hasMore -and $page -le 5)
    } catch {}
}
Write-Host "[2] Trades fechados reais na janela: $($trades.Count)"
Write-Host ""

# 3) Para uma amostra (limitar chamadas de candle -- top 40 por |pnl| pra cobrir os mais relevantes)
$sample = @($trades | Sort-Object { [Math]::Abs($_.pnl) } -Descending | Select-Object -First 40)
Write-Host "[3] Medindo MFE via candles 1min pra $($sample.Count) trades (amostra por |pnl|)" -ForegroundColor Yellow
Write-Host ""

$results = @()
foreach ($t in $sample) {
    $durationMin = [Math]::Ceiling(($t.closed_at - $t.opened_at).TotalMinutes)
    if ($durationMin -lt 1) { $durationMin = 1 }
    if ($durationMin -gt 1440) { $durationMin = 1440 } # cap 1 dia pra nao estourar limit

    try {
        $candles = Get-CoinExCandles -Market $t.market -Period "1min" -Limit ([Math]::Min($durationMin + 5, 1000)) -IsFutures $true
    } catch { $candles = @() }

    if (-not $candles -or $candles.Count -eq 0) {
        $results += [PSCustomObject]@{ market=$t.market; side=$t.side; pnl=$t.pnl; finished_type=$t.finished_type; mfe_pct=$null; note="sem_candles" }
        continue
    }

    # candles vem mais recentes primeiro tipicamente -- filtra pela janela do trade
    $inRange = @($candles | Where-Object { $_.timestamp -ge $t.opened_at -and $_.timestamp -le $t.closed_at.AddMinutes(1) })
    if ($inRange.Count -eq 0) { $inRange = $candles }

    if ($t.side -eq "long") {
        $bestPrice = ($inRange | Measure-Object -Property high -Maximum).Maximum
        $mfePct = if ($t.entry -gt 0) { (($bestPrice - $t.entry) / $t.entry) * 100 } else { $null }
    } else {
        $bestPrice = ($inRange | Measure-Object -Property low -Minimum).Minimum
        $mfePct = if ($t.entry -gt 0) { (($t.entry - $bestPrice) / $t.entry) * 100 } else { $null }
    }

    $results += [PSCustomObject]@{ market=$t.market; side=$t.side; pnl=$t.pnl; finished_type=$t.finished_type; mfe_pct=$mfePct; note="ok" }
}

Write-Host ""
Write-Host "=== RESULTADOS (mfe_pct = maior movimento a favor durante a vida do trade) ===" -ForegroundColor Cyan
foreach ($r in ($results | Sort-Object { [Math]::Abs($_.pnl) } -Descending)) {
    $mfeStr = if ($null -ne $r.mfe_pct) { "{0:N2}%" -f $r.mfe_pct } else { "n/a" }
    Write-Host "  [$($r.market)] side=$($r.side) pnl=`$$($r.pnl) finished_type=$($r.finished_type) mfe=$mfeStr note=$($r.note)"
}

Write-Host ""
$valid = @($results | Where-Object { $_.note -eq "ok" -and $null -ne $_.mfe_pct })
$winners = @($valid | Where-Object { $_.pnl -gt 0 })
$losers = @($valid | Where-Object { $_.pnl -le 0 })

Write-Host "=== RESUMO ===" -ForegroundColor Cyan
Write-Host "Amostra valida: $($valid.Count) / $($sample.Count)"
if ($winners.Count -gt 0) {
    $avgMfeWin = ($winners | Measure-Object -Property mfe_pct -Average).Average
    Write-Host "Vencedores (n=$($winners.Count)): MFE medio = $([Math]::Round($avgMfeWin,2))% -- ou seja, o preco chegou a mover em media isso a favor antes de fechar"
}
if ($losers.Count -gt 0) {
    $avgMfeLoss = ($losers | Measure-Object -Property mfe_pct -Average).Average
    Write-Host "Perdedores (n=$($losers.Count)): MFE medio = $([Math]::Round($avgMfeLoss,2))% -- quanto chegou a ir a favor ANTES de reverter e bater stop"
}
Write-Host ""
Write-Host "=== FIM DIAG ===" -ForegroundColor Cyan
