# lib_short_signals.ps1 -- SHORT predicate detector (Wyckoff Buying Climax).
#
# Tier 2 Block 1 C.1 (2026-05-23): Phase 2 T6 backtest validou EV +2.85pp em 505 signals
# usando inverse predicate (vol_climax + new HIGH + close BELOW + RSI > 70).
#
# Aproveita Detect-VolumeClimax -Side SHORT em lib_chart_patterns (ja simetrico).
# Adiciona:
#   - Detect-ShortSignal: wrapper + confluence checks
#   - Get-ShortSignalWss: integration com Wyckoff Spring Score (mesma lib)
#
# Output: PSCustomObject @{detected, pattern_name, strength, vol_ratio, break_pct, rsi}
# Compatible com vol_climax_scanner pattern.
#
# PS 5.1. UTF-8 BOM.


# Importa Detect-VolumeClimax se nao carregado
if (-not (Get-Command Detect-VolumeClimax -ErrorAction SilentlyContinue)) {
    $_cpLib = Join-Path $PSScriptRoot "lib_chart_patterns.ps1"
    if (Test-Path $_cpLib) { . $_cpLib }
}


function Detect-ShortSignal {
    <#
    .SYNOPSIS
    Wyckoff Buying Climax SHORT detector. Reverse of LONG vol_climax+RSI.

    .DESCRIPTION
    Triggers when:
      - Volume >= MULT * avg_lookback (vol spike)
      - New HIGH above prior lookback highs (exhaustion top)
      - Close BELOW high - rng * CLOSE_REJ (rejection from top)
      - RSI > RsiOverboughtMin (overbought confluence)

    Mirrors LONG predicate from lib_chart_patterns.

    .PARAMETER Volumes
    Array volumes.

    .PARAMETER Highs/Lows/Closes
    OHLC arrays.

    .PARAMETER ClimaxMultiplier
    Vol spike threshold. Default 2.5 (matches LONG refined).

    .PARAMETER RsiOverboughtMin
    RSI threshold (>this = overbought). Default 70.

    .OUTPUTS
    PSCustomObject @{ detected, pattern_name, strength, vol_ratio, break_pct, rsi, side="SHORT" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double[]] $Volumes,
        [Parameter(Mandatory)] [double[]] $Highs,
        [Parameter(Mandatory)] [double[]] $Lows,
        [Parameter(Mandatory)] [double[]] $Closes,
        [double] $ClimaxMultiplier = 2.5,
        [double] $RsiOverboughtMin = 70.0
    )

    # Reuse existing Detect-VolumeClimax with Side=SHORT (already implemented in lib_chart_patterns)
    if (-not (Get-Command Detect-VolumeClimax -ErrorAction SilentlyContinue)) {
        return [PSCustomObject]@{
            detected = $false
            pattern_name = "SHORT_climax"
            strength = 0
            vol_ratio = 0
            break_pct = 0
            rsi = 0
            side = "SHORT"
            error = "Detect-VolumeClimax_lib_missing"
        }
    }

    try {
        # SHORT variant: pass Side=SHORT. Detect-VolumeClimax handles inverse logic.
        $r = Detect-VolumeClimax -Volumes $Volumes -Highs $Highs -Lows $Lows -Closes $Closes `
            -Side SHORT -ClimaxMultiplier $ClimaxMultiplier
        if (-not $r.detected) {
            return [PSCustomObject]@{
                detected = $false; pattern_name = "SHORT_climax"; strength = 0
                vol_ratio = $r.vol_ratio; break_pct = 0; rsi = 0; side = "SHORT"
            }
        }

        # Add RSI confluence check (overbought)
        $rsiValue = 50.0
        if (Get-Command _CP-CalcRsiArray -ErrorAction SilentlyContinue) {
            try {
                $rsiArr = _CP-CalcRsiArray -Closes $Closes
                $rsiValue = [double]$rsiArr[-1]
            } catch {}
        }

        $rsiConfluencePass = $rsiValue -gt $RsiOverboughtMin
        if (-not $rsiConfluencePass) {
            return [PSCustomObject]@{
                detected = $false
                pattern_name = "SHORT_climax_rsi_fail"
                strength = $r.strength
                vol_ratio = $r.vol_ratio
                break_pct = $r.break_pct
                rsi = $rsiValue
                side = "SHORT"
                reason = "rsi_${rsiValue}_below_overbought_${RsiOverboughtMin}"
            }
        }

        # All passes
        return [PSCustomObject]@{
            detected = $true
            pattern_name = "SHORT_buying_climax_refined"
            strength = $r.strength
            vol_ratio = $r.vol_ratio
            break_pct = $r.break_pct
            rsi = $rsiValue
            side = "SHORT"
        }
    } catch {
        return [PSCustomObject]@{
            detected = $false
            pattern_name = "SHORT_climax_error"
            strength = 0
            vol_ratio = 0
            break_pct = 0
            rsi = 0
            side = "SHORT"
            error = $_.Exception.Message.Substring(0, [Math]::Min(100, $_.Exception.Message.Length))
        }
    }
}


function Get-ShortSignalWss {
    <#
    .SYNOPSIS
    Wraps Detect-ShortSignal + WSS scoring (per-market quality + regime).

    .DESCRIPTION
    Mirror of Wyckoff Spring Score for SHORT side.
    Returns dict {detected, signal_result, wss_score, tier} or null se not detected.

    .PARAMETER Market
    Market symbol pra lookup quality table.

    .PARAMETER Volumes/Highs/Lows/Closes
    OHLC arrays.

    .PARAMETER BtcDrawdown/BtcVol20d/Mph/ClusterSize
    Context para Get-WyckoffSpringScore (mesma funcao reused).

    .PARAMETER VolDistribution/QualityTable
    WSS inputs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [double[]] $Volumes,
        [Parameter(Mandatory)] [double[]] $Highs,
        [Parameter(Mandatory)] [double[]] $Lows,
        [Parameter(Mandatory)] [double[]] $Closes,
        [Nullable[double]] $BtcDrawdown = $null,
        [Nullable[double]] $BtcVol20d = $null,
        [datetime] $NowUtc = (Get-Date).ToUniversalTime(),
        [int] $ClusterSize = 1,
        [double[]] $VolDistribution = @(),
        [hashtable] $QualityTable = @{}
    )
    $r = Detect-ShortSignal -Volumes $Volumes -Highs $Highs -Lows $Lows -Closes $Closes
    if (-not $r.detected) { return $null }

    # WSS scoring (same as LONG — Wyckoff theory says capitulation signals symmetric)
    if (Get-Command Get-WyckoffSpringScore -ErrorAction SilentlyContinue) {
        try {
            $wss = Get-WyckoffSpringScore `
                -Market $Market `
                -BtcDrawdownPct $BtcDrawdown `
                -BtcVol20d $BtcVol20d `
                -NowUtc $NowUtc `
                -ClusterSize $ClusterSize `
                -VolDistribution $VolDistribution `
                -QualityTable $QualityTable
            return [PSCustomObject]@{
                detected = $true
                signal_result = $r
                wss = $wss.wss
                tier = $wss.tier
                components = $wss.components
                side = "SHORT"
            }
        } catch {
            return [PSCustomObject]@{
                detected = $true
                signal_result = $r
                wss = 0
                tier = "U"  # Unknown
                error = "wss_compute_failed"
                side = "SHORT"
            }
        }
    }
    return [PSCustomObject]@{
        detected = $true
        signal_result = $r
        wss = 0
        tier = "U"
        error = "wss_lib_missing"
        side = "SHORT"
    }
}


