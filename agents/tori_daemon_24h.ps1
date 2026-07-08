# tori_daemon_24h.ps1 - Production 24/7 Tori Trades Scanner Daemon
#
# Core daemon for scanning 100+ CoinEx futures pairs across multiple timeframes.
# Implements trendline confluence detection, state persistence, crash recovery.
#
# Dependencies: lib_tori_confluence_detector, lib_tori_trades_scanner, lib_coinex, lib_rate_limiter
# State file: journal/tori_daemon_state.json
# Heartbeat: journal/tori_daemon_heartbeat.txt
# Log: journal/tori_daemon.log
#
# PS 5.1 compatible, UTF-8 BOM

# ============================================================================
# CONFIGURATION
# ============================================================================

$script:SCAN_INTERVAL_MINUTES = 240           # 4-hour scan cycle
$script:HEARTBEAT_INTERVAL_SEC = 300          # 5-minute heartbeat
$script:CANDLES_LIMIT = 300                   # Max candles per timeframe
$script:TIMEFRAMES = @("1W", "1D", "4H", "1H")  # Primary timeframes (4H cycle)
$script:CONFLUENCE_THRESHOLD = 80             # Minimum confluence score
$script:MIN_AMOUNT_USDT = 50                  # Minimum order size
$script:PAIR_CACHE_HOURS = 6                  # Refresh pair list every 6 hours
$script:MAX_PAIRS_PER_SCAN = 150              # Limit pairs per cycle
$script:API_RATE_LIMIT_DELAY_MS = 100        # Delay between API calls (50 req/min = 1.2s)
$script:MAX_CONCURRENT_PAIRS = 10             # Parallel fetch limit per batch

# State file locations
$script:STATE_FILE = Join-Path $PSScriptRoot "..\journal\tori_daemon_state.json"
$script:HEARTBEAT_FILE = Join-Path $PSScriptRoot "..\journal\tori_daemon_heartbeat.txt"
$script:LOCK_FILE = Join-Path $PSScriptRoot "..\journal\tori_daemon.lock"
$script:LOG_FILE = Join-Path $PSScriptRoot "..\journal\tori_daemon.log"
$script:PAIRS_CACHE_FILE = Join-Path $PSScriptRoot "..\journal\tori_daemon_pairs_cache.json"

# ============================================================================
# GLOBALS: Maintain state across scans
# ============================================================================

$script:ActiveSetups = @()          # Current open setups
$script:ClosedTrades = @()          # Historical closed trades
$script:PerformanceMetrics = @{
    total_scans = 0
    pairs_analyzed = 0
    setups_found = 0
    avg_confluence_score = 0.0
    win_rate = 0.0
    total_pnl = 0.0
}
$script:LastScanTime = [DateTime]::MinValue
$script:LastHeartbeatTime = [DateTime]::Now
$script:PairListCacheTime = [DateTime]::MinValue
$script:CachedPairs = @()
$script:IsRunning = $false

# ============================================================================
# HELPER: LOGGING
# ============================================================================

function Write-DaemonLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = "[$timestamp] [$Level] $Message"

    Write-Host $logEntry

    if (Test-Path $script:LOG_FILE) {
        Add-Content -Path $script:LOG_FILE -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
    } else {
        try {
            Set-Content -Path $script:LOG_FILE -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
        } catch {
            Write-Host "Warning: Could not write to log file: $_"
        }
    }
}

# ============================================================================
# HELPER: HEARTBEAT (watchdog monitoring)
# ============================================================================

function Write-DaemonHeartbeat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$Message = "alive"
    )

    $heartbeat = @{
        timestamp = Get-Date -Format "o"
        status = $Message
        scans_completed = $script:PerformanceMetrics.total_scans
        setups_found = $script:ActiveSetups.Count
    } | ConvertTo-Json

    try {
        Set-Content -Path $script:HEARTBEAT_FILE -Value $heartbeat -Encoding UTF8 -ErrorAction SilentlyContinue
        $script:LastHeartbeatTime = Get-Date
    } catch {
        Write-DaemonLog "Failed to write heartbeat: $_" -Level WARN
    }
}

# ============================================================================
# HELPER: STATE PERSISTENCE
# ============================================================================

