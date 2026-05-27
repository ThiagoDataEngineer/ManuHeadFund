# reconcile_phantom_positions.ps1
# One-shot ou cron: fecha posicoes locais (trailing_positions.json) que nao
# existem mais na exchange CoinEx. Resolve dessincronizacao.
#
# Usage:
#   .\scripts\reconcile_phantom_positions.ps1          # roda reconcile
#   .\scripts\reconcile_phantom_positions.ps1 -DryRun  # so reporta, nao fecha

param([switch]$DryRun)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root "agents\config.local.ps1")
. (Join-Path $root "agents\lib_coinex.ps1")
. (Join-Path $root "agents\lib_trailing.ps1")
. (Join-Path $root "agents\lib_trailing_orphan_detection.ps1")

Write-Host "=== Phantom Reconciliation ===" -ForegroundColor Cyan
Write-Host "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

$phantoms = @(Detect-PhantomPositions)
Write-Host "Phantoms detectados: $($phantoms.Count)" -ForegroundColor $(if ($phantoms.Count -gt 0) { "Yellow" } else { "Green" })

if ($phantoms.Count -eq 0) {
    Write-Host "Nada pra fazer. Trailing sincronizado com CoinEx." -ForegroundColor Green
    exit 0
}

foreach ($p in $phantoms) {
    Write-Host "  - $($p.market) entry=$($p.entry) opened=$($p.openedAt)" -ForegroundColor Yellow
}

if ($DryRun) {
    Write-Host "DryRun ativo - nao fechando." -ForegroundColor Cyan
    exit 0
}

$result = Reconcile-PhantomPositions
Write-Host ""
Write-Host "Resultado: closed=$($result.closed) errors=$($result.errors)" -ForegroundColor $(if ($result.errors -eq 0) { "Green" } else { "Red" })
foreach ($d in $result.details) {
    $color = if ($d.closed) { "Green" } else { "Red" }
    Write-Host "  $($d.market): closed=$($d.closed) exitPrice=$($d.exitPrice)" -ForegroundColor $color
}
