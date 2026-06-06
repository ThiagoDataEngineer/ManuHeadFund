# lib_orchestrator_performance_integration.ps1 — Injeta Performance Refiner no Orchestrator
# POSIÇÃO: Após Mentor APROVAR, antes de telegram fire
# IMPACTO: Bloqueia entradas fracas mesmo com Mentor OK

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

function Invoke-PerformanceGate {
    <#
    .SYNOPSIS
    Gate final: confluência multi-sinal + timing + validação de dados.
    Roda APÓS Mentor, ANTES de PlaceOrder.
    #>
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [object] $TriagemResult,      # tier + score + direction
        [Parameter(Mandatory)] [object] $MesaResult,          # consensus + sinal
        [Parameter(Mandatory)] [object] $MentorResult,        # decision + conviction
        [double] $CurrentPrice = 0,
        [double] $Change24hPct = 0,
        [double] $VolumeUsd = 0,
        [double] $AtrPct = 0,
        [double] $Volatility5mPct = 0,
        [string] $JournalDir = $global:JOURNAL_DIR,
        [datetime] $Now = (Get-Date)
    )

    if (-not (Test-Path $JournalDir)) {
        New-Item -ItemType Directory -Path $JournalDir -Force | Out-Null
    }

    $timestamp = $Now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $gateLogPath = Join-Path $JournalDir "performance_gate_audit.jsonl"

    # === 1. Validação de dados (pre-requisito) ===
    $faroV3Score = if ($TriagemResult.score_faro) { [double]$TriagemResult.score_faro } else { 0 }
    $toriScore = if ($TriagemResult.score_tori) { [double]$TriagemResult.score_tori } else { 0 }

    # DSR = confiança walk-forward
    $dsrConfidence = if ($TriagemResult.dsr_confidence) { [double]$TriagemResult.dsr_confidence } else { 0 }

    # Mentor conviction (0-100)
    $mentorConviction = if ($MentorResult.conviction_pct) { [double]$MentorResult.conviction_pct } else { 50 }

    # Mesa consensus → score
    $mesaConsensus = if ($MesaResult.consensus) { [string]$MesaResult.consensus } else { "CAOS" }

    # === 2. Calcula confluência ===
    $sources = @()

    # FARO V3 (50+)
    if ($faroV3Score -ge 50) { $sources += "faro" }

    # Tori (50+)
    if ($toriScore -ge 50) { $sources += "tori" }

    # DSR (50+)
    if ($dsrConfidence -ge 50) { $sources += "dsr" }

    # Mentor (60+)
    if ($mentorConviction -ge 60) { $sources += "mentor" }

    # Mesa (FORTE_3)
    if ($mesaConsensus -eq "FORTE_3") { $sources += "mesa" }

    $confluenceCount = $sources.Count

    # === 3. Validação de timing (ruído) ===
    $isNoisyEntry = $Volatility5mPct -gt 5
    $isGoodTiming = $Volatility5mPct -le 2

    # === 4. DECISÃO GATE ===
    $passes = ($confluenceCount -ge 3) -and (-not $isNoisyEntry)
    $reason = ""

    if ($confluenceCount -lt 3) {
        $reason = "CONFLUENCE_LOW: apenas $confluenceCount/5 sinais (limiar 3)"
        $passes = $false
    }
    elseif ($isNoisyEntry) {
        $reason = "NOISY_ENTRY: vol 5m = $([Math]::Round($Volatility5mPct, 2))% (limiar 5%)"
        $passes = $false
    }
    else {
        $reason = "OK: confluência $confluenceCount/5, timing $([Math]::Round($Volatility5mPct, 2))%"
    }

    # === 5. Size multiplier por confluência ===
    # 5/5 = 1.0x (full size)
    # 4/5 = 0.8x
    # 3/5 = 0.5x (conservative)
    $sizeMultiplier = switch ($confluenceCount) {
        5 { 1.0 }
        4 { 0.8 }
        3 { 0.5 }
        default { 0.0 }  # Não entra se < 3
    }

    # === 6. Log ===
    $entry = [ordered]@{
        timestamp = $timestamp
        market = $Market
        passes_performance_gate = $passes
        reason = $reason
        confluence_count = $confluenceCount
        sources_agree = ($sources -join '+')
        faro_v3_score = $faroV3Score
        tori_score = $toriScore
        dsr_confidence = $dsrConfidence
        mentor_conviction = $mentorConviction
        mesa_consensus = $mesaConsensus
        volatility_5m_pct = [Math]::Round($Volatility5mPct, 2)
        is_good_timing = $isGoodTiming
        size_multiplier = [Math]::Round($sizeMultiplier, 2)
    } | ConvertTo-Json -Compress

    Add-Content -Path $gateLogPath -Value $entry -Encoding UTF8

    return [PSCustomObject]@{
        market = $Market
        passes = $passes
        reason = $reason
        confluence_count = $confluenceCount
        sources_agree = ($sources -join '+')
        size_multiplier = $sizeMultiplier
        timestamp = $timestamp
    }
}