# Atomic save with backup (prevents data loss on crash)
function Save-DaemonStateSafe {
    $tempFile = "$script:STATE_FILE.tmp"
    $backupFile = "$script:STATE_FILE.backup"

    try {
        # Write to temp first
        $stateJson = $script:ActiveSetups | ConvertTo-Json -Depth 10
        Set-Content -Path $tempFile -Value $stateJson -Encoding UTF8

        # Only after successful write, move to actual location
        if (Test-Path $backupFile) {
            Remove-Item $backupFile -Force
        }
        if (Test-Path $script:STATE_FILE) {
            Move-Item $script:STATE_FILE $backupFile -Force
        }
        Move-Item $tempFile $script:STATE_FILE -Force

        Write-DaemonLog "State saved atomically" "INFO"
    } catch {
        Write-DaemonLog "State save failed: # tori_daemon_24h.ps1 - Production 24/7 Tori Trades Scanner Daemon
#
# Core daemon for scanning 100+ CoinEx futures pairs across multiple timeframes.
# Implements trendline confluence detection, state persistence, crash recovery.
#
# Dependencies: lib_tori_confluence_detector, lib_tori_trades_scanner, lib_coinex, lib_rate_limiter
# State file: journal/tori_daemon_state.json
# Heartbeat: journal/tori_daemon_heartbeat.txt
# Log: journal/tori_daemon.log
#
# PS 5.1 compatible, UTF-8 BOM

# ============================================================================
# CONFIGURATION
# ============================================================================

$script:SCAN_INTERVAL_MINUTES = 240           # 4-hour scan cycle
$script:HEARTBEAT_INTERVAL_SEC = 300          # 5-minute heartbeat
$script:CANDLES_LIMIT = 300                   # Max candles per timeframe
$script:TIMEFRAMES = @("1W", "1D", "4H", "1H")  # Primary timeframes (4H cycle)
$script:CONFLUENCE_THRESHOLD = 80             # Minimum confluence score
$script:MIN_AMOUNT_USDT = 50                  # Minimum order size
$script:PAIR_CACHE_HOURS = 6                  # Refresh pair list every 6 hours
$script:MAX_PAIRS_PER_SCAN = 150              # Limit pairs per cycle
$script:API_RATE_LIMIT_DELAY_MS = 100        # Delay between API calls (50 req/min = 1.2s)
$script:MAX_CONCURRENT_PAIRS = 10             # Parallel fetch limit per batch

# State file locations
$script:STATE_FILE = Join-Path $PSScriptRoot "..\journal\tori_daemon_state.json"
$script:HEARTBEAT_FILE = Join-Path $PSScriptRoot "..\journal\tori_daemon_heartbeat.txt"
$script:LOCK_FILE = Join-Path $PSScriptRoot "..\journal\tori_daemon.lock"
$script:LOG_FILE = Join-Path $PSScriptRoot "..\journal\tori_daemon.log"
$script:PAIRS_CACHE_FILE = Join-Path $PSScriptRoot "..\journal\tori_daemon_pairs_cache.json"

# ============================================================================
# GLOBALS: Maintain state across scans
# ============================================================================

$script:ActiveSetups = @()          # Current open setups
$script:ClosedTrades = @()          # Historical closed trades
$script:PerformanceMetrics = @{
    total_scans = 0
    pairs_analyzed = 0
    setups_found = 0
    avg_confluence_score = 0.0
    win_rate = 0.0
    total_pnl = 0.0
}
$script:LastScanTime = [DateTime]::MinValue
$script:LastHeartbeatTime = [DateTime]::Now
$script:PairListCacheTime = [DateTime]::MinValue
$script:CachedPairs = @()
$script:IsRunning = $false

# ============================================================================
# HELPER: LOGGING
# ============================================================================

function Write-DaemonLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = "[$timestamp] [$Level] $Message"

    Write-Host $logEntry

    if (Test-Path $script:LOG_FILE) {
        Add-Content -Path $script:LOG_FILE -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
    } else {
        try {
            Set-Content -Path $script:LOG_FILE -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
        } catch {
            Write-Host "Warning: Could not write to log file: $_"
        }
    }
}

# ============================================================================
# HELPER: HEARTBEAT (watchdog monitoring)
# ============================================================================

function Write-DaemonHeartbeat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$Message = "alive"
    )

    $heartbeat = @{
        timestamp = Get-Date -Format "o"
        status = $Message
        scans_completed = $script:PerformanceMetrics.total_scans
        setups_found = $script:ActiveSetups.Count
    } | ConvertTo-Json

    try {
        Set-Content -Path $script:HEARTBEAT_FILE -Value $heartbeat -Encoding UTF8 -ErrorAction SilentlyContinue
        $script:LastHeartbeatTime = Get-Date
    } catch {
        Write-DaemonLog "Failed to write heartbeat: $_" -Level WARN
    }
}

# ============================================================================
# HELPER: STATE PERSISTENCE
# ============================================================================

function Save-DaemonState {
    [CmdletBinding()]
    param()

    try {
        $state = @{
            timestamp = Get-Date -Format "o"
            last_scan_time = $script:LastScanTime.ToString("o")
            active_setups = $script:ActiveSetups
            closed_trades = $script:ClosedTrades | Select-Object -Last 500  # Keep last 500
            performance = $script:PerformanceMetrics
            pairs_cache = $script:CachedPairs
        } | ConvertTo-Json -Depth 5

        Set-Content -Path $script:STATE_FILE -Value $state -Encoding UTF8 -ErrorAction SilentlyContinue
        Write-DaemonLog "State saved: $($script:ActiveSetups.Count) active, $($script:ClosedTrades.Count) closed" -Level INFO
    } catch {
        Write-DaemonLog "Failed to save daemon state: $_" -Level ERROR
    }
}

function Load-DaemonState {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $script:STATE_FILE)) {
        Write-DaemonLog "State file not found, starting fresh" -Level INFO
        return
    }

    try {
        $content = Get-Content -Path $script:STATE_FILE -Raw -Encoding UTF8 -ErrorAction Stop
        $state = $content | ConvertFrom-Json

        $script:LastScanTime = [DateTime]::Parse($state.last_scan_time)
        $script:ActiveSetups = $state.active_setups
        $script:ClosedTrades = $state.closed_trades
        $script:PerformanceMetrics = $state.performance
        $script:CachedPairs = $state.pairs_cache

        Write-DaemonLog "State loaded: $($script:ActiveSetups.Count) active setups restored" -Level INFO
    } catch {
        Write-DaemonLog "Failed to load daemon state: $_" -Level ERROR
    }
}

# ============================================================================
# HELPER: PAIR MANAGEMENT
# ============================================================================

