# diag_weekly_pnl_crosscheck_2026_07_20.ps1 -- diagnostico ONE-SHOT, so leitura
#
# Responde: quanto o sistema REALMENTE perdeu/ganhou nos ultimos 7-10 dias?
# Cruza 2 fontes independentes:
#   [A] CoinEx direto (finished-position/finished-order, mesmos endpoints ja
#       confirmados em audit_coinex_state.ps1/diag_closed_position_shape) --
#       fonte de verdade absoluta, nao depende do journal do sistema.
#   [B] trade_outcomes (Supabase) FILTRADO -- exclui source=position_sync_realtime
#       (residuo confirmado de frota local descontinuada, ~08-10/07) e
#       source que comeca com "e2e_test" (testes, nao trades reais).
#
# Se as duas fontes baterem (mesma ordem de grandeza), confianca alta no
# numero. Se nao baterem, ha lacuna de tracking nao mapeada ainda.

$agentsDir = Join-Path $PSScriptRoot ".." "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

$windowStart = (Get-Date).AddDays(-10)
Write-Host "=== DIAG WEEKLY PNL CROSSCHECK (READ-ONLY) -- janela desde $($windowStart.ToString('yyyy-MM-dd')) ===" -ForegroundColor Cyan
Write-Host ""

# ── [A] CoinEx direto: finished-position (FUTURES) por mercado com posicao aberta/conhecida ──
Write-Host "[A] CoinEx direto -- finished-position (FUTURES)" -ForegroundColor Yellow
$futTotalPnl = 0.0
$futCount = 0
try {
    $futMarkets = @()
    $futPos = CoinEx-Get "/v2/futures/pending-position?market_type=FUTURES" -EA SilentlyContinue
    if ($futPos.code -eq 0) {
        $futMarkets = @($futPos.data | ForEach-Object { $_.market } | Select-Object -Unique)
    }
    Write-Host "  Mercados FUTURES com posicao aberta agora: $($futMarkets -join ', ')" -ForegroundColor White

    foreach ($mkt in $futMarkets) {
        try {
            $r = CoinEx-Get "/v2/futures/finished-position?market=$mkt&market_type=FUTURES&page=1&limit=50" -EA SilentlyContinue
            if ($r.code -eq 0 -and $r.data.Count -gt 0) {
                foreach ($p in $r.data) {
                    $updatedAt = try { [datetimeoffset]::FromUnixTimeMilliseconds([long]$p.updated_at).UtcDateTime } catch { $null }
                    if ($updatedAt -and $updatedAt -ge $windowStart) {
                        $pnl = [double]$p.realized_pnl
                        $futTotalPnl += $pnl
                        $futCount++
                        Write-Host "    [$mkt] $($updatedAt.ToString('yyyy-MM-dd HH:mm')) side=$($p.side) realized_pnl=`$$pnl finished_type=$($p.finished_type)"
                    }
                }
            }
        } catch {
            Write-Host "  [$mkt] erro: $_" -ForegroundColor Red
        }
    }
    Write-Host ""
    Write-Host "  FUTURES total (janela): n=$futCount pnl=`$$([Math]::Round($futTotalPnl,2))" -ForegroundColor White
} catch {
    Write-Host "  ERRO: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# ── [A2] CoinEx direto: finished-order SPOT (proxy -- spot nao tem realized_pnl nativo,
# soma buy vs sell por mercado com holding e' aproximacao, nao exata) ──
Write-Host "[A2] CoinEx direto -- SPOT holdings atuais (contexto, sem PnL historico exato)" -ForegroundColor Yellow
try {
    $bal = CoinEx-Get "/v2/assets/spot/balance" -EA SilentlyContinue
    if ($bal.code -eq 0) {
        $spotMarkets = @($bal.data | Where-Object { $_.ccy -ne "USDT" -and ([double]$_.available -gt 0 -or [double]$_.frozen -gt 0) })
        Write-Host "  Holdings SPOT nao-USDT atuais: $($spotMarkets.Count) moeda(s)" -ForegroundColor White
        foreach ($h in $spotMarkets) { Write-Host "    $($h.ccy): available=$($h.available) frozen=$($h.frozen)" }
    }
} catch {
    Write-Host "  ERRO: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# ── [B] trade_outcomes filtrado (exclui residuo conhecido) ──────────────────
Write-Host "[B] trade_outcomes (Supabase) FILTRADO -- exclui position_sync_realtime + e2e_test*" -ForegroundColor Yellow
try {
    $outcomes = @(Get-StateRecords -Table "trade_outcomes" -ErrorAction Stop)
    $filtered = @($outcomes | Where-Object {
        $src = "$($_.source)"
        $src -ne "position_sync_realtime" -and $src -notlike "e2e_test*"
    })
    Write-Host "  Total bruto: $($outcomes.Count) | Apos filtro: $($filtered.Count)" -ForegroundColor White

    $inWindow = @($filtered | Where-Object {
        try { ([datetime]$_.closed_at) -ge $windowStart } catch { $false }
    })
    Write-Host "  Na janela (10d): $($inWindow.Count)" -ForegroundColor White

    if ($inWindow.Count -gt 0) {
        $withPnl = @($inWindow | Where-Object { $null -ne $_.pnl_realized })
        $totalPnl = ($withPnl | ForEach-Object { [double]$_.pnl_realized } | Measure-Object -Sum).Sum
        $wins = @($withPnl | Where-Object { [double]$_.pnl_realized -gt 0 })
        $winRate = if ($withPnl.Count -gt 0) { [Math]::Round(($wins.Count / $withPnl.Count) * 100, 1) } else { 0 }
        Write-Host ""
        Write-Host "  RESULTADO FILTRADO (10d): n=$($withPnl.Count) win_rate=$winRate% pnl_total=`$$([Math]::Round($totalPnl,2))" -ForegroundColor White
        foreach ($o in ($inWindow | Sort-Object closed_at -Descending)) {
            Write-Host "    $($o.closed_at) | $($o.market) | source=$($o.source) | pnl_realized=`$$($o.pnl_realized) | pnl_percent=$($o.pnl_percent)%"
        }
    } else {
        Write-Host "  (nenhum trade filtrado dentro da janela de 10 dias)" -ForegroundColor DarkYellow
    }
} catch {
    Write-Host "  ERRO: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== COMPARACAO ===" -ForegroundColor Cyan
Write-Host "[A] CoinEx FUTURES direto: n=$futCount pnl=`$$([Math]::Round($futTotalPnl,2))"
Write-Host "[B] trade_outcomes filtrado: ver RESULTADO FILTRADO acima"
Write-Host "Se as ordens de grandeza NAO baterem, ha lacuna de tracking (trades fechados na exchange sem outcome correspondente, ou vice-versa)."
Write-Host ""
Write-Host "=== FIM DIAG ===" -ForegroundColor Cyan
