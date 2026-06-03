# lib_correlation_rolling.ps1
# Beta rolling correlation detector for Alpha vs BTC
# Detects when TIER_A assets are losing independence (>0.75 corr with BTC in BEAR_WEAK)

function Get-RollingCorrelation {
    param(
        [decimal[]] $Series1,
        [decimal[]] $Series2
    )

    if ($Series1.Count -lt 2 -or $Series2.Count -lt 2) { return $null }
    if ($Series1.Count -ne $Series2.Count) { return $null }

    $n = $Series1.Count
    $mean1 = ($Series1 | Measure-Object -Average).Average
    $mean2 = ($Series2 | Measure-Object -Average).Average

    # Check for zero variance (fail-soft)
    $var1 = 0; $var2 = 0
    for ($i = 0; $i -lt $n; $i++) {
        $var1 += [math]::Pow($Series1[$i] - $mean1, 2)
        $var2 += [math]::Pow($Series2[$i] - $mean2, 2)
    }

    if ($var1 -eq 0 -or $var2 -eq 0) { return $null }

    # Pearson correlation
    $covar = 0
    for ($i = 0; $i -lt $n; $i++) {
        $covar += ($Series1[$i] - $mean1) * ($Series2[$i] - $mean2)
    }

    $correlation = $covar / [math]::Sqrt($var1 * $var2)
    return [math]::Round($correlation, 4)
}

function Test-CorrelationThreshold {
    param(
        [decimal] $Correlation,
        [decimal] $Threshold = 0.75
    )

    $pass = $Correlation -lt $Threshold

    return @{
        pass = $pass
        correlation = $Correlation
        threshold = $Threshold
        alert_demote = -not $pass
    }
}

function Test-CorrelationTrend {
    param(
        [object] $Previous,
        [decimal] $Current
    )

    # First measurement (no prior correlation)
    if ($null -eq $Previous) {
        return @{
            direction = "INIT"
            delta = $null
            trending_up = $false
        }
    }

    $delta = $Current - $Previous
    $absDelta = [math]::Abs($delta)

    if ($absDelta -le 0.01) {
        $direction = "FLAT"
    } elseif ($delta -gt 0) {
        $direction = "UP"
    } else {
        $direction = "DOWN"
    }

    return @{
        direction = $direction
        delta = [math]::Round($delta, 4)
        trending_up = ($direction -eq "UP" -and $absDelta -gt 0.05)
    }
}

function Test-AlphaCorrelationGate {
    param(
        [string] $AssetMarket,
        [decimal] $Correlation,
        [hashtable] $Trend = @{},
        [string] $Regime = "BEAR_WEAK",
        [string] $CachePath
    )

    # Gate only applies in BEAR_WEAK (defensive regime)
    if ($Regime -ne "BEAR_WEAK") {
        return @{
            pass = $true
            reason = "not_applicable (regime=$Regime)"
        }
    }

    $threshold = 0.75
    $test = Test-CorrelationThreshold -Correlation $Correlation -Threshold $threshold

    if (-not $test.pass) {
        $trendInfo = $Trend.direction ?? "UNKNOWN"
        $trendingUp = $Trend.trending_up ?? $false

        # Demote if high correlation AND trending up (worsening)
        if ($trendingUp) {
            return @{
                pass = $false
                action = "DEMOTE_TO_OBSERVE"
                reason = "ALPHA_LOST: corr=$($Correlation) trending_up=true (regime=$Regime)"
                correlation = $Correlation
                trend = $trendInfo
            }
        } else {
            # High corr but not worsening — watch but don't demote yet
            return @{
                pass = $true
                action = "WATCH"
                reason = "decorrelating: corr=$($Correlation) trending down (alpha recovering)"
                correlation = $Correlation
            }
        }
    }

    # Correlation acceptable
    if ($Trend.direction -eq "DOWN") {
        return @{
            pass = $true
            reason = "decorrelating: corr=$($Correlation) trending down (alpha recovering)"
            correlation = $Correlation
        }
    }

    return @{
        pass = $true
        reason = "alpha_valid (corr=$($Correlation) < $threshold)"
        correlation = $Correlation
    }
}

function Save-CorrelationSnapshot {
    param(
        [string] $Path,
        [string] $Market,
        [decimal] $Correlation,
        [string] $Trend = "FLAT",
        [datetime] $Timestamp
    )

    $entry = @{
        ts = $Timestamp.ToUniversalTime().ToString("o")
        market = $Market
        correlation = $Correlation
        trend = $Trend
    }

    $json = $entry | ConvertTo-Json -Compress
    Add-Content -Path $Path -Value $json -Encoding UTF8
}

function Get-LastCorrelationSnapshot {
    param(
        [string] $Path,
        [string] $Market
    )

    if (-not (Test-Path $Path)) { return $null }

    $lines = @(Get-Content $Path)
    if ($lines.Count -eq 0) { return $null }

    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $obj = $lines[$i] | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($obj -and $obj.market -eq $Market) {
            return $obj
        }
    }

    return $null
}

Write-Host "✅ lib_correlation_rolling loaded" -ForegroundColor Green
