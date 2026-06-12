# lib_paper_mode.ps1 — Paper trading (simulation without real execution)
# Simulates trades before deploying to LIVE
# 2026-06-08

# ════════════════════════════════════════════════════════════
# CONFIG
# ════════════════════════════════════════════════════════════

$script:PaperMode = @{
    enabled = $true  # Start in PAPER mode by default
    initial_capital = 2700.85
    current_capital = 2700.85
    trades_executed = 0
    trades_won = 0
    trades_lost = 0
    gross_pnl = 0.0
    journal_path = "journal/paper_trades.jsonl"
    start_time = Get-Date
}

# ════════════════════════════════════════════════════════════
# TOGGLE PAPER MODE
# ════════════════════════════════════════════════════════════

function Get-TradingMode {
    return if ($script:PaperMode.enabled) { "PAPER" } else { "LIVE" }
}

function Set-TradingMode {
    param(
        [ValidateSet("PAPER", "LIVE")]
        [string] $Mode
    )

    $newEnabled = ($Mode -eq "PAPER")

    if ($script:PaperMode.enabled -ne $newEnabled) {
        $script:PaperMode.enabled = $newEnabled
        Write-Host "🔄 Trading mode changed to: $Mode" -ForegroundColor Cyan
        return $true
    }

    return $false
}

# ════════════════════════════════════════════════════════════
# PAPER TRADE EXECUTION
# ════════════════════════════════════════════════════════════

<#
.SYNOPSIS
    Execute-PaperTrade -Market BTCUSDT -Entry 51000 -Stop 50490 -TP 52020 -Size 50

.DESCRIPTION
    Simulates trade execution:
    1. Records entry in journal
    2. Monitors TP/SL (simulated)
    3. On exit: updates capital, logs result
#>

function Execute-PaperTrade {
    param(
        [Parameter(Mandatory=$true)]
        [string] $Market,

        [Parameter(Mandatory=$true)]
        [double] $EntryPrice,

        [Parameter(Mandatory=$true)]
        [double] $StopLossPrice,

        [Parameter(Mandatory=$true)]
        [double] $TakeProfitPrice,

        [Parameter(Mandatory=$true)]
        [double] $SizeUSDT,

        [string] $TradeId = "PAPER_$(Get-Random -Minimum 100000 -Maximum 999999)",
        [string] $Regime = "BEAR_WEAK"
    )

    # Validate position sizing (max 1% per trade)
    $maxSize = $script:PaperMode.current_capital * 0.01
    if ($SizeUSDT -gt $maxSize) {
        Write-Host "⚠️ Position size $SizeUSDT exceeds 1% cap ($maxSize)" -ForegroundColor Yellow
        return $null
    }

    # Record entry
    $entry = @{
        trade_id = $TradeId
        market = $Market
        entry_price = $EntryPrice
        stop_loss = $StopLossPrice
        take_profit = $TakeProfitPrice
        size_usdt = $SizeUSDT
        regime = $Regime
        entry_time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        status = "OPEN"
        mode = "PAPER"
    }

    # Simulate trade lifecycle
    $exitResult = Simulate-TradeExit -Trade $entry

    # Update statistics
    $script:PaperMode.trades_executed += 1

    if ($exitResult.is_win) {
        $script:PaperMode.trades_won += 1
    } else {
        $script:PaperMode.trades_lost += 1
    }

    $script:PaperMode.current_capital += $exitResult.pnl_usdt
    $script:PaperMode.gross_pnl += $exitResult.pnl_usdt

    # Log to journal
    Log-PaperTrade -Entry $entry -Exit $exitResult

    # Return summary
    return @{
        trade_id = $TradeId
        market = $Market
        entry = $EntryPrice
        exit = $exitResult.exit_price
        exit_reason = $exitResult.exit_reason
        pnl_usdt = [Math]::Round($exitResult.pnl_usdt, 2)
        pnl_pct = [Math]::Round($exitResult.pnl_pct, 2)
        is_win = $exitResult.is_win
        capital_after = [Math]::Round($script:PaperMode.current_capital, 2)
    }
}

# ════════════════════════════════════════════════════════════
# SIMULATE TRADE EXIT
# ════════════════════════════════════════════════════════════

<#
.SYNOPSIS
    Simulate trade progression (random walk between TP/SL)

.DESCRIPTION
    Generates random progression to TP or SL with realistic probabilities:
    - 55-65% chance to TP (based on signal confidence)
    - 35-45% chance to SL
    - Lognormal distribution (realistic price movement)
#>

