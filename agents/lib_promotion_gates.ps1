# lib_promotion_gates.ps1 -- Suite de gates pre-promotion + pre-trade.
#
# Cada funcao retorna PSCustomObject @{ passes; reason; details }.
# Filosofia: composability — pode aplicar todos em sequencia, blocking == false.
#
# Gates:
#   1. Test-ConcentrationLimit   max N posicoes Tier A LIVE
#   2. Test-DailyLossCircuit     equity -X% dia -> halt
#   3. Test-SectorConcentration  max N markets do mesmo setor
#   4. Test-CooldownPostDemote   nao re-promote em <N dias
#   5. Test-MinVolumeGate        vol minima
#   6. Test-PhaseBoundarySafety  N dias apos phase change
#
# Helpers:
#   - Add-DemoteEvent: append jsonl historico
#   - Get-SectorOf: lookup market->setor
#
# PS 5.1, UTF-8 BOM, pure functions (excepto I/O em demote_history).


if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

# 2026-05-20: dot-source lib_pump_buy_gate (era orfa antes do wire em Invoke-AllGates)
if (-not (Get-Command Test-PumpBuyGate -ErrorAction SilentlyContinue)) {
    $_pumpLib = Join-Path $PSScriptRoot "lib_pump_buy_gate.ps1"
    if (Test-Path $_pumpLib) { . $_pumpLib }
}
# 2026-05-23 Tier 1 v9: dot-source lib_beta_cap_per_phase (opt-in via env BETA_CAP_PER_PHASE_ENABLED)
if (-not (Get-Command Get-BetaCapForPhase -ErrorAction SilentlyContinue)) {
    $_betaCapLib = Join-Path $PSScriptRoot "lib_beta_cap_per_phase.ps1"
    if (Test-Path $_betaCapLib) { . $_betaCapLib }
}

$script:SECTOR_MAP_DEFAULT_PATH    = Join-Path $global:JOURNAL_DIR "sector_map.json"
$script:DEMOTE_HISTORY_DEFAULT_PATH = Join-Path $global:JOURNAL_DIR "demote_history.jsonl"


function Get-DailyEquityDelta {
    # I/O helper: registra equity inicial do dia em journal/equity_daily_YYYYMMDD.json
    # e devolve delta percentual vs inicial. Primeiro call do dia retorna 0 (registra baseline).
    # Saida: PSCustomObject @{ start_equity; current_equity; delta_pct; first_call }
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double] $CurrentEquityUsd,
        [string] $StateDir = $global:JOURNAL_DIR,
        [datetime] $Now = (Get-Date)
    )
    if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
    $dayKey = $Now.ToString("yyyyMMdd")
    $stateFile = Join-Path $StateDir "equity_daily_$dayKey.json"
    $firstCall = $false
    $startEquity = $CurrentEquityUsd
    # B17 fix 2026-05-20 PM6+400min: corruption explicit (era silent fail-open).
    $corrupt = $false
    if (Test-Path $stateFile) {
        try {
            $st = Get-Content $stateFile -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($null -ne $st.start_equity_usd) {
                $startEquity = [double]$st.start_equity_usd
            } else {
                $corrupt = $true
            }
        } catch {
            $corrupt = $true
        }
    } else {
        $firstCall = $true
        @{
            day = $dayKey
            start_equity_usd = $CurrentEquityUsd
            recorded_at = $Now.ToString("yyyy-MM-ddTHH:mm:ssZ")
        } | ConvertTo-Json | Out-File -FilePath $stateFile -Encoding utf8 -Force
    }
    $deltaPct = if ($startEquity -gt 0) {
        [Math]::Round((($CurrentEquityUsd - $startEquity) / $startEquity) * 100, 2)
    } else { 0 }
    return [PSCustomObject]@{
        start_equity   = $startEquity
        current_equity = $CurrentEquityUsd
        delta_pct      = $deltaPct
        first_call     = $firstCall
        state_file     = $stateFile
        corrupt        = $corrupt   # B17: caller deve fail-closed se true
    }
}


