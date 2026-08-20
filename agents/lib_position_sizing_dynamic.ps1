# lib_position_sizing_dynamic.ps1 — Position Sizing: Beta * Confluence dinâmico
# PROBLEMA: hoje 1% fixo = não protege em HIGH volatilidade + não aproveita confluência FORTE
# SOLUÇÃO: ajusta size por (beta_pct * confluence_score * regime_multiplier)

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

function Invoke-DynamicPositionSize {
    <#
    .SYNOPSIS
    Calcula position size dinâmico baseado em:
      - Beta do ativo (vol vs BTC)
      - Confluência multi-sinal (3/5 = 0.6x, 5/5 = 1.0x)
      - Regime (BULL = 1.0x, BEAR = 0.5x, SIDEWAYS = 0.7x)
      - Account equity

    Formula:
      position_size = (account_equity * base_pct) * beta_multiplier * confluence_multiplier * regime_multiplier
    #>
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [double] $AccountEquityUsd,
        [Parameter(Mandatory)] [double] $BetaVsBtc,  # 0.5-2.0 (0.5=stable, 2.0=volatile)
        [Parameter(Mandatory)] [int] $ConfluenceCount,  # 3/5 to 5/5
        [string] $Regime = "SIDEWAYS",  # BULL, BEAR, SIDEWAYS
        [double] $BasePct = 0.01,  # 1% base
        [string] $JournalDir = $global:JOURNAL_DIR,
        [datetime] $Now = (Get-Date)
    )

    if (-not (Test-Path $JournalDir)) {
        New-Item -ItemType Directory -Path $JournalDir -Force | Out-Null
    }

    $timestamp = $Now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $sizeLogPath = Join-Path $JournalDir "position_sizing_audit.jsonl"

    # === 1. Beta multiplier (inverse: high beta = smaller size) ===
    # beta 0.5 (stable) → 1.2x (bigger)
    # beta 1.0 (normal) → 1.0x (normal)
    # beta 2.0 (volatile) → 0.5x (smaller)
    $betaMultiplier = [Math]::Max(0.3, 2.0 / $BetaVsBtc)

    # === 2. Confluence multiplier ===
    # 3/5 (borderline) → 0.6x
    # 4/5 (strong) → 0.8x
    # 5/5 (consensus) → 1.0x
    $confluenceMultiplier = switch ($ConfluenceCount) {
        5 { 1.0 }
        4 { 0.8 }
        3 { 0.6 }
        default { 0.0 }  # Não entra
    }

    # === 3. Regime multiplier ===
    $regimeMultiplier = switch ($Regime) {
        "BULL" { 1.0 }
        "BEAR" { 0.5 }
        "SIDEWAYS" { 0.7 }
        default { 0.7 }
    }

    # === 4. Capital constraint ===
    # Máximo 2% da conta em single trade (risk management)
    $maxSizePct = 0.02

    # === 5. Calcula final size ===
    $baseSizeUsd = $AccountEquityUsd * $BasePct
    $adjustedSizeUsd = $baseSizeUsd * $betaMultiplier * $confluenceMultiplier * $regimeMultiplier
    $finalSizeUsd = [Math]::Min($adjustedSizeUsd, $AccountEquityUsd * $maxSizePct)

    # Clamp minimo (não quer trades muito pequenos)
    $minSizeUsd = $AccountEquityUsd * 0.001  # 0.1% minimo
    $finalSizeUsd = [Math]::Max($finalSizeUsd, $minSizeUsd)

    # === 6. Log ===
    $entry = [ordered]@{
        timestamp = $timestamp
        market = $Market
        account_equity_usd = [Math]::Round($AccountEquityUsd, 2)
        base_size_usd = [Math]::Round($baseSizeUsd, 2)
        beta_vs_btc = [Math]::Round($BetaVsBtc, 2)
        beta_multiplier = [Math]::Round($betaMultiplier, 3)
        confluence_count = $ConfluenceCount
        confluence_multiplier = [Math]::Round($confluenceMultiplier, 3)
        regime = $Regime
        regime_multiplier = [Math]::Round($regimeMultiplier, 3)
        adjusted_size_usd = [Math]::Round($adjustedSizeUsd, 2)
        final_size_usd = [Math]::Round($finalSizeUsd, 2)
        final_size_pct = [Math]::Round(($finalSizeUsd / $AccountEquityUsd) * 100, 3)
    } | ConvertTo-Json -Compress

    Add-Content -Path $sizeLogPath -Value $entry -Encoding UTF8

    return [PSCustomObject]@{
        market = $Market
        final_size_usd = [Math]::Round($finalSizeUsd, 2)
        final_size_pct = [Math]::Round(($finalSizeUsd / $AccountEquityUsd) * 100, 3)
        beta_multiplier = [Math]::Round($betaMultiplier, 3)
        confluence_multiplier = [Math]::Round($confluenceMultiplier, 3)
        regime_multiplier = [Math]::Round($regimeMultiplier, 3)
        timestamp = $timestamp
    }
}