function Update-PairCache {
    [CmdletBinding()]
    param()

    # Check if cache is stale
    if ($script:PairListCacheTime -ne [DateTime]::MinValue) {
        $hoursSinceUpdate = ((Get-Date) - $script:PairListCacheTime).TotalHours
        if ($hoursSinceUpdate -lt $script:PAIR_CACHE_HOURS) {
            return  # Cache still fresh
        }
    }

    Write-DaemonLog "Refreshing pair cache from CoinEx..." -Level INFO

    try {
        # Get all futures markets
        $allMarkets = CoinEx-GetFuturesMarkets | Where-Object { $_.market -match "USDT$" }

        $validPairs = @()
        foreach ($market in $allMarkets) {
            # Filter by minimum order amount
            if ([double]$market.min_amount -lt $script:MIN_AMOUNT_USDT) {
                continue
            }

            # Skip delisted or problematic pairs
            if ($market.market -match "TEST|DEMO|DEX") {
                continue
            }

            $validPairs += $market.market
        }

        $script:CachedPairs = @($validPairs | Sort-Object)
        $script:PairListCacheTime = Get-Date

        Write-DaemonLog "Pair cache updated: $($script:CachedPairs.Count) pairs available" -Level INFO
    } catch {
        Write-DaemonLog "Failed to update pair cache: $_" -Level WARN

        # If we have cached pairs, keep using them
        if ($script:CachedPairs.Count -eq 0) {
            throw "No pairs available and cache is empty"
        }
    }
}

# ============================================================================
# HELPER: ANALYZE SINGLE PAIR
# ============================================================================

function Analyze-PairTrendlines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Pair
    )

    $pairSetups = @()

    foreach ($timeframe in $script:TIMEFRAMES) {
        try {
            # Fetch candles
            $candles = CoinEx-GetFuturesCandles -market $Pair -period $timeframe -limit $script:CANDLES_LIMIT -TimeoutSec 10

            if (-not $candles -or $candles.Count -lt 5) {
                continue
            }

            # Extract OHLCV
            $opens = @($candles | ForEach-Object { [double]$_.open })
            $highs = @($candles | ForEach-Object { [double]$_.high })
            $lows = @($candles | ForEach-Object { [double]$_.low })
            $closes = @($candles | ForEach-Object { [double]$_.close })
            $volumes = @($candles | ForEach-Object { [double]$_.volume })

            $currentPrice = $closes[-1]

            # Analyze LONG trendline
            $longSetups = Analyze-TrendlineSetup -Pair $Pair -Timeframe $timeframe -Candles $candles -Highs $highs -Lows $lows -Closes $closes -TrendType "LONG"
            $pairSetups += @($longSetups)

            # Analyze SHORT trendline
            $shortSetups = Analyze-TrendlineSetup -Pair $Pair -Timeframe $timeframe -Candles $candles -Highs $highs -Lows $lows -Closes $closes -TrendType "SHORT"
            $pairSetups += @($shortSetups)

        } catch {
            Write-DaemonLog "Error analyzing $Pair [$timeframe]: $_" -Level WARN
        }

        # Rate limiting
        Start-Sleep -Milliseconds $script:API_RATE_LIMIT_DELAY_MS
    }

    return @($pairSetups)
}

function Analyze-TrendlineSetup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Pair,

        [Parameter(Mandatory=$true)]
        [string]$Timeframe,

        [Parameter(Mandatory=$true)]
        [PSObject[]]$Candles,

        [Parameter(Mandatory=$true)]
        [double[]]$Highs,

        [Parameter(Mandatory=$true)]
        [double[]]$Lows,

        [Parameter(Mandatory=$true)]
        [double[]]$Closes,

        [Parameter(Mandatory=$true)]
        [ValidateSet("LONG", "SHORT")]
        [string]$TrendType
    )

    $trendline = Detect-Trendline -Highs $Highs -Lows $Lows -TrendType $TrendType

    if (-not $trendline) {
        return @()
    }

    $currentPrice = $Closes[-1]

    # Calculate proximity to trendline
    $distance = if ($TrendType -eq "LONG") {
        $currentPrice - $trendline.start_price
    } else {
        $trendline.start_price - $currentPrice
    }

    $proximityPct = ($distance / $trendline.start_price) * 100

    # Only process if price is near trendline (within 5%)
    if ($proximityPct -lt -3 -or $proximityPct -gt 5) {
        return @()
    }

    # Calculate confluence score
    $confluenceResult = Get-ConfluenceScoreEnhanced -Candles $Candles -SetupType $TrendType -TrendlineStartPrice $trendline.start_price -TrendlineTouches $trendline.touches

    if ($confluenceResult.total_score -lt $script:CONFLUENCE_THRESHOLD) {
        return @()  # Below threshold
    }

    # Calculate risk/reward
    $stop = if ($TrendType -eq "LONG") {
        $trendline.start_price * 0.98
    } else {
        $trendline.start_price * 1.02
    }

    $risk = [Math]::Abs($currentPrice - $stop)
    $target = if ($TrendType -eq "LONG") {
        $currentPrice + ($risk * 5.0)  # 1:5 R:R target
    } else {
        $currentPrice - ($risk * 5.0)
    }

    $setup = [PSCustomObject]@{
        id = "{0}_{1}_{2}_{3}" -f $Pair, $Timeframe, $TrendType, (Get-Date -Format "yyyyMMddHHmm")
        timestamp = Get-Date -Format "o"
        pair = $Pair
        timeframe = $Timeframe
        trend_type = $TrendType
        confidence_score = $confluenceResult.total_score
        signals_fired = $confluenceResult.signals_fired -join "|"
        rsi = $confluenceResult.rsi
        volume_climax_ratio = $confluenceResult.volume_climax_ratio
        trendline_touches = $confluenceResult.trendline_touches
        entry_price = [Math]::Round($currentPrice, 8)
        stop_loss = [Math]::Round($stop, 8)
        target_price = [Math]::Round($target, 8)
        risk_usdt = [Math]::Round($risk, 8)
        reward_usdt = [Math]::Round([Math]::Abs($target - $currentPrice), 8)
        rr_ratio = if ($risk -ne 0) { [Math]::Round([Math]::Abs($target - $currentPrice) / $risk, 2) } else { 0 }
        status = "NEW"
        unrealized_pnl = 0.0
        creation_scan = $script:PerformanceMetrics.total_scans
    }

    return @($setup)
}

