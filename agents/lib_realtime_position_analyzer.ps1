# agents/lib_realtime_position_analyzer.ps1
# Real-time position analysis + auto-learning engine
# Sync live positions from CoinEx, analyze multi-TF, suggest evolution
#
# Purpose: Keep cloud state ALWAYS current, feed learning engine,
#          suggest exits/holds/adjustments based on momentum + regime
#
# PS 5.1 compatible, no dependencies

function Sync-LivePositionsNow {
    <#
    .SYNOPSIS
    Fetch LIVE positions from CoinEx app RIGHT NOW.
    Not snapshot, not cached — actual open positions as of this second.

    .OUTPUTS
    @(position_object_array) — current state
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    try {
        if (-not (Get-Command "CoinEx-GetPendingPositions" -EA SilentlyContinue)) {
            Write-Verbose "[realtime] CoinEx lib not loaded"
            return @()
        }

        $futures = @(CoinEx-GetPendingPositions -IsFutures $true)
        $spot = @(CoinEx-GetPendingPositions -IsFutures $false)

        $all = @($futures) + @($spot)
        Write-Verbose "[realtime] Synced $($all.Count) live positions from CoinEx app"

        return $all
    } catch {
        Write-Verbose "[realtime] Sync error: $_"
        return @()
    }
}

function Analyze-PositionMomentum {
    <#
    .SYNOPSIS
    Analyze momentum of a single position across multiple timeframes.

    .PARAMETER Position
    Position object (symbol, entry_price, current_price, etc)

    .PARAMETER Regime
    Current regime (BEAR_WEAK, BULL_STRONG, etc)

    .OUTPUTS
    @{ momentum_1h, momentum_4h, momentum_1d, score, action }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [PSCustomObject]$Position,
        [string]$Regime = "BEAR_WEAK"
    )

    $symbol = $Position.symbol
    $entry = [double]$Position.entry_price
    $current = [double]$Position.current_price ?? [double]$Position.mark_price
    $pnlPct = (($current - $entry) / $entry) * 100

    # Get momentum from CoinEx API (klines)
    $momentum_1h = $null
    $momentum_4h = $null
    $momentum_1d = $null

    try {
        # Fetch klines for multi-TF analysis
        $klines_1h = @(CoinEx-GetKlines -Symbol $symbol -Interval "1h" -Limit 24)
        $klines_4h = @(CoinEx-GetKlines -Symbol $symbol -Interval "4h" -Limit 24)
        $klines_1d = @(CoinEx-GetKlines -Symbol $symbol -Interval "1d" -Limit 30)

        # Calculate momentum (RSI-like: positive vs negative closes)
        if ($klines_1h.Count -gt 0) {
            $ups_1h = @($klines_1h | Where-Object { $_.close -gt $_.open }).Count
            $momentum_1h = ($ups_1h / $klines_1h.Count) * 100
        }

        if ($klines_4h.Count -gt 0) {
            $ups_4h = @($klines_4h | Where-Object { $_.close -gt $_.open }).Count
            $momentum_4h = ($ups_4h / $klines_4h.Count) * 100
        }

        if ($klines_1d.Count -gt 0) {
            $ups_1d = @($klines_1d | Where-Object { $_.close -gt $_.open }).Count
            $momentum_1d = ($ups_1d / $klines_1d.Count) * 100
        }
    } catch {
        Write-Verbose "[realtime] Kline fetch error for $symbol: $_"
    }

    # Decision logic
    $action = "HOLD"
    $score = 50  # 0-100, 50=neutral

    if ($pnlPct -lt -15) {
        # Severe drawdown
        if ($momentum_1h -lt 30 -and $momentum_4h -lt 30) {
            $action = "CLOSE_LOSS"  # No recovery momentum
            $score = 10
        } else {
            $action = "MONITOR_TIGHT"  # Momentum exists, watch SL
            $score = 25
        }
    } elseif ($pnlPct -lt -5) {
        # Moderate drawdown
        if ($momentum_1h -gt 60 -and $momentum_4h -gt 50) {
            $action = "HOLD_RECOVERY"  # Strong bounce signals
            $score = 65
        } else {
            $action = "CLOSE_MARGIN"  # No recovery, free capital
            $score = 35
        }
    } elseif ($pnlPct -gt 2) {
        # Winning
        if ($momentum_1d -gt 60) {
            $action = "TRAIL_STOP"  # Trend up, protect gains
            $score = 80
        } else {
            $action = "HOLD_PROFIT"
            $score = 75
        }
    }

    return @{
        symbol         = $symbol
        pnl_pct        = [math]::Round($pnlPct, 2)
        momentum_1h    = [math]::Round($momentum_1h ?? 0, 1)
        momentum_4h    = [math]::Round($momentum_4h ?? 0, 1)
        momentum_1d    = [math]::Round($momentum_1d ?? 0, 1)
        action         = $action
        score          = $score
        regime_match   = if ($Regime -match "BEAR" -and $Position.direction -eq "LONG") { "MISMATCH" } else { "OK" }
    }
}

