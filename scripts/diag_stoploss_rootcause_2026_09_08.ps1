# diag_stoploss_rootcause_2026_09_08.ps1 -- ONE-SHOT, so leitura.
#
# Owner (2026-09-08): apos 8+ "FIX CRITICO" empilhados nos ultimos dias no
# motor de trailing/PARTIAL/EXIT, sensacao de "ainda toma stop loss cedo
# demais / perde dinheiro que deveria ter sido protegido" persiste. Dado
# real ja confirmado (extrato CoinEx, nao Supabase trade_outcomes que esta
# contaminado): 70 trades/10d, PnL total real = -$6.08 (quase neutro).
#
# Este diagnostico cruza, para cada trade FUTURES fechado via
# finished_type=stop_loss nos ultimos 14 dias, o log de decisao real do
# motor unificado (tabela manuheadfund.trailing_unified_shadow -- population
# real do cron a cada ciclo, NAO contaminada como trade_outcomes) na janela
# antes do fechamento: o motor chegou a ver sinal de reversao
# (reason contem "reversal"/"reversao") e o piso de lucro bloqueou
# (reason contem "piso" ou action=EXIT com pushed_live=false), ou o stop
# nunca chegou a apertar (nenhum unified_action=UPDATE relevante antes do
# fechamento)?
#
# Tambem separa trades ANTES vs DEPOIS do deploy dos fixes 64eba60/b12ac14
# (push 2026-09-03 22:23/22:29 -03:00 = 2026-09-04 01:23/01:29 UTC) para
# checar se o comportamento real mudou.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"

$windowStart = (Get-Date).ToUniversalTime().AddDays(-14)
$deployUtc = [datetime]::Parse("2026-09-04T01:23:00Z").ToUniversalTime()

Write-Host "=== DIAG STOP LOSS ROOT CAUSE (READ-ONLY) -- janela desde $($windowStart.ToString('yyyy-MM-dd HH:mm')) UTC ===" -ForegroundColor Cyan
Write-Host "Deploy fixes 64eba60/b12ac14: $($deployUtc.ToString('yyyy-MM-dd HH:mm')) UTC"
Write-Host ""