function Detect-Trendline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [double[]]$Highs,

        [Parameter(Mandatory=$true)]
        [double[]]$Lows,

        [Parameter(Mandatory=$true)]
        [ValidateSet("LONG", "SHORT")]
        [string]$TrendType
    )

    if ($Highs.Length -lt 3) {
        return $null
    }

    # Simple linear regression on last N candles
    $fitData = if ($TrendType -eq "LONG") { $Lows } else { $Highs }

    $n = $fitData.Length
    $sumX = 0; $sumY = 0; $sumXY = 0; $sumX2 = 0

    for ($i = 0; $i -lt $n; $i++) {
        $sumX += $i
        $sumY += $fitData[$i]
        $sumXY += $i * $fitData[$i]
        $sumX2 += $i * $i
    }

    $denom = ($n * $sumX2) - ($sumX * $sumX)
    if ($denom -eq 0) { return $null }

    $slope = (($n * $sumXY) - ($sumX * $sumY)) / $denom
    $intercept = ($sumY - ($slope * $sumX)) / $n

    # Count touches within tolerance (1.5%)
    $touches = 0
    $tolerance = 0.015

    for ($i = 0; $i -lt $n; $i++) {
        $lineValue = $intercept + ($slope * $i)
        if ($lineValue -le 0) { continue }

        $diffPct = [Math]::Abs($fitData[$i] - $lineValue) / $lineValue
        if ($diffPct -le $tolerance) {
            $touches += 1
        }
    }

    # Require at least 2 touches
    if ($touches -lt 2) {
        return $null
    }

    # Validate slope is reasonable (5-35 degrees)
    $slopeDeg = [Math]::Atan($slope) * (180 / [Math]::PI)
    if ([Math]::Abs($slopeDeg) -lt 5 -or [Math]::Abs($slopeDeg) -gt 35) {
        return $null
    }

    return [PSCustomObject]@{
        slope = $slope
        intercept = $intercept
        start_price = $intercept
        end_price = $intercept + ($slope * ($n - 1))
        touches = $touches
        quality = if ($touches -ge 3) { "A+" } else { "A" }
    }
}

# ============================================================================
# MAIN SCAN LOOP
# ============================================================================

function Invoke-DaemonScan {
    [CmdletBinding()]
    param()

    $scanStartTime = Get-Date
    Write-DaemonLog "--- SCAN CYCLE START ---" -Level INFO

    # Update pair cache
    Update-PairCache

    # Select pairs to analyze (rotate through full list)
    $pairsToAnalyze = $script:CachedPairs | Select-Object -First $script:MAX_PAIRS_PER_SCAN

    Write-DaemonLog "Scanning $($pairsToAnalyze.Count) pairs..." -Level INFO

    $cycleSetups = @()
    $analyzed = 0

    foreach ($pair in $pairsToAnalyze) {
        $analyzed += 1

        # Throttle output
        if ($analyzed % 10 -eq 0) {
            Write-DaemonLog "Progress: $analyzed/$($pairsToAnalyze.Count) pairs" -Level INFO
        }

        try {
            $setups = Analyze-PairTrendlines -Pair $pair

            foreach ($setup in $setups) {
                if ($setup.confidence_score -ge $script:CONFLUENCE_THRESHOLD) {
                    $cycleSetups += $setup
                }
            }
        } catch {
            # Continue on error
        }
    }

    Write-DaemonLog "Found $($cycleSetups.Count) high-quality setups" -Level INFO

    # Update active setups
    $script:ActiveSetups += $cycleSetups

    # Mark setups as closed if price hits target or stop
    Update-SetupStatuses

    # Update performance metrics
    $script:PerformanceMetrics.total_scans += 1
    $script:PerformanceMetrics.pairs_analyzed = $pairsToAnalyze.Count
    $script:PerformanceMetrics.setups_found = $cycleSetups.Count

    if ($script:ActiveSetups.Count -gt 0) {
        $script:PerformanceMetrics.avg_confluence_score = ($script:ActiveSetups | Measure-Object -Property confidence_score -Average).Average
    }

    $scanEndTime = Get-Date
    $scanDuration = ($scanEndTime - $scanStartTime).TotalSeconds

    Write-DaemonLog "Scan completed in $([Math]::Round($scanDuration, 1))s. Active: $($script:ActiveSetups.Count)" -Level INFO

    # Save state
    Save-DaemonState

    # Send Telegram alerts for new setups
    foreach ($setup in $cycleSetups) {
        Send-ToriSetupAlert -Setup $setup
    }

    $script:LastScanTime = $scanEndTime
}

