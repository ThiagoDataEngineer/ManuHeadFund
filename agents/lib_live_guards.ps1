# lib_live_guards.ps1 -- 4 guards de seguranca para Mode 2 LIVE
#
# 1. SIZING CAP        -- max $X por trade (override do risk_pct)
# 2. FREQUENCY CAP     -- max N trades/semana (circuit breaker)
# 3. TIER FILTER       -- so Tier A LIVE pode executar real
# 4. CUSTODIAL CAP     -- exchange balance / total_capital <= 30%
#
# Cada guard retorna {pass=$true|$false, reason=string}
# Guard MASTER consolida todos antes de permitir ordem real.
#
# Estado persistido em journal/live_guards_state.json (trades/semana counter).

$LIVE_GUARDS_FILE = (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "journal") "live_guards_state.json")


function Get-LiveGuardsState {
    if (-not (Test-Path $LIVE_GUARDS_FILE)) {
        return [PSCustomObject]@{
            week_start    = (Get-Date -Hour 0 -Minute 0 -Second 0).ToString("o")
            trades_this_week = 0
            last_trade_ts = $null
        }
    }
    try {
        return Get-Content $LIVE_GUARDS_FILE -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return [PSCustomObject]@{
            week_start    = (Get-Date -Hour 0 -Minute 0 -Second 0).ToString("o")
            trades_this_week = 0
            last_trade_ts = $null
        }
    }
}


function Save-LiveGuardsState {
    param([PSObject]$State)
    $dir = Split-Path $LIVE_GUARDS_FILE
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $State | ConvertTo-Json -Depth 5 | Set-Content -Path $LIVE_GUARDS_FILE -Encoding UTF8
}


function Reset-LiveGuardsIfNewWeek {
    param([PSObject]$State)
    try {
        $weekStart = [DateTime]::Parse($State.week_start)
        $now = Get-Date
        $weekEnd = $weekStart.AddDays(7)
        if ($now -ge $weekEnd) {
            $State.week_start = (Get-Date -Hour 0 -Minute 0 -Second 0).ToString("o")
            $State.trades_this_week = 0
            Save-LiveGuardsState -State $State
        }
    } catch {}
    return $State
}


# â”€â”€ Guard 1: Sizing cap â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function Test-SizingCap {
    [CmdletBinding()]
    param(
        [double]$ProposedSizeUsd,
        [double]$MaxSizeUsd = 50.0
    )
    if ($ProposedSizeUsd -le $MaxSizeUsd) {
        return [PSCustomObject]@{ pass = $true; reason = "sizing OK ($ProposedSizeUsd <= $MaxSizeUsd)" }
    }
    return [PSCustomObject]@{
        pass = $false
        reason = "BLOCKED sizing: proposto `$$ProposedSizeUsd > cap `$$MaxSizeUsd"
    }
}


function Resolve-SizingClamp {
    # 2026-07-08: overage pequeno (<=TolerancePct) clampa pro cap em vez de deixar
    # o guard matar o trade inteiro (ex.: $102.75 > $100 = 8 blocks em 07-07/08).
    # Overage acima da tolerancia NAO clampa -> Test-SizingCap bloqueia (fail-closed
    # p/ sizing genuinamente errado). Nunca aumenta size.
    [CmdletBinding()]
    param(
        [double]$ProposedSizeUsd,
        [double]$MaxSizeUsd,
        [double]$TolerancePct = 10.0
    )
    $clamped = $false
    $size = $ProposedSizeUsd
    if ($MaxSizeUsd -gt 0 -and $size -gt $MaxSizeUsd -and $size -le ($MaxSizeUsd * (1 + $TolerancePct / 100))) {
        $size = $MaxSizeUsd
        $clamped = $true
    }
    return [PSCustomObject]@{ size_usd = $size; clamped = $clamped }
}


