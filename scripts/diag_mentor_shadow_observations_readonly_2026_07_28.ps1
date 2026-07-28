# diag_mentor_shadow_observations_readonly_2026_07_28.ps1 -- diagnostico ONE-SHOT, so leitura
# Owner quer confirmar se mentor_shadow_observations (tabela criada 2026-07-27,
# commit 13eaeab) ja esta acumulando dado real -- Invoke-MentorShadowObservation
# so persiste quando journal/MENTOR_SHADOW_ENABLED.flag existe (gated, opt-in).

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

Write-Host "=== DIAG MENTOR_SHADOW_OBSERVATIONS (READ-ONLY) ===" -ForegroundColor Cyan
try {
    $rows = @(Get-StateRecords -Table "mentor_shadow_observations")
    Write-Host "Total: $($rows.Count)" -ForegroundColor Green
    if ($rows.Count -gt 0) {
        $sorted = $rows | Sort-Object { try { [datetime]$_.ts_utc } catch { [datetime]::MinValue } }
        foreach ($r in ($sorted | Select-Object -Last 15)) {
            Write-Host "  ts=$($r.ts_utc) market=$($r.market) dir=$($r.real_direction) llm_decision=$($r.llm_decision) confidence=$($r.mentor_confidence) agrees=$($r.agrees_with_real)"
        }
    } else {
        Write-Host "Vazio -- ou MENTOR_SHADOW_ENABLED.flag ausente (gate opt-in), ou nenhum ciclo chamou Invoke-MentorShadowObservation ainda." -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERRO: $_" -ForegroundColor Red
}

Write-Host "`n--- Flag MENTOR_SHADOW_ENABLED presente no runner atual? ---" -ForegroundColor Cyan
$flagPath = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) "journal") "MENTOR_SHADOW_ENABLED.flag"
Write-Host "  $flagPath -- existe: $(Test-Path $flagPath)"
Write-Host "=== FIM ===" -ForegroundColor Cyan