function Update-SetupStatuses {
    [CmdletBinding()]
    param()

    $closedSetups = @()

    foreach ($setup in $script:ActiveSetups) {
        try {
            # Fetch current price
            $ticker = CoinEx-GetTicker -market $setup.pair
            $currentPrice = [double]$ticker.last

            # Check if target hit
            if ($setup.trend_type -eq "LONG" -and $currentPrice -ge $setup.target_price) {
                $setup.status = "CLOSED_TARGET"
                $setup.unrealized_pnl = $setup.reward_usdt
                $closedSetups += $setup
                Write-DaemonLog "Setup $($setup.id) closed at target: $currentPrice" -Level INFO
            }
            # Check if stop hit
            elseif ($setup.trend_type -eq "LONG" -and $currentPrice -le $setup.stop_loss) {
                $setup.status = "CLOSED_STOP"
                $setup.unrealized_pnl = -$setup.risk_usdt
                $closedSetups += $setup
                Write-DaemonLog "Setup $($setup.id) stopped: $currentPrice" -Level INFO
            }
            # SHORT logic
            elseif ($setup.trend_type -eq "SHORT" -and $currentPrice -le $setup.target_price) {
                $setup.status = "CLOSED_TARGET"
                $setup.unrealized_pnl = $setup.reward_usdt
                $closedSetups += $setup
                Write-DaemonLog "Setup $($setup.id) closed at target: $currentPrice" -Level INFO
            }
            elseif ($setup.trend_type -eq "SHORT" -and $currentPrice -ge $setup.stop_loss) {
                $setup.status = "CLOSED_STOP"
                $setup.unrealized_pnl = -$setup.risk_usdt
                $closedSetups += $setup
                Write-DaemonLog "Setup $($setup.id) stopped: $currentPrice" -Level INFO
            }
            else {
                # Still open, update unrealized PnL
                if ($setup.trend_type -eq "LONG") {
                    $setup.unrealized_pnl = $currentPrice - $setup.entry_price
                } else {
                    $setup.unrealized_pnl = $setup.entry_price - $currentPrice
                }
            }
        } catch {
            Write-DaemonLog "Failed to update status for $($setup.pair): $_" -Level WARN
        }
    }

    # Move closed setups to history
    if ($closedSetups.Count -gt 0) {
        $script:ActiveSetups = $script:ActiveSetups | Where-Object { $_.id -notin $closedSetups.id }
        $script:ClosedTrades += $closedSetups
    }
}

# ============================================================================
# DAEMON MAIN LOOP
# ============================================================================

function Start-ToriDaemon {
    [CmdletBinding()]
    param()

    Write-DaemonLog "=== TORI DAEMON STARTED ===" -Level INFO

    # Load existing state
    Load-DaemonState

    # Load dependencies
    $libPath = Join-Path $PSScriptRoot "lib_tori_confluence_detector.ps1"
    if (Test-Path $libPath) {
        . $libPath
    }

    $coinexPath = Join-Path $PSScriptRoot "lib_coinex.ps1"
    if (Test-Path $coinexPath) {
        . $coinexPath
    }

    $script:IsRunning = $true
    $nextScanTime = Get-Date

    # Main loop
    while ($script:IsRunning) {
        $now = Get-Date

        # Check if it's time for a scan
        if ($now -ge $nextScanTime) {
            try {
                Invoke-DaemonScan
            } catch {
                Write-DaemonLog "Scan failed: $_" -Level ERROR
            }

            $nextScanTime = $now.AddMinutes($script:SCAN_INTERVAL_MINUTES)
            Write-DaemonLog "Next scan scheduled for: $nextScanTime" -Level INFO
        }

        # Write heartbeat every 5 minutes
        if (((Get-Date) - $script:LastHeartbeatTime).TotalSeconds -ge $script:HEARTBEAT_INTERVAL_SEC) {
            Write-DaemonHeartbeat
        }

        # Sleep before checking again
        Start-Sleep -Seconds 60
    }

    Write-DaemonLog "=== TORI DAEMON STOPPED ===" -Level INFO
}

function Stop-ToriDaemon {
    [CmdletBinding()]
    param()

    Write-DaemonLog "Stop signal received" -Level INFO
    $script:IsRunning = $false

    # Final save
    Save-DaemonState
    Write-DaemonLog "Final state saved" -Level INFO
}

# ============================================================================
# PLACEHOLDER: Telegram Alert (implemented in tori_telegram_alerts.ps1)
# ============================================================================

function Send-ToriSetupAlert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$Setup
    )

    # Placeholder - integrated with tori_telegram_alerts.ps1
    # Write-DaemonLog "New setup alert: $($Setup.pair) $($Setup.trend_type) score=$($Setup.confidence_score)" -Level INFO
}

# ============================================================================
# EXPORT & ENTRY POINT
# ============================================================================

Export-ModuleMember -Function Start-ToriDaemon, Stop-ToriDaemon, Invoke-DaemonScan, Update-SetupStatuses

# If run directly (not sourced)
if ($MyInvocation.InvocationName -ne ".") {
    Start-ToriDaemon
}

, attempting restore from backup" "ERROR"
        if (Test-Path $backupFile) {
            Copy-Item $backupFile $script:STATE_FILE -Force
        }
        throw
    }
}
function Save-DaemonState {
    [CmdletBinding()]
    param()

    try {
        $state = @{
            timestamp = Get-Date -Format "o"
            last_scan_time = $script:LastScanTime.ToString("o")
            active_setups = $script:ActiveSetups
            closed_trades = $script:ClosedTrades | Select-Object -Last 500  # Keep last 500
            performance = $script:PerformanceMetrics
            pairs_cache = $script:CachedPairs
        } | ConvertTo-Json -Depth 5

        Set-Content -Path $script:STATE_FILE -Value $state -Encoding UTF8 -ErrorAction SilentlyContinue
        Write-DaemonLog "State saved: $($script:ActiveSetups.Count) active, $($script:ClosedTrades.Count) closed" -Level INFO
    } catch {
        Write-DaemonLog "Failed to save daemon state: $_" -Level ERROR
    }
}

