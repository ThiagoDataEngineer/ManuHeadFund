# diag_evolution_cycle_live_trace_2026_08_04.ps1 -- ONE-SHOT.
#
# Roda Invoke-EvolutionCycle de VERDADE (mesma chamada do cron real,
# mesmo -JournalDir "journal"), capturando -WarningAction Continue e
# checando o read-back imediatamente depois, no MESMO processo -- pra
# ver se o write silencioso falha (warning visivel aqui, sumido no log
# real porque WARN eh soft) ou se o problema esta em outro lugar (o
# valor grava certo AQUI mas alguma outra coisa reverte depois).

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")
. (Join-Path $agentsDir "lib_evolution_engine.ps1")
. (Join-Path $agentsDir "lib_direction_learning.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"
$global:JOURNAL_DIR = "journal"
New-Item -ItemType Directory -Path "journal","logs" -Force | Out-Null

Write-Host "=== DIAG: Invoke-EvolutionCycle real, com warnings visiveis ===" -ForegroundColor Cyan

Write-Host "`n[ANTES] overlay atual:" -ForegroundColor Yellow
$before = @(_Get-LearningFromSupabase -Table "evolution_params" -Filter @{ id = "current" })
if ($before.Count -gt 0) { Write-Host "  sentinel_move_pct = $($before[0].sentinel_move_pct)" }

Write-Host "`n[RODANDO] Invoke-EvolutionCycle -JournalDir journal -LogsDir logs (WarningAction Continue):" -ForegroundColor Yellow
$WarningPreference = "Continue"
$result = Invoke-EvolutionCycle -JournalDir "journal" -LogsDir "logs" -WarningVariable evoWarnings 3>&1
Write-Host "Applied: $($result.applied.Count) | Frozen: $($result.frozen.Count) | OwnerPending: $($result.owner_pending.Count)"
$result.applied | ForEach-Object { Write-Host "  APLICADO: $($_.param) $($_.before) -> $($_.after)" -ForegroundColor Green }
$result.frozen | ForEach-Object { Write-Host "  CONGELADO: $($_.param)" -ForegroundColor DarkYellow }

if ($evoWarnings) {
    Write-Host "`n[WARNINGS capturados durante o ciclo]:" -ForegroundColor Red
    $evoWarnings | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
} else {
    Write-Host "`n[Nenhum warning capturado]" -ForegroundColor Green
}

Write-Host "`n[DEPOIS, imediatamente] read-back direto do Supabase:" -ForegroundColor Yellow
Start-Sleep -Seconds 1
$after = @(_Get-LearningFromSupabase -Table "evolution_params" -Filter @{ id = "current" })
if ($after.Count -gt 0) {
    Write-Host "  sentinel_move_pct = $($after[0].sentinel_move_pct)" -ForegroundColor $(if ($result.applied.Count -gt 0 -and [double]$after[0].sentinel_move_pct -ne [double]$before[0].sentinel_move_pct) { "Green" } else { "Red" })
    Write-Host "  updated_at = $($after[0].updated_at)"
}

Write-Host "`n[Local journal/evolution_params.json apos o ciclo]:" -ForegroundColor Yellow
$localPath = Join-Path "journal" "evolution_params.json"
if (Test-Path $localPath) {
    Get-Content $localPath -Raw | Write-Host
} else {
    Write-Host "  (arquivo local nao foi criado -- applied.Count deve ter sido 0)"
}

Write-Host "`n=== FIM DIAG ===" -ForegroundColor Cyan
