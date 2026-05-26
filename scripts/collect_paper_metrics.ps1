# scripts/collect_paper_metrics.ps1
# Coleta de métricas dos 48h de paper trades com Trailing Adaptativo (Layer 1)
# Uso: .\scripts\collect_paper_metrics.ps1 -StartTime "2026-05-25 14:00" -EndTime "2026-05-27 14:00"

param(
    [DateTime]$StartTime = (Get-Date).AddHours(-48),
    [DateTime]$EndTime = (Get-Date),
    [string]$OutputDir = "",
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"

# Setup
if (-not $OutputDir) {
    $OutputDir = Join-Path (Split-Path $PSScriptRoot -Parent) "metrics"
}
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$journalDir = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
$tradesFile = Join-Path $journalDir "trades.csv"
$metricsOutput = Join-Path $OutputDir "paper_metrics_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"

Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  PAPER TRADE METRICS COLLECTOR — Layer 1 Trailing Adaptativo" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "Period: $($StartTime.ToString('yyyy-MM-dd HH:mm')) → $($EndTime.ToString('yyyy-MM-dd HH:mm'))" -ForegroundColor Yellow
Write-Host "Output: $metricsOutput" -ForegroundColor Yellow
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# 1. Parse trades.csv (histórico de trades)
# ─────────────────────────────────────────────────────────────────────────────

$trades = @()
if (Test-Path $tradesFile) {
    Write-Host "[1/4] Lendo trades.csv..." -ForegroundColor DarkGreen
    $content = Get-Content -Path $tradesFile -Raw
    $lines = $content -split "`n" | Where-Object { $_.Trim() -and -not $_.StartsWith("#") }
    
    foreach ($line in $lines) {
        try {
            $parts = $line -split ","
            if ($parts.Count -lt 10) { continue }
            
            $timestamp = [DateTime]::Parse($parts[0])
            if ($timestamp -lt $StartTime -or $timestamp -gt $EndTime) { continue }
            
            $trades += [PSCustomObject]@{
                timestamp = $timestamp
                market = $parts[1]
                side = $parts[2]
                entry = [double]$parts[3]
                target = [double]$parts[4]
                stop = [double]$parts[5]
                phase = [int]$parts[6]
                status = $parts[7]  # open|closed
                reason = $parts[8]  # trailing_updated|stop_hit|target_reached
                pnl = [double]$parts[9]
            }
        } catch {
            if ($Verbose) { Write-Host "  Aviso: Erro parsing linha: $_" -ForegroundColor DarkYellow }
        }
    }
}

$tradeCount = @($trades).Count
Write-Host "  ✓ Lidos $tradeCount trades no período" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────────────────
# 2. Análise de Trailing (atualização de stops)
# ─────────────────────────────────────────────────────────────────────────────

Write-Host "[2/4] Analisando trailing stops..." -ForegroundColor DarkGreen

$trailingStats = @{
    total_updates = 0
    by_regime = @{}
    by_phase = @{}
    by_market = @{}
    avg_buffer = 0
}

$buffers = @()
foreach ($trade in $trades) {
    if ($trade.reason -eq "trailing_updated") {
        $trailingStats.total_updates++
        
        # Detectar regime do contexto (heurístico baseado em PnL médio)
        $regime = "SIDEWAYS"  # default
        $bufferValue = [Math]::Abs($trade.target - $trade.stop) / [Math]::Abs($trade.target - $trade.entry) * 100
        $buffers += $bufferValue
        
        if ($bufferValue -lt 3) { $regime = "BULL_STRONG" }
        elseif ($bufferValue -gt 8) { $regime = "BEAR_STRONG" }
        
        if (-not $trailingStats.by_regime.ContainsKey($regime)) {
            $trailingStats.by_regime[$regime] = 0
        }
        $trailingStats.by_regime[$regime]++
        
        if (-not $trailingStats.by_phase.ContainsKey($trade.phase)) {
            $trailingStats.by_phase[$trade.phase] = 0
        }
        $trailingStats.by_phase[$trade.phase]++
        
        if (-not $trailingStats.by_market.ContainsKey($trade.market)) {
            $trailingStats.by_market[$trade.market] = 0
        }
        $trailingStats.by_market[$trade.market]++
    }
}

$trailingStats.avg_buffer = if ($buffers.Count -gt 0) { [Math]::Round(($buffers | Measure-Object -Average).Average, 4) } else { 0 }

Write-Host "  ✓ Total trailing updates: $($trailingStats.total_updates)" -ForegroundColor Green
Write-Host "  ✓ Por regime: $($trailingStats.by_regime | ConvertTo-Json -Compress)" -ForegroundColor Green
Write-Host "  ✓ Por fase: $($trailingStats.by_phase | ConvertTo-Json -Compress)" -ForegroundColor Green
Write-Host "  ✓ Buffer médio: $($trailingStats.avg_buffer)%" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────────────────
# 3. Performance Analysis
# ─────────────────────────────────────────────────────────────────────────────

Write-Host "[3/4] Analisando performance..." -ForegroundColor DarkGreen

$perfStats = @{
    total_trades = $tradeCount
    closed_trades = 0
    win_rate = 0
    avg_pnl = 0
    total_pnl = 0
    stops_hit = 0
    targets_reached = 0
    by_market = @{}
}

$closedPnL = @()
foreach ($trade in $trades) {
    if ($trade.status -eq "closed") {
        $perfStats.closed_trades++
        $closedPnL += $trade.pnl
        $perfStats.total_pnl += $trade.pnl
        
        if ($trade.pnl -gt 0) { $perfStats.win_rate++ }
        if ($trade.reason -eq "stop_hit") { $perfStats.stops_hit++ }
        if ($trade.reason -eq "target_reached") { $perfStats.targets_reached++ }
        
        if (-not $perfStats.by_market.ContainsKey($trade.market)) {
            $perfStats.by_market[$trade.market] = @{ wins = 0; losses = 0; pnl = 0 }
        }
        if ($trade.pnl -gt 0) { $perfStats.by_market[$trade.market].wins++ }
        else { $perfStats.by_market[$trade.market].losses++ }
        $perfStats.by_market[$trade.market].pnl += $trade.pnl
    }
}

if ($perfStats.closed_trades -gt 0) {
    $perfStats.win_rate = [Math]::Round($perfStats.win_rate / $perfStats.closed_trades * 100, 2)
    $perfStats.avg_pnl = [Math]::Round($perfStats.total_pnl / $perfStats.closed_trades, 2)
}

Write-Host "  ✓ Closed trades: $($perfStats.closed_trades) / $($perfStats.total_trades)" -ForegroundColor Green
Write-Host "  ✓ Win rate: $($perfStats.win_rate)%" -ForegroundColor Green
Write-Host "  ✓ Avg PnL per trade: $($perfStats.avg_pnl)" -ForegroundColor Green
Write-Host "  ✓ Total PnL: $($perfStats.total_pnl)" -ForegroundColor Green
Write-Host "  ✓ Stops hit: $($perfStats.stops_hit) | Targets reached: $($perfStats.targets_reached)" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────────────────
# 4. Regime Distribution
# ─────────────────────────────────────────────────────────────────────────────

Write-Host "[4/4] Regime distribution..." -ForegroundColor DarkGreen

$regimeStats = @{
    BULL_STRONG = 0
    BULL_WEAK = 0
    SIDEWAYS = 0
    BEAR_STRONG = 0
    OTHER = 0
}

$phaseStats = @{
    phase_0 = 0
    phase_1 = 0
    phase_2 = 0
    phase_3 = 0
}

foreach ($trade in $trades) {
    $phaseKey = "phase_$($trade.phase)"
    if ($phaseStats.ContainsKey($phaseKey)) {
        $phaseStats[$phaseKey]++
    }
}

Write-Host "  ✓ Fase distribution:" -ForegroundColor Green
$phaseStats.GetEnumerator() | ForEach-Object {
    $pct = if ($tradeCount -gt 0) { [Math]::Round($_.Value / $tradeCount * 100, 1) } else { 0 }
    Write-Host "    $($_.Key): $($_.Value) ($pct%)" -ForegroundColor Gray
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. Export Results
# ─────────────────────────────────────────────────────────────────────────────

$results = [PSCustomObject]@{
    period = @{
        start = $StartTime.ToString("o")
        end = $EndTime.ToString("o")
        duration_hours = [Math]::Round(($EndTime - $StartTime).TotalHours, 1)
    }
    trailing = $trailingStats
    performance = $perfStats
    phases = $phaseStats
    trades = @($trades | Select-Object market, side, entry, target, stop, phase, status, reason, pnl)
    export_time = (Get-Date).ToString("o")
}

$results | ConvertTo-Json -Depth 10 | Out-File -FilePath $metricsOutput -Encoding UTF8
Write-Host ""
Write-Host "✅ Métricas exportadas: $metricsOutput" -ForegroundColor Green
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# 6. Summary Output
# ─────────────────────────────────────────────────────────────────────────────

Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  SUMMARY — 48h Paper Trade Validation" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  📊 Trailing Stops" -ForegroundColor Yellow
Write-Host "    • Total updates: $($trailingStats.total_updates)" -ForegroundColor Gray
Write-Host "    • Avg buffer: $($trailingStats.avg_buffer)%" -ForegroundColor Gray
Write-Host ""
Write-Host "  📈 Performance" -ForegroundColor Yellow
Write-Host "    • Closed: $($perfStats.closed_trades) / $($perfStats.total_trades)" -ForegroundColor Gray
Write-Host "    • Win rate: $($perfStats.win_rate)%" -ForegroundColor Gray
Write-Host "    • Total PnL: $($perfStats.total_pnl)" -ForegroundColor Gray
Write-Host ""
Write-Host "  🎯 Phase Distribution" -ForegroundColor Yellow
$phaseStats.GetEnumerator() | ForEach-Object {
    $pct = if ($tradeCount -gt 0) { [Math]::Round($_.Value / $tradeCount * 100, 1) } else { 0 }
    Write-Host "    • $($_.Key): $pct%" -ForegroundColor Gray
}
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
