# lib_universe_sweep.ps1 -- Universe snapshot and gate quality analysis
#
# Contrato:
#   Get-UniverseSnapshot -Pairs -TopN
#     => PSCustomObject:
#        total_pairs, top_long_movers, top_short_movers, gate_stats, snapshot_ts
#
#   Get-TopMoversLong -Pairs -N
#     => object[] (change_24h > 0, sorted desc)
#
#   Get-TopMoversShort -Pairs -N
#     => object[] (change_24h < 0, sorted asc)
#
#   Get-UniverseGateStats -Pairs
#     => PSCustomObject (mcap_below_1m, age_below_7d, vol_below_500k, spread_above_5pct)
#
# Sem dependencias externas. Pure functions. UTF-8 BOM.

function Get-TopMoversLong {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)] [AllowEmptyCollection()] [object[]] $Pairs,
        [Parameter()] [int] $N = 10
    )

    $movers = @()
    foreach ($pair in $Pairs) {
        if ($null -eq $pair.change_24h) { continue }
        $change = [double]$pair.change_24h
        if ($change -gt 0) {
            $movers += $pair
        }
    }

    # Sort desc by change_24h
    $movers = $movers | Sort-Object -Property { [double]$_.change_24h } -Descending
    return $movers | Select-Object -First $N
}

function Get-TopMoversShort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)] [AllowEmptyCollection()] [object[]] $Pairs,
        [Parameter()] [int] $N = 10
    )

    $movers = @()
    foreach ($pair in $Pairs) {
        if ($null -eq $pair.change_24h) { continue }
        $change = [double]$pair.change_24h
        if ($change -lt 0) {
            $movers += $pair
        }
    }

    # Sort asc by change_24h (mais negativo primeiro)
    $movers = $movers | Sort-Object -Property { [double]$_.change_24h }
    return $movers | Select-Object -First $N
}

function Get-UniverseGateStats {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)] [AllowEmptyCollection()] [object[]] $Pairs
    )

    $mcap_below_1m    = 0
    $age_below_7d     = 0
    $vol_below_500k   = 0
    $spread_above_5pct = 0

    foreach ($pair in $Pairs) {
        if ($null -ne $pair.market_cap) {
            if ([double]$pair.market_cap -lt 1000000) {
                $mcap_below_1m++
            }
        }
        if ($null -ne $pair.age_days) {
            if ([double]$pair.age_days -lt 7) {
                $age_below_7d++
            }
        }
        if ($null -ne $pair.vol_24h) {
            if ([double]$pair.vol_24h -lt 500000) {
                $vol_below_500k++
            }
        }
        if ($null -ne $pair.spread_pct) {
            if ([double]$pair.spread_pct -gt 5) {
                $spread_above_5pct++
            }
        }
    }

    return [PSCustomObject]@{
        mcap_below_1m    = $mcap_below_1m
        age_below_7d     = $age_below_7d
        vol_below_500k   = $vol_below_500k
        spread_above_5pct = $spread_above_5pct
    }
}

function Get-UniverseSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)] [AllowEmptyCollection()] [object[]] $Pairs,
        [Parameter()] [int] $TopN = 10
    )

    $total = if ($null -eq $Pairs -or $Pairs.Count -eq 0) { 0 } else { $Pairs.Count }

    $long_movers = Get-TopMoversLong -Pairs $Pairs -N $TopN
    $short_movers = Get-TopMoversShort -Pairs $Pairs -N $TopN
    $gate_stats = Get-UniverseGateStats -Pairs $Pairs

    return [PSCustomObject]@{
        total_pairs       = $total
        top_long_movers   = $long_movers
        top_short_movers  = $short_movers
        gate_stats        = $gate_stats
        snapshot_ts       = Get-Date
    }
}
