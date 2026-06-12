# wire_short_vol_climax_passive.ps1
# Wire SHORT vol_climax gate into passive observation collection
# Runs in BEAR_WEAK regime (no executions, log only)
# Timeline: passive collection 3-4 weeks → validation → deploy in BEAR_STRONG

param(
    [string]$ObservationsPath = "$PSScriptRoot\..\journal\observations.csv",
    [string]$ScanResultsPath = "$PSScriptRoot\..\journal\scan_results.jsonl"
)

. "$PSScriptRoot\..\agents\lib_vol_climax_gate.ps1"
. "$PSScriptRoot\..\config.faro_aggressive_2026_06_02.ps1"

function Invoke-VolClimaxPassiveCollection {
    param(
        [Parameter(Mandatory)] [string]$Market,
        [Parameter(Mandatory)] [decimal]$RSI,
        [Parameter(Mandatory)] [decimal]$CurrentVol,
        [Parameter(Mandatory)] [decimal]$Avg3dVol,
        [Parameter(Mandatory)] [decimal]$ADX,
        [Parameter(Mandatory)] [string]$Regime
    )

    $gate = Test-VolClimaxGate -RSI $RSI -CurrentVolume $CurrentVol -Avg3dVolume $Avg3dVol -ADX $ADX

    if ($gate.passes) {
        $obs = Add-VolClimaxObservation -Path $ObservationsPath -Market $Market -GateResult $gate -Regime $Regime -Notes "passive_collection_2026_06"

        Write-Host "[VOL_CLIMAX] SIGNAL: $Market (RSI=$([int]$RSI) vol=$($gate.vol_ratio)x ADX=$([int]$ADX))" -ForegroundColor Yellow
        return $obs
    }

    return $null
}

function Start-VolClimaxPassiveMonitor {
    param(
        [string]$Market = "BTCUSDT",
        [string]$Regime = "BEAR_WEAK"
    )

    Write-Host "🔍 SHORT vol_climax passive monitor START" -ForegroundColor Cyan
    Write-Host "   Market: $Market" -ForegroundColor Gray
    Write-Host "   Regime: $Regime (observation only, no execution)" -ForegroundColor Gray
    Write-Host "   Gate: RSI≥80 + vol≥2.5x + ADX>60" -ForegroundColor Gray
    Write-Host "   Collection period: 3-4 weeks → deploy in BEAR_STRONG" -ForegroundColor Gray
    Write-Host ""

    # This would be called from scan_master.ps1 in its main loop
    # Example integration:
    # foreach ($market in $topMovers) {
    #     $metrics = Get-TechMetrics $market
    #     Invoke-VolClimaxPassiveCollection -Market $market -RSI $metrics.rsi -CurrentVol $metrics.vol -Avg3dVol $metrics.avg3d_vol -ADX $metrics.adx -Regime $currentRegime
    # }
}

# Dry-run example
if ($PSBoundParameters.Count -eq 0) {
    Write-Host "Testing vol_climax gate with simulated data..." -ForegroundColor Magenta

    # Scenario 1: PASS (vol climax detected)
    $obs1 = Invoke-VolClimaxPassiveCollection -Market "BTCUSDT" -RSI 82 -CurrentVol 350000 -Avg3dVol 100000 -ADX 68 -Regime "BEAR_WEAK"
    if ($obs1) { Write-Host "✓ Collected: $($obs1.market)" }

    # Scenario 2: FAIL (RSI not extreme)
    $obs2 = Invoke-VolClimaxPassiveCollection -Market "ETHUSDT" -RSI 70 -CurrentVol 350000 -Avg3dVol 100000 -ADX 68 -Regime "BEAR_WEAK"
    if (-not $obs2) { Write-Host "✗ Rejected: RSI too low" }

    # Scenario 3: FAIL (volume not spiked)
    $obs3 = Invoke-VolClimaxPassiveCollection -Market "LINKUSDT" -RSI 82 -CurrentVol 200000 -Avg3dVol 100000 -ADX 68 -Regime "BEAR_WEAK"
    if (-not $obs3) { Write-Host "✗ Rejected: volume ratio too low" }
}
