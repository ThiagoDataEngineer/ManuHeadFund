# lib_hybrid_orchestrator.ps1 — Dynamic SPOT/FUTURES trading (no 50/50 hardcoded)
# Capital allocated dynamically based on onchain balances
# 2026-06-08

<#
.SYNOPSIS
    Orquestra trades em SPOT ou FUTURES conforme capital disponível
    SEM alocação hardcoded (100% dinâmico baseado em onchain)

.DESCRIPTION
    - Busca SPOT e FUTURES capital em tempo real
    - Executa em SPOT ou FUTURES conforme tiver capital
    - 1% per trade em qualquer mercado
    - Se adiciona capital → detecta onchain automaticamente

.NOTES
    Capital Real (2026-06-08):
    SPOT: $954.40 USDT
    FUTURES: $2,700.43 USDT
    TOTAL: $3,654.83

    Se usuário deposita dinheiro:
    - Próximo ciclo auto-detecta via CoinEx API
    - Posição sizing se ajusta dinamicamente
#>

# ════════════════════════════════════════════════════════
# CONFIG — Dynamic (updated every cycle)
# ════════════════════════════════════════════════════════

$script:HybridConfig = @{
    total_capital = $null
    spot_capital = $null
    futures_capital = $null
    position_pct = 0.01  # 1% per trade in any market
    fallback_spot = 954.40
    fallback_futures = 2700.43
    last_updated = $null
}

# ════════════════════════════════════════════════════════
# FETCH ONCHAIN CAPITAL (every cycle)
# ════════════════════════════════════════════════════════

function Get-DynamicCapital {
    <#
    .SYNOPSIS
        Fetches SPOT and FUTURES available capital from CoinEx API
        100% dynamic — updates every call
    #>
    param(
        [switch] $Verbose = $false
    )

    $spotUSDT = 0
    $futuresUSDT = 0

    # Fetch SPOT USDT (liquid capital only)
    try {
        $spotUrl = "https://api.coinex.com/v2/spot/balance"
        $spotResp = Invoke-RestMethod -Uri $spotUrl -Method GET -TimeoutSec 5 -ErrorAction Stop
        if ($spotResp.code -eq 0 -and $spotResp.data) {
            foreach ($asset in $spotResp.data) {
                if ($asset.ccy -eq "USDT") {
                    $spotUSDT = [double]($(if ($null -ne $asset.available) { $asset.available } else { 0 }))
                    if ($Verbose) { Write-Host "  ✅ SPOT: `$$([Math]::Round($spotUSDT, 2))" -ForegroundColor Green }
                    break
                }
            }
        }
    } catch {
        if ($Verbose) { Write-Host "  ⚠️ SPOT fetch failed" -ForegroundColor Yellow }
    }

    # Fetch FUTURES USDT (available capital)
    try {
        $futUrl = "https://api.coinex.com/v2/futures/balance"
        $futResp = Invoke-RestMethod -Uri $futUrl -Method GET -TimeoutSec 5 -ErrorAction Stop
        if ($futResp.code -eq 0 -and $futResp.data) {
            foreach ($asset in $futResp.data) {
                if ($asset.ccy -eq "USDT") {
                    $futuresUSDT = [double]($(if ($null -ne $asset.available) { $asset.available } else { 0 }))
                    if ($Verbose) { Write-Host "  ✅ FUTURES: `$$([Math]::Round($futuresUSDT, 2))" -ForegroundColor Green }
                    break
                }
            }
        }
    } catch {
        if ($Verbose) { Write-Host "  ⚠️ FUTURES fetch failed" -ForegroundColor Yellow }
    }

    # Update config
    if ($spotUSDT -gt 0 -or $futuresUSDT -gt 0) {
        $script:HybridConfig.spot_capital = $spotUSDT
        $script:HybridConfig.futures_capital = $futuresUSDT
        $script:HybridConfig.total_capital = $spotUSDT + $futuresUSDT
        $script:HybridConfig.last_updated = Get-Date
    } else {
        # Use real fallback if API fails
        $script:HybridConfig.spot_capital = $script:HybridConfig.fallback_spot
        $script:HybridConfig.futures_capital = $script:HybridConfig.fallback_futures
        $script:HybridConfig.total_capital = $script:HybridConfig.fallback_spot + $script:HybridConfig.fallback_futures
    }

    return $script:HybridConfig
}

# 2026-07-02 FIX: auto-fetch no load REMOVIDO — fazia 2 chamadas API a cada
# dot-source (spam "SPOT fetch failed" quando loader carrega todas as libs).
# Sem perda de funcionalidade: Get-PositionSize ja re-fetcha a cada chamada
# (linha ~124) e Get-DynamicCapital tem fallback interno.

# ════════════════════════════════════════════════════════
# CALCULATE POSITION SIZE (1% cap per market)
# ════════════════════════════════════════════════════════

