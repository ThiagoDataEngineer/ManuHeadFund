# lib_tori_gate_wrapper.ps1 -- Tori Trades as production gate + analysis layer
#
# Wraps lib_tori_confluence_detector + lib_tori_trades_scanner into fail-closed gates
# for entry validation. Confluence threshold: 80 (strict; otherwise BLOCK).
#
# Gate functions:
#   - Test-ToriConfluence: Validates entry via Tori confluence scoring
#   - Get-ToriAnalysisSummary: Returns detailed analysis for logging/audit
#
# Wire into: gem_executor, scan_master, lib_entry_score_boost, lib_gem_decision_cache
# PS 5.1, UTF-8 BOM

# ============================================================================
# CONFIGURATION
# ============================================================================

$script:TORI_CONFLUENCE_THRESHOLD = 80    # Minimum confluence score for ALLOW
$script:TORI_CANDLE_LOOKBACK = 100        # Candles to fetch for analysis
$script:TORI_ANALYSIS_TIMEOUT_SEC = 8     # Max time to compute analysis

# ============================================================================
# Gate function: Test-ToriConfluence
# ============================================================================

function Test-ToriConfluence {
    <#
    .SYNOPSIS
        Fail-closed gate: validate entry via Tori confluence scoring

    .DESCRIPTION
        Before allowing any entry, fetch historical candles and compute Tori
        confluence score. Entry is ALLOWED only if score >= threshold (default 80).
        Otherwise, return fail-closed BLOCK.

        Used as PRE-ENTRY gate in gem_executor + scan_master.

    .PARAMETER Market
        Market symbol (e.g., "BTCUSDT")

    .PARAMETER SetupType
        "LONG" or "SHORT" trade direction

    .PARAMETER TimeframeMinutes
        Primary timeframe to analyze (default 60 = 1H). Supports 5, 15, 60, 240, 1440

    .PARAMETER Price
        Current market price (used for proximity validation)

    .PARAMETER TimeoutSeconds
        Max time to spend analyzing (default 8; fail-gracious on timeout)

    .OUTPUTS
        PSCustomObject @{
            allows = [bool]                   # true=PASS gate, false=BLOCK entry
            confluence_score = [int]          # 0-100, -1 if error
            signals_fired = [string[]]        # Which confluence signals triggered
            reason = [string]                 # "pass" | "fail_low_confidence" | "error:..."
            details = [PSCustomObject]        # Analysis breakdown (rsi, volumes, fractals, etc)
            audit_log = [string]              # Multi-line log for debugging
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Market,

        [Parameter(Mandatory=$true)]
        [ValidateSet("LONG", "SHORT")]
        [string]$SetupType,

        [int]$TimeframeMinutes = 60,
        [double]$Price = 0.0,
        [int]$TimeoutSeconds = 8
    )

    $auditLog = [System.Collections.ArrayList]@()
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        # Log start
        [void]$auditLog.Add("[TORI Gate] START test-confluence $Market dir=$SetupType tf=$($TimeframeMinutes)m")

        # Validate inputs
        if (-not $Market -or $Market.Length -eq 0) {
            return [PSCustomObject]@{
                allows = $false
                confluence_score = -1
                signals_fired = @()
                reason = "fail_closed:invalid_market"
                details = $null
                audit_log = ($auditLog -join "`n")
            }
        }

        # Map timeframe minutes to CoinEx API format
        $tfMap = @{
            5 = "5m"; 15 = "15m"; 60 = "1h"; 240 = "4h"; 1440 = "1d"; 10080 = "1w"
        }
        $tfStr = if ($tfMap.ContainsKey($TimeframeMinutes)) { $tfMap[$TimeframeMinutes] } else { "1h" }
        [void]$auditLog.Add("[TORI Gate] Timeframe mapped: $TimeframeMinutes min -> $tfStr")

        # Fetch historical candles
        [void]$auditLog.Add("[TORI Gate] Fetching $script:TORI_CANDLE_LOOKBACK candles from CoinEx...")
        $candles = Get-ToriHistoricalCandles -Market $Market -Timeframe $tfStr -Limit $script:TORI_CANDLE_LOOKBACK -TimeoutSeconds ([int]($TimeoutSeconds * 0.4))

        if (-not $candles -or $candles.Count -lt 10) {
            [void]$auditLog.Add("[TORI Gate] WARN: insufficient candle data ($($candles.Count) candles)")
            return [PSCustomObject]@{
                allows = $false
                confluence_score = -1
                signals_fired = @()
                reason = "fail_closed:insufficient_candle_data"
                details = @{ candle_count = if ($candles) { $candles.Count } else { 0 } }
                audit_log = ($auditLog -join "`n")
            }
        }
        [void]$auditLog.Add("[TORI Gate] Fetched $($candles.Count) candles OK")

        # Compute confluence score via lib_tori_confluence_detector
        [void]$auditLog.Add("[TORI Gate] Computing confluence score...")

        # Get current close as trendline reference
        $currentClose = if ($Price -gt 0) { $Price } else { [double]$candles[-1].close }

        $confluenceResult = Get-ConfluenceScoreEnhanced -Candles $candles -SetupType $SetupType -TrendlineStartPrice $currentClose -TrendlineTouches 2

        if (-not $confluenceResult) {
            [void]$auditLog.Add("[TORI Gate] ERROR: confluence calculation failed")
            return [PSCustomObject]@{
                allows = $false
                confluence_score = -1
                signals_fired = @()
                reason = "fail_closed:confluence_calculation_error"
                details = $null
                audit_log = ($auditLog -join "`n")
            }
        }

        $score = [int]$confluenceResult.total_score
        $signals = @($confluenceResult.signals_fired)
        $signalsJoined = if ($signals.Count -gt 0) { $signals -join ", " } else { "none" }
        [void]$auditLog.Add("[TORI Gate] Confluence score computed: $score (signals: $signalsJoined)")

        # Decision: PASS if score >= threshold
        $passes = ($score -ge $script:TORI_CONFLUENCE_THRESHOLD)
        $reason = if ($passes) { "pass" } else { "fail_low_confidence" }

        [void]$auditLog.Add("[TORI Gate] Decision: $reason (score=$score vs threshold=$script:TORI_CONFLUENCE_THRESHOLD)")

        # Elapsed time check
        $stopwatch.Stop()
        if ($stopwatch.ElapsedMilliseconds -gt ($TimeoutSeconds * 1000)) {
            [void]$auditLog.Add("[TORI Gate] WARN: analysis took $($stopwatch.ElapsedMilliseconds)ms (timeout=$($TimeoutSeconds * 1000)ms)")
        }

        return [PSCustomObject]@{
            allows = $passes
            confluence_score = $score
            signals_fired = @($signals)
            reason = $reason
            details = [PSCustomObject]@{
                rsi = [double]($confluenceResult.rsi)
                volume_climax_ratio = [double]($confluenceResult.volume_climax_ratio)
                peak_volume_level = [double]($confluenceResult.peak_volume_level)
                trendline_touches = [int]($confluenceResult.trendline_touches)
                breakdown = $confluenceResult.breakdown
            }
            audit_log = ($auditLog -join "`n")
        }

    } catch {
        [void]$auditLog.Add("[TORI Gate] EXCEPTION: $($_.Exception.Message)")
        return [PSCustomObject]@{
            allows = $false
            confluence_score = -1
            signals_fired = @()
            reason = "fail_closed:exception"
            details = @{ error = "$($_.Exception.Message)" }
            audit_log = ($auditLog -join "`n")
        }
    }
}

