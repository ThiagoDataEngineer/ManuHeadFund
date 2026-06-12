# lib_market_context_engine.ps1 -- Market Context Engine (MCE)
#
# Modula decisoes TA via 6 fatores contextuais:
#   dow_factor      x season_factor x halving_factor x session_factor
#   x macro_factor x regime_factor
#
# Output:
#   - score (produto)
#   - action: BLOCK | PAPER_ONLY | LIVE_REDUCED | LIVE_FULL
#   - size_multiplier
#
# Referencia canonica: knowledge/MARKET_TIMING_BRT.md
#
# PS 5.1. UTF-8 BOM. Funcoes puras (sem I/O).

# ── Constantes hardcoded da referencia canonica ──────────────────────────────

$script:HALVING_2024 = [datetime]"2024-04-19"

$script:FOMC_2026 = @(
    [datetime]"2026-01-28", [datetime]"2026-03-18", [datetime]"2026-04-29",
    [datetime]"2026-06-17", [datetime]"2026-07-29", [datetime]"2026-09-16",
    [datetime]"2026-10-28", [datetime]"2026-12-09"
)

$script:DOW_FACTOR = @{
    "Monday"    = 1.2
    "Tuesday"   = 1.0
    "Wednesday" = 0.9
    "Thursday"  = 0.4   # pior dia, block LONG
    "Friday"    = 1.0
    "Saturday"  = 0.7
    "Sunday"    = 0.8
}

$script:SEASON_FACTOR = @{
    1=1.2; 2=1.3; 3=1.1; 4=1.4
    5=0.5    # Sell in May
    6=0.6
    7=1.1
    8=0.7
    9=0.4    # pior mes
    10=1.3
    11=1.5   # melhor mes
    12=1.0
}

$script:REGIME_FACTOR = @{
    "BULL_STRONG"      = 1.5
    "BULL_WEAK"        = 1.0
    "TRANSITION_UP"    = 1.2
    "SIDEWAYS"         = 0.5
    "TRANSITION_DOWN"  = 0.3
    "BEAR_WEAK"        = 0.2
    "BEAR_STRONG"      = 0.0
    "CAPITULATION"     = 0.0
}


# ── Factor functions ─────────────────────────────────────────────────────────

function Get-DowFactor {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [datetime] $DateBrt)
    $name = $DateBrt.DayOfWeek.ToString()
    if ($script:DOW_FACTOR.ContainsKey($name)) {
        return [double]$script:DOW_FACTOR[$name]
    }
    return 1.0
}


function Get-SeasonalFactor {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [datetime] $DateBrt)
    $m = $DateBrt.Month
    if ($script:SEASON_FACTOR.ContainsKey($m)) {
        return [double]$script:SEASON_FACTOR[$m]
    }
    return 1.0
}


function Get-HalvingFactor {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [datetime] $DateBrt)
    $delta = $DateBrt - $script:HALVING_2024
    $months = [int]([Math]::Floor($delta.TotalDays / 30.44))
    if ($months -lt 0) { return 0.5 }              # pre-halving
    if ($months -le 6)  { return 0.8 }              # acumulacao
    if ($months -le 12) { return 1.3 }              # bull primario
    if ($months -le 18) { return 1.5 }              # blow-off
    if ($months -le 24) { return 0.7 }              # distribuicao
    if ($months -le 36) { return 0.3 }              # bear
    return 0.5                                       # late cycle
}


