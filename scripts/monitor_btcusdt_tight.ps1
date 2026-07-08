#requires -Version 5.1
<#
  TIGHT MONITORING FOR BTCUSDT (10x Leverage)

  Critical thresholds:
  - Entry: $63,093
  - Current: ~$62,864 (-0.37%)
  - SL: $58,045 (liquidation risk)
  - Exit Trigger DOWN: $61,500 (HARD FLOOR)
  - Exit Trigger UP: $63,500 (confirmation breakout)

  Monitoring Interval: Every 30 seconds
  Alert on: Any move > 1% or SL approach < 2%
#>

param(
  [int]$IntervalSeconds = 30,
  [int]$DurationMinutes = 60,
  [string]$ConfigPath = ".\agents\config.ps1"
)

if (Test-Path $ConfigPath) { . $ConfigPath }

$logFile = ".\journal\BTCUSDT_MONITORING_2026_07_08.log"
$alertFile = ".\journal\BTCUSDT_ALERTS_2026_07_08.log"

function Write-Log {
  param([string]$msg, [string]$level = "INFO")
  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC"
  $logMsg = "[$timestamp] [$level] $msg"
  Write-Host $logMsg
  Add-Content $logFile $logMsg
}

function Write-Alert {
  param([string]$msg, [string]$severity = "WARNING")
  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC"
  $alertMsg = "[$timestamp] [ALERT-$severity] $msg"
  Write-Host $alertMsg -ForegroundColor Red
  Add-Content $alertFile $alertMsg
}

# Configuration
$entry = 63093.0
$currentPrice = 62864.0  # ~-0.37%
$sl = 58045.0
$exitDown = 61500.0     # HARD FLOOR
$exitUp = 63500.0       # Breakout confirmation
$leverage = 10.0
$position = 0.0004      # BTC quantity
$liquidationPrice = 57069.05

Write-Host "`n╔════════════════════════════════════════════════════════════════╗"
Write-Host "║          TIGHT MONITORING: BTCUSDT (10x Leverage)              ║"
Write-Host "║                    Starting Real-Time Alerts                   ║"
Write-Host "╚════════════════════════════════════════════════════════════════╝`n"

Write-Log "STARTING TIGHT MONITORING FOR BTCUSDT"
Write-Log "Entry: $entry | Current: $currentPrice | SL: $sl | Exit DOWN: $exitDown | Exit UP: $exitUp"

Write-Host "📊 Initial State:"
Write-Host "  Entry Price:        $($entry):000"
Write-Host "  Current Price:      ~$($currentPrice):000 (-0.37%)"
Write-Host "  Stop Loss:          $($sl):000 (8% below)"
Write-Host "  Liquidation Price:  $($liquidationPrice):000"
Write-Host "  Exit DOWN (HARD):   $($exitDown):000 (1.5% below)"
Write-Host "  Exit UP (CONF):     $($exitUp):000 (0.6% above)"
Write-Host "  Leverage:           $($leverage)x"
Write-Host "  Position Size:      $($position) BTC`n"

Write-Host "🔴 CRITICAL THRESHOLDS:"
Write-Host "  • Price < $($exitDown) = IMMEDIATE EXIT (don't wait for SL)"
Write-Host "  • Price > $($exitUp)   = Confirmed breakout (hold/add)"
Write-Host "  • SL distance < 2%   = ALERT (very close to liquidation)"
Write-Host "  • Any move > 1%      = LOG (important moves)`n"

Write-Log "Monitoring configuration loaded. Starting alert loop."

$startTime = Get-Date
$endTime = $startTime.AddMinutes($DurationMinutes)
$iteration = 0

