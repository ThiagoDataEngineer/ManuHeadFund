# lib_regime_surf.ps1 -- CEREBRO PURO do "surf em qualquer regime" (LONG bull / SHORT bear).
# 2026-06-30: Causa raiz de "nada trada em bear" -> sistema bloqueava LONG (faca caindo,
# correto pela Regra #7) mas NUNCA virava SHORT. Este core decide o LADO alinhado ao
# cenario e devolve entry/stop/target/sizing fail-closed. Wiring chama CoinEx-PlaceOrder
# (futures, side=sell p/ SHORT) com o stop OBRIGATORIO ja calculado aqui.
#
# Principios (Regras de Ouro):
#   #1 Stop antes de entrar  -> sem stop computavel = SKIP (nunca entra "nu")
#   #2 Risco 1% por trade    -> sizing risk-based (notional = risco_usd / dist_stop)
#   #3 R:R minimo            -> target = stop_dist * RR
#   #5 Fail-closed           -> dado invalido = SKIP, nunca "passa por default"
#   Surf = entra A FAVOR da tendencia do regime (nao contra): SHORT so em downtrend.

function Resolve-RegimeSurfDecision {
    <#
    .SYNOPSIS
    Decide direcao (LONG/SHORT/SKIP) alinhada ao cenario de mercado + monta o trade.

    .PARAMETER Scenario
    Objeto de Get-MarketScenario: .allow_long, .allow_short, .scenario, .strategy

    .PARAMETER Momentum30dPct
    Momentum 30d em % (confirma tendencia): SHORT exige <0, LONG exige >=0.

    .OUTPUTS
    [pscustomobject] @{
      act; direction (LONG|SHORT|SKIP); entry; stop; target; size_usd;
      risk_usd; rr; scenario; reason
    }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$Market = "",
        $Scenario = $null,
        [double]$Price = 0,
        [double]$Momentum30dPct = 0,
        [double]$LongConviction = 0,
        [double]$ShortConviction = 0,
        [double]$Capital = 0,
        [double]$RiskPct = 1.0,        # % do capital em risco por trade (Regra #2)
        [double]$StopPct = 8.0,        # distancia do stop em %
        [double]$RR = 1.5,             # reward:risk minimo
        [double]$MinConviction = 40    # gate de conviccao p/ o lado escolhido
    )

    function _skip($reason) {
        $scenLabel = "none"
        if ($Scenario) { $scenLabel = "$($Scenario.scenario)" }
        return [pscustomobject]@{
            act=$false; direction="SKIP"; entry=0; stop=0; target=0;
            size_usd=0; risk_usd=0; rr=0;
            scenario=$scenLabel;
            reason=$reason
        }
    }

    # ── Fail-closed: dados invalidos = SKIP (Regra #5) ──
    if (-not $Scenario)            { return (_skip "sem cenario") }
    if ($Price -le 0)              { return (_skip "preco invalido") }
    if ($Capital -le 0)            { return (_skip "capital invalido") }
    if ($StopPct -le 0)            { return (_skip "stop_pct invalido") }
    if ($RiskPct -le 0)            { return (_skip "risk_pct invalido") }

    # ── Lado permitido pelo cenario ──
    $allowLong  = [bool]$Scenario.allow_long
    $allowShort = [bool]$Scenario.allow_short

    if (-not $allowLong -and -not $allowShort) {
        return (_skip "cenario $($Scenario.scenario): caixa (nenhum lado liberado)")
    }

    # ── Escolhe direcao: cenario + tendencia (surf A FAVOR) + conviccao ──
    $direction = "SKIP"
    if ($allowShort -and -not $allowLong) {
        # BEAR: so SHORT, e so se a tendencia confirma (downtrend)
        if ($Momentum30dPct -ge 0) { return (_skip "cenario SHORT mas momentum $Momentum30dPct% nao confirma downtrend") }
        if ($ShortConviction -lt $MinConviction) { return (_skip "short conviction $ShortConviction < $MinConviction") }
        $direction = "SHORT"
    }
    elseif ($allowLong -and -not $allowShort) {
        # BULL/CAPITULACAO: so LONG, e so se nao esta despencando
        if ($Momentum30dPct -lt 0 -and $Scenario.scenario -ne "CAPITULACAO") {
            return (_skip "cenario LONG mas momentum $Momentum30dPct% contradiz")
        }
        if ($LongConviction -lt $MinConviction) { return (_skip "long conviction $LongConviction < $MinConviction") }
        $direction = "LONG"
    }
    else {
        # Ambos liberados (raro): maior conviccao vence
        if ($ShortConviction -gt $LongConviction -and $ShortConviction -ge $MinConviction -and $Momentum30dPct -lt 0) {
            $direction = "SHORT"
        } elseif ($LongConviction -ge $MinConviction -and $Momentum30dPct -ge 0) {
            $direction = "LONG"
        } else {
            return (_skip "ambos liberados mas nenhum lado com edge+tendencia")
        }
    }

    # ── Monta entry/stop/target (Regra #1 + #3) ──
    $entry = $Price
    if ($direction -eq "SHORT") {
        $stop   = $entry * (1 + $StopPct / 100)            # stop ACIMA da entrada
        $target = $entry * (1 - ($StopPct * $RR) / 100)    # alvo ABAIXO
    } else {
        $stop   = $entry * (1 - $StopPct / 100)            # stop ABAIXO da entrada
        $target = $entry * (1 + ($StopPct * $RR) / 100)    # alvo ACIMA
    }

    # ── Sizing risk-based: notional tal que mover ate o stop = RiskPct do capital (Regra #2) ──
    $risk_usd = $Capital * ($RiskPct / 100)
    $size_usd = $risk_usd / ($StopPct / 100)

    return [pscustomobject]@{
        act       = $true
        direction = $direction
        entry     = [math]::Round($entry, 8)
        stop      = [math]::Round($stop, 8)
        target    = [math]::Round($target, 8)
        size_usd  = [math]::Round($size_usd, 2)
        risk_usd  = [math]::Round($risk_usd, 2)
        rr        = $RR
        scenario  = "$($Scenario.scenario)"
        reason    = "$direction surf $($Scenario.scenario) (mom=${Momentum30dPct}%, risco `$$([math]::Round($risk_usd,2)))"
    }
}