function Get-HalvingPhase {
    # Categorical (vs Get-HalvingFactor numeric).
    # Validado backtest 14y BTC 2026-05-19:
    #   phase_1_bull (0-12m)   : BULL_WEAK + soft trendline +2.0R avg  -> ALLOW
    #   phase_2_top (12-18m)   : BULL_WEAK -0.4R avg (validado 2025)   -> BLOCK
    #   phase_3_bear (18-30m)  : dados insuficientes -> OBSERVATION
    #   phase_4_recovery (30+) : soft +0.5R avg -> ALLOW reduzido
    [CmdletBinding()]
    param([Parameter(Mandatory)] [datetime] $DateBrt)
    $delta = $DateBrt - $script:HALVING_2024
    $months = $delta.TotalDays / 30.44
    if ($months -lt 0) { return "pre_halving" }
    if ($months -lt 12) { return "phase_1_bull" }
    if ($months -lt 18) { return "phase_2_top" }
    if ($months -lt 30) { return "phase_3_bear" }
    return "phase_4_recovery"
}


function Test-PhaseAllowsBullWeak {
    # Gate strict_v3 phase-aware pra BULL_WEAK LONG.
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Phase)
    $allowed = @("phase_1_bull", "phase_4_recovery")
    return $allowed -contains $Phase
}


function Get-SessionFactor {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [datetime] $DateBrt)
    $h = $DateBrt.Hour
    if ($h -ge 9 -and $h -lt 13)  { return 1.0 }    # golden hours
    if ($h -ge 13 -and $h -lt 16) { return 0.9 }    # NY only
    if ($h -ge 16 -and $h -lt 19) { return 0.7 }    # US close
    if ($h -ge 19 -and $h -lt 22) { return 0.5 }    # Sydney/Tokyo early
    if ($h -ge 22 -or $h -lt 2)   { return 0.6 }    # Asia peak (stop hunts)
    if ($h -ge 2 -and $h -lt 4)   { return 0.4 }    # Asia close
    return 0.8                                       # 04h-09h London open
}


function Get-MacroEventFactor {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [datetime] $DateBrt)
    # FOMC blackout: dia + dia +/- 1 (24h around)
    $dateOnly = $DateBrt.Date
    foreach ($fomc in $script:FOMC_2026) {
        $delta = ($dateOnly - $fomc).TotalDays
        if ([Math]::Abs($delta) -le 1) {
            return 0.0   # BLOCK ±24h FOMC
        }
    }
    # CPI US (dia 10-15 mensal) -- conservador: 12 do mes
    if ($DateBrt.Day -ge 10 -and $DateBrt.Day -le 15) {
        # Apenas reducao moderada (nao sabemos data exata)
        return 0.7
    }
    # NFP (1a sexta do mes) -- pode reduzir
    if ($DateBrt.DayOfWeek -eq "Friday" -and $DateBrt.Day -le 7) {
        return 0.7
    }
    return 1.0
}


function Get-RegimeFactor {
    [CmdletBinding()]
    param([string] $Regime)
    if (-not $Regime) { return 0.5 }   # default conservador
    if ($script:REGIME_FACTOR.ContainsKey($Regime)) {
        return [double]$script:REGIME_FACTOR[$Regime]
    }
    return 0.5
}


# ── Context score + gate ─────────────────────────────────────────────────────

function Get-ContextScore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [datetime] $DateBrt,
        [Parameter(Mandatory)] [string] $Regime
    )
    $dow = Get-DowFactor -DateBrt $DateBrt
    $season = Get-SeasonalFactor -DateBrt $DateBrt
    $halving = Get-HalvingFactor -DateBrt $DateBrt
    $session = Get-SessionFactor -DateBrt $DateBrt
    $macro = Get-MacroEventFactor -DateBrt $DateBrt
    $regime = Get-RegimeFactor -Regime $Regime
    $score = $dow * $season * $halving * $session * $macro * $regime
    return [PSCustomObject]@{
        score    = [Math]::Round($score, 4)
        dow      = $dow
        season   = $season
        halving  = $halving
        session  = $session
        macro    = $macro
        regime   = $regime
        date_brt = $DateBrt
    }
}


