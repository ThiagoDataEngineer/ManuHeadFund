# lib_mesa_relaxed_criteria.ps1 — Relaxar critérios de votação per regime
#
# Problema Histórico (2026-07-07):
#   - TORI exige wick >2% (raro em BEAR_WEAK → sempre NO_CONFIDENCE)
#   - RICARDO exige ADX >20 (raro em range → sempre NO_CONFIDENCE)
#   - Resultado: 1/1/1 split = 12% CAOS, zero consensus
#
# Solução:
#   - Relaxar thresholds em regimes fracos (BEAR_WEAK, TRANSITION_UP)
#   - Apertados em regimes fortes (BULL_STRONG)
#   - Implementar tie-break via ranked voting (Tori > Ricardo > Lopez)
#
# PS 5.1. UTF-8 BOM.

function Get-MesaCriteriaByRegime {
    <#
    .SYNOPSIS
    Retorna thresholds de votação adaptados ao regime de mercado.

    .PARAMETER Regime
    Regime atual (ex: "BEAR_WEAK", "BULL_STRONG", "TRANSITION_UP")

    .OUTPUTS
    @{
        tori_wick_pct_threshold
        tori_volume_decline_required
        ricardo_adx_threshold
        ricardo_macd_required
        consensus_quorum  # "STRICT_3/3" ou "SIMPLE_2/3"
    }
    #>
    [CmdletBinding()]
    param([string] $Regime = "BEAR_WEAK")

    $regimeUpper = $Regime.ToUpper()

    # BEAR_WEAK: critérios fracos (mercado chato)
    if ($regimeUpper -match "BEAR_WEAK") {
        return @{
            tori_wick_pct_threshold = 0.01          # 1% instead of 2% — mais fácil
            tori_volume_decline_required = $false   # relaxar
            ricardo_adx_threshold = 15              # 15 instead of 20
            ricardo_macd_required = $false          # optional
            consensus_quorum = "SIMPLE_2/3"         # maioria simples
            rationale = "bear_weak: relaxar pra nao ficar tudo CAOS"
        }
    }

    # BULL_STRONG: critérios restritivos
    if ($regimeUpper -match "BULL_STRONG") {
        return @{
            tori_wick_pct_threshold = 0.03          # 3% — bem confirmado
            tori_volume_decline_required = $true    # obrigatório
            ricardo_adx_threshold = 25              # 25 — forte trend
            ricardo_macd_required = $true           # obrigatório
            consensus_quorum = "STRICT_3/3"         # precisa 3/3
            rationale = "bull_strong: apertado pra filtrar false signals"
        }
    }

    # TRANSITION_UP: médio (relaxar um pouco)
    if ($regimeUpper -match "TRANSITION_UP") {
        return @{
            tori_wick_pct_threshold = 0.015         # 1.5%
            tori_volume_decline_required = $false   # relaxar
            ricardo_adx_threshold = 18              # 18
            ricardo_macd_required = $false          # optional
            consensus_quorum = "SIMPLE_2/3"         # maioria
            rationale = "transition_up: médio relaxado"
        }
    }

    # Default (fallback)
    return @{
        tori_wick_pct_threshold = 0.02
        tori_volume_decline_required = $true
        ricardo_adx_threshold = 20
        ricardo_macd_required = $false
        consensus_quorum = "SIMPLE_2/3"
        rationale = "default_fallback"
    }
}

