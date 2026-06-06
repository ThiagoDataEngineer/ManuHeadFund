# lib_volatility_filter.ps1 — Volatilidade: bloqueia entrada barulhenta ou reduz size

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

function Test-VolatilityAcceptable {
    <#
    .SYNOPSIS
    Verifica se volatilidade está aceitável pra entrada.
    Bloqueia se vol > 5%, reduz se vol 3-5%, OK se < 3%.
    #>
    param(
        [Parameter(Mandatory)] [double] $VolatilityChange5mPct,
        [Parameter(Mandatory)] [string] $Market,
        [string] $JournalDir = $global:JOURNAL_DIR
    )

    if (-not (Test-Path $JournalDir)) {
        New-Item -ItemType Directory -Path $JournalDir -Force | Out-Null
    }

    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $filterLogPath = Join-Path $JournalDir "volatility_filter_audit.jsonl"

    # Decisão
    $passes = $VolatilityChange5mPct -le 5
    $action = if ($VolatilityChange5mPct -gt 5) {
        "BLOCK"
    } elseif ($VolatilityChange5mPct -gt 3) {
        "REDUCE"
    } else {
        "OK"
    }

    $sizeMultiplier = switch ($action) {
        "BLOCK" { 0.0 }      # Não entra
        "REDUCE" { 0.5 }     # Reduz 50%
        "OK" { 1.0 }         # Normal
    }

    # Log
    $entry = [ordered]@{
        timestamp = $timestamp
        market = $Market
        volatility_5m_pct = [Math]::Round($VolatilityChange5mPct, 2)
        action = $action
        size_multiplier = $sizeMultiplier
        passes = $passes
    } | ConvertTo-Json -Compress

    Add-Content -Path $filterLogPath -Value $entry -Encoding UTF8

    return [PSCustomObject]@{
        market = $Market
        volatility_5m_pct = [Math]::Round($VolatilityChange5mPct, 2)
        action = $action
        size_multiplier = $sizeMultiplier
        passes = $passes
        timestamp = $timestamp
    }
}

function Get-VolatilityTrend {
    <#
    .SYNOPSIS
    Detecta se volatilidade está AUMENTANDO (trending up) ou caindo (trending down).
    Util pra evitar entrada quando vol está subindo.
    #>
    param(
        [Parameter(Mandatory)] [array] $VolatilityHistory,  # Últimos 3-5 candles
        [string] $Market
    )

    if ($VolatilityHistory.Count -lt 2) {
        return [PSCustomObject]@{
            market = $Market
            trend = "UNKNOWN"
            direction = 0  # 0 = flat, 1 = up, -1 = down
        }
    }

    $first = [double]$VolatilityHistory[0]
    $last = [double]$VolatilityHistory[-1]
    $change = $last - $first

    $direction = if ($change -gt 0.5) { 1 } elseif ($change -lt -0.5) { -1 } else { 0 }
    $trend = switch ($direction) {
        1 { "INCREASING" }
        -1 { "DECREASING" }
        default { "FLAT" }
    }

    return [PSCustomObject]@{
        market = $Market
        first_vol = [Math]::Round($first, 2)
        last_vol = [Math]::Round($last, 2)
        change = [Math]::Round($change, 2)
        trend = $trend
        direction = $direction
    }
}