# ── [1] CoinEx direto: finished-position FUTURES com finished_type=stop_loss ──
Write-Host "[1] CoinEx direto -- finished-position FUTURES, finished_type=stop_loss" -ForegroundColor Yellow
$slTrades = @()
try {
    $futMarkets = @()
    $futPos = CoinEx-Get "/v2/futures/pending-position?market_type=FUTURES" -EA SilentlyContinue
    if ($futPos.code -eq 0) {
        $futMarkets = @($futPos.data | ForEach-Object { $_.market } | Select-Object -Unique)
    }
    # tambem inclui mercados sem posicao aberta agora mas que tiveram atividade recente --
    # usa a lista de trailing_unified_shadow como fonte adicional de mercados conhecidos
    try {
        $shadowMarketsAll = @(Get-StateRecords -Table "trailing_unified_shadow" -ErrorAction SilentlyContinue | ForEach-Object { $_.market } | Select-Object -Unique)
        $futMarkets = @($futMarkets + $shadowMarketsAll | Select-Object -Unique)
    } catch {}

    Write-Host "  Mercados verificados: $($futMarkets -join ', ')" -ForegroundColor White

    foreach ($mkt in $futMarkets) {
        try {
            $r = CoinEx-Get "/v2/futures/finished-position?market=$mkt&market_type=FUTURES&page=1&limit=50" -EA SilentlyContinue
            if ($r.code -eq 0 -and $r.data.Count -gt 0) {
                foreach ($p in $r.data) {
                    $updatedAt = try { [datetimeoffset]::FromUnixTimeMilliseconds([long]$p.updated_at).UtcDateTime } catch { $null }
                    if ($updatedAt -and $updatedAt -ge $windowStart -and "$($p.finished_type)" -eq "stop_loss") {
                        $slTrades += [PSCustomObject]@{
                            market       = $mkt
                            closed_at    = $updatedAt
                            side         = "$($p.side)"
                            realized_pnl = [double]$p.realized_pnl
                            post_deploy  = ($updatedAt -ge $deployUtc)
                        }
                    }
                }
            }
        } catch {
            Write-Host "  [$mkt] erro: $_" -ForegroundColor Red
        }
    }
    $slTrades = @($slTrades | Sort-Object closed_at)
    Write-Host "  Total stop_loss trades na janela: $($slTrades.Count)" -ForegroundColor White
    foreach ($t in $slTrades) {
        $tag = if ($t.post_deploy) { "POS-DEPLOY" } else { "pre-deploy" }
        Write-Host ("    [{0}] {1} {2} side={3} pnl=`${4} ({5})" -f $t.closed_at.ToString("yyyy-MM-dd HH:mm"), $t.market, $tag, $t.side, [Math]::Round($t.realized_pnl,2), $tag)
    }
} catch {
    Write-Host "  ERRO: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# ── [2] Para cada stop_loss trade, busca janela de trailing_unified_shadow ANTES do fechamento ──
Write-Host "[2] Cruzamento com trailing_unified_shadow (decisao real do motor por ciclo)" -ForegroundColor Yellow
$summary = @()
foreach ($t in $slTrades) {
    Write-Host ""
    Write-Host "  --- $($t.market) fechado $($t.closed_at.ToString('yyyy-MM-dd HH:mm')) UTC (pnl=`$$([Math]::Round($t.realized_pnl,2)), $(if ($t.post_deploy) {'POS-DEPLOY'} else {'pre-deploy'})) ---" -ForegroundColor White
    try {
        $rows = @(Get-StateRecords -Table "trailing_unified_shadow" -Filter @{ market = $t.market } -ErrorAction Stop)
        $rows = @($rows | Where-Object {
            try {
                $ts = [datetime]$_.ts
                $ts -le $t.closed_at -and $ts -ge $t.closed_at.AddHours(-12)
            } catch { $false }
        } | Sort-Object { [datetime]$_.ts })

        if ($rows.Count -eq 0) {
            Write-Host "    (nenhum registro shadow nas 12h antes do fechamento -- motor pode nao ter rodado ciclo pra essa posicao, ou dado nao persistiu)" -ForegroundColor DarkYellow
            $summary += [PSCustomObject]@{ market = $t.market; closed_at = $t.closed_at; post_deploy = $t.post_deploy; pnl = $t.realized_pnl; had_shadow_data = $false; saw_reversal_signal = $false; exit_recommended = $false; exit_pushed = $false; last_reason = "sem_dado_shadow" }
            continue
        }

        $sawReversal = $false
        $exitRecommended = $false
        $exitPushed = $false
        $lastReason = ""
        foreach ($row in $rows) {
            $reason = "$($row.reason)"
            $action = "$($row.unified_action)"
            $isReversalReason = ($reason -match "revers")
            if ($isReversalReason) { $sawReversal = $true }
            if ($action -eq "EXIT") { $exitRecommended = $true; if ($row.pushed_live -eq $true) { $exitPushed = $true } }
            $lastReason = $reason
            Write-Host ("    {0} action={1} reason={2} exhaustion={3} pushed_live={4}" -f ([datetime]$row.ts).ToString("HH:mm:ss"), $action, $reason, $row.exhaustion_score, $row.pushed_live)
        }

        Write-Host ("    RESUMO: {0} registros | viu_sinal_reversao={1} | EXIT_recomendado={2} | EXIT_executado={3} | ultimo_motivo={4}" -f $rows.Count, $sawReversal, $exitRecommended, $exitPushed, $lastReason) -ForegroundColor Cyan

        $summary += [PSCustomObject]@{
            market = $t.market; closed_at = $t.closed_at; post_deploy = $t.post_deploy; pnl = $t.realized_pnl
            had_shadow_data = $true; saw_reversal_signal = $sawReversal
            exit_recommended = $exitRecommended; exit_pushed = $exitPushed; last_reason = $lastReason
        }
    } catch {
        Write-Host "    ERRO lendo shadow: $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== SUMARIO GERAL ===" -ForegroundColor Cyan
Write-Host "Total stop_loss trades (14d): $($slTrades.Count)"
$pre = @($summary | Where-Object { -not $_.post_deploy })
$post = @($summary | Where-Object { $_.post_deploy })
Write-Host "  Pre-deploy (antes de 2026-09-04 01:23 UTC): $($pre.Count)"
Write-Host "  Pos-deploy: $($post.Count)"
Write-Host ""
Write-Host "Trades COM dado shadow (motor rodou ciclo antes do stop): $($summary | Where-Object { $_.had_shadow_data } | Measure-Object | Select-Object -ExpandProperty Count)"
Write-Host "Trades SEM dado shadow (motor nunca viu essa posicao antes do stop -- gap real de cobertura): $($summary | Where-Object { -not $_.had_shadow_data } | Measure-Object | Select-Object -ExpandProperty Count)"
Write-Host ""
Write-Host "Trades onde o motor VIU sinal de reversao mas o stop ainda assim disparou: $($summary | Where-Object { $_.saw_reversal_signal } | Measure-Object | Select-Object -ExpandProperty Count)"
Write-Host "  -- destes, quantos tiveram EXIT recomendado mas NAO executado (pushed_live=false): $($summary | Where-Object { $_.saw_reversal_signal -and $_.exit_recommended -and -not $_.exit_pushed } | Measure-Object | Select-Object -ExpandProperty Count)"
Write-Host ""
foreach ($s in $summary) {
    Write-Host ("  {0} | {1} | pnl=`${2} | shadow={3} | reversal_visto={4} | exit_reco={5} | exit_exec={6} | motivo={7}" -f `
        $s.market, $(if($s.post_deploy){"POS"}else{"PRE"}), [Math]::Round($s.pnl,2), $s.had_shadow_data, $s.saw_reversal_signal, $s.exit_recommended, $s.exit_pushed, $s.last_reason)
}
Write-Host ""
Write-Host "=== FIM DIAG ===" -ForegroundColor Cyan