function Test-ConcentrationLimit {
    # 2026-05-19 PM: expandido de 5 -> 17 markets. Elegiveis NAO eh = posicoes abertas;
    # posicoes simultaneas continuam gated por MAX_RISCO_ABERTO (3% capital ~$82 = 3 trades).
    # Cap 17 alinha com objetivo: 5 amplifiers grandfather + 8-12 AAA+ tier 2-3 alvos.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [int] $CurrentTierACount,
        [int] $MaxTierA = 17
    )
    $passes = $CurrentTierACount -le $MaxTierA
    return [PSCustomObject]@{
        passes  = $passes
        current = $CurrentTierACount
        max     = $MaxTierA
        reason  = if ($passes) { "ok" } else { "concentration_limit_exceeded" }
    }
}


function Get-BetaFromMatrix {
    # Calcula beta vs BTC pra um market consultando correlation_matrix.json.
    # beta = corr(X, BTC) * (sigma_X / sigma_BTC). Aproximamos via correlation
    # signed * scale = matriz nao guarda sigmas. Como aproximacao: usar corr direta
    # como proxy de beta (correto pra returns normalizados; subestima beta de alta-vol).
    # Implementacao completa: backtest/inverse_correlation_analysis.py (regression beta).
    # Aqui usamos cache offline em journal/beta_vs_btc.json se presente.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [string] $BetaPath = (Join-Path $global:JOURNAL_DIR "beta_vs_btc.json"),
        [string] $MatrixPath = (Join-Path $global:JOURNAL_DIR "correlation_matrix.json")
    )
    if ($Market -eq "BTCUSDT") { return 1.0 }
    # Primario: cache de beta calculado off-line
    if (Test-Path $BetaPath) {
        try {
            $bm = Get-Content $BetaPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($bm.beta -and $bm.beta.PSObject.Properties[$Market]) {
                return [double]$bm.beta.$Market
            }
        } catch {}
    }
    # Fallback: corr cruzada como proxy (under-estima magnitude de high-vol)
    if (Test-Path $MatrixPath) {
        try {
            $mat = Get-Content $MatrixPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($mat.matrix -and $mat.matrix.PSObject.Properties[$Market]) {
                $row = $mat.matrix.$Market
                if ($row.PSObject.Properties['BTCUSDT'] -and $null -ne $row.BTCUSDT) {
                    return [double]$row.BTCUSDT
                }
            }
        } catch {}
    }
    # Unknown: assume beta=1 (BTC-correlated default, conservador no sentido de "max risk")
    return 1.0
}