function Resolve-EffectiveSizingCap {
    # 2026-08-07 FIX CRITICO: existiam 2 tetos de sizing desconectados --
    # o cap fixo em dolar (MaxSizeUsd, historico desde o commit inicial
    # 05-22, quando o projeto ainda nao tinha % dinamico de capital) rodava
    # PRIMEIRO em Test-LiveTradeGuards e BLOQUEAVA (return, mata o trade
    # inteiro) antes do "HARD CAP DE RISCO 3%" (gem_executor.ps1, adicionado
    # 2026-07-24, a Regra de Ouro real) ter qualquer chance de rodar -- esse
    # so clampa (reduz o tamanho, nunca cancela). Achado real: XRPUSDT
    # propos $142.09 com capital=$2560 (=5.5%, quase 2x a Regra de Ouro de
    # 3%=$76.80) e foi INTEIRAMENTE DESCARTADO pelo cap fixo de $100, que
    # e mais restritivo que 3% pra qualquer capital abaixo de ~$3333.
    #
    # Fix: o teto EFETIVO usado pelo guard de bloqueio (Test-SizingCap) e
    # pela tolerancia de clamp (Resolve-SizingClamp) passa a ser o MENOR
    # entre o cap fixo em dolar e 3% do capital atual -- nunca deixa a
    # Regra de Ouro perder pra um cap fixo esquecido, mas tambem nunca
    # relaxa o cap fixo pra cima (se 3% do capital for MAIOR que o cap
    # fixo, o cap fixo continua valendo -- protege capitais grandes de
    # trades desproporcionais de qualquer forma).
    [CmdletBinding()]
    param(
        [double]$FixedCapUsd,
        [double]$Capital,
        [double]$RiskPct = 0.03
    )
    if ($Capital -le 0) {
        # capital indisponivel -- fail-safe, usa so o cap fixo (nao
        # inventa um teto de 3% de um valor que nao existe).
        return [PSCustomObject]@{ cap_usd = $FixedCapUsd; source = "fixed_only_no_capital" }
    }
    $riskCapUsd = [math]::Round($Capital * $RiskPct, 2)
    if ($riskCapUsd -lt $FixedCapUsd) {
        return [PSCustomObject]@{ cap_usd = $riskCapUsd; source = "risk_pct" }
    }
    return [PSCustomObject]@{ cap_usd = $FixedCapUsd; source = "fixed" }
}


function Resolve-GoldenRuleSizeClamp {
    # 2026-08-07 FIX CRITICO: gem_executor.ps1 calcula $usd_size logo no
    # inicio (dynamic_feedback/kelly/legacy_pct), mas gates de bloqueio
    # (ex: Test-CoinExposureCap "cap_por_moeda", ~130 linhas depois no
    # arquivo) rodavam contra esse valor CRU, antes do clamp de 3% (a
    # Regra de Ouro, "HARD CAP DE RISCO 3%" mais abaixo no arquivo) ter
    # qualquer chance de reduzir o tamanho. Achado real: SOLUSDT propos
    # usd_size~$237 (=10.11% de capital=$2345.92, mais que o triplo de 3%)
    # e foi bloqueado por inteiro pelo exposure cap repetidamente, ciclo
    # apos ciclo, mesmo quando o Mentor aprovava o setup -- nunca chegava
    # a ser clampado pra um tamanho que passaria no gate.
    #
    # Pure: recebe o usd_size proposto e o capital, devolve o valor
    # clampado (nunca aumenta, so reduz se exceder RiskPct do capital).
    # Sem nocao de cap fixo em dolar -- esse ponto do fluxo nao tem
    # nenhum concorrente (diferente de Resolve-EffectiveSizingCap, usado
    # mais tarde no mesmo arquivo onde ha um cap fixo historico tambem
    # em jogo).
    [CmdletBinding()]
    param(
        [double]$ProposedUsd,
        [double]$Capital,
        [double]$RiskPct = 0.03
    )
    if ($Capital -le 0 -or $ProposedUsd -le 0) {
        # dado indisponivel/invalido -- fail-safe, nao mexe no valor
        # (nao inventa teto de um capital que nao existe, nao bloqueia
        # por engano um caller que passou 0 de proposito).
        return [PSCustomObject]@{ usd_size = $ProposedUsd; clamped = $false }
    }
    $capUsd = [math]::Round($Capital * $RiskPct, 2)
    if ($ProposedUsd -gt $capUsd) {
        return [PSCustomObject]@{ usd_size = $capUsd; clamped = $true }
    }
    return [PSCustomObject]@{ usd_size = $ProposedUsd; clamped = $false }
}


