# lib_vol_climax_gate.ps1 — Volatility climax SHORT detection gate
# Passive collector: logs potential SHORT vol_climax signals to observations.csv
# Gate criteria: RSI ≥80 + vol ≥2.5x + ADX >60 (all 3 must pass)
# Purpose: collect real-world data during BEAR_WEAK for validation in BEAR_STRONG

function Test-VolClimaxGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [decimal] $RSI,
        [Parameter(Mandatory)] [decimal] $CurrentVolume,
        [Parameter(Mandatory)] [decimal] $Avg3dVolume,
        [Parameter(Mandatory)] [decimal] $ADX
    )

    $volRatio = if ($Avg3dVolume -gt 0) { $CurrentVolume / $Avg3dVolume } else { 0 }

    $rsiPass = $RSI -ge 80
    $volPass = $volRatio -ge 2.5
    $adxPass = $ADX -gt 60

    $allPass = $rsiPass -and $volPass -and $adxPass

    return [PSCustomObject]@{
        passes = $allPass
        rsi_pass = $rsiPass
        vol_ratio = [decimal]::Round($volRatio, 2)
        vol_pass = $volPass
        adx_pass = $adxPass
        signal_strength = @{
            rsi = $RSI
            vol_ratio = $volRatio
            adx = $ADX
        }
    }
}

function Add-VolClimaxObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [PSCustomObject] $GateResult,
        [Parameter(Mandatory)] [string] $Regime,
        [string] $Notes = ""
    )

    if (-not (Test-Path $Path)) {
        New-Item -ItemType File -Path $Path -Force | Out-Null
    }

    $entry = [PSCustomObject]@{
        ts = (Get-Date).ToUniversalTime().ToString("O")
        market = $Market
        signal_type = "vol_climax"
        rsi = [int]$GateResult.signal_strength.rsi
        vol_ratio = $GateResult.vol_ratio
        adx = [int]$GateResult.signal_strength.adx
        passes = $GateResult.passes
        regime = $Regime
        notes = $Notes
    }

    try {
        $lines = @(Get-Content $Path -ErrorAction SilentlyContinue)
        $lines += ($entry | ConvertTo-Json -Compress)
        Set-Content -Path $Path -Value $lines -Encoding UTF8 -Force
    } catch {
        Write-Warning "Failed to log vol_climax observation: $_"
    }

    return $entry
}
