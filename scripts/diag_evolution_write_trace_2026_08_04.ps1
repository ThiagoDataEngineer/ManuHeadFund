# diag_evolution_write_trace_2026_08_04.ps1 -- ONE-SHOT, so leitura + 1 escrita de teste isolada.
#
# Achado: evolution_history mostra 41x a mesma proposta "sentinel_move_pct:
# 3.25 -> 3", mas evolution_params.current sempre le de volta 3.25 -- ou o
# write do singleton nao esta persistindo o campo, ou Test-AntiOscillation
# nunca engata (historico local nao sobrevive entre runs do cloud) e cada
# ciclo recalcula do zero a partir de 3.25 sem nunca ver o "3" anterior.
# Este script roda o MESMO fluxo do Invoke-EvolutionCycle real (sem
# -DryRun, mas escrevendo em singleton de teste separado pra nao afetar
# producao) pra ver exatamente onde o valor se perde.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")
. (Join-Path $agentsDir "lib_evolution_engine.ps1")
. (Join-Path $agentsDir "lib_direction_learning.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"

Write-Host "=== DIAG: rastreio do write de evolution_params (singleton real, so leitura) ===" -ForegroundColor Cyan

Write-Host "`n[1] Get-EvolutionParams -- overlay real lido AGORA:" -ForegroundColor Yellow
$current = Get-EvolutionParams -JournalDir "journal"
$current.PSObject.Properties | ForEach-Object { Write-Host "  $($_.Name) = $($_.Value)" }

Write-Host "`n[2] Registro cru retornado por _Get-LearningFromSupabase (sem clamp/merge):" -ForegroundColor Yellow
$raw = @(_Get-LearningFromSupabase -Table "evolution_params" -Filter @{ id = "current" })
if ($raw.Count -gt 0) {
    $raw[0].PSObject.Properties | ForEach-Object { Write-Host "  $($_.Name) = $($_.Value) (type=$($_.TypeNameOfValue))" }
} else {
    Write-Host "  Nenhum registro retornado."
}

Write-Host "`n[3] Simulando 1 ciclo de Get-EvolutionProposals com evidencia forcada (0 triggers 48h):" -ForegroundColor Yellow
$fakeEvidence = @{ pumpfade_days_zero_match=0; pumpfade_dumpers_seen=0; pumpfade_matches_per_day=0.0
                   sentinel_triggers_24h=0; sentinel_triggers_48h=0
                   tori_confluence_rejected_n=0; tori_confluence_rejected_hit_rate=0.0 }
$props = Get-EvolutionProposals -Current $current -Evidence $fakeEvidence
Write-Host "Propostas geradas: $($props.Count)"
$props | ForEach-Object { Write-Host "  $($_.param): $($_.before) -> $($_.after) [$($_.class)] ($($_.reason))" }

Write-Host "`n[4] Teste de escrita isolada: grava sentinel_move_pct=1.75 num singleton de TESTE (id=diag_test_write) e le de volta:" -ForegroundColor Yellow
try {
    $testRecord = @{ id = "diag_test_write"; sentinel_move_pct = 1.75; updated_at = (Get-Date).ToUniversalTime().ToString("o") }
    Save-StateRecords -Table "evolution_params" -Records @($testRecord) -PrimaryKey "id"
    Start-Sleep -Seconds 1
    $readBack = @(Get-StateRecords -Table "evolution_params" -Filter @{ id = "diag_test_write" })
    if ($readBack.Count -gt 0) {
        Write-Host "  READ-BACK: sentinel_move_pct=$($readBack[0].sentinel_move_pct) (esperado 1.75)" -ForegroundColor $(if ([double]$readBack[0].sentinel_move_pct -eq 1.75) { "Green" } else { "Red" })
    } else {
        Write-Host "  [CRITICAL] write nao gerou erro mas read-back nao encontrou o registro" -ForegroundColor Red
    }
    Remove-StateRecord -Table "evolution_params" -PrimaryKey "id" -Value "diag_test_write" | Out-Null
    Write-Host "  (registro de teste limpo)"
} catch {
    Write-Host "  [CRITICAL] write/read-back falhou: $_" -ForegroundColor Red
}

Write-Host "`n=== FIM DIAG ===" -ForegroundColor Cyan
