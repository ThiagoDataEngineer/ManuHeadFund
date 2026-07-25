# lib_short_executor.ps1 -- EXECUTOR SHORT (futures).
#
# Estado (2026-07-25): LIVE via scripts/short_scanner.ps1, que chama
# Build-ShortOrderPlan/Test-ShortLiveGate/Test-ShortEntryReady diretamente
# (Invoke-ShortEntry abaixo e um wrapper alternativo, nao usado pelo scanner
# real). Chaves de ativacao (config/short_universe.json, git-tracked):
#   1. live_enabled=true (ativo desde 2026-07-09), E
#   2. market em tier_a_live (15 majors liquidos).
# Sem as duas, Test-ShortLiveGate NEGA -> so observa/loga (nao envia ordem).
# Protecoes: Tori gate >=80, Mesa consensus, capital_safety sizing cap,
# dedup posicao, funding-squeeze guard (2026-07-25, Test-ShortFundingSafe).
#
# Respeita Regras de Ouro: stop ANTES da entrada, risco <=1%/trade, R:R >=1:5,
# fail-closed (plano invalido = nao opera).

. (Join-Path $PSScriptRoot "lib_leverage_cap.ps1")  # 2026-07-19: Oracle Bug #15 -- cap 5x antes de ordem futures real
. (Join-Path $PSScriptRoot "lib_coinex_position_management.ps1")

# ----------------------------------------------------------------------------
# Build-ShortOrderPlan -- PURO. Converte candidato em plano de ordem SHORT validado.
# SHORT: stop ACIMA da entrada; alvo ABAIXO. Loss no stop = Capital*RiskPct.
# ----------------------------------------------------------------------------
function Build-ShortOrderPlan {
    [CmdletBinding()]
    param(
        [double]$EntryPrice,
        [double]$Capital,
        [double]$Atr = 0,
        [double]$RiskPct = 0.01,
        [double]$AtrMult = 2.0,
        [double]$RR = 5.0,
        [double]$MaxLeverage = 10.0,
        [double]$StopPctFallback = 0.05
    )

    function _invalid($reason) {
        return [PSCustomObject]@{
            side = "sell"; valid = $false; reason = $reason
            entry = $EntryPrice; stop = 0.0; target = 0.0
            notional_usd = 0.0; amount = 0.0; leverage = 0.0; risk_usd = 0.0; stop_dist_pct = 0.0; rr = $RR
        }
    }

    if ($EntryPrice -le 0) { return (_invalid "entry_price<=0") }
    if ($Capital -le 0)    { return (_invalid "capital<=0") }
    if ($RiskPct -le 0)    { return (_invalid "risk_pct<=0") }

    $stopDist = if ($Atr -gt 0) { $AtrMult * $Atr } else { $StopPctFallback * $EntryPrice }
    if ($stopDist -le 0) { return (_invalid "stop_dist<=0") }

    $stop        = $EntryPrice + $stopDist           # SHORT: stop ACIMA
    $stopDistPct = $stopDist / $EntryPrice
    $riskUsd     = $Capital * $RiskPct
    $notional    = $riskUsd / $stopDistPct
    $leverage    = $notional / $Capital
    $reason      = "ok"

    if ($leverage -gt $MaxLeverage) {
        # clamp p/ teto de alavancagem (reduz notional -> risco efetivo < alvo, mais seguro)
        $notional = $Capital * $MaxLeverage
        $leverage = $MaxLeverage
        $reason   = "leverage_capped"
    }

    $amount = $notional / $EntryPrice
    $target = $EntryPrice - ($RR * $stopDist)         # SHORT: alvo ABAIXO

    $valid = $true
    if ($target -le 0) { $valid = $false; $reason = "target_below_zero (stop muito largo p/ RR $RR)" }

    return [PSCustomObject]@{
        side = "sell"; valid = $valid; reason = $reason
        entry = $EntryPrice; stop = $stop; target = $target
        notional_usd = [math]::Round($notional, 2); amount = $amount
        leverage = [math]::Round($leverage, 2); risk_usd = [math]::Round($riskUsd, 2)
        stop_dist_pct = [math]::Round($stopDistPct, 4); rr = $RR
    }
}

# ----------------------------------------------------------------------------
# Test-ShortLiveGate -- PURO. So permite ordem SHORT real com as DUAS chaves.
# ----------------------------------------------------------------------------
function Test-ShortLiveGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Market,
        [bool]$FlagPresent = $false,
        [string[]]$ShortTierA = @()
    )
    $inTier = ($ShortTierA -contains $Market)
    $allow  = ($FlagPresent -and $inTier)
    $reason = "ok"
    if (-not $FlagPresent) { $reason = "no_live_flag" }
    elseif (-not $inTier)  { $reason = "not_in_short_tier_a" }
    return [PSCustomObject]@{ allow = $allow; flag = $FlagPresent; in_tier = $inTier; reason = $reason }
}

