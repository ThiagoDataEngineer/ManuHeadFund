# lib_router_spot_futures.ps1 — Route SPOT vs FUTURES (OPERACIONAL)

function Get-Route {
    param(
        [double]$momentum,
        [bool]$hasFutures,
        [bool]$hasSpot,
        [string]$direction
    )

    # Momentum alto → FUTURES (máximo capital)
    if ($momentum -gt 80 -and $hasFutures) {
        return @{ route = "FUTURES"; leverage = if ($direction -eq "LONG") { 3 } else { 2 } }
    }

    # Momentum médio/baixo → SPOT (seguro)
    if ($hasSpot) {
        return @{ route = "SPOT"; leverage = 1 }
    }

    # Fallback
    if ($hasFutures) {
        return @{ route = "FUTURES"; leverage = 2 }
    }

    @{ route = "FAILED"; leverage = 0 }
}

function Get-CapitalAllocation {
    param([double]$total)
    @{
        futures = $total * 0.70
        spot    = $total * 0.30
    }
}

function Get-Leverage {
    param([string]$regime, [string]$route)

    if ($route -eq "SPOT") { return 1 }

    switch ($regime) {
        "BEAR_WEAK"  { return 3 }
        "BULL_STRONG" { return 5 }
        default      { return 3 }
    }
}

function Test-RiskParity {
    param([double]$longSize, [double]$shortSize)
    $shortSize -le $longSize  # SHORT ≤ LONG
}

function Test-TotalCapOk {
    param([double]$futures, [double]$capital)
    ($futures / $capital) -lt 0.50  # Max 50% capital em futures
}
