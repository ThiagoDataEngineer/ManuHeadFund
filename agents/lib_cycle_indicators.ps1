# lib_cycle_indicators.ps1 -- Indicadores de ciclo PUROS (sem I/O)
# Dot-source: . (Join-Path $PSScriptRoot "lib_cycle_indicators.ps1")
#
# Funcoes:
#   Get-NUPLProxy    -- proxy de NUPL via F&G + distancia SMA200 + funding
#   Get-ATHDrawdown  -- drawdown desde ATH e classificacao do estagio
#
# Contrato Get-NUPLProxy:
#   In : FearGreed (0-100), DistanceFromSMA200 (% em pontos: 30 = +30%),
#        FundingRate8h (decimal: 0.001 = 0.1%)
#   Out: PSCustomObject { score (0-1), zone, components{fg,sma,funding} }
#
#   Zonas:
#     score < 0.20         -> CAPITULATION
#     0.20 <= score < 0.40 -> ANSIEDADE
#     0.40 <= score < 0.60 -> NEUTRO
#     0.60 <= score < 0.75 -> OTIMISMO
#     score >= 0.75        -> EUFORIA
#
#   Mapeamento de componentes (cada um 0..1):
#     fg      = clamp(FearGreed/100, 0, 1)
#     sma     = clamp((DistanceFromSMA200 + 30) / 60, 0, 1)   # -30%=0, 0%=0.5, +30%=1
#     funding = clamp((FundingRate8h / 0.001 + 0.5), 0, 1)    # -0.05%=0, 0%=0.5, +0.05%=1
#     score   = 0.5*fg + 0.3*sma + 0.2*funding
#
# Contrato Get-ATHDrawdown:
#   In : DailyCloses (double[]), Dates (datetime[]), CurrentPrice (double)
#   Out: PSCustomObject { ath, ath_date, ath_age_days, drawdown_pct, status, sufficient_data }
#
#   Status:
#     dd >= -2%               -> AT_ATH
#     -2%   > dd >= -15%      -> HEALTHY
#     -15%  > dd >= -30%      -> CORRECTION
#     -30%  > dd >= -50%      -> SEVERE
#     -50%  > dd >= -75%      -> BEAR_DEEP
#     dd < -75%               -> CAPITULATION


function _Clamp01 {
    param([double]$Value)
    if ($Value -lt 0.0) { return 0.0 }
    if ($Value -gt 1.0) { return 1.0 }
    return $Value
}


function _Resolve-NUPLZone {
    param([double]$Score)
    if ($Score -lt 0.20) { return "CAPITULATION" }
    if ($Score -lt 0.40) { return "ANSIEDADE" }
    if ($Score -lt 0.60) { return "NEUTRO" }
    if ($Score -lt 0.75) { return "OTIMISMO" }
    return "EUFORIA"
}


function Get-NUPLProxy {
    param(
        [int]$FearGreed,
        [double]$DistanceFromSMA200,
        [double]$FundingRate8h = 0.0
    )

    $fgComp      = _Clamp01 ([double]$FearGreed / 100.0)
    $smaComp     = _Clamp01 (($DistanceFromSMA200 + 30.0) / 60.0)
    $fundingComp = _Clamp01 (($FundingRate8h / 0.001) + 0.5)

    $score = (0.5 * $fgComp) + (0.3 * $smaComp) + (0.2 * $fundingComp)
    $score = _Clamp01 $score

    return [PSCustomObject]@{
        score      = $score
        zone       = _Resolve-NUPLZone -Score $score
        components = @{
            fg_component      = $fgComp
            sma_component     = $smaComp
            funding_component = $fundingComp
        }
    }
}


function _Resolve-ATHStatus {
    param([double]$DrawdownPct)
    if ($DrawdownPct -ge -2.0)  { return "AT_ATH" }
    if ($DrawdownPct -ge -15.0) { return "HEALTHY" }
    if ($DrawdownPct -ge -30.0) { return "CORRECTION" }
    if ($DrawdownPct -ge -50.0) { return "SEVERE" }
    if ($DrawdownPct -ge -75.0) { return "BEAR_DEEP" }
    return "CAPITULATION"
}


function Get-ATHDrawdown {
    param(
        [double[]]$DailyCloses,
        [datetime[]]$Dates,
        [double]$CurrentPrice
    )

    $n = 0
    if ($DailyCloses) { $n = $DailyCloses.Count }
    $sufficient = ($n -ge 30)

    if ($n -eq 0) {
        return [PSCustomObject]@{
            ath              = 0.0
            ath_date         = [datetime]::MinValue
            ath_age_days     = 0
            drawdown_pct     = 0.0
            status           = "AT_ATH"
            sufficient_data  = $false
        }
    }

    $athIdx = 0
    $athVal = [double]$DailyCloses[0]
    for ($i = 1; $i -lt $n; $i++) {
        $v = [double]$DailyCloses[$i]
        if ($v -gt $athVal) {
            $athVal = $v
            $athIdx = $i
        }
    }

    $athDate = if ($Dates -and $Dates.Count -gt $athIdx) { $Dates[$athIdx] } else { [datetime]::MinValue }

    $ageDays = 0
    if ($Dates -and $Dates.Count -gt $athIdx) {
        try { $ageDays = [int]((Get-Date) - $athDate).TotalDays } catch { $ageDays = 0 }
    }

    $dd = 0.0
    if ($athVal -gt 0.0) {
        $dd = (($CurrentPrice - $athVal) / $athVal) * 100.0
    }

    return [PSCustomObject]@{
        ath              = $athVal
        ath_date         = $athDate
        ath_age_days     = $ageDays
        drawdown_pct     = $dd
        status           = _Resolve-ATHStatus -DrawdownPct $dd
        sufficient_data  = $sufficient
    }
}