function Test-BetaConcentration {
    # Soma |beta_X * weight_X| em todas posicoes Tier A LIVE atuais + posicao proposta.
    # Cap default 6.5 (SOFT grandfather: aceita estado atual ~6.36 de 5 amplifiers
    # historicos; novos promotes que levem >6.5 sao bloqueados).
    # Roadmap: reduzir cap gradualmente conforme amplifiers naturalmente demoted.
    # 2026-05-19 PM: gate criado apos descoberta que ZEC/INJ/CFG/RENDER sao todos
    # beta>1.2; exposure portfolio efetiva = 6.36x BTC sem nenhum gate atual capturar.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter()] [string[]] $CurrentTierAMarkets = @(),
        [Parameter()] [hashtable] $Weights = $null,  # opt: $Weights["INJUSDT"]=1.0 etc.
        [double] $MaxAbsBetaSum = 17.0,    # legacy fallback; AVG primary
        [double] $WarnAbsBetaSum = 13.6,   # legacy fallback
        # 2026-05-20 V1.6 recalibragem: distribution analysis (45 markets) revelou
        # median = 0.00 (uncorrelated), high_normal 1.0-1.3 = 22%. Cap 1.0 era too strict.
        # Novo: 1.2 BLOCK + 1.0 WARN alinhado com realidade crypto.
        [double] $MaxAvgBeta = 1.2,        # PRIMARY gate: portfolio amplifica ate +20% (limit razoavel)
        [double] $WarnAvgBeta = 1.0,       # WARN se portfolio ja amplifica BTC
        # 2026-05-23 Tier 1 v9 wire: opt-in per-phase caps. Caller passa $Phase + flag.
        # Backward compat: vazio = usa MaxAvgBeta/WarnAvgBeta padroes (atual prod).
        # Quando $Phase fornecido AND env BETA_CAP_PER_PHASE_ENABLED=1, lookup dynamic cap.
        [string] $Phase = "",
        [string] $BetaPath = (Join-Path $global:JOURNAL_DIR "beta_vs_btc.json"),
        [string] $MatrixPath = (Join-Path $global:JOURNAL_DIR "correlation_matrix.json")
    )
    # Per-phase cap dynamic (opt-in, flag-gated pra rollback fast)
    if ($Phase -and $env:BETA_CAP_PER_PHASE_ENABLED -eq "1") {
        if (Get-Command Get-BetaCapForPhase -ErrorAction SilentlyContinue) {
            try {
                $dynCap = Get-BetaCapForPhase -Phase $Phase
                $MaxAvgBeta = [double]$dynCap.block
                $WarnAvgBeta = [double]$dynCap.warn
            } catch {}
        }
    }
    # Weights default: 1.0 por market (sizing igual). User pode passar pesos reais.
    $betaSum = 0.0
    $details = @()
    $allMarkets = @($CurrentTierAMarkets)
    if ($Market -notin $allMarkets) { $allMarkets = $allMarkets + @($Market) }
    foreach ($m in $allMarkets) {
        $b = Get-BetaFromMatrix -Market $m -BetaPath $BetaPath -MatrixPath $MatrixPath
        $w = if ($Weights -and $Weights.ContainsKey($m)) { [double]$Weights[$m] } else { 1.0 }
        $contribution = [Math]::Abs($b) * $w
        $betaSum += $contribution
        $details += [PSCustomObject]@{ market = $m; beta = [Math]::Round($b, 3); weight = $w; abs_contribution = [Math]::Round($contribution, 3) }
    }
    $betaSum = [Math]::Round($betaSum, 2)
    $nPositions = $allMarkets.Count
    $betaAvg = if ($nPositions -gt 0) { [Math]::Round($betaSum / $nPositions, 3) } else { 0 }
    # 2026-05-19 PM: migrado de SUM-only -> AVG primary (escalavel pra 17 markets).
    # SUM mantido pra audit mas DECISAO via AVG (scale-invariant).
    # AVG = portfolio effective beta vs BTC. Cap 1.0 = portfolio nao amplifica BTC.
    $passes = $betaAvg -le $MaxAvgBeta
    $warning = ($betaAvg -gt $WarnAvgBeta) -and $passes
    $level = if (-not $passes) { "BLOCK" } elseif ($warning) { "WARN" } else { "OK" }
    return [PSCustomObject]@{
        passes         = $passes
        beta_avg       = $betaAvg
        beta_sum       = $betaSum
        n_positions    = $nPositions
        max_avg        = $MaxAvgBeta
        warn_avg       = $WarnAvgBeta
        max_sum        = $MaxAbsBetaSum
        warn_sum       = $WarnAbsBetaSum
        level          = $level
        candidate      = $Market
        candidate_beta = (Get-BetaFromMatrix -Market $Market -BetaPath $BetaPath -MatrixPath $MatrixPath)
        positions      = $details
        reason         = if ($passes) { if ($warning) { "warn_avg_above_$WarnAvgBeta" } else { "ok" } } else { "beta_avg_exceeded" }
        note           = "AVG primary (scalable); avg cap $MaxAvgBeta warn $WarnAvgBeta; legacy sum cap $MaxAbsBetaSum"
    }
}


function Get-CapitalScaledDailyLossThreshold {
    # 2026-05-19 PM (vulnerability #7): daily loss cap escala com capital.
    # Capital pequeno = sistema fragil + impacto psicologico maior por perda %.
    # Tier1: <$5K = -2% (conservador, protege fase fragil)
    # Tier2: $5K-$10K = -3% (intermediario)
    # Tier3: >=$10K = -5% (default antigo, sistema robusto)
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double] $CapitalUsd,
        [double] $Tier1Cap = 5000.0,
        [double] $Tier2Cap = 10000.0,
        [double] $Tier1Threshold = -2.0,
        [double] $Tier2Threshold = -3.0,
        [double] $Tier3Threshold = -5.0
    )
    if ($CapitalUsd -lt $Tier1Cap) { return $Tier1Threshold }
    if ($CapitalUsd -lt $Tier2Cap) { return $Tier2Threshold }
    return $Tier3Threshold
}


