# scripts/capital_snapshot_runner.ps1
# Entry point para GitHub Actions atualizar capital_context a cada 15min.
# Chama Get-CapitalContext -Force que faz fetch ao vivo de CoinEx (spot+futures)
# e persiste em manuheadfund.capital_context no Supabase.
#
# Uso (GitHub Actions):
#   pwsh ./scripts/capital_snapshot_runner.ps1
#
# Uso local (manual force-refresh):
#   $env:SUPABASE_URL = "..."; $env:SUPABASE_SERVICE_KEY = "..."
#   pwsh ./scripts/capital_snapshot_runner.ps1

$ErrorActionPreference = "Continue"  # Nao matar workflow inteiro num erro pontual

$here = $PSScriptRoot
$root = Split-Path $here -Parent
$agentsDir = Join-Path $root "agents"

# Forca backend Supabase + schema dedicado
$global:STATE_STORE_BACKEND = "supabase"
$global:STATE_STORE_SCHEMA  = "manuheadfund"

# Carregar dependencias minimas
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "config.local.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_capital_context.ps1")

Write-Host "=== Capital Snapshot Runner ===" -ForegroundColor Cyan
Write-Host "Backend: $(Test-StateBackend)" -ForegroundColor DarkGray
Write-Host "Schema:  $(Get-StateStoreSchema)" -ForegroundColor DarkGray
Write-Host ""

# Estado anterior (Supabase)
try {
    $before = @(Get-StateRecords -Table "capital_context")
    if ($before.Count -gt 0) {
        $b = $before[0]
        Write-Host "Antes:  spot=$($b.spot) futures=$($b.futures) total=$($b.total) ts=$($b.snapshot_ts)" -ForegroundColor DarkGray
    } else {
        Write-Host "Antes:  (vazio, primeira execucao)" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "Antes:  (erro ao ler) $_" -ForegroundColor DarkYellow
}

# Force refresh - chama CoinEx ao vivo + escreve Supabase
try {
    $ctx = Get-CapitalContext -Force
    Write-Host ""
    Write-Host "Refresh OK:" -ForegroundColor Green
    Write-Host "  spot:    $($ctx.spot)" -ForegroundColor Green
    Write-Host "  futures: $($ctx.futures)" -ForegroundColor Green
    Write-Host "  total:   $($ctx.total)" -ForegroundColor Green
    Write-Host "  source:  $($ctx.source)" -ForegroundColor $(if ($ctx.source -eq 'fresh') { 'Green' } else { 'Yellow' })
    Write-Host "  ts:      $($ctx.snapshot_ts)" -ForegroundColor DarkGray

    # Sanidade: source=fallback significa CoinEx falhou (credenciais ausentes ou network)
    if ($ctx.source -eq "fallback") {
        Write-Host ""
        Write-Host "AVISO: source=fallback — CoinEx fetch falhou (verificar credenciais/rede)" -ForegroundColor Yellow
        exit 0  # Nao falhar workflow, apenas avisar
    }

    # Sanidade: total = 0 e suspeito (mesmo com fresh)
    if ($ctx.total -le 0) {
        Write-Host ""
        Write-Host "AVISO: total=0 — possivel falha silenciosa CoinEx" -ForegroundColor Yellow
        exit 0
    }

    Write-Host ""
    Write-Host "Capital context atualizado em Supabase." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "ERRO: $_" -ForegroundColor Red
    # Nao throw - capital snapshot falhar nao deve matar outros jobs
    exit 0
}
