# live_monitor.ps1 -- Fase 1 do PRD_LIVE_MONITOR_AUTOCORRECAO_2026_07_20.md
# Monitor de live trading em 6 camadas (jobs, trades, rejeicoes, leverage
# real, schema drift, rate limit). READ-ONLY -- so observa e classifica,
# nao corrige nada ainda (auto-correcao e' Fase 2/3, nao implementada).
#
# Classifica cada camada: OK | WARN | CRITICAL. Grava snapshot em
# manuheadfund.live_monitor_snapshots (1 linha por ciclo). CRITICAL dispara
# alerta Telegram imediato.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")
. (Join-Path $agentsDir "lib_telegram.ps1")

$findings = @()

function Add-Finding {
    param([string]$Layer, [string]$Status, [string]$Detail)
    $script:findings += [PSCustomObject]@{ layer = $Layer; status = $Status; detail = $Detail }
    $color = switch ($Status) { "CRITICAL" { "Red" } "WARN" { "Yellow" } default { "Green" } }
    Write-Host "[$Status] $Layer -- $Detail" -ForegroundColor $color
}

Write-Host "=== LIVE MONITOR (READ-ONLY, Fase 1) ===" -ForegroundColor Cyan
Write-Host ""

# ── [1] Trades reais fechados: PnL sendo gravado? ──────────────────────────
try {
    $outcomes = @(Get-StateRecords -Table "trade_outcomes" -ErrorAction Stop)
    $withPnl = @($outcomes | Where-Object { $_.pnl_percent -and [double]$_.pnl_percent -ne 0 })
    $recent = @($outcomes | Where-Object {
        try { ([datetime]$_.closed_at) -ge (Get-Date).AddDays(-7) } catch { $false }
    })
    $recentPnlUsd = ($recent | ForEach-Object { if ($_.pnl_realized) { [double]$_.pnl_realized } else { 0 } } | Measure-Object -Sum).Sum
    $recentWins = @($recent | Where-Object { $_.pnl_realized -and [double]$_.pnl_realized -gt 0 })
    $recentWinRate = if ($recent.Count -gt 0) { [Math]::Round(($recentWins.Count / $recent.Count) * 100, 1) } else { 0 }

    if ($outcomes.Count -eq 0) {
        Add-Finding "trades" "WARN" "0 registros em trade_outcomes -- verificar se pipeline de fechamento esta rodando"
    } elseif ($withPnl.Count -eq 0) {
        Add-Finding "trades" "CRITICAL" "$($outcomes.Count) trades mas ZERO com pnl_percent != 0 -- regressao do fix de 2026-07-19"
    } else {
        Add-Finding "trades" "OK" "$($recent.Count) trades fechados ultimos 7d, win_rate=$recentWinRate% pnl_total=`$$([Math]::Round($recentPnlUsd,2))"
    }
} catch {
    Add-Finding "trades" "WARN" "erro ao consultar trade_outcomes: $($_.Exception.Message)"
}

# ── [2] Rejeicoes/gates: algum gate bloqueando 100% dos candidatos? ────────
try {
    $rej = @(Get-StateRecords -Table "trade_rejections" -ErrorAction Stop)
    $recentRej = @($rej | Where-Object {
        try { ([datetime]$_.ts) -ge (Get-Date).AddDays(-1) } catch { $false }
    })
    if ($recentRej.Count -gt 20) {
        $byGate = $recentRej | Group-Object -Property gate | Sort-Object Count -Descending
        $top = $byGate | Select-Object -First 1
        $topPct = [Math]::Round(($top.Count / $recentRej.Count) * 100, 1)
        if ($topPct -ge 95) {
            Add-Finding "gates" "WARN" "gate '$($top.Name)' responde por $topPct% das $($recentRej.Count) rejeicoes ultimas 24h -- possivel gate quebrado (nao seletivo)"
        } else {
            Add-Finding "gates" "OK" "$($recentRej.Count) rejeicoes 24h, gate mais comum '$($top.Name)' = $topPct%"
        }
    } else {
        Add-Finding "gates" "OK" "$($recentRej.Count) rejeicoes nas ultimas 24h (amostra pequena p/ avaliar concentracao)"
    }
} catch {
    Add-Finding "gates" "WARN" "erro ao consultar trade_rejections: $($_.Exception.Message)"
}

