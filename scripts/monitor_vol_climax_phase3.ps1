# monitor_vol_climax_phase3.ps1 — Real-time vol_climax signal monitoring
# PHASE 3: Collect 5-10 signals over 24-72h, validate >45% win rate before scaling

param(
    [int]$RefreshSec = 5,
    [switch]$Once
)

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$journalDir = Join-Path $projectRoot "journal"
$gemLogFile = Join-Path $journalDir "gem_loop.log"

Write-Host ""
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host " PHASE 3: VOL_CLIMAX SIGNAL MONITOR (Real-time)" -ForegroundColor Cyan
Write-Host " Target: 5-10 signals over 24-72h, validate >45% win rate" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host ""

$startTime = Get-Date
$signalCount = 0
$lastOffset = 0

function Parse-GemLog {
    param([string]$LogFile, [int]$LastOffset)

    if (-not (Test-Path $LogFile)) { return @(), $LastOffset }

    $events = @()
    $lines = @(Get-Content $LogFile -ErrorAction SilentlyContinue)

    for ($i = $LastOffset; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        # Vol Climax signal detected: [VC] boost
        if ($line -match '\[VC\]\s+(\S+)\s+boost\s+\+(\d+)') {
            $market = $matches[1]
            $boost = [int]$matches[2]
            $timestamp = if ($line -match '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') { $matches[1] } else { "?" }

            $events += @{
                type = "VC_BOOST"
                timestamp = $timestamp
                market = $market
                boost = $boost
            }
        }

        # Gem execution
        if ($line -match '\[EXEC\]\s+(\S+)\s+order=') {
            $market = $matches[1]
            $timestamp = if ($line -match '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') { $matches[1] } else { "?" }

            $events += @{
                type = "EXEC"
                timestamp = $timestamp
                market = $market
            }
        }
    }

    return $events, $lines.Count
}

function Display-Summary {
    param([int]$SignalCount, [int]$ExecCount, [datetime]$StartTime)

    $elapsed = (Get-Date) - $StartTime
    $hours = [int]$elapsed.TotalHours
    $mins = [int]$elapsed.TotalMinutes % 60

    Write-Host ""
    Write-Host "SUMMARY:" -ForegroundColor Green
    Write-Host "  Time:     ${hours}h ${mins}m"
    Write-Host "  Signals:  $SignalCount detected"
    Write-Host "  Executed: $ExecCount"
    Write-Host "  Target:   5-10 signals ($(if ($SignalCount -ge 5) {'✅'} else {'⏳'}))"
    Write-Host ""
}

# Initial scan
if (-not (Test-Path $gemLogFile)) {
    Write-Host "⏳ Waiting for gem_loop to start... ($gemLogFile)" -ForegroundColor Yellow
    Write-Host ""
    while (-not (Test-Path $gemLogFile)) {
        Start-Sleep 5
    }
}

$vcSignals = @()
$execCount = 0

Write-Host "✅ Monitoring live from: $gemLogFile" -ForegroundColor Green
Write-Host ""
Write-Host "Live signals (updates every ${RefreshSec}s):" -ForegroundColor Yellow
Write-Host ""

while ($true) {
    $events, $newOffset = Parse-GemLog $gemLogFile $lastOffset
    $lastOffset = $newOffset

    foreach ($evt in $events) {
        if ($evt.type -eq "VC_BOOST") {
            $vcSignals += $evt
            Write-Host "  [$($evt.timestamp)] [VC] $($evt.market) +$($evt.boost) points" -ForegroundColor Cyan
        }
        elseif ($evt.type -eq "EXEC") {
            $execCount++
            Write-Host "  [$($evt.timestamp)] [EXEC] $($evt.market)" -ForegroundColor Green
        }
    }

    if ($Once) { break }

    Start-Sleep $RefreshSec
}

Display-Summary $vcSignals.Count $execCount $startTime

# Export for analysis
$reportFile = Join-Path $journalDir "phase3_vol_climax_signals.json"
@{
    start_time = $startTime.ToString("o")
    end_time = (Get-Date).ToString("o")
    signals = $vcSignals
    executions = $execCount
    target = "5-10 signals"
    status = if ($vcSignals.Count -ge 5) { "ON_TRACK" } else { "COLLECTING" }
} | ConvertTo-Json | Out-File $reportFile -Encoding utf8

Write-Host "📊 Report saved: $reportFile" -ForegroundColor Yellow