function Load-DaemonState {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $script:STATE_FILE)) {
        Write-DaemonLog "State file not found, starting fresh" -Level INFO
        return
    }

    try {
        $content = Get-Content -Path $script:STATE_FILE -Raw -Encoding UTF8 -ErrorAction Stop
        $state = $content | ConvertFrom-Json

        $script:LastScanTime = [DateTime]::Parse($state.last_scan_time)
        $script:ActiveSetups = $state.active_setups
        $script:ClosedTrades = $state.closed_trades
        $script:PerformanceMetrics = $state.performance
        $script:CachedPairs = $state.pairs_cache

        Write-DaemonLog "State loaded: $($script:ActiveSetups.Count) active setups restored" -Level INFO
    } catch {
        Write-DaemonLog "Failed to load daemon state: $_" -Level ERROR
    }
}

# ============================================================================
# HELPER: PAIR MANAGEMENT
# ============================================================================

function Update-PairCache {
    [CmdletBinding()]
    param()

    # Check if cache is stale
    if ($script:PairListCacheTime -ne [DateTime]::MinValue) {
        $hoursSinceUpdate = ((Get-Date) - $script:PairListCacheTime).TotalHours
        if ($hoursSinceUpdate -lt $script:PAIR_CACHE_HOURS) {
            return  # Cache still fresh
        }
    }

    Write-DaemonLog "Refreshing pair cache from CoinEx..." -Level INFO

    try {
        # Get all futures markets
        $allMarkets = CoinEx-GetFuturesMarkets | Where-Object { $_.market -match "USDT$" }

        $validPairs = @()
        foreach ($market in $allMarkets) {
            # Filter by minimum order amount
            if ([double]$market.min_amount -lt $script:MIN_AMOUNT_USDT) {
                continue
            }

            # Skip delisted or problematic pairs
            if ($market.market -match "TEST|DEMO|DEX") {
                continue
            }

            $validPairs += $market.market
        }

        $script:CachedPairs = @($validPairs | Sort-Object)
        $script:PairListCacheTime = Get-Date

        Write-DaemonLog "Pair cache updated: $($script:CachedPairs.Count) pairs available" -Level INFO
    } catch {
        Write-DaemonLog "Failed to update pair cache: $_" -Level WARN

        # If we have cached pairs, keep using them
        if ($script:CachedPairs.Count -eq 0) {
            throw "No pairs available and cache is empty"
        }
    }
}

# ============================================================================
# HELPER: ANALYZE SINGLE PAIR
# ============================================================================

function Analyze-PairTrendlines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Pair
    )

    $pairSetups = @()

    foreach ($timeframe in $script:TIMEFRAMES) {
        try {
            # Fetch candles
            $candles = CoinEx-GetFuturesCandles -market $Pair -period $timeframe -limit $script:CANDLES_LIMIT -TimeoutSec 10

            if (-not $candles -or $candles.Count -lt 5) {
                continue
            }

            # Extract OHLCV
            $opens = @($candles | ForEach-Object { [double]$_.open })
            $highs = @($candles | ForEach-Object { [double]$_.high })
            $lows = @($candles | ForEach-Object { [double]$_.low })
            $closes = @($candles | ForEach-Object { [double]$_.close })
            $volumes = @($candles | ForEach-Object { [double]$_.volume })

            $currentPrice = $closes[-1]

            # Analyze LONG trendline
            $longSetups = Analyze-TrendlineSetup -Pair $Pair -Timeframe $timeframe -Candles $candles -Highs $highs -Lows $lows -Closes $closes -TrendType "LONG"
            $pairSetups += @($longSetups)

            # Analyze SHORT trendline
            $shortSetups = Analyze-TrendlineSetup -Pair $Pair -Timeframe $timeframe -Candles $candles -Highs $highs -Lows $lows -Closes $closes -TrendType "SHORT"
            $pairSetups += @($shortSetups)

        } catch {
            Write-DaemonLog "Error analyzing $Pair [$timeframe]: $_" -Level WARN
        }

        # Rate limiting
        Start-Sleep -Milliseconds $script:API_RATE_LIMIT_DELAY_MS
    }

    return @($pairSetups)
}

function Analyze-TrendlineSetup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Pair,

        [Parameter(Mandatory=$true)]
        [string]$Timeframe,

        [Parameter(Mandatory=$true)]
        [PSObject[]]$Candles,

        [Parameter(Mandatory=$true)]
        [double[]]$Highs,

        [Parameter(Mandatory=$true)]
        [double[]]$Lows,

        [Parameter(Mandatory=$true)]
        [double[]]$Closes,

        [Parameter(Mandatory=$true)]
        [ValidateSet("LONG", "SHORT")]
        [string]$TrendType
    )

    $trendline = Detect-Trendline -Highs $Highs -Lows $Lows -TrendType $TrendType

    if (-not $trendline) {
        return @()
    }

    $currentPrice = $Closes[-1]

    # Calculate proximity to trendline
    $distance = if ($TrendType -eq "LONG") {
        $currentPrice - $trendline.start_price
    } else {
        $trendline.start_price - $currentPrice
    }

    $proximityPct = ($distance / $trendline.start_price) * 100

    # Only process if price is near trendline (within 5%)
    if ($proximityPct -lt -3 -or $proximityPct -gt 5) {
        return @()
    }

    # Calculate confluence score
    $confluenceResult = Get-ConfluenceScoreEnhanced -Candles $Candles -SetupType $TrendType -TrendlineStartPrice $trendline.start_price -TrendlineTouches $trendline.touches

    if ($confluenceResult.total_score -lt $script:CONFLUENCE_THRESHOLD) {
        return @()  # Below threshold
    }

    # Calculate risk/reward
    $stop = if ($TrendType -eq "LONG") {
        $trendline.start_price * 0.98
    } else {
        $trendline.start_price * 1.02
    }

    $risk = [Math]::Abs($currentPrice - $stop)
    $target = if ($TrendType -eq "LONG") {
        $currentPrice + ($risk * 5.0)  # 1:5 R:R target
    } else {
        $currentPrice - ($risk * 5.0)
    }

    $setup = [PSCustomObject]@{
        id = "{0}_{1}_{2}_{3}" -f $Pair, $Timeframe, $TrendType, (Get-Date -Format "yyyyMMddHHmm")
        timestamp = Get-Date -Format "o"
        pair = $Pair
        timeframe = $Timeframe
        trend_type = $TrendType
        confidence_score = $confluenceResult.total_score
        signals_fired = $confluenceResult.signals_fired -join "|"
        rsi = $confluenceResult.rsi
        volume_climax_ratio = $confluenceResult.volume_climax_ratio
        trendline_touches = $confluenceResult.trendline_touches
        entry_price = [Math]::Round($currentPrice, 8)
        stop_loss = [Math]::Round($stop, 8)
        target_price = [Math]::Round($target, 8)
        risk_usdt = [Math]::Round($risk, 8)
        reward_usdt = [Math]::Round([Math]::Abs($target - $currentPrice), 8)
        rr_ratio = if ($risk -ne 0) { [Math]::Round([Math]::Abs($target - $currentPrice) / $risk, 2) } else { 0 }
        status = "NEW"
        unrealized_pnl = 0.0
        creation_scan = $script:PerformanceMetrics.total_scans
    }

    return @($setup)
}

