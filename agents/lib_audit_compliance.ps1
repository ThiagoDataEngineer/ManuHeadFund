# lib_audit_compliance.ps1 — Auditoria completa para reguladores
# ✅ Validação de dados (normalidade)
# ✅ Logs estruturados (Timestamp | Ativo | Decisão | Confiança | Preço)
# ✅ Simulação vs Real (flag clara)

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

# ============================================================================
# PART 1: Data Validation — checa normalidade dos dados ANTES de model
# ============================================================================

function Test-InputDataNormality {
    <#
    .SYNOPSIS
    Valida que dados de entrada estão dentro de intervalos aceitáveis.
    Rejeita outliers, valores negros, dados corrompidos.
    #>
    param(
        [Parameter(Mandatory)] [string] $Market,
        [double] $CurrentPrice,
        [double] $Change24hPct = 0,
        [double] $VolumeUsd = 0,
        [double] $AtrPct = 0,
        [string] $Direction = "LONG",
        [string] $JournalDir = $global:JOURNAL_DIR
    )

    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $validationPath = Join-Path $JournalDir "data_validation_audit.jsonl"

    if (-not (Test-Path $JournalDir)) {
        New-Item -ItemType Directory -Path $JournalDir -Force | Out-Null
    }

    $errors = @()

    # 1. Preço válido (> 0)
    if ($CurrentPrice -le 0) {
        $errors += "PRICE_INVALID: CurrentPrice=$CurrentPrice (deve ser > 0)"
    }

    # 2. Change 24h dentro de limites razoáveis (-50% a +100%)
    if ($Change24hPct -lt -50 -or $Change24hPct -gt 100) {
        $errors += "CHANGE_OUTLIER: 24h change=$Change24hPct% (limiar -50% a +100%)"
    }

    # 3. Volume sensato (se zero, pode ser OK pra alguns mercados; se <0, inválido)
    if ($VolumeUsd -lt 0) {
        $errors += "VOLUME_INVALID: VolumeUsd=$VolumeUsd (negativo)"
    }
    if ($VolumeUsd -gt 0 -and $VolumeUsd -lt 10000) {
        # Warning, não erro (alguns altcoins têm volume baixo)
        $errors += "VOLUME_LOW_WARNING: $VolumeUsd USD (baixo)"
    }

    # 4. ATR% sensato (0.1% a 20%)
    if ($AtrPct -lt 0.1 -or $AtrPct -gt 20) {
        $errors += "ATR_OUTLIER: AtrPct=$AtrPct% (limiar 0.1% a 20%)"
    }

    # 5. Direction válida
    if ($Direction -notmatch "^(LONG|SHORT)$") {
        $errors += "DIRECTION_INVALID: Direction=$Direction (deve ser LONG ou SHORT)"
    }

    $isValid = $errors.Count -eq 0
    $severity = if ($errors.Count -eq 0) { "OK" } elseif ($errors.Count -le 2) { "WARNING" } else { "ERROR" }

    # Log
    $entry = [ordered]@{
        timestamp = $timestamp
        market = $Market
        is_valid = $isValid
        severity = $severity
        error_count = $errors.Count
        errors = ($errors -join ' | ')
        current_price = $CurrentPrice
        change_24h_pct = $Change24hPct
        volume_usd = $VolumeUsd
        atr_pct = $AtrPct
        direction = $Direction
    } | ConvertTo-Json -Compress

    Add-Content -Path $validationPath -Value $entry -Encoding UTF8

    return [PSCustomObject]@{
        market = $Market
        is_valid = $isValid
        severity = $severity
        errors = $errors
        timestamp = $timestamp
    }
}

# ============================================================================
# PART 2: Structured Audit Logs — entradas auditáveis em JSON + CSV
# ============================================================================

