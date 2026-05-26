# scripts/migrate_journal_to_supabase.ps1
# Migra journal/trailing_positions.json para Supabase manuheadfund.trailing_positions
# Idempotente: pode rodar varias vezes (upsert por pk_id).
#
# Uso:
#   pwsh ./scripts/migrate_journal_to_supabase.ps1 [-DryRun]
#
# DryRun mostra o que seria migrado sem escrever.

param([switch]$DryRun)

$ErrorActionPreference = "Stop"

$here = $PSScriptRoot
$root = Split-Path $here -Parent
. (Join-Path $root "agents/config.local.ps1")
. (Join-Path $root "agents/lib_state_store.ps1")
. (Join-Path $root "agents/lib_trailing.ps1")

# Forca backend supabase pra escrita
$global:STATE_STORE_BACKEND = "supabase"
$global:STATE_STORE_SCHEMA  = "manuheadfund"

Write-Host "=== Journal -> Supabase migration ===" -ForegroundColor Cyan
Write-Host "Backend: $(Test-StateBackend)" -ForegroundColor DarkGray
Write-Host "Schema:  $(Get-StateStoreSchema)" -ForegroundColor DarkGray
Write-Host "DryRun:  $($DryRun.IsPresent)" -ForegroundColor $(if ($DryRun) { "Yellow" } else { "Magenta" })
Write-Host ""

# Leitura: journal local raw (state_store local)
$journalFile = Join-Path $root "journal/trailing_positions.json"
if (-not (Test-Path $journalFile)) {
    Write-Host "Journal nao existe: $journalFile" -ForegroundColor Yellow
    exit 0
}

$rawPositions = @()
try {
    $raw = Get-Content $journalFile -Raw
    if ($raw -and $raw.Trim().Length -gt 0) {
        $parsed = $raw | ConvertFrom-Json
        $rawPositions = @($parsed)
    }
} catch {
    Write-Host "Erro lendo journal: $_" -ForegroundColor Red
    exit 1
}

# Filtrar apenas posicoes validas (com .market) — defesa contra corrupcao
$validPositions = @($rawPositions | Where-Object { $_.PSObject.Properties['market'] -and $_.market })

Write-Host "Posicoes encontradas no journal: $($validPositions.Count)" -ForegroundColor Cyan
foreach ($p in $validPositions) {
    $kind = if ($p.PSObject.Properties['moonBagKind'] -and $p.moonBagKind) { ":" + $p.moonBagKind } else { "" }
    $active = if ($p.active) { "ATIVA" } else { "fechada" }
    Write-Host ("  - {0,-12}{1,-9} {2,-7} entry={3} stop={4} target={5}" -f `
        $p.market, $kind, $active, $p.entry, $p.stop, $p.target)
}
Write-Host ""

if ($validPositions.Count -eq 0) {
    Write-Host "Nada para migrar." -ForegroundColor Yellow
    exit 0
}

# Verificar o que ja esta em Supabase (cleanup ou idempotencia)
$existing = @(Get-StateRecords -Table "trailing_positions")
Write-Host "Posicoes ja em Supabase: $($existing.Count)" -ForegroundColor Cyan
foreach ($p in $existing) {
    Write-Host ("  - {0} pk_id={1} active={2}" -f $p.market, $p.pk_id, $p.active)
}
Write-Host ""

if ($DryRun) {
    Write-Host "DryRun: parando aqui. Sem escrever no Supabase." -ForegroundColor Yellow
    exit 0
}

# Escrita: usa Save-TrailingPositions com flag state_store ON
$global:TRAILING_USE_STATE_STORE = $true

Write-Host "Migrando $($validPositions.Count) posicoes..." -ForegroundColor Magenta
try {
    Save-TrailingPositions -Positions $validPositions
    Write-Host "OK escrita Supabase concluida" -ForegroundColor Green
} catch {
    Write-Host "ERRO escrita: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== Verificacao pos-migracao ===" -ForegroundColor Cyan
$after = @(Get-StateRecords -Table "trailing_positions")
Write-Host "Posicoes em Supabase agora: $($after.Count)" -ForegroundColor Green
foreach ($p in $after) {
    Write-Host ("  - {0,-25} pk_id={1,-30} active={2} entry={3}" -f $p.market, $p.pk_id, $p.active, $p.entry)
}

Write-Host ""
Write-Host "=== Migration COMPLETE ===" -ForegroundColor Green
Write-Host "Journal local intocado em: $journalFile" -ForegroundColor DarkGray
Write-Host "Para reverter: pode dropar tabela ou desligar TRAILING_USE_STATE_STORE flag." -ForegroundColor DarkGray