function Test-DailyLossCircuit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double] $EquityTodayPct,
        [double] $ThresholdPct = -5.0,
        # B17 fix 2026-05-20 PM6+400min: fail-closed quando state corrompido.
        # Antes: corrupt JSON -> delta=0 -> passes=true (CB silently desabilitado).
        # Agora: caller passa $StateCorrupt -> BLOCK explicito.
        [switch] $StateCorrupt
    )
    if ($StateCorrupt) {
        return [PSCustomObject]@{
            passes    = $false
            equity_pct = $EquityTodayPct
            threshold = $ThresholdPct
            reason    = "state_corrupt_fail_closed_block"
        }
    }
    # ThresholdPct deve ser negativo (-5 = stop em -5%). passa SE equity > threshold (i.e., perda menor que threshold).
    $passes = $EquityTodayPct -gt $ThresholdPct
    return [PSCustomObject]@{
        passes    = $passes
        equity_pct = $EquityTodayPct
        threshold = $ThresholdPct
        reason    = if ($passes) { "ok" } else { "daily_loss_circuit_triggered" }
    }
}


function Get-SectorOf {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [string] $SectorMapPath = $script:SECTOR_MAP_DEFAULT_PATH
    )
    if (-not (Test-Path $SectorMapPath)) { return "unknown" }
    try {
        $map = Get-Content $SectorMapPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($map.markets.PSObject.Properties[$Market]) {
            return [string]$map.markets.$Market
        }
    } catch {}
    return "unknown"
}


function Test-SectorConcentration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter()] [string[]] $CurrentTierAMarkets = @(),
        [string] $SectorMapPath = $script:SECTOR_MAP_DEFAULT_PATH,
        [int] $MaxPerSector = 2
    )
    $sector = Get-SectorOf -Market $Market -SectorMapPath $SectorMapPath
    if ($sector -eq "unknown") {
        return [PSCustomObject]@{
            passes  = $true
            sector  = "unknown"
            count   = 0
            max     = $MaxPerSector
            reason  = "sector_unknown_pass"
        }
    }
    # Conta quantos current Tier A markets ja sao do mesmo setor
    $count = 0
    foreach ($m in $CurrentTierAMarkets) {
        if ((Get-SectorOf -Market $m -SectorMapPath $SectorMapPath) -eq $sector) {
            $count++
        }
    }
    $passes = $count -lt $MaxPerSector
    return [PSCustomObject]@{
        passes = $passes
        sector = $sector
        count  = $count
        max    = $MaxPerSector
        reason = if ($passes) { "ok" } else { "sector_concentration_exceeded" }
    }
}


function Add-DemoteEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter()] [string] $Reason = "manual",
        [string] $DemoteHistoryPath = $script:DEMOTE_HISTORY_DEFAULT_PATH
    )
    $dir = Split-Path $DemoteHistoryPath
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $event = @{
        market     = $Market
        demoted_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        reason     = $Reason
    }
    $json = $event | ConvertTo-Json -Compress
    Add-Content -Path $DemoteHistoryPath -Value $json -Encoding UTF8
}


function Test-CooldownPostDemote {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [string] $DemoteHistoryPath = $script:DEMOTE_HISTORY_DEFAULT_PATH,
        [int] $CooldownDays = 30
    )
    if (-not (Test-Path $DemoteHistoryPath)) {
        return [PSCustomObject]@{ passes = $true; reason = "no_history" }
    }
    $events = Get-Content $DemoteHistoryPath -Encoding UTF8 -ErrorAction SilentlyContinue
    $latestDemote = $null
    foreach ($line in $events) {
        if (-not $line) { continue }
        try {
            $o = $line | ConvertFrom-Json
            if ($o.market -eq $Market) {
                $ts = [DateTime]::ParseExact($o.demoted_at, "yyyy-MM-ddTHH:mm:ssZ", $null).ToUniversalTime()
                if ($null -eq $latestDemote -or $ts -gt $latestDemote) { $latestDemote = $ts }
            }
        } catch {}
    }
    if ($null -eq $latestDemote) {
        return [PSCustomObject]@{ passes = $true; reason = "never_demoted" }
    }
    $daysSince = ((Get-Date).ToUniversalTime() - $latestDemote).TotalDays
    $passes = $daysSince -ge $CooldownDays
    return [PSCustomObject]@{
        passes         = $passes
        days_since     = [Math]::Round($daysSince, 1)
        cooldown_days  = $CooldownDays
        latest_demote  = $latestDemote.ToString("yyyy-MM-dd")
        reason         = if ($passes) { "cooldown_expired" } else { "cooldown_active" }
    }
}


function Test-MinVolumeGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double] $VolumeUsd,
        [double] $MinVolumeUsd = 500000
    )
    $passes = $VolumeUsd -ge $MinVolumeUsd
    return [PSCustomObject]@{
        passes = $passes
        volume = $VolumeUsd
        min    = $MinVolumeUsd
        reason = if ($passes) { "ok" } else { "volume_below_minimum" }
    }
}


