# diag_signal_vs_reality_readonly_2026_07_29.ps1 -- diagnostico ONE-SHOT, so
# leitura. Owner pediu avaliacao real: quanto os sinais (score de nascimento,
# target/stop calculados na entrada) diziam que cada posicao ia ganhar, em
# quanto tempo, versus o resultado/idade real agora. Cruza trailing_state
# (ativas, com as colunas birth_score/birth_mesa_sinal/birth_fqs_category
# novas de docs/SETUP_SUPABASE_TRAILING_BIRTH_SCORE_2026_07_29.sql) +
# trade_outcomes (fechadas recentes) + posicoes reais CoinEx.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"

Write-Host "=== POSICOES ATIVAS (trailing_state) -- sinal de nascimento vs agora ===" -ForegroundColor Cyan
try {
    $rows = @(Get-StateRecords -Table "trailing_state" -Filter @{ active = $true })
    Write-Host "Total ativas: $($rows.Count)`n" -ForegroundColor Green

    $futPos = @()
    try { $futPos = @(CoinEx-GetPendingPositions) } catch { Write-Host "  (CoinEx FUTURES falhou: $_)" -ForegroundColor DarkYellow }

    foreach ($r in $rows) {
        $entry = [double]$r.entry
        $stop = [double]$r.stop
        $target = [double]$r.target
        $side = [string]$r.side
        $mkt = [string]$r.market

        # R:R planejado na entrada (o que o sinal prometia)
        $riskPts = [math]::Abs($entry - $stop)
        $rewardPts = [math]::Abs($target - $entry)
        $plannedRR = if ($riskPts -gt 0) { [math]::Round($rewardPts / $riskPts, 2) } else { 0 }
        $targetPct = if ($entry -gt 0) { [math]::Round(($rewardPts / $entry) * 100, 2) } else { 0 }

        # idade da posicao (campo real: openedAt, PascalCase no shape de trailing_state)
        $openedAt = if ($r.PSObject.Properties['openedAt']) { $r.openedAt } else { $null }
        $ageStr = "?"
        if ($openedAt) {
            try {
                $age = ((Get-Date).ToUniversalTime() - [datetime]$openedAt)
                $ageStr = "{0}d{1}h" -f [int]$age.TotalDays, $age.Hours
            } catch {}
        }

        # birth_score: campo novo (2026-07-29). $null quando posicao foi
        # registrada ANTES desta migracao (orfas, ou caller sem BirthScore).
        $birthScore = if ($r.PSObject.Properties['birth_score'] -and $null -ne $r.birth_score) { $r.birth_score } else { "N/D (registrado antes do fix 2026-07-29 ou origem sem birth-score)" }
        $birthMesaSinal = if ($r.PSObject.Properties['birth_mesa_sinal']) { $r.birth_mesa_sinal } else { "" }

        # preco atual real (match por market no snapshot CoinEx). Campo real
        # da API /v2/futures/pending-position e settle_price (ver uso em
        # lib_position_sync_realtime.ps1:142) -- close_price/current_price
        # (tentativa anterior) nao existem no shape real, causava "indisponivel"
        # em toda posicao.
        $live = $futPos | Where-Object { $_.market -eq $mkt } | Select-Object -First 1
        $currentPrice = if ($live -and $live.settle_price) { [double]$live.settle_price } else { $null }
        $pnlNowPct = if ($currentPrice -and $entry -gt 0) {
            if ($side -eq "SHORT") { [math]::Round((($entry - $currentPrice) / $entry) * 100, 2) }
            else { [math]::Round((($currentPrice - $entry) / $entry) * 100, 2) }
        } else { $null }
        $progressToTargetPct = if ($null -ne $pnlNowPct -and $targetPct -gt 0) { [math]::Round(($pnlNowPct / $targetPct) * 100, 1) } else { $null }

        Write-Host "$mkt [$side]" -ForegroundColor Yellow
        Write-Host "  nascimento: birth_score=$birthScore ($birthMesaSinal)"
        Write-Host "  plano: entry=$entry stop=$stop target=$target -> R:R planejado=$plannedRR (alvo=+$targetPct%)"
        Write-Host "  idade: $ageStr (abriu em $openedAt)"
        if ($null -ne $pnlNowPct) {
            Write-Host "  agora: preco=$currentPrice pnl_atual=$pnlNowPct% (progresso ate o alvo: $progressToTargetPct%)" -ForegroundColor $(if ($pnlNowPct -ge 0) { "Green" } else { "Red" })
        } else {
            Write-Host "  agora: preco atual indisponivel (sem match no snapshot CoinEx)" -ForegroundColor DarkYellow
        }
        Write-Host ""
    }
} catch {
    Write-Host "ERRO trailing_state: $_" -ForegroundColor Red
}

Write-Host "`n=== TRADES FECHADOS RECENTES (trade_outcomes) -- previsto vs realizado ===" -ForegroundColor Cyan
try {
    # Schema real (docs/SETUP_SUPABASE_MANUHEADFUND_2026_07_09.sql): id, entry_ts,
    # symbol, direction, source, entry_price, exit_price, quantity, pnl_realized,
    # pnl_percent, status, regime, has_confluence, conviction_score, created_at, updated_at.
    # NAO tem market/opened_at/closed_at/pnl_pct/close_reason -- nomes usados numa
    # tentativa anterior deste script estavam errados, corrigido aqui.
    $closed = @(Get-StateRecords -Table "trade_outcomes" -Filter @{ status = "closed" })
    $closed = $closed | Sort-Object -Property @{Expression={ try { [datetime]$_.updated_at } catch { [datetime]::MinValue } }} -Descending | Select-Object -First 15
    foreach ($c in $closed) {
        $holdStr = "?"
        try {
            if ($c.entry_ts -and $c.updated_at) {
                $hold = [datetime]$c.updated_at - [datetime]$c.entry_ts
                $holdStr = "{0}d{1}h" -f [int]$hold.TotalDays, $hold.Hours
            }
        } catch {}
        Write-Host "$($c.symbol) [$($c.direction)] pnl=$($c.pnl_percent)% (conviction_score=$($c.conviction_score)) hold=$holdStr entry_ts=$($c.entry_ts) regime=$($c.regime)"
    }
    if ($closed.Count -eq 0) { Write-Host "  (nenhum registro status=closed encontrado)" -ForegroundColor DarkYellow }
} catch {
    Write-Host "ERRO trade_outcomes: $_" -ForegroundColor Red
}

Write-Host "`n=== RESUMO PnL REAL (CoinEx direto) ===" -ForegroundColor Cyan
try {
    $fut = @(CoinEx-GetPendingPositions)
    $totalUnrealized = ($fut | ForEach-Object { [double]$_.unrealized_pnl } | Measure-Object -Sum).Sum
    Write-Host "FUTURES abertas: $($fut.Count) | PnL nao-realizado total: `$$([math]::Round($totalUnrealized,2))"
    foreach ($p in $fut) {
        Write-Host "  $($p.market) side=$($p.side) pnl=`$$($p.unrealized_pnl) leverage=$($p.leverage)"
    }
} catch { Write-Host "ERRO CoinEx FUTURES: $_" -ForegroundColor Red }

Write-Host "`n=== FIM ===" -ForegroundColor Cyan