# â”€â”€ Guard 2: Frequency cap â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function Test-FrequencyCap {
    [CmdletBinding()]
    param([int]$MaxTradesPerWeek = 5)
    $state = Get-LiveGuardsState
    $state = Reset-LiveGuardsIfNewWeek -State $state
    if ($state.trades_this_week -lt $MaxTradesPerWeek) {
        return [PSCustomObject]@{
            pass = $true
            reason = "freq OK ($($state.trades_this_week)/$MaxTradesPerWeek esta semana)"
        }
    }
    return [PSCustomObject]@{
        pass = $false
        reason = "BLOCKED freq: $($state.trades_this_week) trades esta semana >= cap $MaxTradesPerWeek"
    }
}


function Register-LiveTrade {
    $state = Get-LiveGuardsState
    $state = Reset-LiveGuardsIfNewWeek -State $state
    $state.trades_this_week += 1
    $state.last_trade_ts = (Get-Date).ToString("o")
    Save-LiveGuardsState -State $state
}


# â”€â”€ Guard 3: Tier filter â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function Test-TierGuard {
    [CmdletBinding()]
    param(
        [string]$Market,
        [string]$AllowedMode = "LIVE"   # LIVE = sÃ³ Tier A | PAPER = A+B | ANY = sem filtro
    )
    if ($AllowedMode -eq "ANY") {
        return [PSCustomObject]@{ pass = $true; reason = "$Market sem filtro tier (DISCOVERY mode)" }
    }
    if (-not (Get-Command Get-QuantWhitelistMarkets -ErrorAction SilentlyContinue)) {
        return [PSCustomObject]@{ pass = $false; reason = "lib_quant_whitelist nao carregada" }
    }
    $allowed = @(Get-QuantWhitelistMarkets -Mode $AllowedMode)
    if ($allowed -contains $Market) {
        return [PSCustomObject]@{ pass = $true; reason = "$Market eh Tier $AllowedMode" }
    }
    return [PSCustomObject]@{
        pass = $false
        reason = "BLOCKED tier: $Market NAO esta em Tier $AllowedMode whitelist"
    }
}


# â”€â”€ Guard 4: Custodial cap â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function Test-CustodialCap {
    # 2026-05-18: guard desativado por design (privacy + responsabilidade user).
    # Sistema nao rastreia capital fora da CoinEx. User gerencia exposicao
    # exchange conscientemente (FTX-lesson eh decisao, nao policial automated).
    [CmdletBinding()]
    param(
        [double]$ExchangeBalanceUsd,
        [double]$TotalCapitalUsd,
        [double]$MaxRatio = 0.30
    )
    return [PSCustomObject]@{
        pass = $true
        reason = "custodial cap DESATIVADO (privacy/responsabilidade user)"
    }
}


# â”€â”€ Master â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function Test-LiveTradeGuards {
    [CmdletBinding()]
    param(
        [string]$Market,
        [double]$ProposedSizeUsd,
        [double]$ExchangeBalanceUsd,
        [double]$TotalCapitalUsd,
        [double]$MaxSizeUsd          = 50.0,
        [int]   $MaxTradesPerWeek    = 5,
        [string]$AllowedTierMode     = "LIVE",
        [double]$MaxCustodialRatio   = 0.30
    )
    $checks = @()
    $checks += Test-SizingCap     -ProposedSizeUsd $ProposedSizeUsd -MaxSizeUsd $MaxSizeUsd
    $checks += Test-FrequencyCap  -MaxTradesPerWeek $MaxTradesPerWeek
    $checks += Test-TierGuard     -Market $Market -AllowedMode $AllowedTierMode
    $checks += Test-CustodialCap  -ExchangeBalanceUsd $ExchangeBalanceUsd `
                                    -TotalCapitalUsd $TotalCapitalUsd `
                                    -MaxRatio $MaxCustodialRatio

    $failed = @($checks | Where-Object { -not $_.pass })
    $passed = ($failed.Count -eq 0)
    return [PSCustomObject]@{
        pass    = $passed
        checks  = $checks
        reasons = @($checks | ForEach-Object { $_.reason })
        blocked_by = @($failed | ForEach-Object { $_.reason })
    }
}
