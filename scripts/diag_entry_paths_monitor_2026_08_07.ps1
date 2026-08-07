# diag_entry_paths_monitor_2026_08_07.ps1 -- ONE-SHOT, so leitura.
#
# Owner pediu monitoramento continuo dos 3 caminhos de entrada de trade
# novo: SHORT FUTURES (short_scanner.ps1), LONG FUTURES e LONG SPOT (ambos
# via gem_executor.ps1/Get-RouteForMode, GEM mode prefere spot, TIER_A/
# STANDARD/BLUE_CHIP preferem futures). Le direto o trailing_state real
# (fonte de verdade das posicoes abertas) e reporta market+side+asset_class
# das mais recentes, sem depender de parsear logs do GitHub Actions.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"

Write-Host "=== MONITOR: 3 caminhos de entrada (SHORT FUTURES / LONG FUTURES / LONG SPOT) ===" -ForegroundColor Cyan

$rows = @(Get-StateRecords -Table "trailing_state" -Filter @{ active = $true })
Write-Host "Posicoes ativas no journal: $($rows.Count)`n"

$byPath = @{
    "SHORT_FUTURES" = @()
    "LONG_FUTURES"  = @()
    "LONG_SPOT"     = @()
    "OUTRO"         = @()
}

foreach ($r in $rows) {
    $side = "$($r.side)".ToUpper()
    $assetClass = if ($r.origin -and $r.origin.asset_class) { "$($r.origin.asset_class)".ToUpper() } else { "UNKNOWN" }

    $key = if ($side -eq "SHORT" -and $assetClass -eq "FUTURES") { "SHORT_FUTURES" }
           elseif ($side -eq "LONG" -and $assetClass -eq "FUTURES") { "LONG_FUTURES" }
           elseif ($side -eq "LONG" -and $assetClass -eq "SPOT") { "LONG_SPOT" }
           else { "OUTRO" }

    $byPath[$key] += [PSCustomObject]@{
        market    = $r.market
        entry     = $r.entry
        openedAt  = $r.openedAt
        mode      = if ($r.PSObject.Properties['mode']) { $r.mode } else { "" }
        side      = $side
        asset     = $assetClass
    }
}

foreach ($pathName in @("SHORT_FUTURES", "LONG_FUTURES", "LONG_SPOT", "OUTRO")) {
    $items = @($byPath[$pathName] | Sort-Object openedAt -Descending)
    Write-Host "--- $pathName ($($items.Count) posicoes ativas) ---" -ForegroundColor Yellow
    if ($items.Count -eq 0) {
        Write-Host "  (nenhuma)"
    } else {
        foreach ($it in ($items | Select-Object -First 10)) {
            Write-Host ("  {0,-14} entry={1,-14} openedAt={2} mode={3}" -f $it.market, $it.entry, $it.openedAt, $it.mode)
        }
    }
    Write-Host ""
}

Write-Host "=== FIM MONITOR ===" -ForegroundColor Cyan
