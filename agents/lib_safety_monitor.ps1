# lib_safety_monitor.ps1 — Automatic safety checks every cycle
# Auto-switches PAPER mode if any red flag detected
# 2026-06-08

<#
.SYNOPSIS
    Invoke-SafetyMonitor — Runs all checks and takes action if needed

.DESCRIPTION
    Checks:
    1. Win rate (< 30% = PAPER)
    2. Daily drawdown (> 10% = PAPER)
    3. Capital discrepancy (> $50 = PAPER)
    4. System health (Telegram offline > 30min = PAPER)
    5. Pair quality (WR < 40% = disable pair)
    6. Hot streak detection (> 5 losses = PAUSE)

.NOTES
    Runs at end of each scan_master.ps1 cycle
    Logs all findings to journal/safety_events.jsonl
    Auto-alerts via Telegram on critical issues
#>

# ════════════════════════════════════════════════════════
# CONFIG
# ════════════════════════════════════════════════════════

$script:SafetyConfig = @{
    journal_path = "journal/trade_outcomes.jsonl"
    safety_events_path = "journal/safety_events.jsonl"
    logs_path = "logs"

    # Thresholds
    min_win_rate = 0.30  # < 30% = critical
    max_daily_drawdown = 0.10  # > 10% = critical
    max_capital_discrepancy = 50.0  # > $50 = critical
    max_log_age_min = 30  # > 30min offline = critical
    min_pair_win_rate = 0.40  # < 40% = disable pair
    max_consecutive_losses = 5  # > 5 in row = pause

    check_interval_min = 5  # Every 5 minutes
    last_check = $null
}

# ════════════════════════════════════════════════════════
# 1. CHECK: WIN RATE
# ════════════════════════════════════════════════════════

function Test-WinRateCritical {
    param(
        [int] $TradesLookback = 20,
        [switch] $Verbose = $false
    )

    $trades = @()
    if (Test-Path $script:SafetyConfig.journal_path) {
        $trades = @(Get-Content $script:SafetyConfig.journal_path |
                   ConvertFrom-Json -ErrorAction SilentlyContinue |
                   Where-Object { $_ }) | Select-Object -Last $TradesLookback
    }

    if ($trades.Count -lt 5) {
        if ($Verbose) { Write-Host "ℹ️ Não há trades suficientes pra avaliar WR" -ForegroundColor Gray }
        return $false
    }

    $wins = @($trades | Where-Object { $_.pnl_usdt -gt 0 }).Count
    $losses = @($trades | Where-Object { $_.pnl_usdt -le 0 }).Count
    $winRate = $wins / ($wins + $losses)

    if ($Verbose) {
        Write-Host "📊 Win Rate: $($winRate * 100)% ($wins W / $losses L)" -ForegroundColor Cyan
    }

    if ($winRate -lt $script:SafetyConfig.min_win_rate) {
        Write-Host "🚨 CRÍTICO: Win rate $($winRate * 100)% < 30%" -ForegroundColor Red
        return $true
    }

    if ($winRate -lt 0.45) {
        Write-Host "⚠️ AVISO: Win rate $($winRate * 100)% (esperado 60%+)" -ForegroundColor Yellow
    }

    return $false
}

# ════════════════════════════════════════════════════════
# 2. CHECK: Daily Drawdown
# ════════════════════════════════════════════════════════

function Test-DailyDrawdownCritical {
    param(
        [switch] $Verbose = $false
    )

    $today = (Get-Date).ToString("yyyy-MM-dd")
    $trades = @()

    if (Test-Path $script:SafetyConfig.journal_path) {
        $trades = @(Get-Content $script:SafetyConfig.journal_path |
                   ConvertFrom-Json -ErrorAction SilentlyContinue |
                   Where-Object { $_ -and $_.timestamp -like "$today*" })
    }

    if ($trades.Count -eq 0) {
        if ($Verbose) { Write-Host "ℹ️ Sem trades hoje ainda" -ForegroundColor Gray }
        return $false
    }

    $totalLoss = ($trades | Where-Object { $_.pnl_usdt -lt 0 } |
                 Measure-Object -Property pnl_usdt -Sum).Sum
    $totalGain = ($trades | Where-Object { $_.pnl_usdt -gt 0 } |
                 Measure-Object -Property pnl_usdt -Sum).Sum

    $netPnL = $totalGain + $totalLoss
    $drawdownPct = if ($netPnL -lt 0) { [Math]::Abs($netPnL) / 3654.83 } else { 0 }

    if ($Verbose) {
        Write-Host "📉 Daily Drawdown: $($drawdownPct * 100)% (ganho: `$$totalGain, perda: `$$totalLoss)" -ForegroundColor Cyan
    }

    if ($drawdownPct -gt $script:SafetyConfig.max_daily_drawdown) {
        Write-Host "🚨 CRÍTICO: Drawdown $($drawdownPct * 100)% > 10% em 1 dia" -ForegroundColor Red
        return $true
    }

    if ($drawdownPct -gt 0.05) {
        Write-Host "⚠️ AVISO: Drawdown $($drawdownPct * 100)% (monitorar)" -ForegroundColor Yellow
    }

    return $false
}

