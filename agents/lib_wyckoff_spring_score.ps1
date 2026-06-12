# lib_wyckoff_spring_score.ps1 -- WSS composite scoring (0-100) + tier S/A/B.
#
# Filosofia: vol_climax+RSI<30 predicate eh detector de Wyckoff Spring phase.
# Edge eh CONCENTRADO em regime especifico (12-26 meses post-halving + vol elevada
# + BTC drawdown moderado). WSS computa 0-100 score combinando 5 dimensoes:
#
#   - market_quality       (35%) — historical T1/T2/T3 per market (p3_bear EV)
#   - btc_vol_percentile   (10%) — vol_20d daily realizada vs distribuicao historica
#   - btc_dd_zone          (20%) — -15% a -40% drawdown 90d = sweet zone
#   - months_post_halving  (35%) — 12-18mo=95, 18-22=60, 22-26=85, 26-30=70
#   - cluster_penalty      (-25) — se >=3 markets disparam mesmo dia, subtrai
#
# Tier classification:
#   WSS >= 60 = Tier S — paper-trade eligible (high confidence)
#   45 <= WSS < 60 = Tier A — observatory + TG alert
#   WSS < 45 = Tier B — log silent (low confidence)
#
# Validacao backtest 2026-05-22:
#   OOS h20: Tier S lift +3.20pp vs baseline (n=5)
#   OOS h24: Tier S lift -0.42pp vs baseline (n=4, neutro)
#   Train EV: Tier S +5.09pp / Tier A +9.53pp / Tier B +7.26pp
#
# LIMITACOES (declaradas pra usuario):
#   - Market quality table eh retrofit de p3_bear historicamente (risco overfit)
#   - h24 Tier S so n=7 cross-cycle — sample apertado
#   - Forward validation requer 6-12 meses outcomes reais
#
# PS 5.1. UTF-8 BOM.


# ─── Constants ────────────────────────────────────────────────────────────────

$script:WSS_HALVING_2020 = [datetime]::new(2020, 5, 11, 0, 0, 0, [DateTimeKind]::Utc)
$script:WSS_HALVING_2024 = [datetime]::new(2024, 4, 19, 0, 0, 0, [DateTimeKind]::Utc)
$script:WSS_HALVING_2028 = [datetime]::new(2028, 4, 15, 0, 0, 0, [DateTimeKind]::Utc)  # estimativa

$script:WSS_WEIGHTS = @{
    market  = 0.35
    vol     = 0.10
    dd      = 0.20
    mph     = 0.35
    cluster = 1.0   # penalty subtracted directly
}

$script:WSS_TIER_S_MIN = 60.0
$script:WSS_TIER_A_MIN = 45.0


# ─── Helpers ──────────────────────────────────────────────────────────────────

function Get-MonthsPostHalving {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [datetime] $NowUtc)
    if ($NowUtc -ge $script:WSS_HALVING_2028) {
        return ($NowUtc - $script:WSS_HALVING_2028).TotalDays / 30.5
    }
    if ($NowUtc -ge $script:WSS_HALVING_2024) {
        return ($NowUtc - $script:WSS_HALVING_2024).TotalDays / 30.5
    }
    if ($NowUtc -ge $script:WSS_HALVING_2020) {
        return ($NowUtc - $script:WSS_HALVING_2020).TotalDays / 30.5
    }
    return -1.0
}

function Read-WyckoffMarketQuality {
    [CmdletBinding()]
    param([string] $Path = "journal/wyckoff_market_quality.json")
    if (-not (Test-Path $Path)) { return @{} }
    try {
        $raw = Get-Content -Path $Path -Raw -Encoding UTF8 -ErrorAction Stop
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        $table = @{}
        foreach ($p in $obj.PSObject.Properties) {
            $table[$p.Name] = @{
                tier = $p.Value.tier
                ev_net = [double]$p.Value.ev_net
                hit_rate = [double]$p.Value.hit_rate
                n = [int]$p.Value.n
            }
        }
        return $table
    } catch { return @{} }
}


# ─── Sub-scores ───────────────────────────────────────────────────────────────

function _WSS-ScoreMarketQuality {
    param([string] $Market, [hashtable] $QualityTable)
    if (-not $QualityTable.ContainsKey($Market)) { return 50 }  # unknown = neutral
    switch ($QualityTable[$Market].tier) {
        "T1" { return 100 }
        "T2" { return 60 }
        "T3" { return 20 }
        default { return 50 }
    }
}

function _WSS-ScoreBtcVol {
    param([Nullable[double]] $Vol20d, [double[]] $VolDistribution)
    if ($null -eq $Vol20d -or -not $VolDistribution -or $VolDistribution.Count -eq 0) { return 50 }
    $below = 0
    foreach ($v in $VolDistribution) { if ($v -lt $Vol20d) { $below++ } }
    return [int]([math]::Round(($below / $VolDistribution.Count) * 100))
}

