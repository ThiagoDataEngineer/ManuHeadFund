# lib_cycle_memory_decision.ps1
# Cycle memory cache: skip expensive LLM reflection calls when context unchanged
# If prior veto was "MACRO_UNFAVORABLE" and regime hasn't changed, veto again without LLM

function Save-ReflectionCache {
    param(
        [string] $Path,
        [string] $Market,
        [string] $Regime,
        [string] $Decision,
        [string] $VetoReason,
        [datetime] $Timestamp
    )

    $entry = @{
        ts = $Timestamp.ToUniversalTime().ToString("o")
        market = $Market
        regime = $Regime
        decision = $Decision
        veto_reason = $VetoReason
    }

    $json = $entry | ConvertTo-Json -Compress
    Add-Content -Path $Path -Value $json -Encoding UTF8
}

function Get-ReflectionCache {
    param(
        [string] $Path,
        [string] $Market
    )

    if (-not (Test-Path $Path)) { return $null }

    $lines = @(Get-Content $Path)
    if ($lines.Count -eq 0) { return $null }

    # Return last entry for this market
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $obj = $lines[$i] | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($obj -and $obj.market -eq $Market) {
            return $obj
        }
    }

    return $null
}

function Get-CycleMemoryDecision {
    param(
        [string] $Path,
        [string] $Market,
        [string] $CurrentRegime
    )

    $cached = Get-ReflectionCache -Path $Path -Market $Market

    # No cache: proceed with normal reflection
    if ($null -eq $cached) { return $null }

    # Cache expired (>7 days): ignore cache
    $cachedTime = [datetime]::Parse($cached.ts, [System.Globalization.CultureInfo]::InvariantCulture)
    $ageHours = ((Get-Date).ToUniversalTime() - $cachedTime).TotalHours
    if ($ageHours -gt 168) {  # 7 days
        return $null
    }

    # Different regime: ignore cache (decision might differ)
    if ($cached.regime -ne $CurrentRegime) { return $null }

    # Regime same, but approved decision: skip cache (only cache vetos to avoid re-entry)
    if ($cached.decision -eq "APPROVE") { return $null }

    # Regime same + veto decision: return cached veto (no LLM needed)
    if ($cached.decision -eq "VETO" -and -not [string]::IsNullOrEmpty($cached.veto_reason)) {
        return @{
            decision = "VETO"
            reason = $cached.veto_reason
            from_cache = $true
            cached_at = $cachedTime
        }
    }

    return $null
}

Write-Host "✅ lib_cycle_memory_decision loaded" -ForegroundColor Green