function Detect-Trendline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [double[]]$Highs,

        [Parameter(Mandatory=$true)]
        [double[]]$Lows,

        [Parameter(Mandatory=$true)]
        [ValidateSet("LONG", "SHORT")]
        [string]$TrendType
    )

    if ($Highs.Length -lt 3) {
        return $null
    }

    # Simple linear regression on last N candles
    $fitData = if ($TrendType -eq "LONG") { $Lows } else { $Highs }

    $n = $fitData.Length
    $sumX = 0; $sumY = 0; $sumXY = 0; $sumX2 = 0

    for ($i = 0; $i -lt $n; $i++) {
        $sumX += $i
        $sumY += $fitData[$i]
        $sumXY += $i * $fitData[$i]
        $sumX2 += $i * $i
    }

    $denom = ($n * $sumX2) - ($sumX * $sumX)
    if ($denom -eq 0) { return $null }

    $slope = (($n * $sumXY) - ($sumX * $sumY)) / $denom
    $intercept = ($sumY - ($slope * $sumX)) / $n

    # Count touches within tolerance (1.5%)
    $touches = 0
    $tolerance = 0.015

    for ($i = 0; $i -lt $n; $i++) {
        $lineValue = $intercept + ($slope * $i)
        if ($lineValue -le 0) { continue }

        $diffPct = [Math]::Abs($fitData[$i] - $lineValue) / $lineValue
        if ($diffPct -le $tolerance) {
            $touches += 1
        }
    }

    # Require at least 2 touches
    if ($touches -lt 2) {
        return $null
    }

    # Validate slope is reasonable (5-35 degrees)
    $slopeDeg = [Math]::Atan($slope) * (180 / [Math]::PI)
    if ([Math]::Abs($slopeDeg) -lt 5 -or [Math]::Abs($slopeDeg) -gt 35) {
        return $null
    }

    return [PSCustomObject]@{
        slope = $slope
        intercept = $intercept
        start_price = $intercept
        end_price = $intercept + ($slope * ($n - 1))
        touches = $touches
        quality = if ($touches -ge 3) { "A+" } else { "A" }
    }
}

# ============================================================================
# MAIN SCAN LOOP
# ============================================================================

function Invoke-DaemonScan {
    [CmdletBinding()]
    param()

    $scanStartTime = Get-Date
    Write-DaemonLog "--- SCAN CYCLE START ---" -Level INFO

    # Update pair cache
    Update-PairCache

    # Select pairs to analyze (rotate through full list)
    $pairsToAnalyze = $script:CachedPairs | Select-Object -First $script:MAX_PAIRS_PER_SCAN

    Write-DaemonLog "Scanning $($pairsToAnalyze.Count) pairs..." -Level INFO

    $cycleSetups = @()
    $analyzed = 0

    foreach ($pair in $pairsToAnalyze) {
        $analyzed += 1

        # Throttle output
        if ($analyzed % 10 -eq 0) {
            Write-DaemonLog "Progress: $analyzed/$($pairsToAnalyze.Count) pairs" -Level INFO
        }

        try {
            $setups = Analyze-PairTrendlines -Pair $pair

            foreach ($setup in $setups) {
                if ($setup.confidence_score -ge $script:CONFLUENCE_THRESHOLD) {
                    $cycleSetups += $setup
                }
            }
        } catch {
            # Continue on error
        }
    }

    Write-DaemonLog "Found $($cycleSetups.Count) high-quality setups" -Level INFO

    # Update active setups
    $script:ActiveSetups += $cycleSetups

    # Mark setups as closed if price hits target or stop
    Update-SetupStatuses

    # Update performance metrics
    $script:PerformanceMetrics.total_scans += 1
    $script:PerformanceMetrics.pairs_analyzed = $pairsToAnalyze.Count
    $script:PerformanceMetrics.setups_found = $cycleSetups.Count

    if ($script:ActiveSetups.Count -gt 0) {
        $script:PerformanceMetrics.avg_confluence_score = ($script:ActiveSetups | Measure-Object -Property confidence_score -Average).Average
    }

    $scanEndTime = Get-Date
    $scanDuration = ($scanEndTime - $scanStartTime).TotalSeconds

    Write-DaemonLog "Scan completed in $([Math]::Round($scanDuration, 1))s. Active: $($script:ActiveSetups.Count)" -Level INFO

    # Save state
    Save-DaemonState

    # Send Telegram alerts for new setups
    foreach ($setup in $cycleSetups) {
        Send-ToriSetupAlert -Setup $setup
    }

    $script:LastScanTime = $scanEndTime
}