function Test-ContextAllowsTrade {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [datetime] $DateBrt,
        [Parameter(Mandatory)] [string] $Regime,
        [Parameter(Mandatory=$false)] [PSCustomObject] $DynamicData = $null
    )
    $ctx = Get-ContextScore -DateBrt $DateBrt -Regime $Regime
    $s = [double]$ctx.score

    # Fatores dinamicos (opcionais — fail-open se ausentes)
    $dynScore = 1.0
    $dynResult = $null
    if ($DynamicData) {
        $dynResult = Get-DynamicContextScore `
            -FearGreed        $DynamicData.fear_greed_score `
            -FundingRate      $DynamicData.funding_rate `
            -EtfFlowMillions  $DynamicData.etf_flow_millions `
            -DxyTrend         $DynamicData.dxy_trend
        $dynScore = $dynResult.dynamic_score
    }

    # Score final = estatico x dinamico (capped 0..3)
    $finalScore = [Math]::Round([Math]::Min(3.0, $s * $dynScore), 4)

    if ($finalScore -lt 0.20)     { $action = "BLOCK";        $mult = 0.0 }
    elseif ($finalScore -lt 0.50) { $action = "PAPER_ONLY";   $mult = 0.0 }
    elseif ($finalScore -lt 1.0)  { $action = "LIVE_REDUCED"; $mult = $finalScore }
    else                          { $action = "LIVE_FULL";     $mult = [Math]::Min(2.0, $finalScore) }

    return [PSCustomObject]@{
        action          = $action
        size_multiplier = [Math]::Round($mult, 2)
        score           = $finalScore
        static_score    = $s
        dynamic_score   = $dynScore
        context         = $ctx
        dynamic_context = $dynResult
    }
}