# ════════════════════════════════════════════════════════
# 3. CHECK: Capital Discrepancy
# ════════════════════════════════════════════════════════

function Test-CapitalDiscrepancyCritical {
    param(
        [switch] $Verbose = $false
    )

    . (Join-Path (Get-Location) "agents\lib_capital_audit.ps1") 2>$null
    $audit = Get-CapitalAudit

    if ($Verbose) {
        Write-Host "💰 Capital Audit: onchain `$$($audit.onchain_capital) vs expected `$$($audit.expected_capital)" -ForegroundColor Cyan
    }

    if ([Math]::Abs($audit.discrepancy) -gt $script:SafetyConfig.max_capital_discrepancy) {
        Write-Host "🚨 CRÍTICO: Discrepância `$$($audit.discrepancy) > \$50" -ForegroundColor Red
        Write-Host "   Pode ser: manual trade no CoinEx ou bug no sistema" -ForegroundColor Yellow
        return $true
    }

    if ([Math]::Abs($audit.discrepancy) -gt 20) {
        Write-Host "⚠️ AVISO: Discrepância `$$($audit.discrepancy) (investigar)" -ForegroundColor Yellow
        Reconcile-CapitalDiscrepancy | Out-Null
    }

    return $false
}

# ════════════════════════════════════════════════════════
# 4. CHECK: System Health (Telegram/Logs)
# ════════════════════════════════════════════════════════

function Test-SystemHealthCritical {
    param(
        [switch] $Verbose = $false
    )

    # Find latest log file
    $logFiles = Get-ChildItem $script:SafetyConfig.logs_path -Filter "master_*.log" -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if (-not $logFiles) {
        if ($Verbose) { Write-Host "⚠️ Nenhum log encontrado" -ForegroundColor Yellow }
        return $false
    }

    $lastWriteTime = $logFiles.LastWriteTime
    $minutesAgo = ((Get-Date) - $lastWriteTime).TotalMinutes

    if ($Verbose) {
        Write-Host "📋 Último log: $minutesAgo minutos atrás ($($lastWriteTime.ToString('HH:mm:ss')))" -ForegroundColor Cyan
    }

    if ($minutesAgo -gt $script:SafetyConfig.max_log_age_min) {
        Write-Host "🚨 CRÍTICO: Sistema offline há $([Math]::Round($minutesAgo))+ minutos" -ForegroundColor Red
        Write-Host "   GitHub Actions workflow pode ter falho" -ForegroundColor Yellow
        return $true
    }

    if ($minutesAgo -gt 20) {
        Write-Host "⚠️ AVISO: Sistema lento ($minutesAgo min atrás)" -ForegroundColor Yellow
    }

    return $false
}

# ════════════════════════════════════════════════════════
# 5. CHECK: Pair Quality
# ════════════════════════════════════════════════════════

