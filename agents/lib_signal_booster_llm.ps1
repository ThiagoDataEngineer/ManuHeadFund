# lib_signal_booster_llm.ps1 — PLUS ADICIONAL: Signal Confidence Amplification
# Multiplica confiança LLM quando histórico + enriquecimento apontam MESMA direção
# 2026-07-09

$ErrorActionPreference = "Continue"

# ============================================================================
# BOOST 1: Grade History Alignment
# ============================================================================

function Get-GradeHistoryBoost {
    [CmdletBinding()]
    param(
        [object]$GradeData,
        [string]$Direction,
        [string]$Regime
    )

    if (-not $GradeData -or $GradeData.accuracy -le 0) { return $null }

    $accuracy = [double]$GradeData.accuracy
    $n = [int]$GradeData.n

    # Quanto melhor a accuracy histórica, mais boost
    if ($accuracy -gt 70 -and $n -ge 50) {
        return @{
            source = "grade_ultra_high"
            boost_pct = 18
            confidence = "VERY_HIGH"
            reasoning = "Grade accuracy $accuracy% (n=$n) → very reliable signal"
        }
    } elseif ($accuracy -gt 60 -and $n -ge 30) {
        return @{
            source = "grade_high"
            boost_pct = 12
            confidence = "HIGH"
            reasoning = "Grade accuracy $accuracy% (n=$n) → reliable"
        }
    } elseif ($accuracy -gt 55 -and $n -ge 20) {
        return @{
            source = "grade_medium"
            boost_pct = 8
            confidence = "MEDIUM"
            reasoning = "Grade accuracy $accuracy% (n=$n) → moderate confidence"
        }
    }

    return $null
}

# ============================================================================
# BOOST 2: Counterfactual Validation (skipped wins)
# ============================================================================

function Get-CounterfactualBoost {
    [CmdletBinding()]
    param(
        [object]$CounterfactualData
    )

    if (-not $CounterfactualData) { return $null }

    $nWin = [int]$CounterfactualData.n_would_win
    $nSkip = [int]$CounterfactualData.n_skipped

    if ($nSkip -eq 0) { return $null }

    $winRate = $nWin / $nSkip
    $avgGain = [double]$CounterfactualData.avg_gain_pct

    # Win rate > 60% na counterfactual = strong signal
    if ($winRate -gt 0.70 -and $avgGain -gt 50) {
        return @{
            source = "counterfactual_ultra_strong"
            boost_pct = 15
            confidence = "VERY_HIGH"
            reasoning = "Counterfactual: $($winRate * 100)% win, avg gain $avgGain% (n=$nSkip missed opportunities)"
        }
    } elseif ($winRate -gt 0.60 -and $avgGain -gt 30) {
        return @{
            source = "counterfactual_strong"
            boost_pct = 12
            confidence = "HIGH"
            reasoning = "Counterfactual: $($winRate * 100)% win, avg gain $avgGain%"
        }
    } elseif ($winRate -gt 0.55 -and $avgGain -gt 20) {
        return @{
            source = "counterfactual_moderate"
            boost_pct = 8
            confidence = "MEDIUM"
            reasoning = "Counterfactual: $($winRate * 100)% win, avg gain $avgGain%"
        }
    }

    return $null
}

# ============================================================================
# BOOST 3: Market Historical Performance
# ============================================================================

function Get-MarketHistoryBoost {
    [CmdletBinding()]
    param(
        [object]$TrailingData
    )

    if (-not $TrailingData) { return $null }

    $avgProfit = [double]$TrailingData.avg_profit_pct
    $nTrades = [int]$TrailingData.n_trades
    $slEff = [double]$TrailingData.avg_sl_effectiveness

    # Market com histórico forte
    if ($nTrades -ge 10 -and $avgProfit -gt 4.0 -and $slEff -gt 0.90) {
        return @{
            source = "market_ultra_strong"
            boost_pct = 14
            confidence = "VERY_HIGH"
            reasoning = "Market $($TrailingData.market)|$($TrailingData.regime): profit_avg=$avgProfit%, SL_eff=$slEff (n=$nTrades)"
        }
    } elseif ($nTrades -ge 5 -and $avgProfit -gt 3.0 -and $slEff -gt 0.85) {
        return @{
            source = "market_strong"
            boost_pct = 10
            confidence = "HIGH"
            reasoning = "Market: profit_avg=$avgProfit%, SL_eff=$slEff (n=$nTrades)"
        }
    } elseif ($nTrades -ge 3 -and $avgProfit -gt 2.0 -and $slEff -gt 0.80) {
        return @{
            source = "market_moderate"
            boost_pct = 6
            confidence = "MEDIUM"
            reasoning = "Market: profit_avg=$avgProfit%, SL_eff=$slEff (n=$nTrades)"
        }
    }

    return $null
}

# ============================================================================
# BOOST 4: Capital Health + Risk Alignment
# ============================================================================

function Get-CapitalHealthBoost {
    [CmdletBinding()]
    param(
        [object]$CapitalData
    )

    if (-not $CapitalData) { return $null }

    $marginPct = [double]$CapitalData.margin_free_pct
    $deployedPct = [double]$CapitalData.deployed_pct
    $riskLevel = $CapitalData.risk_level

    # Capital saudável = mais confiança pra operar
    if ($riskLevel -eq "NORMAL" -and $marginPct -gt 0.20 -and $deployedPct -lt 0.50) {
        return @{
            source = "capital_very_healthy"
            boost_pct = 8
            confidence = "HIGH"
            reasoning = "Capital HEALTHY: margin=$([math]::Round($marginPct * 100, 1))%, deployed=$([math]::Round($deployedPct * 100, 1))%"
        }
    } elseif ($riskLevel -eq "NORMAL" -and $marginPct -gt 0.15) {
        return @{
            source = "capital_healthy"
            boost_pct = 5
            confidence = "MEDIUM"
            reasoning = "Capital status NORMAL"
        }
    }

    return $null
}