function Update-SetupStatuses {
    [CmdletBinding()]
    param()

    $closedSetups = @()

    foreach ($setup in $script:ActiveSetups) {
        try {
            # Fetch current price
            $ticker = CoinEx-GetTicker -market $setup.pair
            $currentPrice = [double]$ticker.last

            # Check if target hit
            if ($setup.trend_type -eq "LONG" -and $currentPrice -ge $setup.target_price) {
                $setup.status = "CLOSED_TARGET"
                $setup.unrealized_pnl = $setup.reward_usdt
                $closedSetups += $setup
                Write-DaemonLog "Setup $($setup.id) closed at target: $currentPrice" -Level INFO
            }
            # Check if stop hit
            elseif ($setup.trend_type -eq "LONG" -and $currentPrice -le $setup.stop_loss) {
                $setup.status = "CLOSED_STOP"
                $setup.unrealized_pnl = -$setup.risk_usdt
                $closedSetups += $setup
                Write-DaemonLog "Setup $($setup.id) stopped: $currentPrice" -Level INFO
            }
            # SHORT logic
            elseif ($setup.trend_type -eq "SHORT" -and $currentPrice -le $setup.target_price) {
                $setup.status = "CLOSED_TARGET"
                $setup.unrealized_pnl = $setup.reward_usdt
                $closedSetups += $setup
                Write-DaemonLog "Setup $($setup.id) closed at target: $currentPrice" -Level INFO
            }
            elseif ($setup.trend_type -eq "SHORT" -and $currentPrice -ge $setup.stop_loss) {
                $setup.status = "CLOSED_STOP"
                $setup.unrealized_pnl = -$setup.risk_usdt
                $closedSetups += $setup
                Write-DaemonLog "Setup $($setup.id) stopped: $currentPrice" -Level INFO
            }
            else {
                # Still open, update unrealized PnL
                if ($setup.trend_type -eq "LONG") {
                    $setup.unrealized_pnl = $currentPrice - $setup.entry_price
                } else {
                    $setup.unrealized_pnl = $setup.entry_price - $currentPrice
                }
            }
        } catch {
            Write-DaemonLog "Failed to update status for $($setup.pair): $_" -Level WARN
        }
    }

    # Move closed setups to history
    if ($closedSetups.Count -gt 0) {
        $script:ActiveSetups = $script:ActiveSetups | Where-Object { $_.id -notin $closedSetups.id }
        $script:ClosedTrades += $closedSetups
    }
}

# ============================================================================
# DAEMON MAIN LOOP
# ============================================================================

function Start-ToriDaemon {
    [CmdletBinding()]
    param()

    Write-DaemonLog "=== TORI DAEMON STARTED ===" -Level INFO

    # Load existing state
    Load-DaemonState

    # Load dependencies
    $libPath = Join-Path $PSScriptRoot "lib_tori_confluence_detector.ps1"
    if (Test-Path $libPath) {
        . $libPath
    }

    $coinexPath = Join-Path $PSScriptRoot "lib_coinex.ps1"
    if (Test-Path $coinexPath) {
        . $coinexPath
    }

    $script:IsRunning = $true
    $nextScanTime = Get-Date

    # Main loop
    while ($script:IsRunning) {
        $now = Get-Date

        # Check if it's time for a scan
        if ($now -ge $nextScanTime) {
            try {
                Invoke-DaemonScan
            } catch {
                Write-DaemonLog "Scan failed: $_" -Level ERROR
            }

            $nextScanTime = $now.AddMinutes($script:SCAN_INTERVAL_MINUTES)
            Write-DaemonLog "Next scan scheduled for: $nextScanTime" -Level INFO
        }

        # Write heartbeat every 5 minutes
        if (((Get-Date) - $script:LastHeartbeatTime).TotalSeconds -ge $script:HEARTBEAT_INTERVAL_SEC) {
            Write-DaemonHeartbeat
        }

        # Sleep before checking again
        Start-Sleep -Seconds 60
    }

    Write-DaemonLog "=== TORI DAEMON STOPPED ===" -Level INFO
}

function Stop-ToriDaemon {
    [CmdletBinding()]
    param()

    Write-DaemonLog "Stop signal received" -Level INFO
    $script:IsRunning = $false

    # Final save
    Save-DaemonState
    Write-DaemonLog "Final state saved" -Level INFO
}

# ============================================================================
# PLACEHOLDER: Telegram Alert (implemented in tori_telegram_alerts.ps1)
# ============================================================================

function Send-ToriSetupAlert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$Setup
    )

    # Placeholder - integrated with tori_telegram_alerts.ps1
    # Write-DaemonLog "New setup alert: $($Setup.pair) $($Setup.trend_type) score=$($Setup.confidence_score)" -Level INFO
}

# ============================================================================
# EXPORT & ENTRY POINT
# ============================================================================

Export-ModuleMember -Function Start-ToriDaemon, Stop-ToriDaemon, Invoke-DaemonScan, Update-SetupStatuses

# If run directly (not sourced)
if ($MyInvocation.InvocationName -ne ".") {
    Start-ToriDaemon
}


