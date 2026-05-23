# lib_methodology_gates.ps1 -- B23/B24 fix 2026-05-20 PM6+520min.
#
# Anti-overfitting gates baseados em evidencia empirica do proprio pipeline:
#
# Strategy edge audit 2026-05-20 PM6+ revelou padrao estatistico claro:
#   Markets promoted Tier A LIVE com Sharpe > 5:
#     PENDLE 8.75 -> demoted -19% dia 1 (overfitting)
#     CFG    8.48 -> demoted FQS 3 SPECULATIVE + beta amplifier
#   Markets promoted Tier A LIVE com Sharpe 2-4 (faixa normal):
#     RENDER 3.63 -> ativo OK
#     INJ    3.88 -> ativo OK
#     ZEC    2.86 -> grandfathered OK
#     SKY    2.57 -> Tier B PAPER OK
#
# Conclusao: Sharpe > 5 = SIGNAL OVERFITTING, nao signal edge robusto.
# Outliers indicam lookahead bias / regime concentration / poucos trades / triple-barrier missing.
#
# Tambem implementa pump-after-discovery gate:
# PENDLE foi promovido APOS +33% mom_20d. Backtest validou edge historica, mas a JANELA
# que disparou descoberta era exatamente o pico ja realizado. Buy-the-top trap.
#
# PS 5.1, UTF-8 BOM.

function Test-SharpeCeilingGate {
    <#
    .SYNOPSIS
        Gate anti-overfitting: Sharpe > 5 = REJECT (red flag empirico).
        Sharpe 4-5 = WARN (zona suspect, requer validacao adicional).
        Sharpe 1.5-4 = PASS robusto.
        Sharpe < 1.5 = marginal (passa mas low confidence).
        Sharpe <= 0 = REJECT (sem edge).
    .OUTPUTS
        PSCustomObject { passes, zone, sharpe, reason }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double] $Sharpe,
        [double] $RedFlagThreshold = 5.0,    # > = overfit
        [double] $SuspectThreshold = 4.0,    # 4-5 = suspect
        [double] $MarginalThreshold = 1.5,   # 1.5-4 = robust; < 1.5 = marginal
        [double] $NoEdgeThreshold  = 0.0,
        # B25 fix 2026-05-21: opt-in regime-conditioned thresholds. Quando -Phase passado,
        # overrides RedFlag/Suspect via Get-RegimeAwareThreshold. Bear regime fica mais
        # tight (sharpe>4 ja red flag) porque poucas oportunidades reais elevam suspicao.
        [string] $Phase = ""
    )
    # Aplicar regime-aware overrides se Phase fornecido
    if ($Phase -and (Get-Command Get-RegimeAwareThreshold -ErrorAction SilentlyContinue)) {
        try {
            $ceiling = Get-RegimeAwareThreshold -Metric "sharpe_ceiling" -Phase $Phase
            $suspect = Get-RegimeAwareThreshold -Metric "sharpe_suspect" -Phase $Phase
            $RedFlagThreshold = $ceiling.threshold
            $SuspectThreshold = $suspect.threshold
        } catch {
            # Fallback aos defaults se metric desconhecido
        }
    }
    if ($Sharpe -le $NoEdgeThreshold) {
        return [PSCustomObject]@{
            passes = $false
            zone   = "no_edge"
            sharpe = $Sharpe
            reason = "sharpe_${Sharpe}_below_zero_no_edge"
        }
    }
    if ($Sharpe -gt $RedFlagThreshold) {
        return [PSCustomObject]@{
            passes = $false
            zone   = "overfit_red_flag"
            sharpe = $Sharpe
            reason = "sharpe_${Sharpe}_above_${RedFlagThreshold}_overfit_red_flag (empiric PENDLE 8.75 CFG 8.48 ambos demoted)"
        }
    }
    if ($Sharpe -gt $SuspectThreshold) {
        return [PSCustomObject]@{
            passes = $true
            zone   = "suspect"
            sharpe = $Sharpe
            reason = "sharpe_${Sharpe}_in_suspect_zone_4_to_5"
        }
    }
    if ($Sharpe -ge $MarginalThreshold) {
        return [PSCustomObject]@{
            passes = $true
            zone   = "robust"
            sharpe = $Sharpe
            reason = "ok"
        }
    }
    return [PSCustomObject]@{
        passes = $true
        zone   = "marginal"
        sharpe = $Sharpe
        reason = "sharpe_${Sharpe}_below_${MarginalThreshold}_low_confidence"
    }
}