function _WSS-ScoreDdZone {
    # Drawdown is negative (e.g., -25). Sweet zone -15 to -40%.
    param([Nullable[double]] $DrawdownPct)
    if ($null -eq $DrawdownPct) { return 50 }
    $d = [double]$DrawdownPct
    if ($d -ge -40 -and $d -le -15) { return 100 }
    if ($d -ge -50 -and $d -le -10) { return 60 }
    if ($d -ge -55 -and $d -le -5)  { return 30 }
    return 0
}

function _WSS-ScoreMonthsPostHalving {
    param([double] $Mph)
    if ($Mph -lt 0) { return 30 }
    if ($Mph -lt 12) { return 40 }
    if ($Mph -lt 18) { return 95 }   # PRIME sweet spot
    if ($Mph -lt 22) { return 60 }   # transition
    if ($Mph -lt 26) { return 85 }   # secondary sweet spot
    if ($Mph -lt 30) { return 70 }   # late phase (n=1 historical, less confident)
    return 30                        # post phase 3 bear
}

function _WSS-ClusterPenalty {
    param([int] $ClusterSize)
    if ($ClusterSize -le 1) { return 0 }
    if ($ClusterSize -eq 2) { return 5 }
    if ($ClusterSize -le 4) { return 15 }
    return 25  # severe penalty for very correlated bets
}


# ─── Main API ─────────────────────────────────────────────────────────────────

function Get-WyckoffSpringScore {
    <#
    .SYNOPSIS
    Calcula WSS composite (0-100) + tier S/A/B + componentes individuais.

    .DESCRIPTION
    Compose 5 sub-scores em weighted sum, subtrai cluster penalty, classifica em tier.
    Retorna PSCustomObject com .wss, .tier, .components (hashtable).

    Default tier thresholds: S>=60, A>=45.

    .PARAMETER Market
    Market symbol (ex: "BTCUSDT").

    .PARAMETER BtcDrawdownPct
    BTC drawdown atual de rolling 90d high. Negativo (ex: -25 = -25%).

    .PARAMETER BtcVol20d
    Realized vol BTC 20d, daily %. Positivo (ex: 2.5 = 2.5%/day).

    .PARAMETER NowUtc
    Timestamp UTC do signal. Default = agora.

    .PARAMETER ClusterSize
    Quantos markets dispararam signal mesmo dia (incluindo este). Default 1.

    .PARAMETER VolDistribution
    Histograma vol_20d historico pra percentile rank. Default = vazio (score=50 neutro).

    .PARAMETER QualityTable
    Hashtable market -> {tier, ev_net, hit_rate, n}. Use Read-WyckoffMarketQuality.

    .EXAMPLE
    $q = Read-WyckoffMarketQuality
    Get-WyckoffSpringScore -Market "ATOMUSDT" -BtcDrawdownPct -25 -BtcVol20d 2.5 `
                           -NowUtc (Get-Date).ToUniversalTime() -ClusterSize 2 -QualityTable $q
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Nullable[double]] $BtcDrawdownPct = $null,
        [Nullable[double]] $BtcVol20d = $null,
        [datetime] $NowUtc = (Get-Date).ToUniversalTime(),
        [int] $ClusterSize = 1,
        [double[]] $VolDistribution = @(),
        [hashtable] $QualityTable = @{}
    )

    $mph = Get-MonthsPostHalving -NowUtc $NowUtc

    $mq   = _WSS-ScoreMarketQuality -Market $Market -QualityTable $QualityTable
    $vp   = _WSS-ScoreBtcVol -Vol20d $BtcVol20d -VolDistribution $VolDistribution
    $ddz  = _WSS-ScoreDdZone -DrawdownPct $BtcDrawdownPct
    $mphs = _WSS-ScoreMonthsPostHalving -Mph $mph
    $cp   = _WSS-ClusterPenalty -ClusterSize $ClusterSize

    $wss = ($script:WSS_WEIGHTS.market * $mq) `
         + ($script:WSS_WEIGHTS.vol    * $vp) `
         + ($script:WSS_WEIGHTS.dd     * $ddz) `
         + ($script:WSS_WEIGHTS.mph    * $mphs) `
         - ($script:WSS_WEIGHTS.cluster * $cp)
    if ($wss -lt 0) { $wss = 0 }
    if ($wss -gt 100) { $wss = 100 }

    $tier = if ($wss -ge $script:WSS_TIER_S_MIN) { "S" }
            elseif ($wss -ge $script:WSS_TIER_A_MIN) { "A" }
            else { "B" }

    return [PSCustomObject]@{
        wss        = [math]::Round($wss, 1)
        tier       = $tier
        mph        = [math]::Round($mph, 1)
        components = [PSCustomObject]@{
            market_quality = $mq
            vol_percentile = $vp
            dd_zone        = $ddz
            mph_score      = $mphs
            cluster_pen    = $cp
        }
    }
}
