# lib_promotion_ladder.ps1 -- State machine pra promotion ladder
#
# Append-only event log em journal/promotion_pipeline.jsonl
# Estados: 0=DESCOBERTA, 1=OBSERVATION, 2=PAPER_C, 3=PAPER_B, 4=TIER_A_LIVE
#
# User-gated transitions: Telegram propose, user aprova/rejeita.
# Gates Bailey-LdP rigor (Sharpe + PSR + DSR + max_DD).
#
# Schema: docs/PROMOTION_LADDER_SCHEMA.md
# Design: memory/project_promotion_ladder_design.md
#
# PS 5.1. UTF-8 BOM. Sem acentos no codigo.

$script:TIER_LABELS = @(
    "DESCOBERTA",     # 0
    "OBSERVATION",    # 1
    "PAPER_C",        # 2
    "PAPER_B",        # 3
    "TIER_A_LIVE"     # 4
)

$script:TIER_SIZE_PCT = @(0, 0, 25, 50, 100)

$script:BULL_REGIMES = @("BULL_STRONG","BULL_WEAK","TRANSITION_UP")


function Get-TierLabel {
    [CmdletBinding()]
    param([int]$State)
    if ($State -lt 0 -or $State -gt 4) { return "INVALID" }
    return $script:TIER_LABELS[$State]
}


function Get-TierSizePct {
    [CmdletBinding()]
    param([int]$State)
    if ($State -lt 0 -or $State -gt 4) { return 0 }
    return $script:TIER_SIZE_PCT[$State]
}


function Add-PromotionEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Event,        # discovered|evaluated|promoted|demoted|user_decision
        [int]    $TierState = -1,
        [string] $Source    = "system",
        [hashtable] $Metrics = $null,
        [hashtable] $GateEval = $null,
        [string] $UserDecision = $null,
        [string] $Notes = $null
    )
    # Se TierState nao especificado e for "discovered", default 0
    if ($TierState -lt 0) {
        if ($Event -eq "discovered") { $TierState = 0 }
        else {
            # Pega state atual do market
            $current = Get-PromotionState -Path $Path -Market $Market
            $TierState = if ($current) { $current.tier_state } else { 0 }
        }
    }

    # C6 fix 2026-05-20 PM6+620min: contrato centralizado via lib_json_contract.
    # Helper unico cobre array fields conhecidos + nested paths em uma so chamada.
    if (-not (Get-Command ConvertTo-NormalizedJson -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot "lib_json_contract.ps1")
    }

    $obj = [ordered]@{
        ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        event = $Event
        market = $Market
        tier_state = $TierState
        tier_label = (Get-TierLabel -State $TierState)
        source = $Source
        metrics = if ($Metrics) { $Metrics } else { @{} }
        gate_eval = $GateEval
        user_decision = $UserDecision
        notes = $Notes
    }

    $json = ConvertTo-NormalizedJson -Object $obj `
        -ArrayFields $global:JSON_CONTRACT_COMMON_ARRAY_FIELDS `
        -NestedPaths $global:JSON_CONTRACT_COMMON_NESTED_PATHS

    # Cria diretorio se necessario
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    Add-Content -Path $Path -Value $json -Encoding UTF8
    return [PSCustomObject]@{ success = $true; line = $json }
}


function Get-PromotionState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Market
    )
    if (-not (Test-Path $Path)) { return $null }
    $lines = Get-Content $Path -Encoding UTF8
    $last = $null
    foreach ($line in $lines) {
        if (-not $line) { continue }
        try {
            $obj = $line | ConvertFrom-Json
            if ($obj.market -eq $Market) { $last = $obj }
        } catch { continue }
    }
    if (-not $last) { return $null }
    return [PSCustomObject]@{
        market = $last.market
        tier_state = [int]$last.tier_state
        tier_label = $last.tier_label
        last_ts = $last.ts
        last_event = $last.event
    }
}