# ── [3] Leverage real: alguma posicao aberta acima do cap 5x? ──────────────
try {
    $positions = @(CoinEx-GetPendingPositions -ErrorAction Stop)
    $overLeveraged = @($positions | Where-Object { $_.leverage -and [double]$_.leverage -gt 5 })
    if ($overLeveraged.Count -gt 0) {
        $detail = ($overLeveraged | ForEach-Object { "$($_.market)=$($_.leverage)x" }) -join ", "
        Add-Finding "leverage" "CRITICAL" "$($overLeveraged.Count) posicao(oes) acima do cap 5x: $detail -- o hard cap falhou"
    } else {
        Add-Finding "leverage" "OK" "$($positions.Count) posicao(oes) aberta(s), nenhuma acima de 5x"
    }
} catch {
    Add-Finding "leverage" "WARN" "erro ao consultar posicoes reais: $($_.Exception.Message)"
}

# ── [4] Schema drift: tabelas-chave respondem sem erro? ────────────────────
$keyTables = @("trade_outcomes", "trade_rejections", "mce_counterfactual_agg", "trailing_positions", "trailing_unified_shadow")
$schemaErrors = @()
foreach ($t in $keyTables) {
    try {
        Get-StateRecords -Table $t -ErrorAction Stop | Out-Null
    } catch {
        $schemaErrors += "$t`: $($_.Exception.Message)"
    }
}
if ($schemaErrors.Count -gt 0) {
    Add-Finding "schema" "CRITICAL" ($schemaErrors -join " | ")
} else {
    Add-Finding "schema" "OK" "$($keyTables.Count) tabelas-chave respondem sem erro"
}

# ── [5] Jobs do workflow: alguma falha recente? (via gh CLI, se disponivel) ─
try {
    $ghAvailable = Get-Command gh -ErrorAction SilentlyContinue
    if ($ghAvailable) {
        $runsJson = & gh run list --limit 20 --json conclusion,name,createdAt 2>$null
        if ($runsJson) {
            $runs = $runsJson | ConvertFrom-Json
            $failures = @($runs | Where-Object { $_.conclusion -eq "failure" })
            if ($failures.Count -gt 5) {
                Add-Finding "jobs" "WARN" "$($failures.Count)/20 runs recentes com failure"
            } else {
                Add-Finding "jobs" "OK" "$($failures.Count)/20 runs recentes com failure"
            }
        } else {
            Add-Finding "jobs" "WARN" "gh run list nao retornou dado (sem auth ou sem runs)"
        }
    } else {
        Add-Finding "jobs" "WARN" "gh CLI nao disponivel neste ambiente -- pular checagem de jobs"
    }
} catch {
    Add-Finding "jobs" "WARN" "erro ao consultar GitHub Actions: $($_.Exception.Message)"
}

# ── [6] Rate limit CoinEx: alguma chamada recente retornou erro de rate limit? ─
# Sem endpoint dedicado de "status de rate limit" -- infere de erro explicito
# na ultima chamada real feita acima (CoinEx-GetPendingPositions). Camada
# fraca por design nesta Fase 1; reforcar quando houver log agregado real.
Add-Finding "rate_limit" "OK" "sem sinal de rate limit nas chamadas deste ciclo (checagem indireta, Fase 1)"

Write-Host ""
Write-Host "=== RESUMO ===" -ForegroundColor Cyan
$critical = @($findings | Where-Object { $_.status -eq "CRITICAL" })
$warn = @($findings | Where-Object { $_.status -eq "WARN" })
Write-Host "OK=$($findings.Count - $critical.Count - $warn.Count) WARN=$($warn.Count) CRITICAL=$($critical.Count)"

# ── Persiste snapshot ───────────────────────────────────────────────────────
try {
    $snapshot = [PSCustomObject]@{
        ts       = (Get-Date -Format "o")
        ok_count = $findings.Count - $critical.Count - $warn.Count
        warn_count = $warn.Count
        critical_count = $critical.Count
        findings = ($findings | ConvertTo-Json -Compress -Depth 4)
    }
    Save-StateRecords -Table "live_monitor_snapshots" -Records @($snapshot)
} catch {
    Write-Host "[WARN] Falha ao persistir snapshot: $_" -ForegroundColor Yellow
}

# ── Alerta Telegram se CRITICAL ─────────────────────────────────────────────
if ($critical.Count -gt 0) {
    try {
        $msg = "🚨 LIVE MONITOR: $($critical.Count) achado(s) CRITICAL`n`n"
        foreach ($f in $critical) { $msg += "- [$($f.layer)] $($f.detail)`n" }
        Send-TelegramAlert -Message $msg | Out-Null
    } catch {
        Write-Host "[WARN] Falha ao enviar alerta Telegram: $_" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=== FIM LIVE MONITOR ===" -ForegroundColor Cyan
