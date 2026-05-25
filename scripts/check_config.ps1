# check_config.ps1 - Ver estado atual do sistema
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path (Join-Path $root "agents") "config.local.ps1")
. (Join-Path (Join-Path $root "agents") "config.ps1")

Write-Host "`n=== CONFIGURACAO ATUAL ===" -ForegroundColor Cyan
Write-Host "QUANT_WHITELIST_MODE = $global:QUANT_WHITELIST_MODE"
Write-Host "LIVE_TIER_FILTER     = $global:LIVE_TIER_FILTER"
Write-Host "DAILY_CYCLE_MODE     = $global:DAILY_CYCLE_MODE"
Write-Host ""
Write-Host "Score minimo   = $SCORE_MINIMO"
Write-Host "RR minimo      = $RR_MINIMO"
Write-Host "Risco max      = $($RISCO_MAXIMO_PCT * 100)%"
Write-Host "Max trades/sem = $global:LIVE_MAX_TRADES_PER_WEEK"
Write-Host "Min size       = `$$global:LIVE_MIN_SIZE_USD"
Write-Host "Max size       = `$$global:LIVE_MAX_SIZE_USD"
Write-Host ""
Write-Host "=== FLAGS ===" -ForegroundColor Cyan
$flags = Get-ChildItem (Join-Path (Join-Path $root "journal") "*.flag") -ErrorAction SilentlyContinue
if ($flags) { foreach ($f in $flags) { Write-Host "  $($f.Name)" } } else { Write-Host "  (nenhuma)" }