function Get-EntrySignalsForConfluence {
    <#
    .SYNOPSIS
    Extrai sinais de FARO V3, Tori, DSR, Mentor pra calcular confluência.
    Interface simples: retorna hashtable com scores 0-100.
    #>
    param(
        [Parameter(Mandatory)] [string] $Market,
        [string] $JournalDir = $global:JOURNAL_DIR
    )

    # Tenta ler scores mais recentes de cache/logs
    $cacheFile = Join-Path $JournalDir "signal_scores_cache.json"
    $scores = @{
        faro_v3_score = 0
        tori_proximity_score = 0
        dsr_confidence = 0
        mentor_conviction = 0
        mesa_consensus = "CAOS"
    }

    # Fallback: valores defaults conservadores
    # Em produção, esses viêm de cada sinal real
    if (Test-Path $cacheFile) {
        try {
            $cached = Get-Content $cacheFile -Raw | ConvertFrom-Json
            if ($cached.PSObject.Properties[$Market]) {
                $mktData = $cached.$Market
                $scores.faro_v3_score = if ($mktData.faro_v3) { [double]$mktData.faro_v3 } else { 0 }
                $scores.tori_proximity_score = if ($mktData.tori) { [double]$mktData.tori } else { 0 }
                $scores.dsr_confidence = if ($mktData.dsr) { [double]$mktData.dsr } else { 0 }
                $scores.mentor_conviction = if ($mktData.mentor) { [double]$mktData.mentor } else { 50 }
                $scores.mesa_consensus = if ($mktData.mesa) { [string]$mktData.mesa } else { "CAOS" }
            }
        } catch {}
    }

    return $scores
}

function Update-SignalScoresCache {
    <#
    .SYNOPSIS
    Atualiza cache de sinais após cada análise (FARO, Tori, DSR, etc).
    Chamado por cada sinal quando completa seu cálculo.
    #>
    param(
        [Parameter(Mandatory)] [string] $Market,
        [double] $FaroV3Score = 0,
        [double] $ToriScore = 0,
        [double] $DsrConfidence = 0,
        [double] $MentorConviction = 50,
        [string] $MesaConsensus = "CAOS",
        [string] $JournalDir = $global:JOURNAL_DIR
    )

    if (-not (Test-Path $JournalDir)) {
        New-Item -ItemType Directory -Path $JournalDir -Force | Out-Null
    }

    $cacheFile = Join-Path $JournalDir "signal_scores_cache.json"

    # Lê cache existente
    $cache = @{}
    if (Test-Path $cacheFile) {
        try {
            $cache = Get-Content $cacheFile -Raw | ConvertFrom-Json | ConvertTo-Hashtable
        } catch { $cache = @{} }
    }

    # Atualiza market
    if (-not $cache[$Market]) {
        $cache[$Market] = @{}
    }

    $cache[$Market] = [ordered]@{
        faro_v3 = $FaroV3Score
        tori = $ToriScore
        dsr = $DsrConfidence
        mentor = $MentorConviction
        mesa = $MesaConsensus
        updated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    }

    # Escreve cache
    $cache | ConvertTo-Json | Set-Content -Path $cacheFile -Encoding UTF8
}

function ConvertTo-Hashtable {
    param([object]$InputObject)
    $hash = @{}
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $InputObject.PSObject.Properties | ForEach-Object { $hash[$_.Name] = $_.Value }
    } elseif ($InputObject -is [hashtable]) {
        return $InputObject
    }
    return $hash
}
