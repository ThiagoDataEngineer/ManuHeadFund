# lib_capital_audit.ps1 — Audit capital consistency
# Validates: onchain vs journal vs executed trades
# Detects manual trades on CoinEx and reconciles
# 2026-06-08

<#
.SYNOPSIS
    Audit capital across onchain (CoinEx API), journal, and executed trades

.DESCRIPTION
    - Fetches onchain capital (SPOT + FUTURES)
    - Reads journal of all executed trades
    - Calculates expected capital based on trades
    - Flags discrepancies (manual trades detected)
    - Auto-reconciles if difference is small

.NOTES
    If you trade manually on CoinEx:
    1. System fetches new onchain balance next cycle
    2. Audit compares journal vs actual
    3. Logs discrepancy to journal
    4. Continues trading with accurate capital
#>

function Get-CapitalAudit {
    param(
        [string] $JournalPath = "journal/trade_outcomes.jsonl"
    )

    # Fetch ONCHAIN capital
    . (Join-Path (Get-Location) "agents\lib_hybrid_orchestrator.ps1") 2>$null
    $onchain = Get-DynamicCapital

    # Read journal (all executed trades)
    $journalTrades = @()
    if (Test-Path $JournalPath) {
        $journalTrades = @(Get-Content $JournalPath | ConvertFrom-Json -ErrorAction SilentlyContinue | Where-Object { $_ })
    }

    # Calculate PnL from trades
    $totalPnL = 0
    $spotTrades = $journalTrades | Where-Object { $_.market_type -eq "SPOT" }
    $futuresTrades = $journalTrades | Where-Object { $_.market_type -eq "FUTURES" }

    foreach ($trade in $journalTrades) {
        if ($trade.pnl_usdt) {
            $totalPnL += $trade.pnl_usdt
        }
    }

    # Initial capital (for reference)
    $initialCapital = 3654.83  # SPOT $954.40 + FUTURES $2700.43

    # Expected capital = initial + PnL
    $expectedCapital = $initialCapital + $totalPnL

    # Actual onchain capital
    $actualCapital = $onchain.total_capital

    # Discrepancy
    $discrepancy = $actualCapital - $expectedCapital
    $discrepancyPct = if ($expectedCapital -gt 0) { ($discrepancy / $expectedCapital) * 100 } else { 0 }

    return @{
        timestamp = Get-Date
        onchain_capital = [Math]::Round($actualCapital, 2)
        onchain_spot = [Math]::Round($onchain.spot_capital, 2)
        onchain_futures = [Math]::Round($onchain.futures_capital, 2)
        expected_capital = [Math]::Round($expectedCapital, 2)
        discrepancy = [Math]::Round($discrepancy, 2)
        discrepancy_pct = [Math]::Round($discrepancyPct, 2)
        total_trades = $journalTrades.Count
        spot_trades = $spotTrades.Count
        futures_trades = $futuresTrades.Count
        journal_pnl = [Math]::Round($totalPnL, 2)
        is_consistent = [Math]::Abs($discrepancy) -lt 5.0  # Allow $5 variance
        notes = if ([Math]::Abs($discrepancy) -gt 5.0) {
            "⚠️ Manual trade detected on CoinEx"
        } else {
            "✅ Capital consistent with journal"
        }
    }
}

function Show-CapitalAudit {
    param(
        [string] $JournalPath = "journal/trade_outcomes.jsonl"
    )

    $audit = Get-CapitalAudit -JournalPath $JournalPath

    Write-Host "`n🔍 CAPITAL AUDIT" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray

    Write-Host "`n💰 ONCHAIN (CoinEx API Real-Time)" -ForegroundColor Green
    Write-Host "  Total: `$$($audit.onchain_capital)" -ForegroundColor Green
    Write-Host "  SPOT: `$$($audit.onchain_spot)" -ForegroundColor Green
    Write-Host "  FUTURES: `$$($audit.onchain_futures)" -ForegroundColor Green

    Write-Host "`n📊 EXPECTED (from journal trades)" -ForegroundColor Cyan
    Write-Host "  Initial Capital: `$3,654.83" -ForegroundColor Gray
    Write-Host "  Total PnL (journal): `$$($audit.journal_pnl)" -ForegroundColor $(if ($audit.journal_pnl -ge 0) { "Green" } else { "Red" })
    Write-Host "  Expected Capital: `$$($audit.expected_capital)" -ForegroundColor Cyan

    Write-Host "`n⚠️ DISCREPANCY" -ForegroundColor Yellow
    Write-Host "  Difference: `$$($audit.discrepancy) ($($audit.discrepancy_pct)%)" -ForegroundColor $(if ([Math]::Abs($audit.discrepancy) -lt 5) { "Green" } else { "Yellow" })
    Write-Host "  Consistency: $($audit.notes)" -ForegroundColor $(if ($audit.is_consistent) { "Green" } else { "Yellow" })

    Write-Host "`n📈 TRADES" -ForegroundColor Cyan
    Write-Host "  Total: $($audit.total_trades)" -ForegroundColor Gray
    Write-Host "  SPOT: $($audit.spot_trades)" -ForegroundColor Gray
    Write-Host "  FUTURES: $($audit.futures_trades)" -ForegroundColor Gray

    Write-Host "`n" -ForegroundColor Gray

    return $audit
}

function Reconcile-CapitalDiscrepancy {
    <#
    .SYNOPSIS
        If discrepancy detected, logs it as "MANUAL_TRADE" in journal
        System then uses onchain as source of truth for next trades
    #>
    param(
        [string] $JournalPath = "journal/trade_outcomes.jsonl"
    )

    $audit = Get-CapitalAudit -JournalPath $JournalPath

    if ([Math]::Abs($audit.discrepancy) -ge 5.0) {
        $reconciliation = @{
            timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            event = "MANUAL_TRADE_DETECTED"
            discrepancy_usdt = $audit.discrepancy
            onchain_capital = $audit.onchain_capital
            expected_capital = $audit.expected_capital
            action = "Using onchain as source of truth"
            reason = "User may have traded manually on CoinEx"
        }

        # Append to journal
        $journalDir = Split-Path -Parent $JournalPath
        if (-not (Test-Path $journalDir)) {
            New-Item -ItemType Directory -Path $journalDir -Force | Out-Null
        }

        $reconciliation | ConvertTo-Json | Add-Content -Path $JournalPath

        Write-Host "`n🔄 RECONCILIATION LOGGED" -ForegroundColor Yellow
        Write-Host "  Event: MANUAL_TRADE_DETECTED" -ForegroundColor Yellow
        Write-Host "  Difference: `$$($audit.discrepancy)" -ForegroundColor Yellow
        Write-Host "  Action: Using onchain capital as new baseline" -ForegroundColor Yellow
        Write-Host "  Journal updated: $JournalPath" -ForegroundColor Gray

        return $true
    } else {
        Write-Host "✅ Capital consistent — no reconciliation needed" -ForegroundColor Green
        return $false
    }
}
