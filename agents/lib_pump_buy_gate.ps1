# lib_pump_buy_gate.ps1 -- Anti-pump-buy gate pre-promotion Tier A.
#
# Filosofia: NUNCA promover Tier A em topo local. Resolve padrao PENDLE/INJ
#            drawdown -17/-19% no primeiro dia LIVE (promocao em pump).
#
# Regra: preco atual deve estar a pelo menos X% abaixo do peak 7d (default -5).
#        Sinal de pullback minimum antes de comprar.
#
# Referencia: docs/REFINO_REGIMES_2026_05_19.md + memory project_pro_polish_2026_05_19.md
#
# PS 5.1. UTF-8 BOM. Pure function (sem I/O).


$script:DEFAULT_MAX_DIST_FROM_PEAK_PCT = -5.0   # default: precisa estar -5% do peak


function Test-PumpBuyGate {
    <#
    .SYNOPSIS
        Gate anti-pump-buy: bloqueia promocao se preco muito perto do peak.
    .EXAMPLE
        Test-PumpBuyGate -CurrentPrice 95 -Peak7d 100
        # → passes=$true (5% abaixo do peak)

        Test-PumpBuyGate -CurrentPrice 100 -Peak7d 100
        # → passes=$false (no peak, pullback insuficiente)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double] $CurrentPrice,
        [Parameter(Mandatory)] [double] $Peak7d,
        [Parameter()] [double] $MaxDistFromPeakPct = $script:DEFAULT_MAX_DIST_FROM_PEAK_PCT
    )

    if ($Peak7d -le 0 -or $CurrentPrice -le 0) {
        return [PSCustomObject]@{
            passes        = $false
            dist_pct      = 0
            current_price = $CurrentPrice
            peak_7d       = $Peak7d
            reason        = "invalid_input"
        }
    }

    $dist_pct = (($CurrentPrice - $Peak7d) / $Peak7d) * 100
    # dist_pct = -5 means current is 5% below peak. We want dist_pct <= MaxDistFromPeakPct
    $passes = $dist_pct -le $MaxDistFromPeakPct

    $reason = if ($passes) {
        "ok_pullback"
    } elseif ($dist_pct -ge 0) {
        "at_or_above_peak"
    } else {
        "no_pullback"
    }

    return [PSCustomObject]@{
        passes        = $passes
        dist_pct      = [Math]::Round($dist_pct, 2)
        current_price = $CurrentPrice
        peak_7d       = $Peak7d
        reason        = $reason
        threshold     = $MaxDistFromPeakPct
    }
}


function Get-Peak7dFromCandles {
    <#
    .SYNOPSIS
        Helper: extrai peak (max high) de array de candles.
    .EXAMPLE
        Get-Peak7dFromCandles -Candles $candles
    #>
    [CmdletBinding()]
    param([array] $Candles = @())
    if (-not $Candles -or $Candles.Count -eq 0) { return 0 }
    $maxHigh = 0
    foreach ($c in $Candles) {
        $h = if ($c.high) { [double]$c.high } elseif ($c['high']) { [double]$c['high'] } else { 0 }
        if ($h -gt $maxHigh) { $maxHigh = $h }
    }
    return $maxHigh
}


function Format-PumpBuyGateReport {
    <#
    .SYNOPSIS
        Formata mensagem Telegram quando gate bloqueia promotion.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [PSCustomObject] $GateResult
    )
    if ($GateResult.passes) {
        return "✅ ${Market}: anti-pump-buy OK (dist $($GateResult.dist_pct)% do peak)"
    }
    return @"
🚫 <b>${Market}</b> bloqueado pelo anti-pump-buy gate
Atual: `$$($GateResult.current_price)
Peak 7d: `$$($GateResult.peak_7d)
Distancia: $($GateResult.dist_pct)% (threshold: $($GateResult.threshold)%)
Razao: $($GateResult.reason)
Aguardar pullback antes de promover.
"@
}