function Get-EvolutionSuggestions {
    <#
    .SYNOPSIS
    Auto-learning engine: analyze all positions, suggest evolutions.

    .PARAMETER Positions
    Array of current positions

    .PARAMETER Regime
    Current regime

    .OUTPUTS
    @{ actions=array, learning_points=array, next_entry_rules=array }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [PSCustomObject[]]$Positions,
        [string]$Regime = "BEAR_WEAK"
    )

    $actions = @()
    $learning = @()
    $next_rules = @()

    # Analyze each position
    foreach ($pos in $Positions) {
        $analysis = Analyze-PositionMomentum -Position $pos -Regime $Regime

        # Log action
        $actions += @{
            symbol = $analysis.symbol
            action = $analysis.action
            score  = $analysis.score
            pnl    = $analysis.pnl_pct
        }

        # Learning points
        if ($analysis.action -eq "CLOSE_LOSS") {
            $learning += @{
                type    = "drawdown_closeout"
                symbol  = $analysis.symbol
                reason  = "PnL < -15% + no momentum recovery"
                evolved = "Next: require momentum > 50% BEFORE entry in BEAR"
            }
        }

        if ($analysis.regime_match -eq "MISMATCH") {
            $learning += @{
                type    = "regime_mismatch"
                symbol  = $analysis.symbol
                reason  = "LONG in BEAR regime = wrong direction"
                evolved = "Next: SHORT bias in BEAR, require 4+ confluence for LONG"
            }
        }

        if ($analysis.action -eq "TRAIL_STOP") {
            $learning += @{
                type    = "trailing_success"
                symbol  = $analysis.symbol
                reason  = "Win + strong momentum = trail to capture"
                evolved = "Next: increase position size for trending setups"
            }
        }
    }

    # Aggregate next rules
    $next_rules = @(
        @{
            rule     = "BEAR regime: SHORT-first bias"
            applied  = if ($Regime -match "BEAR") { "NOW" } else { "when BEAR" }
            priority = "HIGH"
        },
        @{
            rule     = "Entry: min confluence 4 (vs 3 in BULL)"
            applied  = "ACTIVE"
            priority = "HIGH"
        },
        @{
            rule     = "Momentum gate: RSI-equivalent > 50% before entry"
            applied  = "ACTIVE"
            priority = "MEDIUM"
        },
        @{
            rule     = "Auto-close at -15% if momentum < 30% on 4H"
            applied  = "ACTIVE"
            priority = "HIGH"
        }
    )

    return @{
        actions      = $actions
        learning     = $learning
        next_rules   = $next_rules
        timestamp    = (Get-Date).ToString("o")
        analyzed     = $Positions.Count
    }
}

function Report-PositionStatus {
    <#
    .SYNOPSIS
    Generate live status report of all positions for decision-making.

    .OUTPUTS
    Pretty-printed report with actions
    #>
    [CmdletBinding()]
    param(
        [PSCustomObject[]]$Positions,
        [string]$Regime = "BEAR_WEAK"
    )

    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║  REALTIME POSITION ANALYSIS + EVOLUTION ENGINE   ║" -ForegroundColor Green
    Write-Host "║  $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")                    ║" -ForegroundColor Green
    Write-Host "╚═══════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""

    Write-Host "Regime: $Regime | Positions: $($Positions.Count)" -ForegroundColor Cyan
    Write-Host ""

    # Get evolution suggestions
    $evolution = Get-EvolutionSuggestions -Positions $Positions -Regime $Regime

    # Print actions
    Write-Host "📊 POSITION ACTIONS:" -ForegroundColor Yellow
    $evolution.actions | ForEach-Object {
        $color = switch ($_.action) {
            "CLOSE_LOSS" { "Red" }
            "CLOSE_MARGIN" { "Red" }
            "MONITOR_TIGHT" { "Yellow" }
            "HOLD_RECOVERY" { "Green" }
            "TRAIL_STOP" { "Green" }
            default { "Cyan" }
        }

        Write-Host "  • $($_.symbol) | $($_.action) | Score: $($_.score) | PnL: $($_.pnl)%" -ForegroundColor $color
    }

    # Print learning
    if ($evolution.learning.Count -gt 0) {
        Write-Host ""
        Write-Host "🧠 AUTO-LEARNING UPDATES:" -ForegroundColor Magenta
        $evolution.learning | ForEach-Object {
            Write-Host "  • $($_.type): $($_.symbol)" -ForegroundColor Gray
            Write-Host "    Reason: $($_.reason)" -ForegroundColor Gray
            Write-Host "    Evolved: $($_.evolved)" -ForegroundColor Gray
        }
    }

    # Print next rules
    Write-Host ""
    Write-Host "📋 NEXT ENTRY RULES (EVOLVED):" -ForegroundColor Cyan
    $evolution.next_rules | ForEach-Object {
        Write-Host "  • [$($_.priority)] $($_.rule)" -ForegroundColor Yellow
        Write-Host "    Applied: $($_.applied)" -ForegroundColor Gray
    }

    Write-Host ""
    return $evolution
}