function Tori-StructureVoteRegimeAware {
    <#
    .SYNOPSIS
    TORI vote com critérios adaptados ao regime.
    Antes: wick >2% SEMPRE → NO_CONFIDENCE em BEAR_WEAK
    Depois: wick >1% em BEAR_WEAK → YES possível

    .PARAMETER Regime
    Regime atual (ex: "BEAR_WEAK")
    #>
    [CmdletBinding()]
    param(
        [double] $PeakPrice = 0,
        [double] $ClosePrice = 0,
        [double] $LowPrice = 0,
        [double] $WickPct = 0,
        [double] $PeakVolume = 0,
        [double] $CurrentVolume = 0,
        [string] $Regime = "BEAR_WEAK"
    )

    $vote = "NO_CONFIDENCE"
    $score = 0
    $reasons = @()

    # Pegar thresholds por regime
    $criteria = Get-MesaCriteriaByRegime -Regime $Regime
    $wickThreshold = $criteria.tori_wick_pct_threshold
    $volRequired = $criteria.tori_volume_decline_required

    # Critério 1: Wick (relaxado por regime)
    if ($WickPct -ge $wickThreshold) {
        $score += 25
        $reasons += "WICK_REJECTION_$($WickPct.ToString('P1'))_(threshold=$($wickThreshold.ToString('P0')))"
    }

    # Critério 2: Fechou below peak
    if ($ClosePrice -lt $PeakPrice) {
        $score += 25
        $reasons += "CLOSE_BELOW_PEAK"
    }

    # Critério 3: Volume decline (opcional por regime)
    if ($volRequired) {
        if ($PeakVolume -gt $CurrentVolume * 1.1) {  # 10% decline threshold
            $score += 25
            $reasons += "VOLUME_DECLINE"
        }
    } else {
        # Em regimes fracos, volume decline é optional
        if ($PeakVolume -gt $CurrentVolume * 1.2) {  # 20% decline = bom sinal
            $score += 15
            $reasons += "VOLUME_SLIGHT_DECLINE"
        }
    }

    # Critério 4: Pico confirmado
    if ($PeakPrice -gt $ClosePrice * 1.01) {
        $score += 25
        $reasons += "PEAK_CONFIRMED_NOT_WICK"
    }

    # Votação
    if ($score -ge 75) {
        $vote = "STRONG_YES"
    } elseif ($score -ge 50) {
        $vote = "YES"
    } elseif ($score -ge 25) {
        $vote = "MAYBE"
    }

    return [PSCustomObject]@{
        voter = "TORI_STRUCTURE"
        vote = $vote
        score = $score
        reasons = $reasons
        confidence = [math]::Round(($score / 100), 2)
        regime_criteria = $criteria.rationale
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
}

function Ricardo-ReversalVoteRegimeAware {
    <#
    .SYNOPSIS
    RICARDO vote com critérios adaptados ao regime.
    Antes: ADX >20 SEMPRE → NO_CONFIDENCE em consolidation
    Depois: ADX >15 em BEAR_WEAK → YES possível
    #>
    [CmdletBinding()]
    param(
        [double] $ADX = 0,
        [double] $RSI = 0,
        [double] $RSIPeakValue = 85,
        [double] $MACD = 0,
        [double] $RetractionPct = 0,
        [string] $Regime = "BEAR_WEAK"
    )

    $vote = "NO_CONFIDENCE"
    $score = 0
    $reasons = @()

    # Pegar thresholds por regime
    $criteria = Get-MesaCriteriaByRegime -Regime $Regime
    $adxThreshold = $criteria.ricardo_adx_threshold
    $macdRequired = $criteria.ricardo_macd_required

    # Critério 1: ADX (relaxado por regime)
    if ($ADX -ge $adxThreshold) {
        $score += 25
        $reasons += "ADX_CONFIRMED_$($ADX.ToString('F1'))_(threshold=$adxThreshold)"
    } elseif ($ADX -ge $adxThreshold * 0.8) {
        # Partial credit se perto do threshold
        $score += 12
        $reasons += "ADX_BORDERLINE_$($ADX.ToString('F1'))"
    }

    # Critério 2: RSI decline (sempre importante)
    if ($RSI -lt $RSIPeakValue -and $RSI -lt 70) {
        $score += 25
        $reasons += "RSI_DECLINE_FROM_OVERBOUGHT_$($RSI.ToString('F0'))"
    }

    # Critério 3: MACD (opcional por regime)
    if ($macdRequired) {
        if ($MACD -lt 0) {
            $score += 25
            $reasons += "MACD_NEGATIVE_REQUIRED"
        }
    } else {
        # Optional: give partial credit
        if ($MACD -lt -0.5) {
            $score += 15
            $reasons += "MACD_NEGATIVE_SIGNAL"
        } elseif ($MACD -lt 0) {
            $score += 8
            $reasons += "MACD_SLIGHTLY_NEGATIVE"
        }
    }

    # Critério 4: Retração visible
    if ($RetractionPct -gt 5) {
        $score += 25
        $reasons += "RETRACTION_VISIBLE_$($RetractionPct.ToString('F1'))%"
    } elseif ($RetractionPct -gt 2) {
        $score += 12
        $reasons += "RETRACTION_MODEST_$($RetractionPct.ToString('F1'))%"
    }

    # Votação
    if ($score -ge 75) {
        $vote = "STRONG_YES"
    } elseif ($score -ge 50) {
        $vote = "YES"
    } elseif ($score -ge 25) {
        $vote = "MAYBE"
    }

    return [PSCustomObject]@{
        voter = "RICARDO_REVERSAL"
        vote = $vote
        score = $score
        reasons = $reasons
        confidence = [math]::Round(($score / 100), 2)
        regime_criteria = $criteria.rationale
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
}

function Resolve-MesaTiebreak {
    <#
    .SYNOPSIS
    Ranked voting tie-break: se votação é 1/1/1 ou indecisa, usar ranked priority.
    Ordem: TORI (structure é base) > RICARDO (reversal confirma) > LOPEZ (flow)
    #>
    [CmdletBinding()]
    param(
        [PSCustomObject[]] $Votes,
        [string] $Regime = "BEAR_WEAK"
    )

    $criteria = Get-MesaCriteriaByRegime -Regime $Regime
    $quorum = $criteria.consensus_quorum

    # Count votos por tipo
    $strongYes = @($Votes | Where-Object { $_.vote -eq "STRONG_YES" }).Count
    $yes = @($Votes | Where-Object { $_.vote -eq "YES" }).Count
    $maybe = @($Votes | Where-Object { $_.vote -eq "MAYBE" }).Count
    $no = @($Votes | Where-Object { $_.vote -eq "NO_CONFIDENCE" }).Count

    # Lógica de consensus por quorum
    if ($quorum -eq "STRICT_3/3") {
        # Precisa 3/3 concordarem (raro em BEAR_WEAK)
        if ($strongYes -eq 3) { return "FORTE_3" }
        if ($strongYes + $yes -eq 3) { return "MEDIO_3" }
        return "CAOS"  # Tie ou desacordo
    }

    # Maioria simples (2/3) — default
    if ($strongYes -ge 2) { return "FORTE_3" }
    if ($strongYes + $yes -ge 2) { return "MEDIO_2" }

    # Tie: usar ranked priority (Tori > Ricardo > Lopez)
    $toriVote = @($Votes | Where-Object { $_.voter -match "TORI" })[0]
    if ($toriVote -and $toriVote.vote -match "YES|STRONG") {
        return "MEDIO_2_TORI_RANKED"
    }

    $ricardoVote = @($Votes | Where-Object { $_.voter -match "RICARDO" })[0]
    if ($ricardoVote -and $ricardoVote.vote -match "YES|STRONG") {
        return "MEDIO_2_RICARDO_RANKED"
    }

    # Ainda tie? Retorna CAOS (sem consensus definido)
    return "CAOS"
}

# ─────────────────────────────────────────────────────────────────────
# WIRE-UP: Substituir chamadas antigas por versões regime-aware
# ─────────────────────────────────────────────────────────────────────
# Em lib_mesa_reversal_votation.ps1 ou orquestrador:
#   Ao invés de:
#     Tori-StructureVote -PeakPrice $pp -ClosePrice $cp -WickPct $wp
#   Usar:
#     Tori-StructureVoteRegimeAware -PeakPrice $pp -ClosePrice $cp -WickPct $wp -Regime $regime
# ─────────────────────────────────────────────────────────────────────
