# lib_funding_exhaustion_gate.ps1
# Dead-hand SHORT mode: hunt divergence opportunities when SHORT suspended
# Detects funding rate exhaustion on high-quality assets when BTC is lateral

function Test-FundingExhaustionGate {
    param(
        [string] $AssetMarket,
        [decimal] $FQSScore,
        [decimal] $BtcADX,
        [decimal] $FundingRate,
        [string] $Regime = "BEAR_WEAK"
    )

    # Only applicable in BEAR_WEAK (defensive regime)
    if ($Regime -ne "BEAR_WEAK") { return $null }

    # Gate 1: FQS >= 4 (high-quality asset)
    if ($FQSScore -lt 4.0) { return $null }

    # Gate 2: BTC must be lateral (ADX < 20, no strong trend)
    if ($BtcADX -ge 20) { return $null }

    # Gate 3: Funding rate must be exhaus ted (>= 0.05% per 8h)
    if ($FundingRate -lt 0.0005) { return $null }

    # All conditions met: divergence opportunity found
    return @{
        divergence_found = $true
        funding_rate = $FundingRate
        btc_adx = $BtcADX
        fqs_score = $FQSScore
        risk_tier = "0.1%"  # reduced risk vs standard 0.5%
        entry_signal = "FUNDING_EXHAUS_SHORT"
    }
}

function Save-DivergenceOpportunity {
    param(
        [string] $Path,
        [string] $Market,
        [hashtable] $Divergence,
        [decimal] $BtcADX,
        [datetime] $Timestamp
    )

    $entry = @{
        ts = $Timestamp.ToUniversalTime().ToString("o")
        market = $Market
        divergence_type = "FUNDING_EXHAUSTION"
        funding_rate = $Divergence.funding_rate
        risk_tier = $Divergence.risk_tier
        btc_adx = $BtcADX
        entry_signal = $Divergence.entry_signal
    }

    $json = $entry | ConvertTo-Json -Compress
    Add-Content -Path $Path -Value $json -Encoding UTF8
}

function Get-RecentDivergences {
    param(
        [string] $Path,
        [int] $HourWindow = 24
    )

    if (-not (Test-Path $Path)) { return @() }

    $cutoff = (Get-Date).AddHours(-$HourWindow)
    $divergences = @()

    @(Get-Content $Path) | ForEach-Object {
        $obj = $_ | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($obj) {
            $ts = [datetime]::Parse($obj.ts)
            if ($ts -gt $cutoff) {
                $divergences += $obj
            }
        }
    }

    return $divergences
}

Write-Host "✅ lib_funding_exhaustion_gate loaded" -ForegroundColor Green