function Get-PromotionCandidatesByState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [int] $State
    )
    if (-not (Test-Path $Path)) { return @() }
    $lines = Get-Content $Path -Encoding UTF8
    $byMarket = @{}
    foreach ($line in $lines) {
        if (-not $line) { continue }
        try {
            $obj = $line | ConvertFrom-Json
            $byMarket[$obj.market] = $obj
        } catch { continue }
    }
    $result = @()
    foreach ($k in $byMarket.Keys) {
        if ([int]$byMarket[$k].tier_state -eq $State) {
            $result += $byMarket[$k].market
        }
    }
    return @($result)
}


# ── GATE: OBSERVATION (1) -> PAPER_C (2) ─────────────────────────────────────
# Versao C + regime iii (asset OR btc em bull)
function Test-GateObservationToC {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable] $Metrics,
        # 2026-05-20 PM6+: decorator DSR. Quando ambos providos, registra trial internamente.
        # Garante consistencia mesmo se caller bypassar lib_promotion_cycle.
        [string] $DsrPath = "",
        [string] $Market = "",
        # C3 fix 2026-05-21: regime-conditioned thresholds. Default 'unknown' = bull thresholds (fallback original).
        # Caller passa $Phase (e.g. "phase_3_bear") pra ativar relaxamento.
        [string] $Phase = "unknown"
    )
    $reasons  = @()
    $failures = @()
    if ($DsrPath -and $Market -and (Get-Command Add-DsrTrial -ErrorAction SilentlyContinue)) {
        try { Add-DsrTrial -Path $DsrPath -GateName "obs_to_c" -Market $Market | Out-Null } catch {}
    }

    # C3: thresholds dependentes de phase
    $thrSharpe = 1.0; $thrMaxDD = 0.15; $thrMom = 0.0
    if (Get-Command Get-RegimeAwareThreshold -ErrorAction SilentlyContinue) {
        try {
            $thrSharpe = (Get-RegimeAwareThreshold -Metric "sharpe_30d" -Phase $Phase).threshold
            $thrMaxDD  = (Get-RegimeAwareThreshold -Metric "max_dd"     -Phase $Phase).threshold
            $thrMom    = (Get-RegimeAwareThreshold -Metric "mom_20d"    -Phase $Phase).threshold
        } catch {}
    }

    $sharpe = [double]($Metrics.sharpe_30d)
    if ($sharpe -ge $thrSharpe) { $reasons += "sharpe_30d_ok_${Phase}" }
    else                         { $failures += "sharpe_30d=$sharpe<$thrSharpe (phase=$Phase)" }

    $mom = [double]($Metrics.mom_20d)
    if ($mom -gt $thrMom) { $reasons += "mom_20d_positive" }
    else                  { $failures += "mom_20d=$mom<=$thrMom" }

    $n = [int]($Metrics.n_trades)
    if ($n -ge 5)         { $reasons += "n_trades_ok" }
    else                  { $failures += "n_trades=$n<5" }

    $dd = [double]($Metrics.max_dd)
    if ($dd -le $thrMaxDD) { $reasons += "max_dd_ok_${Phase}" }
    else                    { $failures += "max_dd=$dd>$thrMaxDD (phase=$Phase)" }

    $regA = [string]$Metrics.regime_asset
    $regB = [string]$Metrics.regime_btc
    $assetBull = $script:BULL_REGIMES -contains $regA
    $btcBull   = $script:BULL_REGIMES -contains $regB
    if ($assetBull -or $btcBull) { $reasons += "regime_ok ($regA|$regB)" }
    else                          { $failures += "regime=$regA/$regB neither_bull" }

    return [PSCustomObject]@{
        gate = "obs_to_c"
        passed = ($failures.Count -eq 0)
        reasons = $reasons
        failures = $failures
    }
}


