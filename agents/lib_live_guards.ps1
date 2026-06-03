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
