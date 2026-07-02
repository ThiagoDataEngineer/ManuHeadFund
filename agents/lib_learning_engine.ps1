# lib_learning_engine.ps1 — Learning Engine: Auto-Improve Conviction Thresholds
# Captura mistakes do cloud, analisa padrões, auto-calibra conviction + DSR
# Pure functions, 100% testable
# TDD-driven, zero side effects

$ErrorActionPreference = "Stop"

# ============================================================================
# LOG ANALYSIS — Parse Cloud Logs pra Erros
# ============================================================================

function Read-CloudErrorLog {
    <#
    .SYNOPSIS
    Lê logs da nuvem e extrai trades que FALHARAM (hit SL, rejected, etc)

    .PARAMETER LogPath
    Caminho do log (gem_loop.log, trailing_stop_monitor.log, etc)

    .PARAMETER Hours
    Quantas horas pra trás analisar (default 24)

    .OUTPUTS
    @{
      errors = @(
        @{ timestamp, market, signal, conviction, reason, loss_pct }
      )
      total_scanned = int
      error_rate = double (0-100)
    }
    #>
    param(
        [string]$LogPath,
        [int]$Hours = 24
    )

    if (-not (Test-Path $LogPath)) {
        return @{ errors = @(); total_scanned = 0; error_rate = 0 }
    }

    # Read all lines first
    $allLines = @(Get-Content $LogPath -ErrorAction SilentlyContinue)
    $totalScanned = $allLines.Count

    # Filter error lines
    $logs = @($allLines | Select-String -Pattern "\[BLOCKED\]|\[ERROR\]|\[SL.*HIT\]|\[REJECTED\]" |
        ForEach-Object { $_.Line })

    $cutoff = (Get-Date).AddHours(-$Hours)
    $errors = @()

    foreach ($log in $logs) {
        # Parse pattern: [2026-06-18 14:09:27] [BLOCKED] MARKET -- reason
        if ($log -match "\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\].*\[(\w+)\]\s+(\w+USDT).*--\s+(.+)") {
            $ts = [datetime]$Matches[1]
            if ($ts -ge $cutoff) {
                $errors += @{
                    timestamp = $ts
                    market = $Matches[3]
                    reason = $Matches[4].Trim()
                    category = if ($Matches[2] -eq "BLOCKED") { "blocked" } else { "error" }
                }
            }
        }
    }

    $errorRate = if ($totalScanned -gt 0) { $errors.Count / $totalScanned * 100 } else { 0 }

    @{
        errors = $errors
        total_scanned = $totalScanned
        error_rate = [math]::Round($errorRate, 2)
    }
}

function Classify-ErrorPattern {
    <#
    .SYNOPSIS
    Classifica erros em categorias pra encontrar patterns

    .PARAMETER Error
    Objeto de erro com reason field

    .OUTPUTS
    @{ pattern = string; severity = "low"|"medium"|"high"; fixable = $true|$false }
    #>
    param(
        [hashtable]$Error
    )

    $reason = $Error.reason.ToLower()

    $pattern = switch -Regex ($reason) {
        "trendline.*invalid" { "trendline_weak" }
        "downtrend.*strong" { "bear_rejection" }
        "confluence.*insufficient" { "low_confluence" }
        "vol.*climax" { "vol_too_low" }
        "conviction.*low|below" { "conviction_low" }
        "spread.*wide" { "liquidity_issue" }
        "funding.*high" { "funding_risky" }
        "drawdown.*exceed" { "risk_exceeded" }
        default { "other" }
    }

    $severity = switch ($pattern) {
        { $_ -in "conviction_low", "confluence_low" } { "high" }
        { $_ -in "bear_rejection", "drawdown" } { "high" }
        { $_ -in "trendline_weak", "vol_too_low" } { "medium" }
        { $_ -in "liquidity_issue", "funding_risky" } { "medium" }
        default { "low" }
    }

    $fixable = $pattern -in "conviction_low", "trendline_weak", "vol_too_low", "confluence_low"

    @{
        pattern = $pattern
        severity = $severity
        fixable = $fixable
    }
}

# ============================================================================
# PATTERN DETECTION — Find Root Causes
# ============================================================================

function Analyze-ErrorPatterns {
    <#
    .SYNOPSIS
    Agrupa erros por pattern e calcula frequência

    .PARAMETER Errors
    @(@{ timestamp, market, reason, category }, ...)

    .OUTPUTS
    @{
      patterns = @{
        trendline_weak = @{ count, markets, avg_severity }
        conviction_low = @{ count, markets, avg_severity }
        ...
      }
      top_issue = string
      recommendation = string
    }
    #>
    param(
        [array]$Errors
    )

    $patterns = @{}

    foreach ($err in $Errors) {
        $class = Classify-ErrorPattern -Error $err
        $p = $class.pattern

        if (-not $patterns.ContainsKey($p)) {
            $patterns[$p] = @{ count = 0; markets = @(); severity = @() }
        }

        $patterns[$p].count++
        $patterns[$p].markets += $err.market
        $patterns[$p].severity += $class.severity
    }

    $topPattern = $patterns.GetEnumerator() | Sort-Object -Property { $_.Value.count } -Descending | Select-Object -First 1

    $topIssue = if ($topPattern) { $topPattern.Name } else { "none" }

    $recommendation = switch ($topIssue) {
        "conviction_low" { "Raise conviction threshold (currently catching noise)" }
        "trendline_weak" { "Require stronger trendline formation (2+ touches)" }
        "confluence_low" { "Require more signals before entry (3+ confluence)" }
        "bear_rejection" { "Filter SHORT entries in strong downtrends (DSR < 0.3)" }
        "vol_too_low" { "Require volume confirmation before entry" }
        default { "Monitor market conditions" }
    }

    @{
        patterns = $patterns
        top_issue = $topIssue
        recommendation = $recommendation
        total_patterns = $patterns.Count
    }
}