function Write-AuditLog {
    <#
    .SYNOPSIS
    Escreve log estruturado para auditores reguladores.
    Formato: Timestamp | Market | AI_Decision | Confidence | Price | Trade_Type | Paper_Or_Live
    #>
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $AiDecision,  # EXECUTE, OBSERVE, SKIP, BLOCK
        [Parameter(Mandatory)] [double] $Confidence,   # 0-100
        [Parameter(Mandatory)] [double] $Price,
        [Parameter(Mandatory)] [string] $TradeType,   # LONG, SHORT, NONE
        [Parameter(Mandatory)] [bool] $IsLiveTrading,  # $true = real, $false = paper
        [string] $Reason = "",
        [string] $JournalDir = $global:JOURNAL_DIR,
        [datetime] $Now = (Get-Date)
    )

    if (-not (Test-Path $JournalDir)) {
        New-Item -ItemType Directory -Path $JournalDir -Force | Out-Null
    }

    $timestamp = $Now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $tradingMode = if ($IsLiveTrading) { "LIVE" } else { "PAPER" }

    # === JSONL (máquina-legível) ===
    $jsonlPath = Join-Path $JournalDir "audit_log.jsonl"
    $jsonlEntry = [ordered]@{
        timestamp = $timestamp
        market = $Market
        ai_decision = $AiDecision
        confidence_pct = [Math]::Round($Confidence, 2)
        current_price = $Price
        trade_type = $TradeType
        trading_mode = $tradingMode
        reason = $Reason
    } | ConvertTo-Json -Compress

    Add-Content -Path $jsonlPath -Value $jsonlEntry -Encoding UTF8

    # === CSV (auditor-legível) ===
    $csvPath = Join-Path $JournalDir "audit_log.csv"
    $csvEntry = "$timestamp|$Market|$AiDecision|$([Math]::Round($Confidence,2))|$([Math]::Round($Price,4))|$TradeType|$tradingMode"

    # Header na primeira execução
    if (-not (Test-Path $csvPath)) {
        "Timestamp|Market|Decision|Confidence_%|Price|Trade_Type|Mode_(LIVE/PAPER)" |
            Add-Content -Path $csvPath -Encoding UTF8
    }

    Add-Content -Path $csvPath -Value $csvEntry -Encoding UTF8

    return [PSCustomObject]@{
        timestamp = $timestamp
        logged_to_jsonl = $true
        logged_to_csv = $true
    }
}

# ============================================================================
# PART 3: Paper vs Live Tracking — distinção clara entre teste e produção
# ============================================================================

function Get-TradingMode {
    <#
    .SYNOPSIS
    Retorna modo operacional: PAPER (simulação), LIVE (real), HYBRID (mix).
    Checa flags no journal/ para determinar.
    #>
    param(
        [string] $JournalDir = $global:JOURNAL_DIR
    )

    # Flags que indicam modo
    $paperFlag = Join-Path $JournalDir "PAPER_CALIBRATION_MODE.flag"
    $liveFlag = Join-Path $JournalDir "LIVE_ENABLED.flag"

    $isPaper = Test-Path $paperFlag
    $isLive = Test-Path $liveFlag

    $mode = switch ($isPaper, $isLive) {
        {$true, $true} { "HYBRID" }
        {$true, $false} { "PAPER" }
        {$false, $true} { "LIVE" }
        default { "UNKNOWN" }
    }

    return [PSCustomObject]@{
        mode = $mode
        is_paper = $isPaper
        is_live = $isLive
        paper_flag_exists = $isPaper
        live_flag_exists = $isLive
    }
}

function New-TradeAuditRecord {
    <#
    .SYNOPSIS
    Cria registro auditável de cada trade executado.
    Documenta TUDO: entrada, SL, TP, reasoning, confiança, modo.
    #>
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Direction,  # LONG / SHORT
        [Parameter(Mandatory)] [double] $EntryPrice,
        [Parameter(Mandatory)] [double] $StoplossPrice,
        [Parameter(Mandatory)] [double] $TargetPrice,
        [Parameter(Mandatory)] [double] $PositionSizeUsd,
        [Parameter(Mandatory)] [double] $ModelConfidence,  # 0-100
        [Parameter(Mandatory)] [string] $DecisionReasoning,
        [Parameter(Mandatory)] [bool] $IsLiveExecution,
        [double] $ConfluenceScore = 0,  # From Performance Refiner
        [string] $JournalDir = $global:JOURNAL_DIR,
        [datetime] $Now = (Get-Date)
    )

    if (-not (Test-Path $JournalDir)) {
        New-Item -ItemType Directory -Path $JournalDir -Force | Out-Null
    }

    $timestamp = $Now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $tradeId = "TRADE_$Market`_$($Now.ToString('yyyyMMdd_HHmmss'))"
    $tradingMode = if ($IsLiveExecution) { "LIVE" } else { "PAPER" }

    # RR ratio
    $riskPercentage = [Math]::Abs($EntryPrice - $StoplossPrice) / $EntryPrice * 100
    $rewardPercentage = [Math]::Abs($TargetPrice - $EntryPrice) / $EntryPrice * 100
    $rrRatio = if ($riskPercentage -gt 0) { $rewardPercentage / $riskPercentage } else { 0 }

    # Audit record (completo, máquina + auditor)
    $auditPath = Join-Path $JournalDir "trade_audit_records.jsonl"
    $record = [ordered]@{
        timestamp = $timestamp
        trade_id = $tradeId
        market = $Market
        direction = $Direction
        entry_price = $EntryPrice
        stoploss_price = $StoplossPrice
        target_price = $TargetPrice
        position_size_usd = $PositionSizeUsd
        risk_pct = [Math]::Round($riskPercentage, 2)
        reward_pct = [Math]::Round($rewardPercentage, 2)
        rr_ratio = [Math]::Round($rrRatio, 2)
        model_confidence_pct = [Math]::Round($ModelConfidence, 2)
        confluence_score = [Math]::Round($ConfluenceScore, 2)
        decision_reasoning = $DecisionReasoning
        trading_mode = $tradingMode
        is_live_execution = $IsLiveExecution
    } | ConvertTo-Json -Compress

    Add-Content -Path $auditPath -Value $record -Encoding UTF8

    return [PSCustomObject]@{
        trade_id = $tradeId
        timestamp = $timestamp
        market = $Market
        trading_mode = $tradingMode
        logged = $true
    }
}

