# diag_trailing_state_readonly_2026_07_28.ps1 -- diagnostico ONE-SHOT, so leitura
# Achado real: Add-TrailingPosition era chamada com -Side "LONG" hardcoded em
# gem_executor.ps1, independente da direcao real do trade -- confirmado com
# SUIUSDT SHORT real (CoinEx confirma side=short) registrado no trailing como
# "LONG". Este script confere o estado real de trailing_state.active=true pra
# decidir se precisa correcao manual nos registros ja existentes.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

Write-Host "=== DIAG TRAILING_STATE (READ-ONLY) ===" -ForegroundColor Cyan
try {
    $rows = @(Get-StateRecords -Table "trailing_state" -Filter @{ active = $true })
    Write-Host "Total ativas: $($rows.Count)" -ForegroundColor Green
    foreach ($r in $rows) {
        Write-Host "  market=$($r.market) side=$($r.side) entry=$($r.entry) stop=$($r.stop) stopCurrent=$($r.stopCurrent) target=$($r.target) mode=$($r.mode) source=$($r.source)"
    }
} catch {
    Write-Host "ERRO trailing_state: $_" -ForegroundColor Red
}

Write-Host "`n--- Comparacao com CoinEx real (FUTURES) ---" -ForegroundColor Cyan
try {
    $futPos = @(CoinEx-GetPendingPositions)
    foreach ($p in $futPos) {
        Write-Host "  CoinEx real: $($p.market) side=$($p.side)"
    }
} catch { Write-Host "ERRO CoinEx: $_" -ForegroundColor Red }

Write-Host "=== FIM ===" -ForegroundColor Cyan