function Get-AssetBeta {
    <#
    .SYNOPSIS
    Retorna beta estimado do ativo vs BTC.
    Cache via asset_beta_cache.json.
    #>
    param(
        [Parameter(Mandatory)] [string] $Market,
        [string] $JournalDir = $global:JOURNAL_DIR
    )

    $cacheFile = Join-Path $JournalDir "asset_beta_cache.json"
    $cache = @{}

    if (Test-Path $cacheFile) {
        try {
            $cache = Get-Content $cacheFile -Raw | ConvertFrom-Json | ConvertTo-Hashtable
        } catch { }
    }

    # Defaults baseado em histórico macro
    $defaults = @{
        "BTCUSDT" = 1.0
        "ETHUSDT" = 1.3
        "LINKUSDT" = 1.5   # Altcoin correlacionado
        "SOLUSDT" = 1.8    # Muito volátil
        "NEARUSDT" = 1.9   # Altcoin pequenininho
        "UNIUSDT" = 1.6    # DEX token
        "BNBUSDT" = 1.2    # Binance, estável
        "GRAMUSDT" = 1.7   # Telegram/TON rebrand 2026-06-15 (era TONUSDT, par descontinuado na CoinEx)
    }

    if ($cache -and $cache.ContainsKey($Market)) {
        return [double]$cache[$Market]
    }

    return if ($defaults.ContainsKey($Market)) { [double]$defaults[$Market] } else { 1.5 }
}

function ConvertTo-Hashtable {
    param([object]$InputObject)
    $hash = @{}
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $InputObject.PSObject.Properties | ForEach-Object { $hash[$_.Name] = $_.Value }
    } elseif ($InputObject -is [hashtable]) {
        return $InputObject
    }
    return $hash
}

function Compare-PositionSizeImpact {
    <#
    .SYNOPSIS
    Mostra diferença: size fixo (1%) vs size dinâmico.
    Util pra entender o impacto real.
    #>
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [double] $AccountEquityUsd,
        [Parameter(Mandatory)] [double] $BetaVsBtc,
        [Parameter(Mandatory)] [int] $ConfluenceCount,
        [string] $Regime = "SIDEWAYS"
    )

    # Size fixo (atual)
    $fixedSize = $AccountEquityUsd * 0.01

    # Size dinâmico (novo)
    $dynamic = Invoke-DynamicPositionSize -Market $Market `
        -AccountEquityUsd $AccountEquityUsd `
        -BetaVsBtc $BetaVsBtc `
        -ConfluenceCount $ConfluenceCount `
        -Regime $Regime

    $difference = $dynamic.final_size_usd - $fixedSize
    $percentChange = if ($fixedSize -gt 0) { ($difference / $fixedSize) * 100 } else { 0 }

    # Recomendação baseada em mudança %
    $recommendation = if ($percentChange -gt 20) {
        "AUMENTAR posição (confluência forte, volatilidade controlada)"
    } elseif ($percentChange -lt -30) {
        "REDUZIR posição (volatilidade alta ou confluência fraca)"
    } else {
        "MANTER conforme calculado"
    }

    return [PSCustomObject]@{
        market = $Market
        fixed_size_usd = [Math]::Round($fixedSize, 2)
        fixed_size_pct = 1.0
        dynamic_size_usd = [Math]::Round($dynamic.final_size_usd, 2)
        dynamic_size_pct = $dynamic.final_size_pct
        difference_usd = [Math]::Round($difference, 2)
        percent_change = [Math]::Round($percentChange, 1)
        recommendation = $recommendation
    }
}
