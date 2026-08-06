# cleanup_stale_partial_exit_ladders_2026_08_06.ps1 -- ONE-SHOT.
#
# Fix de raiz (commit desta sessao): Close-TrailingPosition agora chama
# Remove-PartialExitLadder ao fechar, entao ISSO SO PREVINE registros
# fantasma NOVOS a partir de agora. Registros JA existentes de posicoes que
# fecharam ANTES desse fix (ex: ARBUSDT registrado em 2026-07-31 20:12:57,
# posicao real ja fechou, mas uma posicao NOVA no mesmo market aberta em
# 2026-08-04 herdou o bloqueio "already_registered" -- confirmado via
# diag_partial_ladder_reality_check_2026_08_06.ps1) continuam active=true
# pra sempre sem esse cleanup manual.
#
# Estrategia: para cada market com linha active=true em partial_exit_ladders,
# consulta a posicao REAL na CoinEx. Se a posicao ainda existe (open_interest
# > 0) E a posicao no journal (trailing_state) tem um take_profit_list REAL
# com mais de 1 nivel, o registro provavelmente e legitimo -- mantem. Caso
# contrario (posicao fechada, ou so tem o TP unico de sempre = ladder nunca
# realmente pegou), desativa o registro pra o proximo ciclo tentar de novo
# do zero com o fix ja aplicado.
#
# NAO deleta nada -- so active=false (mesmo padrao ja usado em
# fix_dogeusdt_stale_ladder_registration_2026_07_31.ps1).
#
# Uso: -DryRun (default $true) so mostra o que faria, sem escrever.
#      -DryRun:$false aplica de verdade.

param(
    [bool] $DryRun = $true
)

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"

Write-Host "=== CLEANUP: registros fantasma em partial_exit_ladders (DryRun=$DryRun) ===" -ForegroundColor Cyan

$allRows = @(Get-StateRecords -Table "partial_exit_ladders")
$activeRows = @($allRows | Where-Object { $_.active -eq $true })
Write-Host "Linhas active=true encontradas: $($activeRows.Count)"

if ($activeRows.Count -eq 0) {
    Write-Host "Nada a fazer." -ForegroundColor Yellow
    exit 0
}

$markets = @($activeRows | Select-Object -ExpandProperty market -Unique)
$toDeactivate = @()

foreach ($mkt in $markets) {
    Write-Host "--- $mkt ---" -ForegroundColor Yellow
    $rowsForMarket = @($activeRows | Where-Object { $_.market -eq $mkt })
    Write-Host "  linhas active=true: $($rowsForMarket.Count)"

    $realPos = $null
    try {
        $realPos = @(CoinEx-GetPendingPositions -Market $mkt) | Select-Object -First 1
    } catch {
        Write-Host "  ERRO ao consultar posicao real: $_ -- trata como fechada (fail-safe: desativa)" -ForegroundColor Red
    }

    $hasOpenInterest = $realPos -and [double]$realPos.open_interest -gt 0
    if (-not $hasOpenInterest) {
        Write-Host "  Posicao FECHADA na corretora -- registro fantasma, desativando." -ForegroundColor Red
        $toDeactivate += $rowsForMarket
        continue
    }

    $tpList = if ($realPos.PSObject.Properties['take_profit_list']) { @($realPos.take_profit_list) } else { @() }
    $hasRealLadder = $tpList.Count -gt 1 -or ($tpList.Count -eq 1 -and $tpList[0].is_all -ne $true)
    if ($hasRealLadder) {
        Write-Host "  Posicao aberta COM ladder real na corretora ($($tpList.Count) niveis) -- mantendo registro." -ForegroundColor Green
    } else {
        Write-Host "  Posicao aberta mas SO TEM TP unico (is_all=true) -- ladder nunca pegou de verdade, desativando pra retry." -ForegroundColor Red
        $toDeactivate += $rowsForMarket
    }
}

if ($toDeactivate.Count -eq 0) {
    Write-Host "`nNenhum registro fantasma confirmado -- nada desativado." -ForegroundColor Green
    exit 0
}

if ($DryRun) {
    Write-Host "`nDRY RUN -- $($toDeactivate.Count) linha(s) seriam desativadas, nenhuma escrita feita. Rode com -DryRun:`$false pra aplicar." -ForegroundColor Yellow
    foreach ($r in $toDeactivate) {
        Write-Host "  [DESATIVARIA] id=$($r.id) market=$($r.market) registered_at=$($r.registered_at)"
    }
    Write-Host "`n=== FIM CLEANUP (dry run) ===" -ForegroundColor Cyan
    exit 0
}

Write-Host "`nDesativando $($toDeactivate.Count) linha(s)..." -ForegroundColor Yellow
foreach ($r in $toDeactivate) {
    $updated = [PSCustomObject]@{
        id            = $r.id
        market        = $r.market
        active        = $false
        registered_at = $r.registered_at
        levels_json   = $r.levels_json
    }
    try {
        Save-StateRecords -Table "partial_exit_ladders" -Records @($updated) -PrimaryKey "id" | Out-Null
        Write-Host "  Desativado id=$($r.id) market=$($r.market)" -ForegroundColor Green
    } catch {
        Write-Host "  FALHOU id=$($r.id) market=$($r.market): $_" -ForegroundColor Red
    }
}

Write-Host "`n--- Confirmando estado final ---" -ForegroundColor Yellow
$rowsAfter = @(Get-StateRecords -Table "partial_exit_ladders")
$stillActive = @($rowsAfter | Where-Object { $_.active -eq $true })
Write-Host "Linhas active=true restantes: $($stillActive.Count)"
foreach ($r in $stillActive) {
    Write-Host "  id=$($r.id) market=$($r.market) registered_at=$($r.registered_at)"
}

Write-Host "`n=== FIM CLEANUP ===" -ForegroundColor Cyan
