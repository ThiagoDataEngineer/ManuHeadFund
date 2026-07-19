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
    # 2026-07-19: campos reais confirmados via job one-shot contra API real
    # (diag_closed_position_shape_readonly_2026_07_19.ps1) -- versao anterior
    # esperava entryPrice/exitPrice/quantity/orderId (camelCase), que NUNCA
    # existiram na resposta real da CoinEx (era especulacao nunca validada).
    # Shape real de /v2/futures/finished-position: position_id, market,
    # side ("long"|"short" minusculo), realized_pnl (STRING, ja calculado
    # pela corretora -- nao precisa recalcular de entry/exit), avg_entry_price,
    # leverage, created_at/updated_at (epoch MILLISECONDS), finished_type
    # (motivo do fechamento: stop_loss, take_profit, etc).
    param([PSCustomObject]$ClosedTrade)

    $sideRaw = [string]$ClosedTrade.side
    $side = if ($sideRaw -eq "long") { "LONG" } elseif ($sideRaw -eq "short") { "SHORT" } else { $sideRaw.ToUpper() }
    $entry = [double]$ClosedTrade.avg_entry_price
    $pnlUsd = [double]$ClosedTrade.realized_pnl
    $margin = [double]$ClosedTrade.ath_margin_size

    # pnl_percent: realized_pnl (USD) sobre a margem inicial usada (ath_margin_size
    # -- "all-time-high" margin, valor de margem no pico da posicao, unico dado de
    # capital alocado disponivel neste shape). Fallback pra 0 se margem ausente/zero
    # (nao adivinha, so nao calcula).
    $pnlPct = if ($margin -ne 0) { ($pnlUsd / $margin) * 100 } else { 0.0 }

    $entryTs = try { [datetimeoffset]::FromUnixTimeMilliseconds([long]$ClosedTrade.created_at).UtcDateTime } catch { [datetime]::UtcNow }
    $closedTs = try { [datetimeoffset]::FromUnixTimeMilliseconds([long]$ClosedTrade.updated_at).UtcDateTime } catch { [datetime]::UtcNow }

    # id: PRIMARY KEY NOT NULL em manuheadfund.trade_outcomes (mesmo achado ja
    # documentado em ConvertTo-SupabaseOutcome -- toda gravacao sem id viola a
    # constraint). position_id da CoinEx e' unico por posicao fechada, entao
    # usa direto (mais estavel que gerar guid novo a cada reconciliacao).
    $genId = "{0}|{1}|position_sync|{2}" -f $ClosedTrade.market, $side, [string]$ClosedTrade.position_id

    @{
        id = $genId
        entry_ts = $entryTs
        symbol = [string]$ClosedTrade.market
        market = [string]$ClosedTrade.market
        side = $side
        direction = $side
        source = "app_import"
        entry_price = $entry
        pnl_realized = $pnlUsd
        pnl_percent = [Math]::Round($pnlPct, 4)
        closed_at = $closedTs.ToString("o")
        close_reason = [string]$ClosedTrade.finished_type
        status = "closed"
        regime = "UNKNOWN"
    }
}

function CoinEx-GetClosedPositions {
    <#
    .SYNOPSIS
    Busca posicoes FUTURES fechadas recentemente, via /v2/futures/finished-position.
    2026-07-19: implementada apos confirmar o shape real da API (job one-shot
    diag_closed_position_shape_readonly_2026_07_19.ps1) -- versao anterior desta
    funcao nunca existiu, causando falha silenciosa em Reconcile-AppToJournal
    desde que foi "wired" em trailing_stop_monitor.ps1 (2026-07-07).

    .DESCRIPTION
    A API exige -market explicito (nao aceita "todos os mercados de uma vez",
    confirmado em audit_coinex_state.ps1 2026-07-19). Descobre mercados
    candidatos via posicoes FUTURES abertas agora (pending-position) --
    cobertura pratica, nao teoricamente completa: uma posicao fechada num
    mercado sem posicao aberta atual nao aparece aqui.

    .PARAMETER Limit
    Max posicoes fechadas por mercado (default 20).

    .OUTPUTS
    @(PSCustomObject com o shape bruto de finished-position: market, side,
    realized_pnl, avg_entry_price, created_at, updated_at, finished_type, ...)
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([int]$Limit = 20)

    $markets = @()
    try {
        $pending = CoinEx-Get "/v2/futures/pending-position?market_type=FUTURES" -ErrorAction SilentlyContinue
        if ($pending.code -eq 0) {
            $markets = @($pending.data | ForEach-Object { $_.market } | Select-Object -Unique)
        }
    } catch {
        Write-Verbose "[position_sync] CoinEx-GetClosedPositions: falha ao descobrir mercados: $_"
        return @()
    }

    if ($markets.Count -eq 0) { return @() }

    $closed = @()
    foreach ($mkt in $markets) {
        try {
            $r = CoinEx-Get "/v2/futures/finished-position?market=$mkt&market_type=FUTURES&page=1&limit=$Limit" -ErrorAction SilentlyContinue
            if ($r.code -eq 0 -and $r.data.Count -gt 0) {
                $closed += $r.data
            }
        } catch {
            Write-Verbose "[position_sync] CoinEx-GetClosedPositions: falha em ${mkt}: $_"
        }
    }
    return @($closed)
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
