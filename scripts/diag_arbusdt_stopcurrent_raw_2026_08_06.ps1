# diag_arbusdt_stopcurrent_raw_2026_08_06.ps1 -- ONE-SHOT, so leitura direta.
#
# Confirma o valor CRU real de stopCurrent no Supabase agora, sem nenhuma
# outra logica no meio -- investigando por que a reconciliacao parece
# nao persistir (dispara de novo no ciclo seguinte).

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"

Write-Host "=== DIAG: stopCurrent CRU de ARBUSDT no Supabase agora ===" -ForegroundColor Cyan

$cfg = Get-SupabaseRequestHeaders -Method "GET"
$uri = "$($cfg.url)/rest/v1/trailing_state?select=*&market=eq.ARBUSDT&active=eq.true"
$rows = @(Invoke-RestMethod -Uri $uri -Method GET -Headers $cfg.headers -TimeoutSec 30)
Write-Host "Registros encontrados: $($rows.Count)"
foreach ($r in $rows) {
    Write-Host "pk_id=$($r.pk_id) stopCurrent=$($r.stopCurrent) updatedAt=$($r.updatedAt)"
    $r | ConvertTo-Json -Compress -Depth 5 | Write-Host
}

Write-Host "`n=== FIM DIAG ===" -ForegroundColor Cyan