function Get-RegimeAwareThreshold {
    <#
    .SYNOPSIS
        Retorna threshold de metric ajustado pra phase atual do ciclo halving.
    .DESCRIPTION
        C3 fix 2026-05-21: gates fixos bull-calibrados travam sistema em bear/sideways.
        Evidencia: em phase_3_bear, TODOS markets falham sharpe_30d > 1.0 (sistema dead).
        Solucao: threshold scaling por regime_class (bull/sideways/bear).
    .OUTPUTS
        PSCustomObject { metric, phase, regime_class, threshold }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Metric,
        [Parameter(Mandatory)] [string] $Phase
    )

    # Phase -> regime class
    $regimeClass = switch -Regex ($Phase) {
        'bull'     { 'bull';     break }
        'bear'     { 'bear';     break }
        'sideways' { 'sideways'; break }
        default    { 'bull' }  # fallback conservador
    }

    # Thresholds por (metric, regime_class)
    # Calibragem: bull = original (era hardcoded antes do C3).
    #             bear = relaxa pra realidade defensiva phase_3.
    #             sideways = intermediario.
    $table = @{
        'sharpe_30d' = @{ bull = 1.0;  sideways = 0.5;  bear = 0.3 }
        'sharpe_60d' = @{ bull = 1.5;  sideways = 0.8;  bear = 0.5 }
        'max_dd'     = @{ bull = 0.15; sideways = 0.22; bear = 0.30 }   # threshold maximo permitido
        'mom_20d'    = @{ bull = 0.0;  sideways = -0.05; bear = -0.10 } # mom positivo bull; pequenas pullbacks OK bear
        # B25 (2026-05-21): regime-conditioned MAX Sharpe (overfit detection).
        # Bear: Sharpe alto MAIS suspect (poucas oportunidades reais = improvavel statistical edge).
        # Bull: Sharpe alto pode ser legitimo momentum (mas ainda red flag se >5).
        # Empiric: PENDLE Sharpe 8.75 + CFG 8.48 ambos demoted apos drawdown >15%.
        'sharpe_ceiling' = @{ bull = 5.0; sideways = 4.5; bear = 4.0 }
        # B25: regime-conditioned suspect zone (lower bound onde warn dispara).
        'sharpe_suspect' = @{ bull = 4.0; sideways = 3.5; bear = 3.0 }
    }

    if (-not $table.ContainsKey($Metric)) {
        throw "Get-RegimeAwareThreshold: metric desconhecida '$Metric'"
    }
    $thresh = $table[$Metric][$regimeClass]
    return [PSCustomObject]@{
        metric       = $Metric
        phase        = $Phase
        regime_class = $regimeClass
        threshold    = $thresh
    }
}


function Test-SampleSizeGate {
    <#
    .SYNOPSIS
        Gate anti-overfitting empirico: amostras pequenas geram Sharpe outlier sem fundamento.
        Justificativa empirica: HYPE N=34 entries -> Sharpe 12.23 (statistical insanity).
    .OUTPUTS
        PSCustomObject { passes, zone, n_entries, reason }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [int] $NEntries,
        [int] $BlockThreshold = 50,  # < = insuficiente; baseado em rule of thumb statistico
        [int] $WarnThreshold  = 80   # 50-80 = marginal
    )
    if ($NEntries -lt $BlockThreshold) {
        return [PSCustomObject]@{
            passes = $false
            zone   = "insufficient_sample"
            n_entries = $NEntries
            reason = "n_entries_${NEntries}_below_${BlockThreshold}_overfitting_risk (HYPE N=34 -> Sharpe 12.23 empirico)"
        }
    }
    if ($NEntries -lt $WarnThreshold) {
        return [PSCustomObject]@{
            passes = $true
            zone   = "marginal"
            n_entries = $NEntries
            reason = "n_entries_${NEntries}_below_warn_${WarnThreshold}_marginal_confidence"
        }
    }
    return [PSCustomObject]@{
        passes = $true
        zone   = "robust"
        n_entries = $NEntries
        reason = "ok"
    }
}

function Test-PumpAfterDiscoveryGate {
    <#
    .SYNOPSIS
        Gate anti chase-trap: se mom_20d > +25% no momento da promotion,
        sistema esta comprando o topo. PENDLE +33% mom_20d -> -19% dia 1.
    .OUTPUTS
        PSCustomObject { passes, zone, mom_20d_pct, reason }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double] $Mom20dPct,
        [double] $BlockThreshold = 25.0,  # > = chase trap
        [double] $WarnThreshold  = 15.0   # 15-25 = warn
    )
    if ($Mom20dPct -gt $BlockThreshold) {
        return [PSCustomObject]@{
            passes      = $false
            zone        = "chase_trap"
            mom_20d_pct = $Mom20dPct
            reason      = "mom_20d_${Mom20dPct}pct_above_${BlockThreshold}pct_chase_trap_top_buying (PENDLE +33% -> -19% dia 1)"
        }
    }
    if ($Mom20dPct -gt $WarnThreshold) {
        return [PSCustomObject]@{
            passes      = $true
            zone        = "warn"
            mom_20d_pct = $Mom20dPct
            reason      = "mom_20d_${Mom20dPct}pct_acima_warn_threshold_pumped_already"
        }
    }
    return [PSCustomObject]@{
        passes      = $true
        zone        = "ok"
        mom_20d_pct = $Mom20dPct
        reason      = "ok"
    }
}