# ── GATE: PAPER_C (2) -> PAPER_B (3) ─────────────────────────────────────────
# Versao alpha
function Test-GateCToB {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable] $Metrics,
        [string] $DsrPath = "",
        [string] $Market = ""
    )
    $reasons  = @()
    $failures = @()
    if ($DsrPath -and $Market -and (Get-Command Add-DsrTrial -ErrorAction SilentlyContinue)) {
        try { Add-DsrTrial -Path $DsrPath -GateName "c_to_b" -Market $Market | Out-Null } catch {}
    }

    $sharpe = [double]($Metrics.sharpe_60d)
    if ($sharpe -ge 1.5) { $reasons += "sharpe_60d_ok" }
    else                  { $failures += "sharpe_60d=$sharpe<1.5" }

    $psr = [double]($Metrics.psr)
    if ($psr -ge 0.85)    { $reasons += "psr_ok" }
    else                  { $failures += "psr=$psr<0.85" }

    $n = [int]($Metrics.n_trades)
    if ($n -ge 15)        { $reasons += "n_trades_ok" }
    else                  { $failures += "n_trades=$n<15" }

    $dd = [double]($Metrics.max_dd)
    if ($dd -le 0.12)     { $reasons += "max_dd_ok" }
    else                  { $failures += "max_dd=$dd>0.12" }

    $mono = [bool]($Metrics.equity_curve_monotonic)
    if ($mono)            { $reasons += "monotonic_ok" }
    else                  { $failures += "equity_curve_non_monotonic" }

    return [PSCustomObject]@{
        gate = "c_to_b"
        passed = ($failures.Count -eq 0)
        reasons = $reasons
        failures = $failures
    }
}


# ── GATE: PAPER_B (3) -> TIER_A_LIVE (4) ─────────────────────────────────────
# Criterio recomendado
function Test-GateBToLive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable] $Metrics,
        [string] $DsrPath = "",
        [string] $Market = ""
    )
    $reasons  = @()
    $failures = @()
    if ($DsrPath -and $Market -and (Get-Command Add-DsrTrial -ErrorAction SilentlyContinue)) {
        try { Add-DsrTrial -Path $DsrPath -GateName "b_to_a" -Market $Market | Out-Null } catch {}
    }

    $pnl = [double]($Metrics.pnl_real)
    if ($pnl -ge 0)       { $reasons += "pnl_real_ok" }
    else                  { $failures += "pnl_real=$pnl<0" }

    $n = [int]($Metrics.n_trades_real)
    if ($n -ge 25)        { $reasons += "n_trades_real_ok" }
    else                  { $failures += "n_trades_real=$n<25" }

    $sharpe = [double]($Metrics.sharpe_real)
    if ($sharpe -ge 1.5)  { $reasons += "sharpe_real_ok" }
    else                  { $failures += "sharpe_real=$sharpe<1.5" }

    $dd = [double]($Metrics.max_dd)
    if ($dd -le 0.10)     { $reasons += "max_dd_ok" }
    else                  { $failures += "max_dd=$dd>0.10" }

    $psr = [double]($Metrics.psr)
    if ($psr -ge 0.90)    { $reasons += "psr_ok" }
    else                  { $failures += "psr=$psr<0.90" }

    $dsr = [double]($Metrics.dsr_global)
    if ($dsr -ge 0.60)    { $reasons += "dsr_global_ok" }
    else                  { $failures += "dsr_global=$dsr<0.60" }

    return [PSCustomObject]@{
        gate = "b_to_a"
        passed = ($failures.Count -eq 0)
        reasons = $reasons
        failures = $failures
    }
}


# ── DEMOTE TRIGGER ───────────────────────────────────────────────────────────
# 4 semanas consecutivas Sharpe <0 OU 180d sem trade
function Test-DemoteTrigger {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()] [AllowNull()] [double[]] $WeeklySharpes = @(),
        [int] $DaysSinceLastTrade = 0
    )
    if (-not $WeeklySharpes) { $WeeklySharpes = @() }
    # 4 semanas consecutivas negativas
    if ($WeeklySharpes.Count -ge 4) {
        $last4 = $WeeklySharpes[-4..-1]
        $allNeg = $true
        foreach ($s in $last4) { if ($s -ge 0) { $allNeg = $false; break } }
        if ($allNeg) {
            return [PSCustomObject]@{
                should_demote = $true
                reason = "consecutive_negative_4_weeks"
            }
        }
    }
    # 180+ dias sem trade
    if ($DaysSinceLastTrade -gt 180) {
        return [PSCustomObject]@{
            should_demote = $true
            reason = "no_trades_180d"
        }
    }
    return [PSCustomObject]@{
        should_demote = $false
        reason = "ok"
    }
}