# ============================================================================
# Helper: Get-ToriHistoricalCandles
# Fetch candles from CoinEx API
# ============================================================================

function Get-ToriHistoricalCandles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Market,

        [Parameter(Mandatory=$true)]
        [string]$Timeframe,

        [int]$Limit = 100,
        [int]$TimeoutSeconds = 3
    )

    try {
        # Try futures first (most liquid)
        $url = "$($global:COINEX_BASE_URL)/v2/futures/candlestick?market=$Market&type=$Timeframe&limit=$Limit"

        $candles = Invoke-RestMethod -Uri $url -Method GET -TimeoutSec $TimeoutSeconds -ErrorAction Stop

        if ($candles.code -eq 0 -and $candles.data -and @($candles.data).Count -gt 0) {
            # Convert to standard candle format
            return @($candles.data | ForEach-Object {
                [PSCustomObject]@{
                    timestamp = [int64]$_[0]
                    open      = [double]$_[1]
                    high      = [double]$_[2]
                    low       = [double]$_[3]
                    close     = [double]$_[4]
                    volume    = [double]$_[5]
                }
            })
        }

        # Fallback to spot
        $url = "$($global:COINEX_BASE_URL)/v2/spot/candlestick?market=$Market&type=$Timeframe&limit=$Limit"
        $candles = Invoke-RestMethod -Uri $url -Method GET -TimeoutSec $TimeoutSeconds -ErrorAction Stop

        if ($candles.code -eq 0 -and $candles.data -and @($candles.data).Count -gt 0) {
            return @($candles.data | ForEach-Object {
                [PSCustomObject]@{
                    timestamp = [int64]$_[0]
                    open      = [double]$_[1]
                    high      = [double]$_[2]
                    low       = [double]$_[3]
                    close     = [double]$_[4]
                    volume    = [double]$_[5]
                }
            })
        }

        return $null
    } catch {
        Write-Host "[WARN] Get-ToriHistoricalCandles failed for $Market`: $($_.Exception.Message)" -ForegroundColor Yellow
        return $null
    }
}

# ============================================================================
# Helper: Get-ToriAnalysisSummary
# Return human-readable summary for logging
# ============================================================================

function Get-ToriAnalysisSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$GateResult
    )

    $summary = @()
    $summary += "╔════════ TORI CONFLUENCE ANALYSIS ════════"
    $summary += "║ Market: $($GateResult.market)"
    $summary += "║ Score: $($GateResult.confluence_score)/100"
    $summary += "║ Status: $(if ($GateResult.allows) { '✓ PASS' } else { '✗ BLOCK' })"
    $summary += "║ Reason: $($GateResult.reason)"

    if ($GateResult.signals_fired -and $GateResult.signals_fired.Count -gt 0) {
        $summary += "║ Signals: $($GateResult.signals_fired -join ' + ')"
    }

    if ($GateResult.details) {
        $summary += "║"
        $summary += "║ Details:"
        $summary += "║   RSI: $([math]::Round($GateResult.details.rsi, 1))"
        $summary += "║   Vol Climax: $([math]::Round($GateResult.details.volume_climax_ratio, 2))x"
        $summary += "║   Trendline Touches: $($GateResult.details.trendline_touches)"
    }

    $summary += "╚════════════════════════════════════════"
    return $summary -join "`n"
}