# ============================================================================
# AUDITOR REPORT — gera relatório consolidado para reguladores
# ============================================================================

function Get-AuditorReport {
    <#
    .SYNOPSIS
    Consolida dados de auditoria em relatório executivo.
    Mostra: validações, decisões, confiança, modo, compliance.
    #>
    param(
        [string] $JournalDir = $global:JOURNAL_DIR,
        [int] $DaysToAnalyze = 7
    )

    if (-not (Test-Path $JournalDir)) {
        return [PSCustomObject]@{ error = "Journal dir not found" }
    }

    $cutoffDate = (Get-Date).AddDays(-$DaysToAnalyze).ToUniversalTime()

    # Lê audit log
    $auditLogPath = Join-Path $JournalDir "audit_log.jsonl"
    $auditCount = 0; $executeCount = 0; $liveCount = 0; $paperCount = 0
    $avgConfidence = 0; $confidenceSum = 0

    if (Test-Path $auditLogPath) {
        $entries = @()
        Get-Content $auditLogPath -Encoding UTF8 | ForEach-Object {
            try {
                $entry = $_ | ConvertFrom-Json
                $entries += $entry
            } catch { }
        }

        $auditCount = $entries.Count
        # 2026-07-24 FIX: "(X | Where-Object {...}).Count" sem @() retorna
        # o objeto cru (nao array) quando ha exatamente 1 match --
        # PSCustomObject nao tem .Count, resultado vinha vazio/$null,
        # fazendo execute/live/paper counts sempre errados com N=1.
        $executeCount = @($entries | Where-Object { $_.ai_decision -eq "EXECUTE" }).Count
        $liveCount = @($entries | Where-Object { $_.trading_mode -eq "LIVE" }).Count
        $paperCount = @($entries | Where-Object { $_.trading_mode -eq "PAPER" }).Count
        $avgConfidence = if ($entries.Count -gt 0) {
            ($entries | Measure-Object -Property confidence_pct -Average).Average
        } else { 0 }
    }

    # Lê trade audit records
    $tradeAuditPath = Join-Path $JournalDir "trade_audit_records.jsonl"
    $tradeCount = 0; $liveTradeCount = 0; $avgRr = 0

    if (Test-Path $tradeAuditPath) {
        $trades = @()
        Get-Content $tradeAuditPath -Encoding UTF8 | ForEach-Object {
            try {
                $trade = $_ | ConvertFrom-Json
                $trades += $trade
            } catch { }
        }

        $tradeCount = $trades.Count
        $liveTradeCount = @($trades | Where-Object { $_.trading_mode -eq "LIVE" }).Count
        $avgRr = if ($trades.Count -gt 0) {
            ($trades | Measure-Object -Property rr_ratio -Average).Average
        } else { 0 }
    }

    # Lê validation data
    $validationPath = Join-Path $JournalDir "data_validation_audit.jsonl"
    $validationCount = 0; $validCount = 0; $invalidCount = 0

    if (Test-Path $validationPath) {
        Get-Content $validationPath -Encoding UTF8 | ForEach-Object {
            try {
                $val = $_ | ConvertFrom-Json
                $validationCount++
                if ($val.is_valid) { $validCount++ } else { $invalidCount++ }
            } catch { }
        }
    }

    $reportDate = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss UTC")

    return [PSCustomObject]@{
        report_generated = $reportDate
        period_days = $DaysToAnalyze
        # Validação
        total_data_validations = $validationCount
        valid_entries = $validCount
        invalid_entries = $invalidCount
        data_quality_pct = if ($validationCount -gt 0) { ($validCount / $validationCount * 100) } else { 0 }
        # Decisões
        total_ai_decisions = $auditCount
        execute_decisions = $executeCount
        execute_rate_pct = if ($auditCount -gt 0) { ($executeCount / $auditCount * 100) } else { 0 }
        avg_model_confidence = [Math]::Round($avgConfidence, 2)
        # Modo
        live_trading_enabled = ($liveCount -gt 0)
        paper_trading_enabled = ($paperCount -gt 0)
        live_decisions = $liveCount
        paper_decisions = $paperCount
        # Execução
        total_trades_executed = $tradeCount
        live_trades = $liveTradeCount
        avg_rr_ratio = [Math]::Round($avgRr, 2)
    }
}
