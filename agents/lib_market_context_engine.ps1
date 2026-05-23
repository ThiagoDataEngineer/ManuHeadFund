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
        [Parameter(Mandatory)] [string] $Regime
    )
    $ctx = Get-ContextScore -DateBrt $DateBrt -Regime $Regime
    $s = [double]$ctx.score

    if ($s -lt 0.20)         { $action = "BLOCK";       $mult = 0.0 }
    elseif ($s -lt 0.50)     { $action = "PAPER_ONLY";  $mult = 0.0 }
    elseif ($s -lt 1.0)      { $action = "LIVE_REDUCED";$mult = $s }
    else                      { $action = "LIVE_FULL";   $mult = [Math]::Min(2.0, $s) }

    return [PSCustomObject]@{
        action          = $action
        size_multiplier = [Math]::Round($mult, 2)
        score           = $s
        context         = $ctx
    }
}


function Format-ContextSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [PSCustomObject] $Context)
    $c = $Context.context
    return ("CONTEXT={0} | DoW={1} Season={2} Halving={3} Session={4} Macro={5} Regime={6}" -f `
            $Context.score, $c.dow, $c.season, $c.halving, $c.session, $c.macro, $c.regime)
}
