# agents/lib_position_sync_live.ps1
# Exchange position sync → Supabase (real-time adoption of app-opened trades)
#
# Fetches pending positions from CoinEx (Futures + Spot), mirrors to Supabase
# open_positions table, and logs reconciliation. Runs 24/7 to keep cloud aware.
#
# PS 5.1 compatible.

$_positionSyncDir = Split-Path $PSScriptRoot -Parent | Join-Path -ChildPath "journal"

# 2026-07-08: COMPLETELY DISABLED - CoinEx-GetPendingPositions param conflict
# Sync-ExchangePositionsLive is now a simple stub that returns empty array
# Positions tracked via parallel Trailing system instead
function Sync-ExchangePositionsLive {
    param(
        [bool]$IsFutures = $true,
        [int]$MaxPositions = 100
    )
    # STUB: return empty array immediately — no position sync from exchange
    return @()
}

function Reconcile-AppToJournal {
    <#
    .SYNOPSIS
    Reconcile closed positions from app → trade_outcomes table + local mirror.
    Triggered when app reports closed trades. Calculates realized PnL.

    .PARAMETER Limit
    Max closed trades to import (default 20)

    .OUTPUTS
    @(trade_outcome_records...)
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [int]$Limit = 20
    )

    try {
        Write-Verbose "[position_sync] Reconciling closed positions..."

        # Fetch closed trades from exchange
        $closed = @()
        try {
            if (Test-Command -Name "CoinEx-GetClosedPositions") {
                $closed = @(CoinEx-GetClosedPositions -Limit $Limit -ErrorAction SilentlyContinue)
            } else {
                Write-Warning "[position_sync] CoinEx-GetClosedPositions not available"
                return @()
            }
        } catch {
            Write-Error "[position_sync] CoinEx closed fetch failed: $_"
            return @()
        }

        if ($closed.Count -eq 0) {
            Write-Verbose "[position_sync] No closed positions to reconcile"
            return @()
        }

        # Convert each closed trade to outcome
        $outcomes = @()
        foreach ($trade in $closed) {
            try {
                $outcome = _Convert-ClosedTradeToOutcome -ClosedTrade $trade

                # Save to Supabase via trade_journal helper (if available)
                if (Test-Command -Name "Save-TradeOutcome") {
                    Save-TradeOutcome -TradeRecord $outcome -ErrorAction SilentlyContinue | Out-Null
                } else {
                    # Direct save fallback
                    if (Test-Command -Name "Save-StateRecords") {
                        Save-StateRecords -Table "trade_outcomes" -Records @($outcome) -PrimaryKey "id" -ErrorAction SilentlyContinue | Out-Null
                    }
                }

                $outcomes += $outcome
            } catch {
                Write-Error "[position_sync] Convert closed trade failed: $_"
            }
        }

        Write-Verbose "[position_sync] Reconciled $($outcomes.Count) closed positions"
        return @($outcomes)
    } catch {
        Write-Error "[position_sync] Reconcile-AppToJournal failed: $_"
        return @()
    }
}

function Get-AdoptableOrphans {
    <#
    .SYNOPSIS
    Find positions missing SL or TP (risk). Returns records needing adoption.

    .OUTPUTS
    @(position_records_orphaned...)
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    try {
        # Get all active positions
        if (-not (Test-Command -Name "Get-StateRecords")) {
            Write-Verbose "[position_sync] Get-StateRecords not available"
            return @()
        }

        $active = @(Get-StateRecords -Table "open_positions" -Filter @{ status = "active" } -ErrorAction SilentlyContinue)
        $orphans = @($active | Where-Object {
            ([double]$_.stop_loss -eq 0 -or [string]::IsNullOrWhiteSpace($_.stop_loss)) -or
            ([double]$_.take_profit -eq 0 -or [string]::IsNullOrWhiteSpace($_.take_profit))
        })

        Write-Verbose "[position_sync] Found $($orphans.Count) orphaned positions (missing SL or TP)"
        return @($orphans)
    } catch {
        Write-Error "[position_sync] Get-AdoptableOrphans failed: $_"
        return @()
    }
}

function Sync-PositionsPeriodic {
    <#
    .SYNOPSIS
    Periodic sync task (runs every 60s in production).
    Orchestrates Futures + Spot sync, reconciliation, and logging.

    .OUTPUTS
    @{ futures_synced=int; spot_synced=int; closed_outcomes=int; orphans=int }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    try {
        $ts = (Get-Date).ToUniversalTime()
        Write-Verbose "[position_sync] [$($ts.ToString('o'))] Starting periodic sync..."

        # 1. Sync Futures
        $futuresPos = @(Sync-ExchangePositionsLive -IsFutures $true)

        # 2. Sync Spot
        $spotPos = @(Sync-ExchangePositionsLive -IsFutures $false)

        # 3. Reconcile closed trades
        $closedOutcomes = @(Reconcile-AppToJournal -Limit 10)

        # 4. Identify orphans
        $orphans = @(Get-AdoptableOrphans)

        $result = @{
            sync_ts = $ts
            futures_synced = $futuresPos.Count
            spot_synced = $spotPos.Count
            closed_outcomes = $closedOutcomes.Count
            orphans_count = $orphans.Count
        }

        Write-Verbose "[position_sync] Sync complete: $($result | ConvertTo-Json -Compress)"
        return $result
    } catch {
        Write-Error "[position_sync] Sync-PositionsPeriodic failed: $_"
        return @{ error = $_.Message }
    }
}

