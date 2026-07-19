# diag_real_edge_readonly_2026_07_19.ps1 -- diagnostico ONE-SHOT, so leitura
# Pergunta unica e honesta: com os dados que o sistema JA coletou (nao
# estimativa, nao backtest), existe edge estatistico real hoje?
#
# NAO envia ordem, NAO altera nenhum estado. So consulta Supabase (fonte de
# verdade -- journal/*.jsonl local nao reflete mais a nuvem desde a migracao
# para GitHub Actions; local tambem nao tem credenciais reais por design) e
# calcula:
#   [1] trade_outcomes reais (win rate, PnL, por sinal/direcao) -- o que
#       realmente aconteceu com capital de verdade.
#   [2] gate_replay_study -- o que teria acontecido nos candidatos que
#       passaram e nos que foram bloqueados (LONG+SHORT, horizontes curtos).
#   [3] mce_counterfactual_agg -- mesma pergunta, agregada por regime|direction
#       (sinais que o sistema pulou via gate, ja calculado por outro job).
#
# Amostra pequena (n<30) e' sinalizada explicitamente -- nao existe "edge
# confirmado" com poucos trades, so hipotese ainda nao refutada.

$agentsDir = Join-Path $PSScriptRoot ".." "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

function Write-SampleWarning($n) {
    if ($n -lt 10) {
        Write-Host "    [AMOSTRA MUITO PEQUENA n=$n -- nao da pra concluir nada, so olhar]" -ForegroundColor Red
    } elseif ($n -lt 30) {
        Write-Host "    [AMOSTRA PEQUENA n=$n -- hipotese, nao conclusao estatistica]" -ForegroundColor DarkYellow
    }
}

Write-Host "=== DIAG EDGE REAL (READ-ONLY) -- fonte: Supabase, nao journal local ===" -ForegroundColor Cyan
Write-Host ""

