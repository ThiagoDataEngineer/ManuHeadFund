# scripts/layers_review_runner.ps1
# Entry point unificado para GitHub Actions rodar Layers 1, 2, 4, 5 em modo cloud.
#
# Uso:
#   pwsh ./scripts/layers_review_runner.ps1 -Layer 1   # Trailing Adaptive
#   pwsh ./scripts/layers_review_runner.ps1 -Layer 2   # Mentor Reflection 6h
#   pwsh ./scripts/layers_review_runner.ps1 -Layer 4   # Tori + TimeStop
#   pwsh ./scripts/layers_review_runner.ps1 -Layer 5   # Moon Bag
#
# Forca state_store backend (Supabase) pra ler/gravar estado compartilhado.
# 0 dependencia de journal/*.json local — tudo via REST API manuheadfund schema.

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("1", "2", "4", "5")]
    [string]$Layer
)

$ErrorActionPreference = "Continue"  # Nao queremos falhar todo o job em 1 erro

$here = $PSScriptRoot
$root = Split-Path $here -Parent
$agentsDir = Join-Path $root "agents"

# Forca backend Supabase + schema dedicado + flag trailing state_store
$global:STATE_STORE_BACKEND      = "supabase"
$global:STATE_STORE_SCHEMA       = "manuheadfund"
$global:TRAILING_USE_STATE_STORE = $true

# Carregar dependencias minimas (sem orchestrator.ps1 / scan_master.ps1)
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "config.local.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_telegram.ps1") -ErrorAction SilentlyContinue
. (Join-Path $agentsDir "lib_macro.ps1") -ErrorAction SilentlyContinue
. (Join-Path $agentsDir "lib_trailing.ps1")
. (Join-Path $agentsDir "lib_trailing_adaptive.ps1") -ErrorAction SilentlyContinue
. (Join-Path $agentsDir "lib_mentor_reflection.ps1") -ErrorAction SilentlyContinue
. (Join-Path $agentsDir "lib_layer4_tori_timestop.ps1") -ErrorAction SilentlyContinue
. (Join-Path $agentsDir "lib_moon_bag.ps1") -ErrorAction SilentlyContinue

Write-Host "=== Layer $Layer Review Runner ===" -ForegroundColor Cyan
Write-Host "Backend: $(Test-StateBackend)" -ForegroundColor DarkGray
Write-Host "Schema:  $(Get-StateStoreSchema)" -ForegroundColor DarkGray

# Quick sanity: alguma posicao para revisar?
$posAll = @(Get-TrailingPositions)
$posActive = @($posAll | Where-Object { $_.active })
Write-Host "Posicoes ativas: $($posActive.Count) / total $($posAll.Count)" -ForegroundColor DarkGray

if ($posActive.Count -eq 0) {
    Write-Host "[$Layer] Nenhuma posicao ativa. Skipping." -ForegroundColor Yellow
    exit 0
}

try {
    switch ($Layer) {
        "1" {
            Write-Host "[Layer 1] Update-TrailingStopsAdaptive..." -ForegroundColor Cyan
            if (Get-Command Update-TrailingStopsAdaptive -ErrorAction SilentlyContinue) {
                Update-TrailingStopsAdaptive
                Write-Host "[Layer 1] OK" -ForegroundColor Green
            } else {
                Write-Host "[Layer 1] Update-TrailingStopsAdaptive nao disponivel" -ForegroundColor Yellow
            }
        }
        "2" {
            Write-Host "[Layer 2] Update-MentorReview..." -ForegroundColor Cyan
            if (Get-Command Update-MentorReview -ErrorAction SilentlyContinue) {
                Update-MentorReview
                Write-Host "[Layer 2] OK" -ForegroundColor Green
            } else {
                Write-Host "[Layer 2] Update-MentorReview nao disponivel" -ForegroundColor Yellow
            }
        }
        "4" {
            Write-Host "[Layer 4] Update-Layer4Review..." -ForegroundColor Cyan
            if (Get-Command Update-Layer4Review -ErrorAction SilentlyContinue) {
                Update-Layer4Review
                Write-Host "[Layer 4] OK" -ForegroundColor Green
            } else {
                Write-Host "[Layer 4] Update-Layer4Review nao disponivel" -ForegroundColor Yellow
            }
        }
        "5" {
            Write-Host "[Layer 5] Update-MoonBagReview..." -ForegroundColor Cyan
            if (Get-Command Update-MoonBagReview -ErrorAction SilentlyContinue) {
                Update-MoonBagReview
                Write-Host "[Layer 5] OK" -ForegroundColor Green
            } else {
                Write-Host "[Layer 5] Update-MoonBagReview nao disponivel" -ForegroundColor Yellow
            }
        }
    }
}
catch {
    Write-Host "[Layer $Layer] ERRO: $_" -ForegroundColor Red
    # Nao throw - layers individuais nao devem matar o workflow inteiro
    exit 0  # opcional: usar 1 quando quiser que GH Actions falhe
}