# ─────────────────────────────────────────────────────────────────────
# Private helpers
# ─────────────────────────────────────────────────────────────────────

function _Normalize-ExchangePosition {
    param(
        [PSCustomObject]$Position,
        [bool]$IsFutures
    )

    # Expected fields from CoinEx API: orderId, symbol, side, entryPrice, quantity, markPrice, stopLossPrice, takeProfitPrice, created_at
    # 2026-07-09 FIX PS5.1: ?? e PS7-only -- quebrava parse da lib inteira (position sync morto, Layer 3)
    $side = if ($Position.side) { [string]$Position.side } else { "LONG" }
    $symbol = [string]$Position.symbol

    # Auto-detect regime (placeholder — integrate with Get-CurrentRegime if available)
    $regime = if (Test-Command -Name "Get-CurrentRegime") {
        Get-CurrentRegime -ErrorAction SilentlyContinue
    } else {
        "UNKNOWN"
    }

    @{
        id = [string]$Position.orderId
        symbol = $symbol
        direction = $side  # LONG|SHORT
        entry_price = [double]$Position.entryPrice
        quantity = [double]$Position.quantity
        stop_loss = [double]$(if ($Position.stopLossPrice) { $Position.stopLossPrice } else { 0 })
        take_profit = [double]$(if ($Position.takeProfitPrice) { $Position.takeProfitPrice } else { 0 })
        current_price = [double]$(if ($Position.markPrice) { $Position.markPrice } elseif ($Position.lastPrice) { $Position.lastPrice } else { 0 })
        trailing_stop = if ($Position.trailingStop) { [double]$Position.trailingStop } else { $null }
        source = "app_sync"
        regime = $regime
        status = "active"
        entered_at = if ($Position.created_at -is [datetime]) { $Position.created_at.ToUniversalTime() } else { [datetime]::Parse([string]$Position.created_at).ToUniversalTime() }
        created_at = (Get-Date).ToUniversalTime()
    }
}

function _Convert-ClosedTradeToOutcome {
    param([PSCustomObject]$ClosedTrade)

    $entry = [double]$ClosedTrade.entryPrice
    $exit = [double]$ClosedTrade.exitPrice
    $qty = [double]$ClosedTrade.quantity
    $side = [string]$ClosedTrade.side

    # Calculate realized PnL (accounting for direction)
    $pnl = if ($side -eq "LONG") {
        ($exit - $entry) * $qty
    } else {
        ($entry - $exit) * $qty
    }

    $pnlPct = if ($entry -ne 0) { ($pnl / ($entry * $qty)) * 100 } else { 0 }

    @{
        entry_ts = if ($ClosedTrade.entered_at -is [datetime]) { $ClosedTrade.entered_at.ToUniversalTime() } else { [datetime]::Parse([string]$ClosedTrade.entered_at).ToUniversalTime() }
        symbol = [string]$ClosedTrade.symbol
        direction = $side
        source = "app_import"
        entry_price = $entry
        exit_price = $exit
        quantity = $qty
        pnl_realized = $pnl
        pnl_percent = $pnlPct
        status = "closed"
        regime = if (Test-Command -Name "Get-CurrentRegime") { Get-CurrentRegime -ErrorAction SilentlyContinue } else { "UNKNOWN" }
    }
}

function _Log-SyncActivity {
    param(
        [string]$Action,  # fetch|adopt|close|liquidate
        [string]$Symbol,
        [hashtable]$State
    )

    try {
        if (-not (Test-Command -Name "Save-StateRecords")) { return }

        $logEntry = @{
            sync_ts = (Get-Date).ToUniversalTime()
            symbol = $Symbol
            action = $Action
            new_state = ($State | ConvertTo-Json -Depth 4 -Compress)
        }

        Save-StateRecords -Table "exchange_sync_log" -Records @($logEntry) -ErrorAction SilentlyContinue | Out-Null
        return $true
    } catch {
        Write-Verbose "[position_sync] Log activity failed: $_"
        return $false
    }
}

function Test-Command {
    param([string]$Name)
    try {
        Get-Command $Name -ErrorAction SilentlyContinue | Out-Null
        return $?
    } catch {
        return $false
    }
}
