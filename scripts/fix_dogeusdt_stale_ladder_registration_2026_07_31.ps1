# fix_dogeusdt_stale_ladder_registration_2026_07_31.ps1 -- ONE-SHOT.
#
# Register-PartialExitLadder so grava em manuheadfund.partial_exit_ladders
# no caminho de sucesso real (pelo menos 1 nivel do ladder aceito pela
# CoinEx) -- em producao normal (ciclo de 5min do cron) isso nunca duplica.
# As MULTIPLAS linhas active=true encontradas pra DOGEUSDT nesta sessao
# vieram de triggers MANUAIS repetidos (workflow_dispatch) rodados de
# perto um do outro durante a investigacao do bug de ancoragem (commit
# fea429c) -- nao e um bug recorrente do fluxo normal.
#
# Este script desativa (active=false, NAO deleta -- mantem historico)
# TODAS as linhas active=true pra DOGEUSDT, deixando o proximo ciclo
# tentar de novo do zero com o fix ja aplicado.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"
$MKT = "DOGEUSDT"

Write-Host "=== FIX: desativa TODAS as linhas active=true de partial_exit_ladders ($MKT) ===" -ForegroundColor Cyan

$rows = @(Get-StateRecords -Table "partial_exit_ladders" -Filter @{ market = $MKT })
Write-Host "Linhas encontradas: $($rows.Count)"
foreach ($r in $rows) {
    Write-Host ("  id={0} active={1} registered_at={2}" -f $r.id, $r.active, $r.registered_at)
}

$activeRows = @($rows | Where-Object { $_.active -eq $true })
if ($activeRows.Count -eq 0) {
    Write-Host "Nenhuma linha active=true -- nada a fazer." -ForegroundColor Yellow
    exit 0
}

Write-Host "`nDesativando $($activeRows.Count) linha(s) active=true..." -ForegroundColor Yellow
foreach ($r in $activeRows) {
    $updated = [PSCustomObject]@{
        id            = $r.id
        market        = $r.market
        active        = $false
        registered_at = $r.registered_at
        levels_json   = $r.levels_json
    }
    Save-StateRecords -Table "partial_exit_ladders" -Records @($updated) -PrimaryKey "id" | Out-Null
    Write-Host "Desativado id=$($r.id)" -ForegroundColor Green
}

Write-Host "`n--- Confirmando estado final ---" -ForegroundColor Yellow
$rowsAfter = @(Get-StateRecords -Table "partial_exit_ladders" -Filter @{ market = $MKT })
foreach ($r in $rowsAfter) {
    Write-Host ("  id={0} active={1} registered_at={2}" -f $r.id, $r.active, $r.registered_at)
}
$stillActive = @($rowsAfter | Where-Object { $_.active -eq $true })
if ($stillActive.Count -gt 0) {
    Write-Host "AVISO: ainda ha $($stillActive.Count) linha(s) active=true apos o fix -- upsert pode nao estar funcionando (on_conflict=id)." -ForegroundColor Red
} else {
    Write-Host "Confirmado: zero linhas active=true pra $MKT." -ForegroundColor Green
}

Write-Host "`n=== FIM ===" -ForegroundColor Cyan