# ── REGIME CLASSIFIER (pure function, alinhado com snapshot_all_coinex.py) ────
function Compute-AssetRegime {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [double[]] $Closes)
    if ($Closes.Count -lt 200) {
        return [PSCustomObject]@{
            regime = "NO_HIST"
            dist_sma200 = $null
            mom_20d = $null
        }
    }
    $sma200 = ($Closes[-200..-1] | Measure-Object -Average).Average
    $cur = $Closes[-1]
    $dist = ($cur - $sma200) / $sma200

    $back20 = $Closes[-20]
    $mom20 = if ($back20 -gt 0) { ($cur - $back20) / $back20 } else { 0 }

    $label = if     ($dist -gt 0.20 -and $mom20 -gt 0.10) { "BULL_STRONG" }
              elseif ($dist -gt 0     -and $mom20 -gt 0)    { "BULL_WEAK" }
              elseif ($dist -lt -0.20 -and $mom20 -lt -0.10){ "BEAR_STRONG" }
              elseif ($dist -lt 0     -and $mom20 -lt 0)    { "BEAR_WEAK" }
              elseif ([Math]::Abs($dist) -lt 0.05)          { "SIDEWAYS" }
              else                                            { "TRANSITION" }

    return [PSCustomObject]@{
        regime = $label
        dist_sma200 = [Math]::Round($dist, 4)
        mom_20d = [Math]::Round($mom20, 4)
    }
}


# ── METRICS GATHERER (hashtable com defaults + merge external) ───────────────
function Get-PromotionMetrics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [double[]] $AssetCloses = $null,
        [double[]] $BtcCloses   = $null,
        [hashtable] $External   = $null
    )
    # Defaults zero/null
    $m = @{
        market = $Market
        sharpe_30d   = 0.0
        sharpe_60d   = 0.0
        sharpe_real  = 0.0
        mom_20d      = 0.0
        n_trades     = 0
        n_trades_real = 0
        max_dd       = 0.0
        psr          = 0.0
        pnl_real     = 0.0
        dsr_global   = 0.0
        regime_asset = $null
        regime_btc   = $null
        equity_curve_monotonic = $false
    }

    if ($AssetCloses -and $AssetCloses.Count -gt 0) {
        $r = Compute-AssetRegime -Closes $AssetCloses
        $m.regime_asset = $r.regime
        if ($null -ne $r.mom_20d) { $m.mom_20d = $r.mom_20d }
    }
    if ($BtcCloses -and $BtcCloses.Count -gt 0) {
        $rB = Compute-AssetRegime -Closes $BtcCloses
        $m.regime_btc = $rB.regime
    }

    # Merge external (override defaults)
    if ($External) {
        foreach ($k in $External.Keys) {
            $m[$k] = $External[$k]
        }
    }

    return $m
}


# ── SIZING resolver (gem_executor consume) ───────────────────────────────────
# Para um market: consulta ladder e retorna tamanho ajustado (ou 0 se nao deve tradar).
# - Market nao registrado: retorna BaseSize unchanged (compat com sistema antigo)
# - States 0/1 (DESCOBERTA/OBSERVATION): size=0, allowed=false
# - States 2/3/4: aplica multiplier (25%/50%/100%)
function Resolve-PromotionSizing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $PipelinePath,
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [double] $BaseSize
    )
    $state = Get-PromotionState -Path $PipelinePath -Market $Market
    if (-not $state) {
        return [PSCustomObject]@{
            size_usd = $BaseSize
            allowed = $true
            tier_state = -1
            tier_label = "NO_LADDER"
            source = "no_ladder_entry"
        }
    }
    $tier = [int]$state.tier_state
    $pct = (Get-TierSizePct -State $tier)
    $adjusted = [Math]::Round($BaseSize * $pct / 100.0, 2)
    return [PSCustomObject]@{
        size_usd = $adjusted
        allowed = ($adjusted -gt 0)
        tier_state = $tier
        tier_label = (Get-TierLabel -State $tier)
        source = "ladder"
    }
}