# === [1] trade_outcomes: o que REALMENTE aconteceu com capital real ===
Write-Host "[1] trade_outcomes (trades reais fechados, capital de verdade)" -ForegroundColor Yellow
try {
    $trades = @(Get-StateRecords -Table "trade_outcomes" -ErrorAction Stop)
    $closed = @($trades | Where-Object { $_.PSObject.Properties['pnl_pct'] -and $null -ne $_.pnl_pct })
    Write-Host "  Total registros: $($trades.Count) | Fechados com PnL: $($closed.Count)" -ForegroundColor White
    Write-SampleWarning $closed.Count

    if ($closed.Count -gt 0) {
        $wins = @($closed | Where-Object { [double]$_.pnl_pct -gt 0 })
        $winRate = [Math]::Round(($wins.Count / $closed.Count) * 100, 1)
        $totalPnlPct = ($closed | ForEach-Object { [double]$_.pnl_pct } | Measure-Object -Sum).Sum
        $avgPnlPct = [Math]::Round($totalPnlPct / $closed.Count, 3)
        Write-Host "  Win rate GLOBAL: $winRate% ($($wins.Count)/$($closed.Count)) | PnL medio/trade: $avgPnlPct%" -ForegroundColor White

        Write-Host ""
        Write-Host "  Por sinal/origem:" -ForegroundColor White
        $bySignal = $closed | Group-Object -Property { if ($_.PSObject.Properties['source']) { "$($_.source)" } else { "desconhecido" } }
        foreach ($g in ($bySignal | Sort-Object Count -Descending)) {
            $gw = @($g.Group | Where-Object { [double]$_.pnl_pct -gt 0 })
            $gwr = if ($g.Count -gt 0) { [Math]::Round(($gw.Count / $g.Count) * 100, 1) } else { 0 }
            $gpnl = [Math]::Round((($g.Group | ForEach-Object { [double]$_.pnl_pct } | Measure-Object -Sum).Sum), 2)
            Write-Host "    $($g.Name): n=$($g.Count) win_rate=$gwr% pnl_total=$gpnl%"
            Write-SampleWarning $g.Count
        }

        Write-Host ""
        Write-Host "  Por direcao:" -ForegroundColor White
        $byDir = $closed | Group-Object -Property { if ($_.PSObject.Properties['direction']) { "$($_.direction)" } else { "desconhecido" } }
        foreach ($g in ($byDir | Sort-Object Count -Descending)) {
            $gw = @($g.Group | Where-Object { [double]$_.pnl_pct -gt 0 })
            $gwr = if ($g.Count -gt 0) { [Math]::Round(($gw.Count / $g.Count) * 100, 1) } else { 0 }
            Write-Host "    $($g.Name): n=$($g.Count) win_rate=$gwr%"
        }
    } else {
        Write-Host "  (nenhum trade fechado com PnL registrado)" -ForegroundColor DarkYellow
    }
} catch {
    Write-Host "  ERRO: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# === [2] gate_replay_study: "e se tivesse entrado?" amostra ampla LONG+SHORT ===
Write-Host "[2] gate_replay_study (o que teria acontecido -- passou vs bloqueado, 10min-4h)" -ForegroundColor Yellow
try {
    $grs = @(Get-StateRecords -Table "gate_replay_study" -ErrorAction Stop)
    Write-Host "  Total registros: $($grs.Count)" -ForegroundColor White
    Write-SampleWarning $grs.Count

    if ($grs.Count -gt 0) {
        $withReturns = @($grs | Where-Object { $_.returns -and $_.returns.PSObject.Properties['4h'] -and $null -ne $_.returns.'4h' })
        Write-Host "  Com retorno 4h ja resolvido: $($withReturns.Count)" -ForegroundColor White

        if ($withReturns.Count -gt 0) {
            $passed = @($withReturns | Where-Object { $_.would_pass -eq $true })
            $blocked = @($withReturns | Where-Object { $_.would_pass -eq $false })

            if ($passed.Count -gt 0) {
                $passedAvg = [Math]::Round((($passed | ForEach-Object { [double]$_.returns.'4h' } | Measure-Object -Average).Average), 2)
                $passedWin = @($passed | Where-Object { [double]$_.returns.'4h' -gt 0 })
                $passedWinRate = [Math]::Round(($passedWin.Count / $passed.Count) * 100, 1)
                Write-Host "    PASSOU nas gates: n=$($passed.Count) win_rate_4h=$passedWinRate% retorno_medio_4h=$passedAvg%"
                Write-SampleWarning $passed.Count
            }
            if ($blocked.Count -gt 0) {
                $blockedAvg = [Math]::Round((($blocked | ForEach-Object { [double]$_.returns.'4h' } | Measure-Object -Average).Average), 2)
                $blockedWin = @($blocked | Where-Object { [double]$_.returns.'4h' -gt 0 })
                $blockedWinRate = [Math]::Round(($blockedWin.Count / $blocked.Count) * 100, 1)
                Write-Host "    BLOQUEADO pelas gates: n=$($blocked.Count) win_rate_4h=$blockedWinRate% retorno_medio_4h=$blockedAvg%"
                Write-SampleWarning $blocked.Count
                if ($blockedAvg -gt 0 -and $blocked.Count -ge 30) {
                    Write-Host "    [ATENCAO: bloqueados teriam retorno medio positivo -- gate pode estar rejeitando edge real]" -ForegroundColor Red
                }
            }
        } else {
            Write-Host "  (nenhum registro com horizonte 4h ja resolvido -- estudo ainda maturando)" -ForegroundColor DarkYellow
        }
    }
} catch {
    Write-Host "  ERRO ou tabela ausente: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# === [3] mce_counterfactual_agg: mesma pergunta, agregada por regime|direction ===
Write-Host "[3] mce_counterfactual_agg (sinais pulados via gate, agregado regime|direction)" -ForegroundColor Yellow
try {
    $cf = @(Get-StateRecords -Table "mce_counterfactual_agg" -ErrorAction Stop)
    if ($cf.Count -eq 0) {
        Write-Host "  (vazio -- sem dados ainda)" -ForegroundColor DarkYellow
    } else {
        $cf | Sort-Object -Property n -Descending | ForEach-Object {
            $hr = if ($_.hit_rate) { [Math]::Round([double]$_.hit_rate * 100, 1) } else { 0 }
            $f24 = if ($_.avg_fwd_24h) { [Math]::Round([double]$_.avg_fwd_24h, 2) } else { 0 }
            Write-Host "  $($_.group): n=$($_.n) hit_rate=$hr% avg_fwd_24h=$f24%"
            Write-SampleWarning $_.n
        }
    }
} catch {
    Write-Host "  ERRO: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== CONCLUSAO HONESTA ===" -ForegroundColor Cyan
Write-Host "Este script NAO decide 'tem edge ou nao' por voce -- ele so mostra o numero real." -ForegroundColor White
Write-Host "Regra pratica (Lopez de Prado / mesa quant): amostra n<30 por grupo = hipotese," -ForegroundColor White
Write-Host "nao conclusao. Sharpe/win-rate calculado com poucos trades tem erro padrao enorme --" -ForegroundColor White
Write-Host "um win rate de 60% com n=8 e estatisticamente indistinguivel de 40%." -ForegroundColor White
Write-Host "=== FIM DIAG ===" -ForegroundColor Cyan