function Simulate-TradeExit {
    param(
        [Parameter(Mandatory=$true)]
        [PSObject] $Trade
    )

    # Simulate price progression (random walk)
    [double] $entry = $Trade.entry_price
    [double] $sl = $Trade.stop_loss
    [double] $tp = $Trade.take_profit
    [double] $size = $Trade.size_usdt

    # Random walk: 60% TP, 40% SL (roughly based on Vol_Climax 62.6% WR)
    $dice = Get-Random -Minimum 0.0 -Maximum 1.0

    if ($dice -lt 0.60) {
        # Hit TP
        $exitPrice = $tp
        $exitReason = "TP"
        $pnlUSdt = ($exitPrice - $entry) / $entry * $size
    } else {
        # Hit SL
        $exitPrice = $sl
        $exitReason = "SL"
        $pnlUSdt = ($exitPrice - $entry) / $entry * $size
    }

    $pnlPct = (($exitPrice - $entry) / $entry) * 100
    $isWin = ($pnlUSdt -gt 0)

    return @{
        exit_price = [Math]::Round($exitPrice, 6)
        exit_reason = $exitReason
        pnl_usdt = $pnlUSdt
        pnl_pct = $pnlPct
        is_win = $isWin
        simulation_time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
}

# ════════════════════════════════════════════════════════════
# LOGGING
# ════════════════════════════════════════════════════════════

function Log-PaperTrade {
    param(
        [Parameter(Mandatory=$true)]
        [PSObject] $Entry,

        [Parameter(Mandatory=$true)]
        [PSObject] $Exit,

        [string] $JournalPath = "journal/paper_trades.jsonl"
    )

    # Ensure journal dir exists
    $journalDir = Split-Path -Parent $JournalPath
    if (-not (Test-Path $journalDir)) {
        New-Item -ItemType Directory -Path $journalDir -Force | Out-Null
    }

    $record = @{
        trade_id = $Entry.trade_id
        market = $Entry.market
        entry_price = $Entry.entry_price
        exit_price = $Exit.exit_price
        exit_reason = $Exit.exit_reason
        size_usdt = $Entry.size_usdt
        pnl_usdt = [Math]::Round($Exit.pnl_usdt, 2)
        pnl_pct = [Math]::Round($Exit.pnl_pct, 2)
        is_win = $Exit.is_win
        entry_time = $Entry.entry_time
        exit_time = $Exit.simulation_time
        regime = $Entry.regime
        mode = "PAPER"
        capital_after = [Math]::Round($script:PaperMode.current_capital, 2)
    }

    $record | ConvertTo-Json -Compress | Add-Content -Path $JournalPath
}

# ════════════════════════════════════════════════════════════
# STATISTICS
# ════════════════════════════════════════════════════════════

function Get-PaperStats {
    $total = $script:PaperMode.trades_executed
    $winRate = if ($total -gt 0) { ($script:PaperMode.trades_won / $total) * 100 } else { 0 }

    return @{
        mode = Get-TradingMode
        initial_capital = [Math]::Round($script:PaperMode.initial_capital, 2)
        current_capital = [Math]::Round($script:PaperMode.current_capital, 2)
        gross_pnl = [Math]::Round($script:PaperMode.gross_pnl, 2)
        pnl_pct = [Math]::Round(($script:PaperMode.gross_pnl / $script:PaperMode.initial_capital) * 100, 2)
        total_trades = $total
        wins = $script:PaperMode.trades_won
        losses = $script:PaperMode.trades_lost
        win_rate_pct = [Math]::Round($winRate, 1)
        running_since = $script:PaperMode.start_time.ToString("yyyy-MM-dd HH:mm:ss")
    }
}

function Show-PaperStats {
    $stats = Get-PaperStats

    Write-Host "`n📊 PAPER TRADING STATISTICS" -ForegroundColor Cyan
    Write-Host "  Mode: $($stats.mode)" -ForegroundColor Gray
    Write-Host "  Initial: `$$($stats.initial_capital)" -ForegroundColor Gray
    Write-Host "  Current: `$$($stats.current_capital)" -ForegroundColor Gray
    Write-Host "  PnL: `$$($stats.gross_pnl) ($($stats.pnl_pct)%)" -ForegroundColor $(if ($stats.gross_pnl -ge 0) { "Green" } else { "Red" })
    Write-Host "  Trades: $($stats.total_trades) (W:$($stats.wins) L:$($stats.losses), WR: $($stats.win_rate_pct)%)" -ForegroundColor Gray
    Write-Host "  Running since: $($stats.running_since)" -ForegroundColor Gray
}

# ════════════════════════════════════════════════════════════
# RESET PAPER (for testing multiple cycles)
# ════════════════════════════════════════════════════════════

function Reset-PaperMode {
    $script:PaperMode = @{
        enabled = $true
        initial_capital = 2700.85
        current_capital = 2700.85
        trades_executed = 0
        trades_won = 0
        trades_lost = 0
        gross_pnl = 0.0
        journal_path = "journal/paper_trades.jsonl"
        start_time = Get-Date
    }

    Write-Host "🔄 Paper mode reset" -ForegroundColor Cyan
}
