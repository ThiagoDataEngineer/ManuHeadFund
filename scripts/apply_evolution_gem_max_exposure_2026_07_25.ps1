# apply_evolution_gem_max_exposure_2026_07_25.ps1 -- one-shot, grava overlay real
# Owner pediu evoluir MaxConcurrentTrades/exposicao (2026-07-25). Achado: o canal
# real de aprovacao de parametros RISK (Evolution Engine -> Get-EvolutionParams)
# nunca recebeu nenhuma escrita -- nem no Supabase (tabela evolution_params
# existe e e lida, mas nunca gravada) nem localmente (journal/evolution_params.json
# e gitignored, nunca chega no cloud). Este script grava gem_max_exposure_pct=25
# (teto ja documentado no clamp [10,25] de lib_evolution_engine.ps1) na tabela
# real, e preserva os outros overrides ja calibrados anteriormente (local).
# NAO envia ordem nenhuma -- so escreve 1 registro de configuracao.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

Write-Host "=== APPLY EVOLUTION gem_max_exposure_pct (READ-WRITE, 1 registro) ===" -ForegroundColor Cyan

$backend = Test-StateBackend
Write-Host "Backend: $backend" -ForegroundColor Cyan

# Preserva os overrides locais ja calibrados (pumpfade_min_pump_pct=12,
# sentinel_ignition_pct=12, pumpfade_dump_pct=-10, sentinel_move_pct=3.25,
# gem_sizing_pct=0.5) + adiciona/atualiza gem_max_exposure_pct=25.
$record = @{
    id                   = "current"
    pumpfade_min_pump_pct = 12
    sentinel_ignition_pct = 12
    pumpfade_dump_pct     = -10
    sentinel_move_pct     = 3.25
    gem_sizing_pct        = 0.5
    gem_max_exposure_pct  = 25
}

try {
    Save-StateRecords -Table "evolution_params" -Records @($record) -PrimaryKey "id"
    Write-Host "SUCESSO: evolution_params.current gravado (gem_max_exposure_pct=25)" -ForegroundColor Green
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
