# lib_cycle_context.ps1 -- V6.5 Parte C: composicao Pi/200WMA/ATH-DD/NUPL
# Compoe as 4 funcoes de A+B em objeto unico consumido pelo ChainAgent.
#
# Contrato Get-CycleContext:
#   Input  : Market, DailyCloses, Dates, CurrentPrice, FearGreed,
#            DistanceFromSMA200, FundingRate8h
#   Output : PSCustomObject {
#              market; pi_cycle; wma_200; ath_dd; nupl_proxy;
#              cycle_phase    : ACUMULACAO|MARKUP_INICIAL|MARKUP_AVANCADO|
#                               DISTRIBUICAO|MARKDOWN_INICIAL|MARKDOWN_PROFUNDO|NEUTRO
#              risk_score     : 0-100 (0=fundo, 100=topo)
#              recommendation : AGRESSIVO_LONG|LONG_CAUTELOSO|NEUTRO|
#                               REDUZIR_LONGS|EVITAR_LONGS
#              summary_line   : <200 chars para Mentor citar
#            }
#
# Formula risk:
#   risk = nupl.score * 60
#        + (pi == TRIGGERED ? 25 : 0)
#        + ((100 + ath.drawdown_pct) / 100) * 15

function Get-CycleContext {
    param(
        [string]     $Market = "BTCUSDT",
        [double[]]   $DailyCloses = @(),
        [datetime[]] $Dates       = @(),
        [double]     $CurrentPrice = 0,
        [int]        $FearGreed = 50,
        [double]     $DistanceFromSMA200 = 0,
        [double]     $FundingRate8h = 0
    )

    # ── Chama Partes A + B (mocks ou reais) ──────────────────────────────────
    $pi   = Get-PiCycleSignal  -DailyCloses $DailyCloses
    $wma  = Get-200WMAContext  -DailyCloses $DailyCloses -CurrentPrice $CurrentPrice
    $ath  = Get-ATHDrawdown    -DailyCloses $DailyCloses -Dates $Dates -CurrentPrice $CurrentPrice
    $nupl = Get-NUPLProxy      -FearGreed $FearGreed -DistanceFromSMA200 $DistanceFromSMA200 -FundingRate8h $FundingRate8h

    # ── Fallback se algo veio null (dados insuficientes) ─────────────────────
    $insufficient = (-not $pi) -or (-not $wma) -or (-not $ath) -or (-not $nupl) -or
                    ($DailyCloses.Count -eq 0) -or ($CurrentPrice -le 0)

    if ($insufficient) {
        return [PSCustomObject]@{
            market         = $Market
            pi_cycle       = $pi
            wma_200        = $wma
            ath_dd         = $ath
            nupl_proxy     = $nupl
            cycle_phase    = "NEUTRO"
            risk_score     = 50
            recommendation = "NEUTRO"
            summary_line   = "Dados insuficientes para inferir fase de ciclo -- operar com cautela padrao."
        }
    }

    # ── Risk score (0-100) ───────────────────────────────────────────────────
    $nuplComp = [double]$nupl.score * 60.0
    $piComp   = if ($pi.signal -eq "TRIGGERED") { 25.0 } else { 0.0 }
    $athComp  = ((100.0 + [double]$ath.drawdown_pct) / 100.0) * 15.0
    $risk     = [math]::Round([math]::Max(0, [math]::Min(100, $nuplComp + $piComp + $athComp)), 1)

    # ── Cycle phase ──────────────────────────────────────────────────────────
    $nuplScore = [double]$nupl.score
    $athZone   = "$($ath.zone)"
    $piSig     = "$($pi.signal)"
    $wmaZone   = "$($wma.zone)"

    $phase = if ($athZone -eq "CAPITULATION" -and $nuplScore -lt 0.25 -and $wmaZone -eq "NEAR") {
        "ACUMULACAO"
    } elseif ($piSig -eq "TRIGGERED" -and $nuplScore -gt 0.70) {
        "DISTRIBUICAO"
    } elseif ($athZone -eq "BEAR_DEEP" -and $wmaZone -eq "BELOW") {
        "MARKDOWN_PROFUNDO"
    } elseif ($athZone -eq "CORRECTION" -and $piSig -eq "POST_PEAK") {
        "MARKDOWN_INICIAL"
    } elseif (($athZone -eq "HEALTHY") -and $nuplScore -ge 0.50 -and $nuplScore -le 0.70 -and $piSig -eq "BEFORE") {
        "MARKUP_AVANCADO"
    } elseif (($athZone -in @("HEALTHY","CORRECTION")) -and $nuplScore -ge 0.30 -and $nuplScore -le 0.50) {
        "MARKUP_INICIAL"
    } else {
        # Fallback heuristico: usa risk_score
        if     ($risk -lt 25) { "ACUMULACAO" }
        elseif ($risk -lt 45) { "MARKUP_INICIAL" }
        elseif ($risk -lt 65) { "MARKUP_AVANCADO" }
        elseif ($risk -lt 85) { "DISTRIBUICAO" }
        else                  { "MARKDOWN_INICIAL" }
    }

    # ── Recommendation ───────────────────────────────────────────────────────
    $rec = if     ($risk -lt 20) { "AGRESSIVO_LONG" }
           elseif ($risk -lt 40) { "LONG_CAUTELOSO" }
           elseif ($risk -lt 60) { "NEUTRO" }
           elseif ($risk -lt 80) { "REDUZIR_LONGS" }
           else                  { "EVITAR_LONGS" }

    # ── Summary line ─────────────────────────────────────────────────────────
    $summary = "$phase | risk=$risk/100 | Pi=$piSig NUPL=$([math]::Round($nuplScore,2))($($nupl.zone)) ATH-DD=$($ath.drawdown_pct)%($athZone) 200WMA=$wmaZone -> $rec"
    if ($summary.Length -ge 200) { $summary = $summary.Substring(0, 199) }

    return [PSCustomObject]@{
        market         = $Market
        pi_cycle       = $pi
        wma_200        = $wma
        ath_dd         = $ath
        nupl_proxy     = $nupl
        cycle_phase    = $phase
        risk_score     = $risk
        recommendation = $rec
        summary_line   = $summary
    }
}
