#!/usr/bin/env pwsh
<#
MONITOR VOL_CLIMAX LIVE
Real-time tracking of vol_climax signals, trades, win rate

Usage:
  pwsh scripts/monitor_vol_climax.ps1          # Real-time tail
  pwsh scripts/monitor_vol_climax.ps1 -Report  # Summary report
#>

param(
    [switch]$Report,
    [int]$RefreshSec = 5
)

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$LogPath = Join-Path $ProjectRoot "journal\gem_loop.log"
$TradesPath = Join-Path $ProjectRoot "journal\trade_outcomes.jsonl"

function Get-VolClimaxMetrics {
    # Parse gem_loop.log for vol_climax activity
    $vcSignals = @()
    $vcTrades = @()

    if (Test-Path $LogPath) {
        $logs = Get-Content $LogPath -ErrorAction SilentlyContinue

        # Find all [VC] boost messages
        $vcMessages = $logs | Where-Object { $_ -match '\[VC\]' }

        foreach ($msg in $vcMessages) {
            if ($msg -match '\[VC\].*boost \+(\d+).*score=(\d+)') {
                $vcSignals += @{
                    boost = [int]$matches[1]
                    score = [int]$matches[2]
                    message = $msg
                }
            }
        }
    }

    # Parse trade_outcomes.jsonl for vol_climax trades (if marked)
    if (Test-Path $TradesPath) {
        Get-Content $TradesPath | Where-Object { $_.Trim() -ne '' } | ForEach-Object {
            try {
                $trade = $_ | ConvertFrom-Json -ErrorAction SilentlyContinue
                # Assume recent trades from vol_climax boost period
                if ($trade.pnl_usd) {
                    $vcTrades += @{
                        market = $trade.market
                        pnl = $trade.pnl_usd
                        win = $trade.pnl_usd -gt 0
                        pnl_pct = $trade.pnl_pct
                    }
                }
            } catch {}
        }
    }

    return @{
        signals = $vcSignals
        trades = $vcTrades
    }
}

function Show-Report {
    $metrics = Get-VolClimaxMetrics

    Write-Host ""
    Write-Host "=" * 80 -ForegroundColor Cyan
    Write-Host "VOL_CLIMAX LIVE MONITOR — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
    Write-Host "=" * 80 -ForegroundColor Cyan

    # Signals
    if ($metrics.signals.Count -gt 0) {
        Write-Host "`n[SIGNALS DETECTED] $($metrics.signals.Count)" -ForegroundColor Green
        foreach ($sig in $metrics.signals[-5..0] | Where-Object { $_ }) {
            $boost = $sig.boost
            $score = $sig.score
            Write-Host "  • Boost +$boost → Score $score" -ForegroundColor Cyan
        }
    } else {
        Write-Host "`n[SIGNALS DETECTED] 0 (waiting...)" -ForegroundColor Yellow
    }

    # Trades
    if ($metrics.trades.Count -gt 0) {
        Write-Host "`n[TRADES EXECUTED] $($metrics.trades.Count)" -ForegroundColor Green
        $wins = @($metrics.trades | Where-Object { $_.win }).Count
        $losses = $metrics.trades.Count - $wins
        $winRate = $wins / $metrics.trades.Count * 100

        Write-Host "  Win/Loss: $wins/$losses (Win rate: $('{0:F1}' -f $winRate)%)" -ForegroundColor $(if ($winRate -ge 45) { 'Green' } else { 'Yellow' })
        Write-Host "  Total PnL: $('{0:F2}' -f ($metrics.trades | Measure-Object -Property pnl -Sum).Sum) USD" -ForegroundColor $(if (($metrics.trades | Measure-Object -Property pnl -Sum).Sum -gt 0) { 'Green' } else { 'Red' })
    } else {
        Write-Host "`n[TRADES EXECUTED] 0 (waiting...)" -ForegroundColor Yellow
    }

    Write-Host "`n" -ForegroundColor Cyan
}

function Show-Tail {
    Write-Host "Monitoring gem_loop.log for [VC] messages (Ctrl+C to exit)..." -ForegroundColor Cyan

    Get-Content $LogPath -Wait -Tail 0 -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_ -match '\[VC\]|GemScan|CYCLE') {
            $color = if ($_ -match '\[VC\]') { 'Green' } else { 'Gray' }
            Write-Host $_ -ForegroundColor $color
        }
    }
}

# Main
if ($Report) {
    while ($true) {
        Clear-Host
        Show-Report
        Start-Sleep $RefreshSec
    }
} else {
    Show-Tail
}