function Test-PhaseBoundarySafety {
    [CmdletBinding()]
    param(
        [Parameter()] [AllowNull()] $PhaseChangedAt,
        [int] $SafetyDays = 7
    )
    if ($null -eq $PhaseChangedAt) {
        return [PSCustomObject]@{ passes = $true; reason = "no_phase_history" }
    }
    $changeDate = if ($PhaseChangedAt -is [DateTime]) { $PhaseChangedAt } else { [DateTime]::Parse([string]$PhaseChangedAt) }
    $daysSince = ((Get-Date) - $changeDate).TotalDays
    $passes = $daysSince -ge $SafetyDays
    return [PSCustomObject]@{
        passes      = $passes
        days_since  = [Math]::Round($daysSince, 1)
        safety_days = $SafetyDays
        reason      = if ($passes) { "safety_period_passed" } else { "phase_boundary_active" }
    }
}


function Test-TimeOfWeekGate {
    # Sexta historica = saida de risk. Bloqueia novas posicoes LONG sexta tarde.
    # Ref: knowledge/MARKET_TIMING_BRT.md + project_dow_seasonality
    [CmdletBinding()]
    param(
        [Parameter()] [datetime] $DateBrt = (Get-Date),
        [Parameter()] [string] $Direction = "long",
        [int[]] $BlockedDays = @(),
        [int] $BlockedHourStart = 14,
        [int] $BlockedHourEnd = 23
    )
    # Default: blocked = Thursday (4) afternoon (historico ruim)
    # Sunday=0, Mon=1, ... Sat=6
    if ($BlockedDays.Count -eq 0) { $BlockedDays = @(4) }  # Thursday
    $dow = [int]$DateBrt.DayOfWeek
    $hr = $DateBrt.Hour
    $isBlockedDay = $BlockedDays -contains $dow
    $isBlockedHour = $hr -ge $BlockedHourStart -and $hr -le $BlockedHourEnd
    $blocked = $isBlockedDay -and $isBlockedHour -and ($Direction -eq "long")
    return [PSCustomObject]@{
        passes       = -not $blocked
        dow          = $DateBrt.DayOfWeek.ToString()
        hour         = $hr
        direction    = $Direction
        reason       = if (-not $blocked) { "ok" } else { "time_of_week_blocked" }
    }
}


function Test-SlippageBudget {
    # Slippage cap: requer vol/position_size >= ratio (default 100x)
    # Ex: posicao $100 em market com vol $10K = ratio 100x = aceitavel
    # Posicao $100 em market com vol $5K = ratio 50x = BLOCK (slippage > 0.2%)
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double] $VolumeUsd24h,
        [Parameter(Mandatory)] [double] $PositionSizeUsd,
        [double] $MinRatio = 100.0
    )
    if ($PositionSizeUsd -le 0) {
        return [PSCustomObject]@{ passes = $false; reason = "invalid_size"; ratio = 0 }
    }
    $ratio = $VolumeUsd24h / $PositionSizeUsd
    $passes = $ratio -ge $MinRatio
    return [PSCustomObject]@{
        passes = $passes
        ratio  = [Math]::Round($ratio, 1)
        min_ratio = $MinRatio
        volume = $VolumeUsd24h
        position_size = $PositionSizeUsd
        estimated_slippage_pct = [Math]::Round(100 / [Math]::Max($ratio, 1), 3)
        reason = if ($passes) { "ok" } else { "slippage_too_high" }
    }
}