# ============================================================================
# AUTO-CALIBRATION — Adjust Thresholds Based on Learning
# ============================================================================

function Calculate-ConvictionAdjustment {
    <#
    .SYNOPSIS
    Calcula novo threshold de conviction baseado em erro patterns

    .PARAMETER CurrentThreshold
    Threshold atual (default 55)

    .PARAMETER ErrorRate
    Error rate em % (0-100)

    .PARAMETER TopPattern
    Pattern mais comum ("conviction_low", etc)

    .OUTPUTS
    @{
      new_threshold = int (0-100)
      delta = int (+/-)
      reason = string
      confidence = 0-100
    }
    #>
    param(
        [int]$CurrentThreshold = 55,
        [double]$ErrorRate = 0,
        [string]$TopPattern = "none"
    )

    $newThreshold = $CurrentThreshold
    $reason = "stable"
    $confidence = 50

    # Se error rate muito alto (>30%), aumenta threshold
    if ($ErrorRate -gt 30) {
        $increase = [int]($ErrorRate / 10)  # 30% → +3, 50% → +5
        $newThreshold = [math]::Min(100, $CurrentThreshold + $increase)
        $reason = "high_error_rate ($ErrorRate%)"
        $confidence = [math]::Min(90, $confidence + 20)
    }
    # Se error rate baixo (<10%), pode abaixar um pouco
    elseif ($ErrorRate -lt 10 -and $CurrentThreshold -gt 50) {
        $newThreshold = [math]::Max(50, $CurrentThreshold - 2)
        $reason = "low_error_rate_allows_reduction"
        $confidence = 70
    }

    # Ajuste por pattern
    if ($TopPattern -eq "conviction_low") {
        $newThreshold = [math]::Max($newThreshold - 3, 45)  # Abaixa conviction
        $reason = "lowering_conviction_tolerance"
        $confidence = 85
    }
    elseif ($TopPattern -eq "trendline_weak") {
        $newThreshold = [math]::Min($newThreshold + 5, 100)  # Sobe trendline exigência
        $reason = "requiring_stronger_trendline"
        $confidence = 75
    }

    $delta = $newThreshold - $CurrentThreshold

    @{
        new_threshold = $newThreshold
        delta = $delta
        reason = $reason
        confidence = $confidence
        old_threshold = $CurrentThreshold
    }
}

function Calculate-DSRAdjustment {
    <#
    .SYNOPSIS
    Calcula novo DSR target baseado em performance por regime

    .PARAMETER CurrentDSR
    DSR atual (default 1.0)

    .PARAMETER RegimePerformance
    @{ BULL_STRONG = 1.5, BEAR_STRONG = 0.3, ... } (sample from trades)

    .OUTPUTS
    @{
      new_dsr = double
      delta = double
      regime_recommendation = @{ BULL = double, BEAR = double }
    }
    #>
    param(
        [double]$CurrentDSR = 1.0,
        [hashtable]$RegimePerformance = @{}
    )

    $avg = if ($RegimePerformance.Count -gt 0) {
        ($RegimePerformance.Values | Measure-Object -Average).Average
    } else { $CurrentDSR }

    $newDSR = [math]::Max(0.5, [math]::Min(2.0, $avg))

    $regimeRec = @{
        BULL_STRONG = 1.4
        BULL_WEAK = 1.0
        BEAR_WEAK = 0.8
        BEAR_STRONG = 0.3
    }

    @{
        new_dsr = [math]::Round($newDSR, 2)
        delta = [math]::Round($newDSR - $CurrentDSR, 2)
        regime_recommendation = $regimeRec
        confidence = if ($RegimePerformance.Count -ge 5) { 85 } else { 50 }
    }
}

# ============================================================================
# INTEGRATED LEARNING CYCLE
# ============================================================================

function Update-ConvictionFromLogs {
    <#
    .SYNOPSIS
    Full cycle: read logs → analyze → adjust conviction threshold

    .PARAMETER LogPath
    Path do gem_loop.log ou trailing_stop_monitor.log

    .PARAMETER CurrentConvictionThreshold
    Threshold atual (default 55)

    .PARAMETER Hours
    Janela de análise (default 24)

    .OUTPUTS
    @{
      success = $true
      conviction_adjustment = @{ old, new, delta, reason }
      pattern_analysis = @{ top_issue, recommendation }
      action_needed = $true|$false
      next_check = datetime
    }
    #>
    param(
        [string]$LogPath,
        [int]$CurrentConvictionThreshold = 55,
        [int]$Hours = 24
    )

    # 1. Ler logs
    $logAnalysis = Read-CloudErrorLog -LogPath $LogPath -Hours $Hours

    # 2. Analisar patterns
    $patternAnalysis = Analyze-ErrorPatterns -Errors $logAnalysis.errors

    # 3. Calcular ajuste
    $adjustment = Calculate-ConvictionAdjustment `
        -CurrentThreshold $CurrentConvictionThreshold `
        -ErrorRate $logAnalysis.error_rate `
        -TopPattern $patternAnalysis.top_issue

    # 4. Decidir se aplica
    $actionNeeded = $adjustment.delta -ne 0 -and $adjustment.confidence -ge 60

    @{
        success = $true
        conviction_adjustment = $adjustment
        pattern_analysis = $patternAnalysis
        action_needed = $actionNeeded
        error_count = $logAnalysis.errors.Count
        error_rate = $logAnalysis.error_rate
        next_check = (Get-Date).AddHours(6)  # Re-check em 6 horas
    }
}

# Functions auto-exported (no Export-ModuleMember needed for tests)
