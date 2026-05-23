# lib_cycle_indicators_advanced.ps1 - Indicadores de ciclo "complexos" (Pi Cycle Top + 200WMA)
#
# CONTRATO:
#   Get-PiCycleSignal -DailyCloses <double[]> [-ShortWindow 111] [-LongWindow 350] [-LongMultiplier 2.0]
#     -> [PSCustomObject]@{
#          triggered        = bool
#          dma_short        = double
#          dma_long_x2      = double
#          distance_pct     = double           # (dma_short - dma_long_x2) / dma_long_x2 * 100
#          days_since_cross = int | $null      # null se nunca cruzou
#          signal           = "BEFORE" | "TRIGGERED" | "POST_PEAK" | "NEUTRAL"
#          sufficient_data  = bool             # true se Count >= LongWindow
#        }
#
#   Get-200WMAContext -DailyCloses <double[]> -CurrentPrice <double>
#     -> [PSCustomObject]@{
#          wma200          = double                            # media dos 200 weekly closes
#          distance_pct    = double                            # (price - wma200) / wma200 * 100
#          status          = "ABOVE_FAR"|"ABOVE_NEAR"|"NEAR"|"BELOW_NEAR"|"CAPITULATION"
#          weeks_above     = int                               # semanas consecutivas com preco > wma200
#          sufficient_data = bool                              # true se Count >= 1400 (200 weeks)
#        }
#
# REGRAS PI CYCLE:
#   - TRIGGERED:  cruzamento ascendente nos ultimos 7 dias (DMA111 cruza DMA350*2 pra cima)
#   - POST_PEAK:  triggered ha mais de 7 dias atras
#   - BEFORE:     distance_pct entre -15% e 0% (aproximando do topo)
#   - NEUTRAL:    distance_pct < -15% (longe do topo)
#
# REGRAS 200WMA STATUS (interpretacao consistente; CAPITULATION = bem abaixo):
#   - ABOVE_FAR:    distance > +50%
#   - ABOVE_NEAR:   +15% < distance <= +50%
#   - NEAR:         |distance| <= 15%
#   - BELOW_NEAR:   -25% <= distance < -15%
#   - CAPITULATION: distance < -25%
#
# Tested in: tests/lib_cycle_indicators_advanced.Tests.ps1 (22 testes Pester 3.x)

# ============================================================================
# Helper: Get-DailyMASeries
# ============================================================================
# Retorna serie de SMA (rolling) para um periodo. Out length = closes.Count - period + 1.
# Ignora NaN/Inf (substitui pelo valor anterior valido).

function Get-DailyMASeries {
    param(
        [double[]]$Closes,
        [int]$Period
    )
    if ($null -eq $Closes -or $Closes.Count -lt $Period) { return @() }

    # Limpa NaN/Inf substituindo pelo anterior valido
    $clean = @()
    $lastValid = $null
    foreach ($v in $Closes) {
        if ([double]::IsNaN($v) -or [double]::IsInfinity($v)) {
            if ($null -ne $lastValid) { $clean += $lastValid } else { $clean += 0.0 }
        } else {
            $clean += $v
            $lastValid = $v
        }
    }

    $series = @()
    for ($i = $Period - 1; $i -lt $clean.Count; $i++) {
        $sum = 0.0
        for ($j = $i - $Period + 1; $j -le $i; $j++) { $sum += $clean[$j] }
        $series += ($sum / $Period)
    }
    return ,$series
}

# ============================================================================
# Get-PiCycleSignal
# ============================================================================