function Test-PairQuality {
    param(
        [switch] $Verbose = $false
    )

    $trades = @()
    if (Test-Path $script:SafetyConfig.journal_path) {
        $trades = @(Get-Content $script:SafetyConfig.journal_path |
                   ConvertFrom-Json -ErrorAction SilentlyContinue |
                   Where-Object { $_ }) | Select-Object -Last 50
    }

    if ($trades.Count -lt 10) {
        if ($Verbose) { Write-Host "ℹ️ Trades insuficientes pra avaliar pares" -ForegroundColor Gray }
        return @()
    }

    $pairStats = $trades | Group-Object market | ForEach-Object {
        $pair = $_.Name
        $pairTrades = $_.Group
        $wins = @($pairTrades | Where-Object { $_.pnl_usdt -gt 0 }).Count
        $total = $pairTrades.Count
        $winRate = if ($total -gt 0) { $wins / $total } else { 0 }
        $totalPnL = ($pairTrades | Measure-Object -Property pnl_usdt -Sum).Sum

        [PSCustomObject]@{
            pair = $pair
            trades = $total
            win_rate = $winRate
            total_pnl = [Math]::Round($totalPnL, 2)
            quality = if ($winRate -lt 0.40) { "BAD" } elseif ($winRate -lt 0.50) { "WARN" } else { "GOOD" }
        }
    }

    # BTCUSDT nunca desativa (é o nosso pai)
    $badPairs = @($pairStats | Where-Object { $_.quality -eq "BAD" -and $_.pair -ne "BTCUSDT" })

    if ($badPairs.Count -gt 0) {
        Write-Host "🔴 PARES RUINS (WR < 40%, exceto BTCUSDT que é nosso pai):" -ForegroundColor Red
        foreach ($pair in $badPairs) {
            Write-Host "   ❌ $($pair.pair): $($pair.win_rate * 100)% WR ($($pair.trades) trades, PnL `$$($pair.total_pnl))" -ForegroundColor Red
        }
    }

    # Se BTCUSDT tá ruim, log mas nunca desativa
    $btcusdtStats = $pairStats | Where-Object { $_.pair -eq "BTCUSDT" }
    if ($btcusdtStats -and $btcusdtStats.win_rate -lt 0.40) {
        Write-Host "⚠️ BTCUSDT baixa performance ($($btcusdtStats.win_rate * 100)% WR) mas NUNCA desativa (é o nosso pai)" -ForegroundColor Yellow
    }

    if ($Verbose) {
        Write-Host "📊 Qualidade de Pares:" -ForegroundColor Cyan
        foreach ($pair in $pairStats) {
            $emoji = switch ($pair.quality) {
                "GOOD" { "✅" }
                "WARN" { "⚠️" }
                "BAD" { "❌" }
            }
            Write-Host "   $emoji $($pair.pair): $($pair.win_rate * 100)% WR ($($pair.trades) trades)" -ForegroundColor Cyan
        }
    }

    return $badPairs
}

# ════════════════════════════════════════════════════════
# 6. CHECK: Consecutive Losses
# ════════════════════════════════════════════════════════

function Test-ConsecutiveLosses {
    param(
        [switch] $Verbose = $false
    )

    $trades = @()
    if (Test-Path $script:SafetyConfig.journal_path) {
        $trades = @(Get-Content $script:SafetyConfig.journal_path |
                   ConvertFrom-Json -ErrorAction SilentlyContinue |
                   Where-Object { $_ }) | Select-Object -Last 10
    }

    if ($trades.Count -lt 3) {
        return $false
    }

    $consecutiveLosses = 0
    foreach ($trade in $trades) {
        if ($trade.pnl_usdt -le 0) {
            $consecutiveLosses++
        } else {
            $consecutiveLosses = 0
        }

        if ($consecutiveLosses -ge $script:SafetyConfig.max_consecutive_losses) {
            if ($Verbose) { Write-Host "⚠️ $consecutiveLosses perdidas consecutivas" -ForegroundColor Yellow }
            return $true
        }
    }

    return $false
}

# ════════════════════════════════════════════════════════
# MAIN: Invoke-SafetyMonitor
# ════════════════════════════════════════════════════════

