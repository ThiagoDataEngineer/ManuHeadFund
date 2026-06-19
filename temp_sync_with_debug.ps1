. agents/config.local.ps1
. agents/config.ps1
. agents/lib_coinex.ps1

# ATIVAR DEBUG GLOBAL
$global:DEBUG_COINEX = $true

Write-Host "=== SYNC WITH DEBUG ===" -ForegroundColor Cyan
Write-Host ""

. scripts/sync_and_fix_tp.ps1 -Markets @('BASEDUSDT')