function Format-ContextSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [PSCustomObject] $Context)
    $c = $Context.context
    return ("CONTEXT={0} | DoW={1} Season={2} Halving={3} Session={4} Macro={5} Regime={6}" -f `
            $Context.score, $c.dow, $c.season, $c.halving, $c.session, $c.macro, $c.regime)
}


# ═══════════════════════════════════════════════════════════════════════════════
# FATORES DINAMICOS — adicionados 2026-05-27
# Fonte: knowledge/ONCHAIN_ANALYSIS.md, MACRO_CONTEXT.md, MARKET_TIMING_BRT.md
# Todos fail-open (retornam 1.0 se dado ausente) — nunca bloqueiam por falta de dado
# ═══════════════════════════════════════════════════════════════════════════════

# ── Get-FearGreedFactor ───────────────────────────────────────────────────────
# Fonte: ONCHAIN_ANALYSIS.md "Fear & Greed Index"
# Extreme Fear = oportunidade historica de compra (Buffett/Tudor Jones)
# Extreme Greed = risco de topo
function Get-FearGreedFactor {
    [CmdletBinding()]
    param([Parameter(Mandatory=$false)] $Score)

    if ($null -eq $Score) { return 1.0 }
    $n = [int]$Score
    if ($n -lt 0 -or $n -gt 100) { return 1.0 }

    if ($n -le 25) { return 1.4 }   # Extreme Fear  — oportunidade historica
    if ($n -le 45) { return 1.2 }   # Fear          — favoravel para entrar
    if ($n -le 55) { return 1.0 }   # Neutral       — sem ajuste
    if ($n -le 75) { return 0.8 }   # Greed         — cautela
    return 0.5                       # Extreme Greed — risco de topo
}


# ── Get-FundingRateFactor ─────────────────────────────────────────────────────
# Fonte: ONCHAIN_ANALYSIS.md "Funding Rate (Futuros Perpetuos)"
# Funding muito negativo = excesso de shorts = short squeeze iminente = bullish
# Funding muito positivo = excesso de longs = risco de liquidacao = bearish
function Get-FundingRateFactor {
    [CmdletBinding()]
    param([Parameter(Mandatory=$false)] $Rate)

    if ($null -eq $Rate) { return 1.0 }
    $r = [double]$Rate

    if ($r -le -0.05)  { return 1.3 }   # Muito negativo — short squeeze iminente
    if ($r -le  0.05)  { return 1.0 }   # Neutro         — mercado equilibrado
    if ($r -le  0.10)  { return 0.8 }   # Positivo       — longs excessivos
    return 0.6                           # Muito positivo — risco de liquidacao
}


# ── Get-EtfFlowFactor ─────────────────────────────────────────────────────────
# Fonte: MACRO_CONTEXT.md "ETFs e Fluxos Institucionais"
# ETF inflow = demanda institucional real = bullish estrutural
# ETF outflow = saida institucional = pressao vendedora
function Get-EtfFlowFactor {
    [CmdletBinding()]
    param([Parameter(Mandatory=$false)] $FlowMillions)

    if ($null -eq $FlowMillions) { return 1.0 }
    $f = [double]$FlowMillions

    if ($f -ge  200) { return 1.3 }   # Inflow forte    — demanda institucional real
    if ($f -ge    0) { return 1.1 }   # Inflow moderado — neutro positivo
    if ($f -ge -200) { return 0.8 }   # Outflow moderado — pressao vendedora
    return 0.5                         # Outflow forte   — saida institucional significativa
}


# ── Get-DxyFactor ─────────────────────────────────────────────────────────────
# Fonte: MACRO_CONTEXT.md "DXY (US Dollar Index)" — correlacao -0.65 a -0.75
# DXY fraco = capital migra para ativos alternativos incluindo BTC
# DXY forte = capital volta para dolar = pressao em crypto
function Get-DxyFactor {
    [CmdletBinding()]
    param([Parameter(Mandatory=$false)] [string] $Trend)

    if (-not $Trend) { return 1.0 }

    switch ($Trend) {
        "DOWN"      { return 1.2 }   # Dolar fraco — bullish crypto
        "FLAT"      { return 1.0 }   # Lateral     — sem ajuste
        "UP"        { return 0.8 }   # Dolar forte — pressao em crypto
        "UP_STRONG" { return 0.6 }   # Dolar muito forte (> 105) — ambiente desfavoravel
        default     { return 1.0 }   # Desconhecido — fail-open
    }
}


# ── Get-DynamicContextScore ───────────────────────────────────────────────────
# Produto dos 4 fatores dinamicos. Capped em 2.0 para nao amplificar demais.
function Get-DynamicContextScore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)] $FearGreed,
        [Parameter(Mandatory=$false)] $FundingRate,
        [Parameter(Mandatory=$false)] $EtfFlowMillions,
        [Parameter(Mandatory=$false)] [string] $DxyTrend
    )

    $fg  = Get-FearGreedFactor   -Score        $FearGreed
    $fr  = Get-FundingRateFactor -Rate         $FundingRate
    $etf = Get-EtfFlowFactor     -FlowMillions $EtfFlowMillions
    $dxy = Get-DxyFactor         -Trend        $DxyTrend

    $raw = $fg * $fr * $etf * $dxy
    $capped = [Math]::Round([Math]::Min(2.0, $raw), 4)

    return [PSCustomObject]@{
        dynamic_score = $capped
        fear_greed    = $fg
        funding_rate  = $fr
        etf_flow      = $etf
        dxy           = $dxy
        raw           = [Math]::Round($raw, 4)
    }
}


# ── Get-DynamicContextData ────────────────────────────────────────────────────
# Busca dados reais das APIs publicas. Fail-open em todos os campos.
# APIs: alternative.me (Fear&Greed), CoinEx (funding), SoSoValue (ETF), FRED (DXY)
function Get-DynamicContextData {
    [CmdletBinding()]
    param(
        [int] $TimeoutSec = 8,
        [string] $CacheFile = ""
    )

    $result = [PSCustomObject]@{
        fear_greed_score  = $null
        funding_rate      = $null
        etf_flow_millions = $null
        dxy_trend         = $null
        source            = @{}
        fetched_at        = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        errors            = @()
    }

    # ── 1. Fear & Greed Index (alternative.me — gratuito, sem auth) ──────────
    try {
        $r = Invoke-RestMethod -Uri "https://api.alternative.me/fng/?limit=1" `
            -TimeoutSec $TimeoutSec -ErrorAction Stop
        if ($r.data -and $r.data[0].value) {
            $result.fear_greed_score = [int]$r.data[0].value
            $result.source.fear_greed = "alternative.me"
        }
    } catch {
        $result.errors += "fear_greed: $($_.Exception.Message.Substring(0,[Math]::Min(60,$_.Exception.Message.Length)))"
    }

    # ── 2. Funding Rate BTC (CoinEx API — ja usada no projeto) ───────────────
    try {
        $apiKey = $env:COINEX_ACCESS_ID
        $url = "https://api.coinex.com/v2/futures/funding-rate?market=BTCUSDT"
        $r = Invoke-RestMethod -Uri $url -TimeoutSec $TimeoutSec -ErrorAction Stop
        if ($r.code -eq 0 -and $r.data) {
            $rate = [double]$r.data.latest_funding_rate
            $result.funding_rate = $rate
            $result.source.funding_rate = "coinex"
        }
    } catch {
        $result.errors += "funding_rate: $($_.Exception.Message.Substring(0,[Math]::Min(60,$_.Exception.Message.Length)))"
    }

    # ── 3. ETF Flow BTC (SoSoValue API — gratuito) ───────────────────────────
    try {
        $r = Invoke-RestMethod -Uri "https://sosovalue.com/api/etf/us-btc-spot/flow-history?limit=1" `
            -TimeoutSec $TimeoutSec -ErrorAction Stop
        if ($r.data -and $r.data[0]) {
            $flow = [double]$r.data[0].totalNetInflow
            $result.etf_flow_millions = [Math]::Round($flow / 1000000, 1)
            $result.source.etf_flow = "sosovalue"
        }
    } catch {
        # Fallback: Coinglass (alternativa publica)
        try {
            $r2 = Invoke-RestMethod -Uri "https://open-api.coinglass.com/public/v2/etf/bitcoin/flow" `
                -TimeoutSec $TimeoutSec -ErrorAction Stop
            if ($r2.data) {
                $flow = [double]$r2.data.totalNetInflow
                $result.etf_flow_millions = [Math]::Round($flow / 1000000, 1)
                $result.source.etf_flow = "coinglass"
            }
        } catch {
            $result.errors += "etf_flow: indisponivel"
        }
    }

    # ── 4. DXY Trend (FRED API — gratuito com key, ou Yahoo Finance) ─────────
    try {
        $fredKey = $env:FRED_API_KEY
        if ($fredKey) {
            # FRED: serie DTWEXBGS (DXY proxy — Broad Dollar Index)
            $url = "https://api.stlouisfed.org/fred/series/observations?series_id=DTWEXBGS&limit=5&sort_order=desc&api_key=$fredKey&file_type=json"
            $r = Invoke-RestMethod -Uri $url -TimeoutSec $TimeoutSec -ErrorAction Stop
            if ($r.observations -and $r.observations.Count -ge 2) {
                $latest = [double]$r.observations[0].value
                $prev   = [double]$r.observations[4].value  # 5 dias atras
                $changePct = ($latest - $prev) / $prev * 100

                $result.dxy_trend = if ($changePct -gt 1.5)      { "UP_STRONG" }
                                    elseif ($changePct -gt 0.3)  { "UP" }
                                    elseif ($changePct -lt -0.3) { "DOWN" }
                                    else                          { "FLAT" }
                $result.source.dxy = "fred"
            }
        }
    } catch {
        $result.errors += "dxy: $($_.Exception.Message.Substring(0,[Math]::Min(60,$_.Exception.Message.Length)))"
    }

    # Cache opcional (para evitar chamadas repetidas no mesmo ciclo)
    if ($CacheFile) {
        try {
            $result | ConvertTo-Json -Depth 3 | Out-File $CacheFile -Encoding UTF8 -Force
        } catch {}
    }

    return $result
}
