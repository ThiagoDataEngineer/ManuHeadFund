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
$script:TORI_CONFLUENCE_THRESHOLD_BULL = 65   # Regime-aware: abaixado em BULL (menos confluencia disponivel em rango)
# 2026-08-20 FIX: score=65 era consistente em mercado BULL/NEUTRO (47 candidatos,
# 100% bloqueados por 80 threshold). Achado: FRACTAL+baseline(50)=65, outros sinais
# (RSI_EXTREME, CHoCH, VOLUME_CLIMAX, VOLUME_PROFILE) nao disparam em rango. Fix:
# regime-aware threshold -- 65 em BULL/NEUTRO, 80 em BEAR/trending.
#
# 2026-07-09 EVOLUTION WIRE: threshold agora e tunavel (registry 70-90).
# Bound 2 de 2: clamp local mesmo se overlay vier fora do range.
if (Get-Command Get-EvolutionParams -ErrorAction SilentlyContinue) {
    try {
        $__evo = Get-EvolutionParams
        if ($__evo.tori_confluence_threshold) {
            $__t = [int]$__evo.tori_confluence_threshold
            if ($__t -ge 70 -and $__t -le 90) { $script:TORI_CONFLUENCE_THRESHOLD = $__t }
        }
    } catch {}
}
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

        # Decision: PASS if score >= threshold (regime-aware)
        $effectiveThreshold = $script:TORI_CONFLUENCE_THRESHOLD
        $scenario = "BEAR"  # default

        # Try to get market scenario (BULL/BEAR/NEUTRO/CAPITULACAO/EUFORIA)
        if (Get-Command Resolve-MarketScenario -ErrorAction SilentlyContinue) {
            try {
                # Resolve-MarketScenario requires: Price, Ema20, Ema50, Ema200, Rsi, Momentum30dPct, VolRatio
                # For now, use a conservative fallback if data not available
                # In production, these would come from tech analysis layer
                $scenario_result = Resolve-MarketScenario -Price 0 -Ema20 0 -Ema50 0 -Ema200 0 -Rsi 50 -Momentum30dPct 0 -VolRatio 1.0
                if ($scenario_result -and $scenario_result.scenario) {
                    $scenario = [string]$scenario_result.scenario
                    if ($scenario -in @("BULL", "NEUTRO")) {
                        $effectiveThreshold = $script:TORI_CONFLUENCE_THRESHOLD_BULL
                    }
                }
            } catch {
                # fallback: stay with BEAR/strict threshold, log error
                [void]$auditLog.Add("[TORI Gate] WARN: Resolve-MarketScenario failed, using default BEAR threshold")
            }
        } else {
            [void]$auditLog.Add("[TORI Gate] NOTE: Resolve-MarketScenario not available, using default BEAR threshold")
        }

        $passes = ($score -ge $effectiveThreshold)
        $reason = if ($passes) { "pass" } else { "fail_low_confidence" }

        [void]$auditLog.Add("[TORI Gate] Market scenario: $scenario, effective threshold: $effectiveThreshold")
        [void]$auditLog.Add("[TORI Gate] Decision: $reason (score=$score vs threshold=$effectiveThreshold)")

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

    # 2026-07-09 FIX RAIZ "0 trades": 3 bugs empilhados aqui bloqueavam 100% das entradas
    # (todo candidato morria com score=-1 fail_closed:insufficient_candle_data):
    #   1. Endpoint /v2/futures/candlestick?type=1h NAO EXISTE -> code=4009 unknown method.
    #      Correto (validado ao vivo): /v2/futures/kline?period=1hour -> code=0.
    #   2. Payload v2 = OBJETOS {open,close,high,low,volume,created_at}, nao arrays
    #      posicionais — o parser $_[0]..$_[5] nunca funcionaria.
    #   3. $global:COINEX_BASE_URL vazio na nuvem (config.ps1 define sem $global: e o
    #      Setup do workflow sobrescreve config.local.ps1) -> fallback hardcoded.
    $base = if ($global:COINEX_BASE_URL) { $global:COINEX_BASE_URL } else { "https://api.coinex.com" }

    # Normaliza timeframe p/ formato period da CoinEx v2 (aceita "1h" legado e "1hour")
    $periodMap = @{
        "1m" = "1min"; "5m" = "5min"; "15m" = "15min"; "30m" = "30min"
        "1h" = "1hour"; "2h" = "2hour"; "4h" = "4hour"; "1d" = "1day"; "1w" = "1week"
    }
    $period = if ($periodMap.ContainsKey($Timeframe)) { $periodMap[$Timeframe] } else { $Timeframe }

    function _ParseKlineData($data) {
        return @($data | ForEach-Object {
            [PSCustomObject]@{
                timestamp = [int64]$_.created_at
                open      = [double]$_.open
                high      = [double]$_.high
                low       = [double]$_.low
                close     = [double]$_.close
                volume    = [double]$_.volume
            }
        })
    }

    # 2026-08-14 FIX: periodo em segundos, usado pra descartar o candle EM
    # FORMACAO (achado real: candle "atual" de 1h com 1-50min de vida
    # comparado contra media de candles fechados de 60min inteiros --
    # ACEUSDT: volume=53.71 no candle em formacao vs ~6000-22000 nos 5
    # anteriores fechados, ratio caindo pra 0.01. TUTUSDT: mesmo padrao,
    # 977.62 vs ~30000-111000. Isso derrubava sistematicamente o
    # VOLUME_CLIMAX (so 4/92 hits reais auditados) e mantinha a maioria
    # dos candidatos travada em score=65 (so fractal_pattern, sem
    # confluencia) contra o threshold=80 do TORI Gate.
    $periodSeconds = @{
        "1min"=60; "5min"=300; "15min"=900; "30min"=1800
        "1hour"=3600; "2hour"=7200; "4hour"=14400; "1day"=86400; "1week"=604800
    }
    $periodSec = if ($periodSeconds.ContainsKey($period)) { $periodSeconds[$period] } else { 3600 }

    function _DropIncompleteLastCandle($parsed) {
        if (@($parsed).Count -lt 2) { return $parsed }
        $lastTs = [double]$parsed[-1].timestamp / 1000.0
        $nowEpoch = [double]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
        $ageSec = $nowEpoch - $lastTs
        if ($ageSec -lt $periodSec) {
            return @($parsed[0..($parsed.Count - 2)])
        }
        return $parsed
    }

    try {
        # Try futures first (most liquid)
        $url = "$base/v2/futures/kline?market=$Market&period=$period&limit=$Limit"
        $candles = Invoke-RestMethod -Uri $url -Method GET -TimeoutSec $TimeoutSeconds -ErrorAction Stop
        if ($candles.code -eq 0 -and $candles.data -and @($candles.data).Count -gt 0) {
            return (_DropIncompleteLastCandle (_ParseKlineData $candles.data))
        }

        # Fallback to spot
        $url = "$base/v2/spot/kline?market=$Market&period=$period&limit=$Limit"
        $candles = Invoke-RestMethod -Uri $url -Method GET -TimeoutSec $TimeoutSeconds -ErrorAction Stop
        if ($candles.code -eq 0 -and $candles.data -and @($candles.data).Count -gt 0) {
            return (_DropIncompleteLastCandle (_ParseKlineData $candles.data))
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