# ----------------------------------------------------------------------------
# Test-ShortEntryReady -- PURO. Consolida TODOS os gates antes de ordem real.
# Espelha a stack do LONG: plano valido + gate live + tier S + sem cluster cap +
# sem posicao aberta + capital safety ok. Qualquer falha -> nao opera (fail-closed).
# ----------------------------------------------------------------------------
function Test-ShortEntryReady {
    [CmdletBinding()]
    param(
        [bool]$PlanValid = $false,
        [bool]$GateAllow = $false,
        [string]$Tier = "",
        [bool]$ClusterExceeded = $false,
        [bool]$HasPosition = $false,
        [bool]$CapitalSafe = $false,
        [bool]$RequireTierS = $true,
        [bool]$FundingSafe = $false
    )
    $reasons = @()
    if (-not $PlanValid)                       { $reasons += "invalid_plan" }
    if (-not $GateAllow)                        { $reasons += "gate_denied" }
    if ($RequireTierS -and $Tier -ne "S")      { $reasons += "tier_not_S($Tier)" }
    if ($ClusterExceeded)                       { $reasons += "cluster_cap" }
    if ($HasPosition)                           { $reasons += "position_exists" }
    if (-not $CapitalSafe)                      { $reasons += "capital_unsafe" }
    if (-not $FundingSafe)                      { $reasons += "funding_squeeze_risk" }
    return [PSCustomObject]@{ ready = ($reasons.Count -eq 0); reason = ($reasons -join ",") }
}

# ----------------------------------------------------------------------------
# Test-ShortFundingSafe -- PURO. Protecao contra short squeeze coordenado
# (knowledge/MANIPULATION.md: funding muito negativo = shorts lotados = risco
# de squeeze -- "nunca manter short grande quando funding esta muito negativo").
# Fail-closed: funding indisponivel (null) = nao seguro, bloqueia por padrao.
# ----------------------------------------------------------------------------
function Test-ShortFundingSafe {
    [CmdletBinding()]
    param(
        [Nullable[double]]$FundingRate = $null,
        [double]$MinFundingRate = -0.0005
    )
    if ($null -eq $FundingRate) {
        return [PSCustomObject]@{ safe = $false; reason = "funding_unavailable" }
    }
    if ($FundingRate -lt $MinFundingRate) {
        return [PSCustomObject]@{ safe = $false; reason = "funding_too_negative_${FundingRate}_squeeze_risk" }
    }
    return [PSCustomObject]@{ safe = $true; reason = "ok" }
}

# ----------------------------------------------------------------------------
# Invoke-ShortEntry -- wrapper gateado. DRY/observe por padrao. NAO esta wired.
# Ativar = criar SHORT_LIVE_ENABLED.flag + por o market em SHORT_TIER_A_LIVE.
# ----------------------------------------------------------------------------
function Invoke-ShortEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Market,
        [Parameter(Mandatory=$true)][double]$EntryPrice,
        [Parameter(Mandatory=$true)][double]$Capital,
        [double]$Atr = 0,
        [string[]]$ShortTierA = @(),
        [string]$FlagDir = $null
    )

    $plan = Build-ShortOrderPlan -EntryPrice $EntryPrice -Capital $Capital -Atr $Atr
    if (-not $plan.valid) {
        Write-Host "  [SHORT SKIP] ${Market}: plano invalido ($($plan.reason))" -ForegroundColor DarkYellow
        return [PSCustomObject]@{ placed = $false; observed = $false; reason = "invalid_plan:$($plan.reason)"; plan = $plan }
    }

    $flagPresent = $false
    if ($FlagDir) { $flagPresent = (Test-Path (Join-Path $FlagDir "SHORT_LIVE_ENABLED.flag")) }
    $gate = Test-ShortLiveGate -Market $Market -FlagPresent $flagPresent -ShortTierA $ShortTierA

    if (-not $gate.allow) {
        Write-Host "  [SHORT OBSERVE] ${Market}: shortaria @ $($plan.entry) stop $($plan.stop) alvo $($plan.target) (gate: $($gate.reason))" -ForegroundColor DarkCyan
        return [PSCustomObject]@{ placed = $false; observed = $true; reason = "gate:$($gate.reason)"; plan = $plan }
    }

    # LIVE: as duas chaves presentes. Coloca ordem futures SHORT (side=sell).
    if (-not (Get-Command CoinEx-PlaceOrder -ErrorAction SilentlyContinue)) {
        return [PSCustomObject]@{ placed = $false; observed = $false; reason = "no_placeorder_fn"; plan = $plan }
    }

    # Leverage cap (Oracle Bug #15): POST /futures/order NAO carrega leverage no
    # payload -- corretora usa o que ja estiver na conta. Fail-closed: se o ajuste
    # falhar, bloqueia a ordem em vez de herdar leverage desconhecida.
    $__safeLeverage = if (Get-Command Get-SafeLeverage -ErrorAction SilentlyContinue) {
        [int](Get-SafeLeverage -RequestedLeverage $plan.leverage -Mode "STANDARD")
    } else { 2 }
    $__levResult = if (Get-Command CoinEx-AdjustPositionLeverage -ErrorAction SilentlyContinue) {
        CoinEx-AdjustPositionLeverage -Market $Market -Leverage $__safeLeverage -MarginMode "isolated"
    } else { [PSCustomObject]@{ success = $false; error_msg = "CoinEx-AdjustPositionLeverage indisponivel" } }
    if (-not $__levResult.success) {
        return [PSCustomObject]@{ placed = $false; observed = $false; reason = "leverage_adjust_failed:$($__levResult.error_msg)"; plan = $plan }
    }

    $res = CoinEx-PlaceOrder $Market "sell" "market" $plan.amount $null $plan.stop $plan.target
    Write-Host "  [SHORT LIVE] ${Market}: ordem SHORT enviada (amount $($plan.amount))" -ForegroundColor Red
    return [PSCustomObject]@{ placed = $true; observed = $false; reason = "live"; plan = $plan; order = $res }
}