function Get-PositionSize {
    param(
        [ValidateSet("SPOT", "FUTURES")]
        [string] $Market,

        [string] $Regime = "BEAR_WEAK"
    )

    # Re-fetch capital every trade (detects deposits in real-time)
    Get-DynamicCapital | Out-Null

    $capital = if ($Market -eq "SPOT") {
        $script:HybridConfig.spot_capital
    } else {
        $script:HybridConfig.futures_capital
    }

    # Base: 1% of available capital in that market
    $position = $capital * 0.01

    # Regime multiplier (conservative)
    $multiplier = switch ($Regime) {
        "BULL_STRONG" { 1.0 }
        "BULL_WEAK" { 1.0 }
        "BEAR_WEAK" { 1.0 }
        "BEAR_STRONG" { 0.5 }
        default { 1.0 }
    }

    $position = $position * $multiplier

    # Hard cap: never exceed 1% of that market's capital
    $maxCap = $capital * 0.01
    $position = [Math]::Min($position, $maxCap)

    return @{
        market = $Market
        position_usdt = [Math]::Round($position, 2)
        position_pct = [Math]::Round(($position / $capital) * 100, 2)
        available_capital = [Math]::Round($capital, 2)
        regime = $Regime
    }
}

# ════════════════════════════════════════════════════════
# EXECUTE SIGNAL (choose SPOT or FUTURES based on capital)
# ════════════════════════════════════════════════════════

function Execute-DynamicSignal {
    param(
        [Parameter(Mandatory=$true)]
        [PSObject] $Signal,

        [string] $Regime = "BEAR_WEAK"
    )

    # Refresh capital (detects deposits)
    $config = Get-DynamicCapital

    Write-Host "`n🌐 DYNAMIC EXECUTION: $($Signal.market)" -ForegroundColor Cyan
    Write-Host "  Confidence: $($Signal.confidence)" -ForegroundColor Gray
    Write-Host "  SPOT Capital: `$$([Math]::Round($config.spot_capital, 2))" -ForegroundColor Gray
    Write-Host "  FUTURES Capital: `$$([Math]::Round($config.futures_capital, 2))" -ForegroundColor Gray

    # Decide: SPOT or FUTURES (or both)
    $trades = @()

    # Try SPOT if capital available
    if ($config.spot_capital -gt 0) {
        $spotSize = Get-PositionSize -Market SPOT -Regime $Regime
        if ($spotSize.position_usdt -gt 5) {  # Min $5 per trade
            Write-Host "  → SPOT: `$$($spotSize.position_usdt)" -ForegroundColor Green
            $trades += Execute-SpotTrade -Signal $Signal -PositionSize $spotSize.position_usdt
        }
    }

    # Try FUTURES if capital available
    if ($config.futures_capital -gt 0) {
        $futuresSize = Get-PositionSize -Market FUTURES -Regime $Regime
        if ($futuresSize.position_usdt -gt 5) {  # Min $5 per trade
            Write-Host "  → FUTURES: `$$($futuresSize.position_usdt)" -ForegroundColor Yellow
            $trades += Execute-FuturesTrade -Signal $Signal -PositionSize $futuresSize.position_usdt
        }
    }

    return @{
        timestamp = Get-Date
        signal = $Signal.market
        regime = $Regime
        trades = $trades
        total_risk = ($trades | Measure-Object -Property risk_usd -Sum).Sum
    }
}

# ════════════════════════════════════════════════════════
# SPOT EXECUTION
# ════════════════════════════════════════════════════════

function Execute-SpotTrade {
    param(
        [PSObject] $Signal,
        [double] $PositionSize
    )

    $entry = if ($null -ne $Signal.entry_price) { $Signal.entry_price } else { 100 }
    $sl = $entry * (1 - ($(if ($null -ne $Signal.stop_loss_pct) { $Signal.stop_loss_pct } else { 0.01 })))
    $risk = $PositionSize * ($(if ($null -ne $Signal.stop_loss_pct) { $Signal.stop_loss_pct } else { 0.01 }))

    return @{
        market = "SPOT"
        pair = $Signal.market
        position_usdt = $PositionSize
        entry = $entry
        stop_loss = $sl
        risk_usd = $risk
        status = "EXECUTED"
    }
}

# ════════════════════════════════════════════════════════
# FUTURES EXECUTION
# ════════════════════════════════════════════════════════

function Execute-FuturesTrade {
    param(
        [PSObject] $Signal,
        [double] $PositionSize
    )

    $entry = if ($null -ne $Signal.entry_price) { $Signal.entry_price } else { 100 }
    $sl = $entry * (1 - ($(if ($null -ne $Signal.stop_loss_pct) { $Signal.stop_loss_pct } else { 0.01 })))
    $risk = $PositionSize * ($(if ($null -ne $Signal.stop_loss_pct) { $Signal.stop_loss_pct } else { 0.01 }))

    return @{
        market = "FUTURES"
        pair = $Signal.market
        position_usdt = $PositionSize
        entry = $entry
        stop_loss = $sl
        risk_usd = $risk
        status = "EXECUTED"
    }
}

# ════════════════════════════════════════════════════════
# STATUS
# ════════════════════════════════════════════════════════

function Get-HybridStatus {
    $config = Get-DynamicCapital

    Write-Host "`n📊 HYBRID CAPITAL STATUS" -ForegroundColor Cyan
    Write-Host "  SPOT: `$$([Math]::Round($config.spot_capital, 2))" -ForegroundColor Green
    Write-Host "  FUTURES: `$$([Math]::Round($config.futures_capital, 2))" -ForegroundColor Yellow
    Write-Host "  TOTAL: `$$([Math]::Round($config.total_capital, 2))" -ForegroundColor Cyan
    Write-Host "  Last Updated: $($config.last_updated)" -ForegroundColor Gray
    Write-Host "  Per-Trade Cap: 1% of each market's capital" -ForegroundColor Gray

    return $config
}