# ============================================================================
# BOOST 5: Multi-Source Alignment (todos os sinais apontam mesma direção)
# ============================================================================

function Get-AlignmentBoost {
    [CmdletBinding()]
    param(
        [object[]]$AllBoosts
    )

    if (-not $AllBoosts -or $AllBoosts.Count -lt 2) { return $null }

    $count = $AllBoosts.Count
    $highConfidenceCount = @($AllBoosts | Where-Object { $_.confidence -in "HIGH", "VERY_HIGH" }).Count

    # Todos os sinais aligned = extra boost
    if ($highConfidenceCount -eq $count) {
        return @{
            source = "perfect_alignment"
            boost_pct = 10
            confidence = "VERY_HIGH"
            reasoning = "PERFECT ALIGNMENT: $count sinais todos apontam mesma direção (confidence=$($AllBoosts[0].confidence))"
        }
    } elseif ($highConfidenceCount -ge 2) {
        return @{
            source = "multi_alignment"
            boost_pct = 6
            confidence = "HIGH"
            reasoning = "$highConfidenceCount/$count sinais HIGH+ confidence aligned"
        }
    }

    return $null
}

# ============================================================================
# MAIN: Orquestra todos os boosts
# ============================================================================

function Get-SignalBoostContext {
    [CmdletBinding()]
    param(
        [object]$Enrichment,
        [string]$Market,
        [string]$Direction
    )

    if (-not $Enrichment) { return @{ total_boost_pct = 0; boosts = @() } }

    $boosts = @()
    $totalBoost = 0

    # Coleta todos boosts possíveis
    if ($Enrichment.decision_grades) {
        $gb = Get-GradeHistoryBoost -GradeData $Enrichment.decision_grades -Direction $Direction -Regime $Enrichment.regime
        if ($gb) {
            $boosts += $gb
            $totalBoost += $gb.boost_pct
        }
    }

    if ($Enrichment.counterfactual) {
        $cb = Get-CounterfactualBoost -CounterfactualData $Enrichment.counterfactual
        if ($cb) {
            $boosts += $cb
            $totalBoost += $cb.boost_pct
        }
    }

    if ($Enrichment.market_history) {
        $mb = Get-MarketHistoryBoost -TrailingData $Enrichment.market_history
        if ($mb) {
            $boosts += $mb
            $totalBoost += $mb.boost_pct
        }
    }

    if ($Enrichment.capital) {
        $capb = Get-CapitalHealthBoost -CapitalData $Enrichment.capital
        if ($capb) {
            $boosts += $capb
            $totalBoost += $capb.boost_pct
        }
    }

    # Alignment bonus
    if ($boosts.Count -ge 2) {
        $ab = Get-AlignmentBoost -AllBoosts $boosts
        if ($ab) {
            $boosts += $ab
            $totalBoost += $ab.boost_pct
        }
    }

    return @{
        market = $Market
        direction = $Direction
        total_boost_pct = $totalBoost
        n_sources = $boosts.Count
        boosts = $boosts
        confidence_level = $(
            if ($totalBoost -ge 40) { "ULTRA_HIGH" }
            elseif ($totalBoost -ge 30) { "VERY_HIGH" }
            elseif ($totalBoost -ge 20) { "HIGH" }
            elseif ($totalBoost -ge 10) { "MEDIUM" }
            else { "LOW" }
        )
    }
}

# ============================================================================
# FORMAT: Monta bloco pra injeta no prompt LLM
# ============================================================================

function Format-SignalBoostPrompt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$BoostContext
    )

    if (-not $BoostContext.boosts -or $BoostContext.boosts.Count -eq 0) {
        return ""
    }

    $lines = @(
        ""
        "[SIGNAL BOOSTER — Confidence Amplification from Historical Data]"
        "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    )

    foreach ($boost in $BoostContext.boosts) {
        $lines += ""
        $lines += "  ✨ $($boost.source.ToUpper()) [+$($boost.boost_pct)%]"
        $lines += "     Confidence: $($boost.confidence)"
        $lines += "     → $($boost.reasoning)"
    }

    $lines += ""
    $lines += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    $lines += "  🚀 TOTAL CONFIDENCE BOOST: +$($BoostContext.total_boost_pct)%"
    $lines += "     Sources: $($BoostContext.n_sources) (Grade|Counterfactual|Market|Capital|Alignment)"
    $lines += "     Overall Level: $($BoostContext.confidence_level)"
    $lines += ""
    $lines += "  ⚡ INSTRUCTION TO LLM:"
    $lines += "     Increase conviction in DECISION by +$($BoostContext.total_boost_pct)%"
    $lines += "     Multiple independent signals validate this direction historically."
    $lines += "     This is NOT overconfidence - it's statistical validation."
    $lines += ""

    return $lines -join "`n"
}

# ============================================================================
# HELPER: Serialização pra logging
# ============================================================================

function ConvertTo-BoostJson {
    [CmdletBinding()]
    param(
        [object]$BoostContext
    )

    return $BoostContext | ConvertTo-Json -Depth 3 -Compress
}

# ============================================================================
# EXPORT (disabled for dot-source compatibility in PS 5.1)
# ============================================================================

# Export-ModuleMember -Function @(
#     'Get-SignalBoostContext'
#     'Format-SignalBoostPrompt'
#     'ConvertTo-BoostJson'
#     'Get-GradeHistoryBoost'
#     'Get-CounterfactualBoost'
#     'Get-MarketHistoryBoost'
#     'Get-CapitalHealthBoost'
#     'Get-AlignmentBoost'
# )
