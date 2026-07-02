# lib_sizing_dynamics.ps1 -- Sizing dinamico (SPOT vs FUTURES, regime-aware)
# Capital total = Spot + Futures. Aloca % por regime. Calcula size por trade respeitando risco 1%

function Get-DynamicCapitalAllocation {
    [CmdletBinding()]
    param(
        [double]$SpotUsdt,
        [double]$FuturesUsdt,
        [string]$Regime = "BEAR_WEAK"
    )

    $total = $SpotUsdt + $FuturesUsdt
    if ($total -le 0) { return $null }

    # Regime-aware: BEAR favorece SHORT (80%), BULL favorece LONG (70%)
    $shortPct, $longPct = switch ($Regime) {
        "BEAR_WEAK"   { 0.80, 0.20 }
        "BEAR_STRONG" { 0.85, 0.15 }
        "BULL_WEAK"   { 0.30, 0.70 }
        "BULL_STRONG" { 0.20, 0.80 }
        default       { 0.50, 0.50 }
    }

    @{
        total_usdt    = $total
        short_alloc   = $total * $shortPct  # futures 20x leverage
        long_alloc    = $total * $longPct   # spot 1x
        short_pct     = $shortPct
        long_pct      = $longPct
    }
}

function Get-SizePerTrade {
    [CmdletBinding()]
    param(
        [double]$AllocatedCapital,
        [int]$MaxConcurrentTrades = 5,
        [double]$RiskTolerancePct = 0.01,  # 1% max loss total
        [double]$StopLossPct = 0.02        # 2% stop-loss width
    )

    # Max perda tolerada = 1% do capital total
    $maxLossTotal = $AllocatedCapital * $RiskTolerancePct

    # Distribui entre trades concorrentes
    $maxLossPerTrade = $maxLossTotal / $MaxConcurrentTrades

    # Size = max_loss_per_trade / stop_width (aprox)
    $sizeUsdt = $maxLossPerTrade / $StopLossPct

    [math]::Round($sizeUsdt, 2)
}

function Test-SizingValidation {
    [CmdletBinding()]
    param(
        [double]$SizeUsdt,
        [double]$CapitalUsdt,
        [double]$Leverage = 1.0
    )

    $maxPctCapital = 5.0  # max 5% por trade
    $singlePct = ($SizeUsdt * $Leverage / $CapitalUsdt) * 100

    if ($singlePct -gt $maxPctCapital) {
        return @{ valid = $false; reason = "size_exceeds_5pct_capital ($singlePct%)" }
    }

    @{ valid = $true; size_pct = [math]::Round($singlePct, 2) }
}

function Resolve-StopTargetPct {
    # 2026-06-17: conserta StopPct=0 -- gems TRIGGER tem sizing sem stop_pct/target_pct
    # -> Calculate-StopTarget lancava. Aqui devolve fracoes validas com default R:R 1:5.
    [CmdletBinding()]
    param(
        [object] $Sizing,
        [double] $DefaultStop   = 0.02,
        [double] $DefaultTarget = 0.10   # R:R 1:5
    )

    $stop = $null; $tgt = $null
    if ($Sizing) {
        if ($Sizing.PSObject.Properties['stop_pct'])   { $stop = $Sizing.stop_pct }
        elseif ($Sizing -is [hashtable] -and $Sizing.ContainsKey('stop_pct')) { $stop = $Sizing['stop_pct'] }
        if ($Sizing.PSObject.Properties['target_pct']) { $tgt = $Sizing.target_pct }
        elseif ($Sizing -is [hashtable] -and $Sizing.ContainsKey('target_pct')) { $tgt = $Sizing['target_pct'] }
    }

    $stopD = [double]($stop)
    $tgtD  = [double]($tgt)
    if ($stopD -le 0 -or $stopD -ge 1) { $stopD = $DefaultStop }
    if ($tgtD  -le 0)                  { $tgtD  = $DefaultTarget }

    @{ stop_pct = $stopD; target_pct = $tgtD }
}

# Export-ModuleMember nao necessario em dot-source; comentado para compatibilidade Pester
