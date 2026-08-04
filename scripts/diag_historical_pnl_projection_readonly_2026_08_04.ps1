# diag_historical_pnl_projection_readonly_2026_08_04.ps1 -- ONE-SHOT, so leitura.
#
# Owner pediu projecao real de "quanto ganharemos" apos subir risco/trade
# de 3% pra 7% (Regra de Ouro #2, commit 4060d4e). Amostra de 5 posicoes
# abertas (2 dias) foi pequena demais pra estatistica confiavel -- este
# script puxa TODOS os trade_outcomes fechados reais (Supabase) pra
# calcular hit-rate e PnL medio por trade numa base maior, sem inventar
# numero.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

Write-Host "=== DIAG: historico real de trade_outcomes (hit-rate + PnL medio) ===" -ForegroundColor Cyan

try {
    $records = @(Get-StateRecords -Table "trade_outcomes" -Filter @{ status = "closed" } -ErrorAction Stop)
    Write-Host "Total trade_outcomes status=closed: $($records.Count)`n"

    if ($records.Count -eq 0) {
        Write-Host "Nenhum registro fechado -- sem base pra projecao." -ForegroundColor Yellow
        exit 0
    }

    $wins = @()
    $losses = @()
    $allPnlPct = @()
    $allPnlUsd = @()

    foreach ($r in $records) {
        $pnlUsd = if ($null -ne $r.pnl_realized) { [double]$r.pnl_realized } elseif ($null -ne $r.pnl_usd) { [double]$r.pnl_usd } else { $null }
        $pnlPct = if ($null -ne $r.pnl_percent) { [double]$r.pnl_percent } else { $null }
        if ($null -eq $pnlUsd) { continue }

        $allPnlUsd += $pnlUsd
        if ($null -ne $pnlPct) { $allPnlPct += $pnlPct }

        if ($pnlUsd -gt 0) { $wins += $pnlUsd } else { $losses += $pnlUsd }
    }

    $total = $allPnlUsd.Count
    $winCount = $wins.Count
    $lossCount = $losses.Count
    $hitRate = if ($total -gt 0) { ($winCount / $total) * 100 } else { 0 }
    $avgWin = if ($winCount -gt 0) { ($wins | Measure-Object -Sum).Sum / $winCount } else { 0 }
    $avgLoss = if ($lossCount -gt 0) { ($losses | Measure-Object -Sum).Sum / $lossCount } else { 0 }
    $avgPnlUsd = if ($total -gt 0) { ($allPnlUsd | Measure-Object -Sum).Sum / $total } else { 0 }
    $avgPnlPct = if ($allPnlPct.Count -gt 0) { ($allPnlPct | Measure-Object -Sum).Sum / $allPnlPct.Count } else { $null }
    $totalPnl = ($allPnlUsd | Measure-Object -Sum).Sum

    Write-Host "--- Estatisticas reais (todos os trades fechados) ---" -ForegroundColor Yellow
    Write-Host "Total trades com PnL valido: $total"
    Write-Host "Wins: $winCount | Losses: $lossCount | Hit rate: $([math]::Round($hitRate,2))%"
    Write-Host "PnL medio por win: `$$([math]::Round($avgWin,2))"
    Write-Host "PnL medio por loss: `$$([math]::Round($avgLoss,2))"
    Write-Host "PnL medio por trade (todos): `$$([math]::Round($avgPnlUsd,2))"
    if ($null -ne $avgPnlPct) { Write-Host "PnL medio percentual por trade: $([math]::Round($avgPnlPct,3))%" }
    Write-Host "PnL total acumulado (soma de tudo): `$$([math]::Round($totalPnl,2))"

    # Data range
    $withDates = @($records | Where-Object { $_.exit_date -or $_.updated_at } | ForEach-Object {
        $raw = if ($_.exit_date) { $_.exit_date } else { $_.updated_at }
        try { if ($raw -is [datetime]) { $raw } else { [datetime]::Parse([string]$raw) } } catch { $null }
    } | Where-Object { $_ })
    if ($withDates.Count -gt 0) {
        $minDate = ($withDates | Measure-Object -Minimum).Minimum
        $maxDate = ($withDates | Measure-Object -Maximum).Maximum
        $spanDays = [math]::Max(1, ($maxDate - $minDate).TotalDays)
        Write-Host "`nPeriodo coberto: $minDate ate $maxDate ($([math]::Round($spanDays,1)) dias)"
        Write-Host "Trades por dia (media): $([math]::Round($total / $spanDays, 2))"
        Write-Host "PnL medio por dia (base historica real, ANTES do sizing 7%): `$$([math]::Round($totalPnl / $spanDays, 2))"
    }

} catch {
    Write-Host "ERRO ao consultar trade_outcomes: $_" -ForegroundColor Red
}

Write-Host "`n=== FIM DIAG ===" -ForegroundColor Cyan
