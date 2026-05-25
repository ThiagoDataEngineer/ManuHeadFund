# b25_backtest_retroactive.ps1 -- Avalia retroativo: quais markets mudariam de classe
# com regime-conditioned Sharpe (B25) vs gates fixos antigos.
#
# Strategy:
#   1. Le per_asset_whitelist_latest com sharpe historico de cada market
#   2. Aplica Test-SharpeCeilingGate (default, sem Phase) vs (-Phase phase_3_bear)
#   3. Reporta diffs: quem mudaria red_flag <-> suspect <-> robust
#
# Phase atual: phase_3_bear (~mes 24 pos-halving, BTC ~$77k vs ATH $109k).

param([string]$Phase = "phase_3_bear")

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
Set-Location $projectRoot
. (Join-Path (Join-Path $projectRoot "agents") "lib_methodology_gates.ps1")

$journalDir = Join-Path $projectRoot "journal"
$wlFiles = Get-ChildItem -Path $journalDir -Filter "per_asset_whitelist_*.json" |
            Sort-Object LastWriteTime -Descending
if (-not $wlFiles) { Write-Host "Nenhuma whitelist encontrada" -ForegroundColor Red; exit 1 }
$wl = Get-Content $wlFiles[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Host ("Whitelist source: " + $wlFiles[0].Name) -ForegroundColor Cyan
Write-Host ("Regime testado: " + $Phase) -ForegroundColor Cyan
Write-Host ""

$allMarkets = @()
foreach ($tier in @('TIER_A_LIVE','TIER_B_PAPER','TIER_C_SKIP')) {
    $entries = $wl.$tier
    foreach ($e in $entries) {
        if ($null -eq $e -or -not $e.market -or $null -eq $e.sharpe) { continue }
        $allMarkets += [PSCustomObject]@{
            market = $e.market
            current_tier = $tier
            sharpe = [double]$e.sharpe
        }
    }
}

Write-Host ("Analisando " + $allMarkets.Count + " markets com Sharpe historico...") -ForegroundColor Cyan
Write-Host ""

$diffs = @()
$same = 0
foreach ($m in $allMarkets) {
    $default = Test-SharpeCeilingGate -Sharpe $m.sharpe
    $regime  = Test-SharpeCeilingGate -Sharpe $m.sharpe -Phase $Phase

    $changed = ($default.zone -ne $regime.zone) -or ($default.passes -ne $regime.passes)
    $row = [PSCustomObject]@{
        market = $m.market
        tier = $m.current_tier
        sharpe = $m.sharpe
        default_zone = $default.zone
        default_passes = $default.passes
        regime_zone = $regime.zone
        regime_passes = $regime.passes
        changed = $changed
    }
    if ($changed) { $diffs += $row } else { $same++ }
}

Write-Host ("DIFFS ($($diffs.Count) markets mudariam de classe com regime=$Phase):") -ForegroundColor Yellow
$diffs | Sort-Object @{Expression={$_.regime_passes};Descending=$false}, @{Expression={$_.sharpe};Descending=$true} |
    Format-Table -Property market, tier, sharpe, default_zone, regime_zone, regime_passes -AutoSize |
    Out-String -Width 200 | Write-Host

Write-Host ("CONSISTENT (" + $same + " markets sem mudanca de classe)") -ForegroundColor DarkGray
Write-Host ""

# Critical: markets atualmente em A_LIVE/B_PAPER que viram red_flag em regime
$critical = $diffs | Where-Object {
    $_.regime_zone -eq 'overfit_red_flag' -and ($_.tier -eq 'TIER_A_LIVE' -or $_.tier -eq 'TIER_B_PAPER')
}
if ($critical) {
    Write-Host "[!] CRITICOS (passariam com gate fixo, BLOQUEADOS em $Phase):" -ForegroundColor Red
    $critical | ForEach-Object {
        '  {0,-14} tier={1} sharpe={2} -> {3}' -f $_.market, $_.tier, $_.sharpe, $_.regime_zone
    }
}

# Save report
$reportPath = Join-Path $journalDir ("b25_backtest_retro_" + (Get-Date -Format "yyyyMMdd_HHmm") + ".json")
@{
    phase_tested = $Phase
    whitelist_source = $wlFiles[0].Name
    total_markets = $allMarkets.Count
    changed = $diffs.Count
    unchanged = $same
    diffs = $diffs
    criticals = $critical
} | ConvertTo-Json -Depth 4 | Out-File $reportPath -Encoding utf8
Write-Host ""
Write-Host ("Report saved: " + $reportPath) -ForegroundColor DarkGray
