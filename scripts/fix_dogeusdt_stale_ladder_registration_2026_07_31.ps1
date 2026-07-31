# fix_dogeusdt_stale_ladder_registration_2026_07_31.ps1 -- ONE-SHOT.
#
# Register-PartialExitLadder registrou DOGEUSDT como "ja registrado"
# (manuheadfund.partial_exit_ladders, active=true) num ciclo em que o
# ladder na verdade FALHOU na corretora (ambos os niveis rejeitados com
# code=3137, bug corrigido no commit fea429c -- ancoragem no preco atual).
# Como a idempotencia usa esse registro, o motor corrigido nunca vai
# tentar de novo pra DOGEUSDT enquanto essa linha continuar active=true.
# Este script desativa (active=false, NAO deleta -- mantem historico) a
# linha existente pra DOGEUSDT, permitindo o proximo ciclo tentar de novo
# com o fix ja aplicado.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"
$MKT = "DOGEUSDT"

Write-Host "=== FIX: desativa registro stale de partial_exit_ladders ($MKT) ===" -ForegroundColor Cyan

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

Write-Host "`n=== FIM ===" -ForegroundColor Cyan