function Test-CrossAssetCorrelation {
    # Bloqueia entrada se ja temos posicao em market correlato > threshold.
    # PRIMARIO: le journal/correlation_matrix.json (calculado off-line por
    # backtest/correlation_matrix.py). Bloqueia se MAX(corr(Market, current LONG)) >= threshold.
    # FALLBACK: se matriz ausente, usa proxy 'mesmo setor' (v1).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter()] [string[]] $CurrentLongMarkets = @(),
        [string] $SectorMapPath = $script:SECTOR_MAP_DEFAULT_PATH,
        [string] $MatrixPath = (Join-Path $global:JOURNAL_DIR "correlation_matrix.json"),
        [double] $CorrelationThreshold = 0.8
    )
    # Tentativa via matriz real
    if (Test-Path $MatrixPath) {
        try {
            $mat = Get-Content $MatrixPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($mat.matrix -and $mat.matrix.PSObject.Properties[$Market]) {
                $row = $mat.matrix.$Market
                $maxCorr = 0.0
                $maxPair = $null
                foreach ($m in $CurrentLongMarkets) {
                    if ($row.PSObject.Properties[$m] -and $null -ne $row.$m) {
                        $c = [double]$row.$m
                        if ($c -ge $maxCorr) { $maxCorr = $c; $maxPair = $m }
                    }
                }
                $passes = $maxCorr -lt $CorrelationThreshold
                return [PSCustomObject]@{
                    passes        = $passes
                    max_corr      = [Math]::Round($maxCorr, 3)
                    max_corr_pair = $maxPair
                    threshold     = $CorrelationThreshold
                    reason        = if ($passes) { "ok" } else { "correlated_position_active" }
                    note          = "matrix_window_${($mat.window_days)}d"
                }
            }
        } catch {
            # cai pro proxy de setor
        }
    }
    # FALLBACK proxy v1: mesmo setor = correlacao alta
    $sector = Get-SectorOf -Market $Market -SectorMapPath $SectorMapPath
    if ($sector -eq "unknown") {
        return [PSCustomObject]@{ passes = $true; reason = "sector_unknown" }
    }
    $sameSectorCount = 0
    foreach ($m in $CurrentLongMarkets) {
        if ((Get-SectorOf -Market $m -SectorMapPath $SectorMapPath) -eq $sector) {
            $sameSectorCount++
        }
    }
    $passes = $sameSectorCount -eq 0
    return [PSCustomObject]@{
        passes = $passes
        sector = $sector
        same_sector_long_count = $sameSectorCount
        threshold = $CorrelationThreshold
        reason = if ($passes) { "ok" } else { "correlated_position_active" }
        note = "v1_proxy_sector_based"
    }
}


function Get-FundingZScore {
    # Le journal/funding_history/<SYMBOL>.jsonl e retorna z-score atual.
    # Fallback rapido: se Python disponivel, delega a backtest/funding_zscore.py
    # (logica mais robusta, ja testada). Senao, compute inline.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [int] $BaselineDays = 90,
        [string] $HistoryDir = (Join-Path $global:JOURNAL_DIR "funding_history")
    )
    $file = Join-Path $HistoryDir "$Market.jsonl"
    if (-not (Test-Path $file)) {
        return [PSCustomObject]@{ z = $null; reason = "no_history"; n = 0 }
    }
    try {
        $rows = @()
        foreach ($line in Get-Content $file -Encoding UTF8) {
            if (-not $line) { continue }
            try { $rows += ($line | ConvertFrom-Json) } catch {}
        }
        if ($rows.Count -eq 0) {
            return [PSCustomObject]@{ z = $null; reason = "empty"; n = 0 }
        }
        $sorted = $rows | Sort-Object funding_time
        $lastTs = [long]$sorted[-1].funding_time
        $cutoff = $lastTs - ([long]$BaselineDays * 86400000)
        $baseline = @($sorted | Where-Object { [long]$_.funding_time -ge $cutoff } | ForEach-Object { [double]$_.funding_rate })
        if ($baseline.Count -lt 10) {
            return [PSCustomObject]@{ z = $null; reason = "insufficient_baseline"; n = $baseline.Count }
        }
        $current = [double]$sorted[-1].funding_rate
        $mean = ($baseline | Measure-Object -Average).Average
        $sumSq = 0.0
        foreach ($v in $baseline) { $sumSq += [Math]::Pow($v - $mean, 2) }
        $std = [Math]::Sqrt($sumSq / $baseline.Count)
        $z = if ($std -eq 0) { 0.0 } else { ($current - $mean) / $std }
        return [PSCustomObject]@{
            z       = [Math]::Round($z, 3)
            current = $current
            mean    = $mean
            std     = $std
            n       = $baseline.Count
            reason  = "ok"
        }
    } catch {
        return [PSCustomObject]@{ z = $null; reason = "parse_error"; error = "$_"; n = 0 }
    }
}