function Get-PiCycleSignal {
    param(
        [double[]]$DailyCloses,
        [int]$ShortWindow = 111,
        [int]$LongWindow  = 350,
        [double]$LongMultiplier = 2.0
    )

    if ($null -eq $DailyCloses -or $DailyCloses.Count -lt $LongWindow) {
        return [PSCustomObject]@{
            triggered        = $false
            dma_short        = 0.0
            dma_long_x2      = 0.0
            distance_pct     = 0.0
            days_since_cross = $null
            signal           = "NEUTRAL"
            sufficient_data  = $false
        }
    }

    $shortSeries = Get-DailyMASeries -Closes $DailyCloses -Period $ShortWindow
    $longSeries  = Get-DailyMASeries -Closes $DailyCloses -Period $LongWindow

    # Alinha as series pelo indice mais recente. Ambas terminam no mesmo bar = ultimo.
    # shortSeries.Count = Closes.Count - 111 + 1
    # longSeries.Count  = Closes.Count - 350 + 1
    # Trim shortSeries para ter mesmo Count que longSeries.
    $offset = $shortSeries.Count - $longSeries.Count
    if ($offset -lt 0) {
        return [PSCustomObject]@{
            triggered        = $false
            dma_short        = 0.0
            dma_long_x2      = 0.0
            distance_pct     = 0.0
            days_since_cross = $null
            signal           = "NEUTRAL"
            sufficient_data  = $false
        }
    }
    $shortAligned = $shortSeries[$offset..($shortSeries.Count - 1)]
    $longX2       = @()
    foreach ($v in $longSeries) { $longX2 += ($v * $LongMultiplier) }

    $dmaShort    = $shortAligned[-1]
    $dmaLongX2   = $longX2[-1]
    $distancePct = if ($dmaLongX2 -ne 0) { (($dmaShort - $dmaLongX2) / $dmaLongX2) * 100.0 } else { 0.0 }
    $distancePct = [math]::Round($distancePct, 4)

    # Detecta cruzamentos ascendentes: shortAligned[i] > longX2[i] AND shortAligned[i-1] <= longX2[i-1]
    $daysSinceCross = $null
    $lastCrossIndex = -1
    for ($i = 1; $i -lt $shortAligned.Count; $i++) {
        if ($shortAligned[$i] -gt $longX2[$i] -and $shortAligned[$i - 1] -le $longX2[$i - 1]) {
            $lastCrossIndex = $i
        }
    }
    if ($lastCrossIndex -ge 0) {
        $daysSinceCross = ($shortAligned.Count - 1) - $lastCrossIndex
    }

    $triggered = ($dmaShort -gt $dmaLongX2)

    # Classifica signal
    if ($triggered -and $null -ne $daysSinceCross -and $daysSinceCross -le 7) {
        $signal = "TRIGGERED"
    } elseif ($triggered -and $null -ne $daysSinceCross -and $daysSinceCross -gt 7) {
        $signal = "POST_PEAK"
    } elseif ((-not $triggered) -and $distancePct -ge -15 -and $distancePct -lt 0) {
        $signal = "BEFORE"
    } else {
        $signal = "NEUTRAL"
    }

    return [PSCustomObject]@{
        triggered        = [bool]$triggered
        dma_short        = [double]$dmaShort
        dma_long_x2      = [double]$dmaLongX2
        distance_pct     = [double]$distancePct
        days_since_cross = $daysSinceCross
        signal           = $signal
        sufficient_data  = $true
    }
}

# ============================================================================
# Get-200WMAContext
# ============================================================================

function Get-200WMAContext {
    param(
        [double[]]$DailyCloses,
        [double]$CurrentPrice
    )
    $DAILY_NEEDED = 1400  # 200 weeks * 7 days
    $WEEKS = 200

    if ($null -eq $DailyCloses -or $DailyCloses.Count -lt $DAILY_NEEDED) {
        return [PSCustomObject]@{
            wma200          = 0.0
            distance_pct    = 0.0
            status          = "NEAR"
            weeks_above     = 0
            sufficient_data = $false
        }
    }

    # Converte daily -> weekly pegando o ultimo close de cada janela de 7 dias.
    # Comeca pelo fim para garantir que a ultima semana inclui o candle mais recente.
    $weekly = @()
    $totalDaily = $DailyCloses.Count
    $i = $totalDaily - 1
    while ($i -ge 6) {
        $weekly = ,$DailyCloses[$i] + $weekly  # insert at start
        $i -= 7
    }

    if ($weekly.Count -lt $WEEKS) {
        return [PSCustomObject]@{
            wma200          = 0.0
            distance_pct    = 0.0
            status          = "NEAR"
            weeks_above     = 0
            sufficient_data = $false
        }
    }

    # WMA200 = media das ultimas 200 weekly closes
    $last200 = $weekly[($weekly.Count - $WEEKS)..($weekly.Count - 1)]
    $sum = 0.0; foreach ($v in $last200) { $sum += $v }
    $wma200 = $sum / $WEEKS

    $distancePct = if ($wma200 -ne 0) { (($CurrentPrice - $wma200) / $wma200) * 100.0 } else { 0.0 }
    $distancePct = [math]::Round($distancePct, 4)

    # Status (interpretacao consistente sem overlaps):
    #   > 50           => ABOVE_FAR
    #   15 < x <= 50   => ABOVE_NEAR
    #   |x| <= 15      => NEAR
    #   -25 <= x < -15 => BELOW_NEAR
    #   x < -25        => CAPITULATION
    if ($distancePct -gt 50) {
        $status = "ABOVE_FAR"
    } elseif ($distancePct -gt 15) {
        $status = "ABOVE_NEAR"
    } elseif ([math]::Abs($distancePct) -le 15) {
        $status = "NEAR"
    } elseif ($distancePct -ge -25) {
        $status = "BELOW_NEAR"
    } else {
        $status = "CAPITULATION"
    }

    # Semanas consecutivas com close acima da WMA200 (olhando para tras)
    $weeksAbove = 0
    for ($k = $weekly.Count - 1; $k -ge 0; $k--) {
        if ($weekly[$k] -gt $wma200) { $weeksAbove++ } else { break }
    }

    return [PSCustomObject]@{
        wma200          = [double]$wma200
        distance_pct    = [double]$distancePct
        status          = $status
        weeks_above     = [int]$weeksAbove
        sufficient_data = $true
    }
}
