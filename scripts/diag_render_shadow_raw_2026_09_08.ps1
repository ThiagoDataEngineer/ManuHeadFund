# diag_render_shadow_raw_2026_09_08.ps1 -- ONE-SHOT, so leitura.
# Segue diag_stoploss_rootcause_2026_09_08.ps1: RENDERUSDT teve EXIT
# recomendado repetidamente (reason="policy_runner_..." -- texto de
# SELECAO de politica, nao de gatilho) por 8h+ sem nunca executar
# (pushed_live sempre False na tabela trailing_unified_shadow), mas o
# job "Trailing Stop Monitor" do GitHub Actions nao mostra RENDERUSDT
# nos runs amostrados nesse periodo -- suspeita de outro job escrevendo
# a tabela, ou tick paralelo nao encontrado na amostra. Dump raw de TODOS
# os campos das linhas RENDERUSDT no dia 09-04 pra decidir.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")
$env:STATE_STORE_SCHEMA = "manuheadfund"

$rows = @(Get-StateRecords -Table "trailing_unified_shadow" -Filter @{ market = "RENDERUSDT" } -ErrorAction Stop)
$rows = @($rows | Where-Object {
    try { ([datetime]$_.ts) -ge [datetime]"2026-09-04T00:00:00Z" -and ([datetime]$_.ts) -le [datetime]"2026-09-04T23:59:59Z" } catch { $false }
} | Sort-Object { [datetime]$_.ts })

Write-Host "Total rows RENDERUSDT 2026-09-04: $($rows.Count)"
foreach ($r in $rows) {
    Write-Host ($r | ConvertTo-Json -Compress -Depth 5)
}
