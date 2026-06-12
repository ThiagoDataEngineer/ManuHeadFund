# wire_e5_divergence_hunt.ps1
# E5 refinement: Wire funding exhaustion divergence hunt into scan loop
# Call this from scan_master.ps1 after processing each market

param(
    [string] $Market,
    [decimal] $FQSScore,
    [decimal] $BtcADX,
    [decimal] $FundingRate,
    [string] $Regime = "BEAR_WEAK",
    [string] $DivergencePath = ".\journal\divergences.jsonl"
)

. .\agents\lib_funding_exhaustion_gate.ps1

# Hunt divergence only when SHORT suspended (not LIVE execution mode)
if ($Regime -ne "BEAR_WEAK") { return }
if ($env:SHORT_VOL_CLIMAX_LIVE -eq 1) { return }

# Test funding exhaustion gate
$div = Test-FundingExhaustionGate -AssetMarket $Market -FQSScore $FQSScore -BtcADX $BtcADX -FundingRate $FundingRate -Regime $Regime

if ($div -and $div.divergence_found) {
    Save-DivergenceOpportunity -Path $DivergencePath `
        -Market $Market `
        -Divergence $div `
        -BtcADX $BtcADX `
        -Timestamp (Get-Date)

    Write-Host "[E5] Divergence found: $Market (funding=$([math]::Round($FundingRate*100, 3))%, FQS=$FQSScore, BTC_ADX=$BtcADX)" -ForegroundColor Yellow
    return $div
}

return $null