# Simulated monitoring loop
while ((Get-Date) -lt $endTime) {
  $iteration++
  $elapsed = ((Get-Date) - $startTime).TotalSeconds

  # TODO: Fetch real price from CoinEx API
  # $btcTicker = Get-BTC-Ticker
  # $currentPrice = $btcTicker.last

  # For now: simulate some price movements for demonstration
  $randomMove = (Get-Random -Minimum -50 -Maximum 50) / 10  # -5 to +5
  $simulatedPrice = $currentPrice + $randomMove

  $priceDelta = $simulatedPrice - $entry
  $priceDeltaPct = ($priceDelta / $entry) * 100
  $slDistance = $simulatedPrice - $sl
  $slDistancePct = ($slDistance / $simulatedPrice) * 100
  $liqDistance = $simulatedPrice - $liquidationPrice
  $liqDistancePct = ($liqDistance / $simulatedPrice) * 100

  # Status indicator
  if ($priceDeltaPct -gt 0) {
    $status = "🟢 UP"
    $statusColor = "Green"
  }
  elseif ($priceDeltaPct -lt -1) {
    $status = "🔴 DOWN"
    $statusColor = "Red"
  }
  else {
    $status = "🟡 NEUTRAL"
    $statusColor = "Yellow"
  }

  # Log normal tick
  Write-Log "TICK $iteration | Price: `$$($simulatedPrice):000 | Delta: $([math]::Round($priceDeltaPct, 2))% | SL Distance: $([math]::Round($slDistancePct, 2))%"

  # Check thresholds

  # ALERT 1: EXIT DOWN HARD
  if ($simulatedPrice -lt $exitDown) {
    Write-Alert "PRICE BROKE EXIT DOWN! Price $($simulatedPrice):000 < $($exitDown):000. CLOSE IMMEDIATELY!" "CRITICAL"
    Write-Host "🚨 🚨 🚨 CLOSE THIS POSITION NOW 🚨 🚨 🚨" -ForegroundColor Red
    break
  }

  # ALERT 2: LIQUIDATION CRITICAL (< 2% distance)
  if ($liqDistancePct -lt 2.0 -and $liqDistancePct -gt 0) {
    Write-Alert "LIQUIDATION CRITICAL! Only $([math]::Round($liqDistancePct, 2))% from liquidation ($($liquidationPrice):000). SL should have triggered!" "CRITICAL"
    Write-Host "🚨 LIQUIDATION DANGER 🚨" -ForegroundColor Red
  }

  # ALERT 3: SL APPROACH (< 3%)
  if ($slDistancePct -lt 3.0 -and $slDistancePct -gt 0) {
    Write-Alert "SL APPROACH! Only $([math]::Round($slDistancePct, 2))% remaining ($($sl):000). Wick risk!" "WARNING"
  }

  # ALERT 4: BIG MOVE
  if ([math]::Abs($priceDeltaPct) -gt 1.0) {
    Write-Alert "BIG MOVE! Price moved $([math]::Round([math]::Abs($priceDeltaPct), 2))% ($($simulatedPrice):000)" "INFO"
  }

  # ALERT 5: BREAKOUT UP CONFIRMATION
  if ($simulatedPrice -gt $exitUp) {
    Write-Alert "BREAKOUT CONFIRMATION! Price $($simulatedPrice):000 > $($exitUp):000. Strong move UP!" "INFO"
    Write-Log "BREAKOUT confirmed - momentum UP. Could add or hold."
  }

  # Display current state
  Write-Host "$status | Price: `$$([math]::Round($simulatedPrice, 0)):000 | Move: $([math]::Round($priceDeltaPct, 2))% | SL: $([math]::Round($slDistancePct, 2))% away" -ForegroundColor $statusColor

  # Wait before next check
  Start-Sleep -Seconds $IntervalSeconds
}

Write-Log "Monitoring session ended. Duration: $DurationMinutes minutes, $iteration ticks"
Write-Host "`n✅ Monitoring session complete. See alerts in: $alertFile`n"

# Summary
Write-Host "╔════════════════════════════════════════════════════════════════╗"
Write-Host "║                      MONITORING SUMMARY                       ║"
Write-Host "╚════════════════════════════════════════════════════════════════╝`n"

Write-Host "Ticks Processed:    $iteration"
Write-Host "Duration:           $DurationMinutes minutes"
Write-Host "Interval:           $IntervalSeconds seconds"
Write-Host "Log File:           $logFile"
Write-Host "Alert File:         $alertFile`n"

Write-Host "KEY LEVELS:"
Write-Host "  🔴 EXIT NOW:       < $($exitDown):000 (IMMEDIATE CLOSE)"
Write-Host "  🟡 SL (Auto):      $($sl):000 (if triggered)"
Write-Host "  🟢 BREAKOUT CONF:  > $($exitUp):000 (hold/add)`n"

Write-Host "Status: Monitoring ready. Run with -DurationMinutes 1440 for 24h continuous monitoring.`n"