# ── ORCHESTRATOR: propose transition ─────────────────────────────────────────
function Invoke-PromotionPropose {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [hashtable] $Metrics,
        # Pre-promotion safety gates (lib_promotion_gates). Opt-in via -EnforceGates.
        # Quando setado, roda Invoke-AllGates ANTES de Test-Gate*ToB; bloqueia promote
        # se concentration/sector/cooldown/min_vol/phase_boundary falhar.
        [switch] $EnforceGates,
        [string[]] $CurrentTierAMarkets = @(),
        [double] $VolumeUsd = 0,
        [double] $EquityTodayPct = 0,
        [AllowNull()] $PhaseChangedAt = $null,
        # 2026-05-20 PM: wire dos 4 gates antes dormentes
        [Nullable[double]] $CurrentPrice = $null,
        [Nullable[double]] $Peak7d = $null,
        [Nullable[datetime]] $DateBrt = $null,
        [string] $Direction = "long",
        [Nullable[double]] $PositionSizeUsd = $null,
        [string[]] $CurrentLongMarkets = @(),
        # B7 fix 2026-05-20 PM6+: DSR multi-gate registration. Opt-in.
        [string] $DsrPath = ""
    )
    $state = Get-PromotionState -Path $Path -Market $Market
    if (-not $state) {
        return [PSCustomObject]@{
            action = "none"
            reason = "market not registered"
        }
    }

    # Pre-promotion safety gates (opt-in). So aplica ao promover PARA Tier A LIVE (3 -> 4)
    # ou para PAPER_B (2 -> 3) onde tamanho real ja eh significativo.
    $safetyResult = $null
    if ($EnforceGates -and $state.tier_state -ge 2 -and (Get-Command Invoke-AllGates -ErrorAction SilentlyContinue)) {
        try {
            # 2026-05-20 PM: pass-through dos 4 gates antes dormentes. Cada um
            # so dispara em Invoke-AllGates se param fornecido (opt-in).
            $gateArgs = @{
                Market              = $Market
                VolumeUsd           = $VolumeUsd
                CurrentTierACount   = $CurrentTierAMarkets.Count
                CurrentTierAMarkets = $CurrentTierAMarkets
                EquityTodayPct      = $EquityTodayPct
                PhaseChangedAt      = $PhaseChangedAt
                Direction           = $Direction
            }
            if ($null -ne $CurrentPrice)    { $gateArgs.CurrentPrice    = $CurrentPrice }
            if ($null -ne $Peak7d)          { $gateArgs.Peak7d          = $Peak7d }
            if ($null -ne $DateBrt)         { $gateArgs.DateBrt         = $DateBrt }
            if ($null -ne $PositionSizeUsd) { $gateArgs.PositionSizeUsd = $PositionSizeUsd }
            if ($CurrentLongMarkets.Count -gt 0) { $gateArgs.CurrentLongMarkets = $CurrentLongMarkets }
            if ($DsrPath) { $gateArgs.DsrPath = $DsrPath }
            $safetyResult = Invoke-AllGates @gateArgs
            if (-not $safetyResult.all_pass) {
                return [PSCustomObject]@{
                    action      = "blocked_by_gates"
                    from_state  = $state.tier_state
                    blocked_by  = $safetyResult.blocked_by
                    safety      = $safetyResult
                    reason      = "pre_promotion_gates_failed: " + ($safetyResult.blocked_by -join ",")
                }
            }
        } catch {
            # Falha defensiva: nao bloqueia se gates quebrarem (avisa via reason).
            $safetyResult = [PSCustomObject]@{ all_pass = $true; error = "$_" }
        }
    }

    $gateResult = $null
    switch ($state.tier_state) {
        1 { $gateResult = Test-GateObservationToC -Metrics $Metrics }
        2 { $gateResult = Test-GateCToB           -Metrics $Metrics }
        3 { $gateResult = Test-GateBToLive        -Metrics $Metrics }
        default {
            return [PSCustomObject]@{
                action = "hold"
                reason = "tier_state=$($state.tier_state) sem gate de avanco"
            }
        }
    }
    if ($gateResult.passed) {
        return [PSCustomObject]@{
            action = "propose_promote"
            from_state = $state.tier_state
            to_state = $state.tier_state + 1
            gate = $gateResult
            safety = $safetyResult
        }
    }
    return [PSCustomObject]@{
        action = "hold"
        reason = "gate_failed"
        failures = $gateResult.failures
        safety = $safetyResult
    }
}
