# diag_stopcurrent_negative_timeline_2026_08_06.ps1 -- ONE-SHOT, so leitura.
#
# Owner pediu causa raiz de verdade do stopCurrent negativo (-129.77
# SOONUSDT, -129.98 PIPPINUSDT) achado em trailing_state. Investigacao ate
# aqui NAO achou nenhuma formula que produza numero negativo com dado
# realista (Get-TrailingNewStop, Update-TrailingPeakLive, Get-
# RegimeAdjustedTrailingStop -- todos multiplicam peak/entry por fator
# positivo). trailing_unified_shadow (Save-StateRecords, trailing_stop_
# monitor.ps1 linha ~382) grava HISTORICO de todo ciclo do motor unificado
# por market -- puxa a timeline completa pra achar o EXATO ciclo/valor que
# introduziu o numero negativo, em vez de continuar adivinhando formula.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"

Write-Host "=== DIAG: timeline real de stopCurrent (trailing_unified_shadow) ===" -ForegroundColor Cyan

$cfg = Get-SupabaseRequestHeaders -Method "GET"
foreach ($mkt in @("SOONUSDT", "PIPPINUSDT")) {
    try {
        $uri = "$($cfg.url)/rest/v1/trailing_unified_shadow?select=*&market=eq.$mkt&order=ts.asc&limit=200"
        $rows = @(Invoke-RestMethod -Uri $uri -Method GET -Headers $cfg.headers -TimeoutSec 30)
        Write-Host "--- $mkt : $($rows.Count) registros de ciclo (RAW, sem conversao) ---" -ForegroundColor Yellow
        foreach ($r in $rows) {
            $r | ConvertTo-Json -Depth 6 -Compress | Write-Host
        }
        Write-Host ""
    } catch {
        Write-Host "  ERRO em ${mkt}: $_" -ForegroundColor Red
    }
}

Write-Host "=== FIM DIAG ===" -ForegroundColor Cyan