function Invoke-SafetyMonitor {
    param(
        [switch] $Verbose = $false
    )

    Write-Host "`n🛡️ SAFETY MONITOR — Verificações Automáticas" -ForegroundColor Cyan
    Write-Host "════════════════════════════════════════════════" -ForegroundColor Gray

    # Run all checks
    $criticalWR = Test-WinRateCritical -Verbose:$Verbose
    $criticalDD = Test-DailyDrawdownCritical -Verbose:$Verbose
    $criticalDC = Test-CapitalDiscrepancyCritical -Verbose:$Verbose
    $criticalSH = Test-SystemHealthCritical -Verbose:$Verbose
    $badPairs = @(Test-PairQuality -Verbose:$Verbose)
    $hotStreak = Test-ConsecutiveLosses -Verbose:$Verbose

    # Determine action
    $shouldSwitchPaper = $criticalWR -or $criticalDD -or $criticalDC -or $criticalSH
    $shouldPauseScan = $hotStreak

    # Log findings
    $event = @{
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        check_type = "SAFETY_MONITOR"
        critical_win_rate = $criticalWR
        critical_drawdown = $criticalDD
        critical_discrepancy = $criticalDC
        critical_system_health = $criticalSH
        bad_pairs = $badPairs | ForEach-Object { $_.pair }
        hot_streak = $hotStreak
        action_taken = if ($shouldSwitchPaper) { "SWITCH_TO_PAPER" } elseif ($shouldPauseScan) { "PAUSE_SCAN" } else { "CONTINUE" }
    }

    # Append to safety events
    $safetyDir = Split-Path -Parent $script:SafetyConfig.safety_events_path
    if (-not (Test-Path $safetyDir)) {
        New-Item -ItemType Directory -Path $safetyDir -Force | Out-Null
    }

    $event | ConvertTo-Json | Add-Content -Path $script:SafetyConfig.safety_events_path

    # Take action
    if ($shouldSwitchPaper) {
        Write-Host "`n❌ CRÍTICO DETECTADO — VOLTANDO PARA PAPER MODE" -ForegroundColor Red
        . (Join-Path (Get-Location) "agents\lib_place_order.ps1") 2>$null
        Set-TradingMode -Mode PAPER

        # Alert via Telegram
        . (Join-Path (Get-Location) "agents\lib_telegram_commands.ps1") 2>$null
        $reason = if ($criticalWR) { "Win rate crítica < 30%" } `
                 elseif ($criticalDD) { "Drawdown > 10% em 1 dia" } `
                 elseif ($criticalDC) { "Discrepância capital > \$50" } `
                 else { "Sistema offline > 30min" }
        Alert-Error -ErrorMessage "🚨 Sistema retornou para PAPER MODE. Motivo: $reason"

        return @{
            status = "CRITICAL"
            action = "SWITCHED_TO_PAPER"
            reason = $reason
            event = $event
        }
    }

    if ($shouldPauseScan) {
        Write-Host "`n⚠️ HOT STREAK DETECTADO — PAUSANDO SCAN TEMPORARIAMENTE" -ForegroundColor Yellow
        . (Join-Path (Get-Location) "agents\lib_telegram_commands.ps1") 2>$null
        Alert-Error -ErrorMessage "⚠️ 5+ perdidas consecutivas. Pausando scanner por 30min."

        return @{
            status = "WARNING"
            action = "PAUSED_SCAN"
            reason = "Hot streak (5+ losses)"
            event = $event
        }
    }

    Write-Host "`n✅ Todas as verificações OK — Continuando LIVE" -ForegroundColor Green

    return @{
        status = "OK"
        action = "CONTINUE"
        event = $event
    }
}

# ════════════════════════════════════════════════════════
# Helper: Show Safety Report
# ════════════════════════════════════════════════════════

function Show-SafetyReport {
    param(
        [int] $EventsLookback = 20
    )

    Write-Host "`n📋 SAFETY EVENTS REPORT" -ForegroundColor Cyan
    Write-Host "════════════════════════════════════════════════" -ForegroundColor Gray

    if (-not (Test-Path $script:SafetyConfig.safety_events_path)) {
        Write-Host "Sem eventos registrados" -ForegroundColor Gray
        return
    }

    $events = @(Get-Content $script:SafetyConfig.safety_events_path |
               ConvertFrom-Json -ErrorAction SilentlyContinue |
               Where-Object { $_ }) | Select-Object -Last $EventsLookback

    foreach ($event in $events) {
        $action = $event.action_taken
        $emoji = switch ($action) {
            "SWITCH_TO_PAPER" { "❌" }
            "PAUSE_SCAN" { "⚠️" }
            default { "✅" }
        }

        Write-Host "$emoji [$($event.timestamp)] $action" -ForegroundColor $(if ($action -eq "SWITCH_TO_PAPER") { "Red" } elseif ($action -eq "PAUSE_SCAN") { "Yellow" } else { "Green" })

        if ($event.critical_win_rate) { Write-Host "   - Win rate crítica" -ForegroundColor Red }
        if ($event.critical_drawdown) { Write-Host "   - Drawdown > 10%" -ForegroundColor Red }
        if ($event.critical_discrepancy) { Write-Host "   - Discrepância capital > \$50" -ForegroundColor Red }
        if ($event.critical_system_health) { Write-Host "   - Sistema offline" -ForegroundColor Red }
        if ($event.hot_streak) { Write-Host "   - 5+ perdidas consecutivas" -ForegroundColor Yellow }
        if ($event.bad_pairs.Count -gt 0) { Write-Host "   - Pares ruins: $($event.bad_pairs -join ', ')" -ForegroundColor Yellow }
    }

    Write-Host ""
}
