# apply_evolution_tori_threshold_fix_2026_08_21.ps1 -- one-shot, corrige overlay real
#
# Causa raiz confirmada (diag_evolution_engine_status, run 32484485983,
# 2026-08-21 12:59): Supabase evolution_params.tori_confluence_threshold=80,
# re-gravado a cada ciclo do Evolution Engine (mesmo sem evidencia suficiente
# pra mover -- Get-EvolutionParams sempre persiste TODOS os params juntos).
# Isso travava 100% dos candidatos com score 65-79 em BLOCK (confirmado no
# log real do Gem Scanner+Executor no mesmo periodo), apesar do commit
# 655c850 ter setado o default LOCAL pra 65 -- o overlay do Supabase sempre
# vence.
#
# Fix do registry (lib_evolution_engine.ps1, commit c9e2bb3) mudou min/default
# pra 65, mas o valor 80 JA PERSISTIDO no Supabase continua dentro do novo
# range (65-90) e passaria no clamp sem problema -- precisa ser corrigido
# explicitamente aqui, uma vez, senao so muda quando o Evolution Engine
# tiver evidencia (toriN>=20) pra mover sozinho.
#
# NAO envia ordem nenhuma -- so escreve 1 registro de configuracao.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

Write-Host "=== APPLY EVOLUTION tori_confluence_threshold FIX (READ-WRITE, 1 registro) ===" -ForegroundColor Cyan

$backend = Test-StateBackend
Write-Host "Backend: $backend" -ForegroundColor Cyan

# Le o overlay atual pra preservar tudo que ja esta calibrado, so troca
# tori_confluence_threshold.
$current = $null
try {
    $rows = @(Get-StateRecords -Table "evolution_params" -Filter @{ id = "current" })
    if ($rows.Count -gt 0) { $current = $rows[0] }
} catch {
    Write-Host "AVISO: leitura do overlay atual falhou, seguindo com defaults conhecidos: $_" -ForegroundColor Yellow
}

$record = @{
    id                          = "current"
    sentinel_move_pct           = if ($current -and $current.sentinel_move_pct)          { [double]$current.sentinel_move_pct }          else { 2.25 }
    sentinel_ignition_pct       = if ($current -and $current.sentinel_ignition_pct)      { [double]$current.sentinel_ignition_pct }      else { 12 }
    pumpfade_min_pump_pct       = if ($current -and $current.pumpfade_min_pump_pct)      { [double]$current.pumpfade_min_pump_pct }      else { 12 }
    pumpfade_dump_pct           = if ($current -and $current.pumpfade_dump_pct)          { [double]$current.pumpfade_dump_pct }          else { -10 }
    gem_sizing_pct              = if ($current -and $current.gem_sizing_pct)             { [double]$current.gem_sizing_pct }             else { 0.5 }
    gem_max_exposure_pct        = if ($current -and $current.gem_max_exposure_pct)       { [double]$current.gem_max_exposure_pct }       else { 25 }
    faro_signals_needed         = if ($current -and $current.faro_signals_needed)        { [double]$current.faro_signals_needed }        else { 5 }
    stop_atr_multiplier         = if ($current -and $current.stop_atr_multiplier)        { [double]$current.stop_atr_multiplier }        else { 2.5 }
    trailing_be_buffer_pct      = if ($current -and $current.trailing_be_buffer_pct)     { [double]$current.trailing_be_buffer_pct }     else { 0.02 }
    tori_confluence_threshold   = 65
}

Write-Host "Overlay ANTES: tori_confluence_threshold=$($current.tori_confluence_threshold)" -ForegroundColor Yellow
Write-Host "Overlay DEPOIS (a gravar): tori_confluence_threshold=65" -ForegroundColor Green

try {
    Save-StateRecords -Table "evolution_params" -Records @($record) -PrimaryKey "id"
    Write-Host "SUCESSO: evolution_params.current gravado (tori_confluence_threshold=65)" -ForegroundColor Green
} catch {
    Write-Host "ERRO ao gravar: $_" -ForegroundColor Red
    exit 1
}

# Confirma read-back
try {
    $readBack = Get-StateRecords -Table "evolution_params" -Filter @{ id = "current" }
    Write-Host "READ-BACK: $($readBack | ConvertTo-Json -Compress)" -ForegroundColor Cyan
} catch {
    Write-Host "AVISO: read-back falhou (gravacao pode ter funcionado mesmo assim): $_" -ForegroundColor Yellow
}

Write-Host "=== FIM ===" -ForegroundColor Cyan
