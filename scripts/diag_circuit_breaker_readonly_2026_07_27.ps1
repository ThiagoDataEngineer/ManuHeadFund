# diag_circuit_breaker_readonly_2026_07_27.ps1 -- diagnostico ONE-SHOT, so leitura
# Owner reportou "perdendo movimentos". Gem Scanner+Executor run 30272500456
# mostrou 11/11 candidatos bloqueados por circuit_breaker_daily_loss (-2%
# diario), mas diag_full_audit_readonly (mesmo dia) mostrou trade_outcomes
# ultimas 48h = 0. Contradicao: se nao fechou trade hoje, PnL diario deveria
# ser 0, nao negativo o bastante pra disparar -2%. Este script inspeciona
# exatamente quais registros Get-DailyPnL esta somando e por que.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")
. (Join-Path $agentsDir "lib_circuit_breaker_simple.ps1")

Write-Host "=== DIAG CIRCUIT BREAKER (READ-ONLY) ===" -ForegroundColor Cyan
Write-Host "Hoje (Get-Date .Date, local do runner): $((Get-Date).Date)" -ForegroundColor Cyan
Write-Host "Hoje UTC: $((Get-Date).ToUniversalTime().Date)" -ForegroundColor Cyan

try {
    $records = @(Get-StateRecords -Table "trade_outcomes" -Filter @{ status = "closed" } -ErrorAction Stop)
    Write-Host "Total registros status=closed: $($records.Count)" -ForegroundColor Green

    $today = (Get-Date).Date
    $sumToday = 0.0
    foreach ($obj in $records) {
        $exitRaw = if ($obj.exit_date) { $obj.exit_date } elseif ($obj.updated_at) { $obj.updated_at } else { $null }
        if (-not $exitRaw) {
            Write-Host "  market=$($obj.market) SEM exit_date/updated_at -- pulado" -ForegroundColor DarkGray
            continue
        }
        try {
            $exitDate = if ($exitRaw -is [datetime]) { $exitRaw.Date } else { ([datetime]::Parse([string]$exitRaw)).Date }
            $pnlField = if ($null -ne $obj.pnl_realized) { $obj.pnl_realized } else { $obj.pnl_usd }
            $isToday = ($exitDate -eq $today)
            if ($isToday) { $sumToday += [double]$pnlField }
            $marker = if ($isToday) { ">>> CONTA HOJE <<<" } else { "" }
            Write-Host ("  market={0} exit_raw={1} exit_date={2} pnl={3} {4}" -f $obj.market, $exitRaw, $exitDate, $pnlField, $marker)
        } catch {
            Write-Host "  ERRO parse: exit_raw=$exitRaw -- $_" -ForegroundColor Red
        }
    }
    Write-Host "`nSoma manual (mesma logica de Get-DailyPnL): $sumToday" -ForegroundColor Yellow
} catch {
    Write-Host "ERRO ao consultar trade_outcomes: $_" -ForegroundColor Red
}

$pnl = Get-DailyPnL
Write-Host "`nGet-DailyPnL() resultado real: $pnl" -ForegroundColor Yellow
Write-Host "Capital global (CAPITAL_TOTAL): $($global:CAPITAL_TOTAL)"
$threshold = if ($global:CAPITAL_TOTAL) { $global:CAPITAL_TOTAL * -0.02 } else { "N/A (CAPITAL_TOTAL nao setado)" }
Write-Host "Threshold -2%: $threshold"
Write-Host "Test-CircuitBreakerTriggered: $(Test-CircuitBreakerTriggered -Capital $global:CAPITAL_TOTAL -DailyLossThreshold -0.02)"
Write-Host "=== FIM DIAG ===" -ForegroundColor Cyan