# ── TDD Sprint 1: Regime-Specific Thresholds (2026-05-23) ───────────────────

function Get-ShortThresholdsForRegime {
    <#
    .SYNOPSIS
    Retorna thresholds otimizados por regime para SHORT patterns.

    .DESCRIPTION
    TDD Sprint 1 (2026-05-23): Otimização regime-specific para SHORT patterns.
    Hipótese: Edge +2.85pp → +5-8pp em BEAR regimes com thresholds adaptativos.

    Thresholds por regime:
    - BEAR_STRONG: ClimaxMult=2.0, RSI>75 (aggressive shorts, high conviction)
    - BEAR_WEAK: ClimaxMult=2.5, RSI>70 (default, moderate shorts)
    - TRANSITION_DOWN: ClimaxMult=3.0, RSI>65 (conservative, early signals)
    - Default (unknown/BULL): ClimaxMult=3.0, RSI>70 (conservative fallback)

    .PARAMETER Regime
    Regime string (BEAR_STRONG, BEAR_WEAK, TRANSITION_DOWN, etc).

    .OUTPUTS
    Hashtable @{ ClimaxMultiplier, RsiOverboughtMin }

    .EXAMPLE
    $thresholds = Get-ShortThresholdsForRegime -Regime "BEAR_STRONG"
    $r = Detect-ShortSignal ... -ClimaxMultiplier $thresholds.ClimaxMultiplier `
        -RsiOverboughtMin $thresholds.RsiOverboughtMin
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Regime
    )

    switch ($Regime) {
        "BEAR_STRONG" {
            # Aggressive shorts: lower vol threshold, higher RSI filter
            # Rationale: BEAR_STRONG = high conviction downtrend, capture more opportunities
            # but filter false positives with stricter RSI (>75 = extreme overbought)
            return @{
                ClimaxMultiplier = 2.0
                RsiOverboughtMin = 75.0
            }
        }
        "BEAR_WEAK" {
            # Moderate shorts: default thresholds (validated in T6 backtest)
            # Rationale: BEAR_WEAK = moderate downtrend, balanced selectivity
            return @{
                ClimaxMultiplier = 2.5
                RsiOverboughtMin = 70.0
            }
        }
        "TRANSITION_DOWN" {
            # Conservative shorts: higher vol threshold, lower RSI filter
            # Rationale: TRANSITION_DOWN = early bear signal, be selective on vol
            # but allow earlier entries with RSI>65 (overbought forming)
            return @{
                ClimaxMultiplier = 3.0
                RsiOverboughtMin = 65.0
            }
        }
        default {
            # Conservative fallback: high vol threshold, moderate RSI
            # Rationale: Unknown regime or BULL = avoid anti-trend shorts
            return @{
                ClimaxMultiplier = 3.0
                RsiOverboughtMin = 70.0
            }
        }
    }
}