function Test-FundingRateGate {
    # Aceita FundingZScore explicito (calculado externamente) OU resolve via Get-FundingZScore
    # quando -Market eh passado. Se historico ausente, retorna pass com note='no_baseline'.
    [CmdletBinding()]
    param(
        [Parameter()] [AllowNull()] [System.Nullable[double]] $FundingZScore = $null,
        [Parameter()] [string] $Market = $null,
        [Parameter()] [string] $Direction = "long",
        [double] $MaxZForLong = 2.0,
        [double] $MaxZForShort = -2.0
    )
    # Se nao passou z explicito, tenta resolver via cache
    if ($null -eq $FundingZScore -and $Market) {
        $resolved = Get-FundingZScore -Market $Market
        if ($null -eq $resolved.z) {
            return [PSCustomObject]@{
                passes    = $true
                funding_z = $null
                direction = $Direction
                reason    = "no_baseline"
                note      = "funding_history ausente para ${Market}: $($resolved.reason)"
            }
        }
        $FundingZScore = [double]$resolved.z
    }
    if ($null -eq $FundingZScore) {
        return [PSCustomObject]@{
            passes    = $true
            funding_z = $null
            direction = $Direction
            reason    = "no_input"
        }
    }
    if ($Direction -eq "long") {
        $passes = $FundingZScore -lt $MaxZForLong
        $reason = if ($passes) { "ok" } else { "funding_overheated_long" }
    } else {
        $passes = $FundingZScore -gt $MaxZForShort
        $reason = if ($passes) { "ok" } else { "funding_overcold_short" }
    }
    return [PSCustomObject]@{
        passes        = $passes
        funding_z     = $FundingZScore
        direction     = $Direction
        reason        = $reason
        note          = "requires_binance_funding_history_baseline"
    }
}


function Invoke-AllGates {
    # Aplica todos os gates em sequencia. Retorna lista de results + summary.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter()] [double] $VolumeUsd = 0,
        [Parameter()] [int] $CurrentTierACount = 0,
        [Parameter()] [string[]] $CurrentTierAMarkets = @(),
        [Parameter()] [double] $EquityTodayPct = 0,
        [Parameter()] [AllowNull()] $PhaseChangedAt = $null,
        [int] $MaxTierA = 5,
        [int] $MaxPerSector = 2,
        [int] $CooldownDays = 30,
        [int] $SafetyDays = 7,
        [double] $MinVolumeUsd = 500000,
        [double] $DailyLossThreshold = -5.0,
        # 2026-05-19 PM: FQS gate opt-in via TargetTier; sem TargetTier nao aplica
        [string] $TargetTier = "",
        [string] $FundamentalRegistryPath = "",
        # 2026-05-20: 4 orphan gates wired opt-in. Sem params -> gate skip (back-compat).
        [Nullable[double]] $CurrentPrice = $null,
        [Nullable[double]] $Peak7d = $null,
        [Nullable[datetime]] $DateBrt = $null,
        [string] $Direction = "long",
        [Nullable[double]] $PositionSizeUsd = $null,
        [string[]] $CurrentLongMarkets = @(),
        # B7 fix 2026-05-20 PM6: registrar cada gate eval em DSR multi-test penalty.
        # Antes do fix: dsr_global.json so via Add-DsrTrial em obs_to_c/c_to_b/b_to_a (3 gates).
        # Outros 9 gates (concentration/daily_loss/sector/cooldown/...) ficavam fora -> Bonferroni torta.
        [string] $DsrPath = "",
        # B23 fix 2026-05-20 PM6+520min: anti-overfitting gates.
        # Sharpe > 5 = red flag (PENDLE 8.75 + CFG 8.48 ambos demoted). mom_20d > 25% = chase trap.
        [Nullable[double]] $Sharpe = $null,
        [Nullable[double]] $Mom20dPct = $null,
        # C4 fix 2026-05-21: sample size gate (HYPE N=34 -> Sharpe 12.23 empirico).
        [Nullable[int]] $NEntries = $null,
        # 2026-05-23 Tier 1 v9 wire: phase param pra dynamic beta cap (opt-in via env BETA_CAP_PER_PHASE_ENABLED)
        [string] $Phase = ""
    )
    $gates = @{
        concentration    = Test-ConcentrationLimit -CurrentTierACount $CurrentTierACount -MaxTierA $MaxTierA
        daily_loss       = Test-DailyLossCircuit -EquityTodayPct $EquityTodayPct -ThresholdPct $DailyLossThreshold
        sector           = Test-SectorConcentration -Market $Market -CurrentTierAMarkets $CurrentTierAMarkets -MaxPerSector $MaxPerSector
        cooldown         = Test-CooldownPostDemote -Market $Market -CooldownDays $CooldownDays
        min_volume       = Test-MinVolumeGate -VolumeUsd $VolumeUsd -MinVolumeUsd $MinVolumeUsd
        phase_boundary   = Test-PhaseBoundarySafety -PhaseChangedAt $PhaseChangedAt -SafetyDays $SafetyDays
        funding          = Test-FundingRateGate -Market $Market -Direction $Direction
        beta_concentration = Test-BetaConcentration -Market $Market -CurrentTierAMarkets $CurrentTierAMarkets -Phase $Phase
    }
    # 2026-05-20: 4 gates antes orfaos -- wired condicionalmente
    if ($null -ne $CurrentPrice -and $null -ne $Peak7d -and $Peak7d -gt 0) {
        try { $gates["pump_buy"] = Test-PumpBuyGate -CurrentPrice $CurrentPrice -Peak7d $Peak7d } catch {}
    }
    if ($null -ne $DateBrt) {
        try { $gates["time_of_week"] = Test-TimeOfWeekGate -DateBrt $DateBrt -Direction $Direction } catch {}
    }
    if ($null -ne $PositionSizeUsd -and $PositionSizeUsd -gt 0 -and $VolumeUsd -gt 0) {
        try { $gates["slippage"] = Test-SlippageBudget -VolumeUsd24h $VolumeUsd -PositionSizeUsd $PositionSizeUsd } catch {}
    }
    if ($CurrentLongMarkets.Count -gt 0) {
        try { $gates["cross_corr"] = Test-CrossAssetCorrelation -Market $Market -CurrentLongMarkets $CurrentLongMarkets } catch {}
    }
    # B23 anti-overfitting gates (opt-in via Sharpe + Mom20dPct params)
    if ($null -ne $Sharpe -and (Get-Command Test-SharpeCeilingGate -ErrorAction SilentlyContinue)) {
        try { $gates["sharpe_ceiling"] = Test-SharpeCeilingGate -Sharpe ([double]$Sharpe) } catch {}
    }
    if ($null -ne $Mom20dPct -and (Get-Command Test-PumpAfterDiscoveryGate -ErrorAction SilentlyContinue)) {
        try { $gates["pump_after_discovery"] = Test-PumpAfterDiscoveryGate -Mom20dPct ([double]$Mom20dPct) } catch {}
    }
    # C4 fix 2026-05-21: sample size gate (HYPE N=34 empirico)
    if ($null -ne $NEntries -and (Get-Command Test-SampleSizeGate -ErrorAction SilentlyContinue)) {
        try { $gates["sample_size"] = Test-SampleSizeGate -NEntries ([int]$NEntries) } catch {}
    }

    # Fundamental Quality gate (opt-in via TargetTier)
    if ($TargetTier -and (Get-Command Test-FundamentalQualityGate -ErrorAction SilentlyContinue)) {
        try {
            $regPath = if ($FundamentalRegistryPath) { $FundamentalRegistryPath } else { (Join-Path $global:JOURNAL_DIR "coin_registry.json") }
            $fqsPass = Test-FundamentalQualityGate -Market $Market -TargetTier $TargetTier -RegistryPath $regPath
            $fqsDetails = Get-FundamentalScore -Market $Market -RegistryPath $regPath
            $gates["fundamental_quality"] = [PSCustomObject]@{
                passes   = $fqsPass
                fqs      = $fqsDetails.fqs
                category = $fqsDetails.category
                target_tier = $TargetTier
                reason   = if ($fqsPass) { "ok" } else { "fqs_$($fqsDetails.fqs)_below_${TargetTier}_threshold" }
            }
        } catch {
            # Defensive: erro em FQS nao bloqueia outras gates
        }
    }
    $allPass = $true
    $blockedBy = @()
    foreach ($k in $gates.Keys) {
        if (-not $gates[$k].passes) {
            $allPass = $false
            $blockedBy += $k
        }
    }

    # B7 fix 2026-05-20 PM6: registra cada gate eval no DSR registry pra Bonferroni multi-gate.
    if ($DsrPath -and (Get-Command Add-DsrTrial -ErrorAction SilentlyContinue)) {
        foreach ($gateName in $gates.Keys) {
            try { Add-DsrTrial -Path $DsrPath -GateName $gateName -Market $Market | Out-Null } catch {}
        }
    }

    return [PSCustomObject]@{
        market     = $Market
        all_pass   = $allPass
        blocked_by = $blockedBy
        gates      = $gates
    }
}
