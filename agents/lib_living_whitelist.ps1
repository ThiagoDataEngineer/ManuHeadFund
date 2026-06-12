# lib_living_whitelist.ps1 -- Item 11: discovery semanal universo CoinEx
#
# Domingo 03:00 (mesmo cron que promotion):
#   1. Fetch CoinEx all tickers
#   2. Filter top N por volume USDT
#   3. Para cada nao-listado em pipeline: compute paper backtest
#   4. Se passa relaxed gate -> propor adicionar a DESCOBERTA
#   5. Telegram alerta novidades
#
# Relaxed gate (so pra DESCOBERTA, nao trade):
#   sharpe paper > 1.0
#   regime asset OR btc bull
#   n_trades observados >= 5
#
# DSR global aplicado mas com peso menor (DESCOBERTA nao executa trade real)
#
# PS 5.1. UTF-8 BOM.


function Filter-LiquidMarkets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Tickers,    # array de {market, value}
        [double]$MinVolumeUsd = 1000000,
        [int]$TopN = 30
    )
    $eligible = @($Tickers | Where-Object {
        [double]$_.value -ge $MinVolumeUsd -and $_.market -match 'USDT$'
    })
    $sorted = @($eligible | Sort-Object { [double]$_.value } -Descending)
    if ($sorted.Count -le $TopN) { return ,$sorted }
    $sliced = @()
    for ($i = 0; $i -lt $TopN; $i++) { $sliced += $sorted[$i] }
    return ,$sliced   # comma forca array (evita unwrap PS de array com 1 elemento)
}


function Test-ShouldDiscover {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $PipelinePath
    )
    $state = Get-PromotionState -Path $PipelinePath -Market $Market
    return (-not $state)
}


function Test-LivingWhitelistGate {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Metrics)
    # Relaxed gate -- so pra DESCOBERTA entry (nao trade real)
    $bullRegimes = @("BULL_STRONG","BULL_WEAK","TRANSITION_UP")
    $assetBull = $bullRegimes -contains [string]$Metrics.regime_asset
    $btcBull   = $bullRegimes -contains [string]$Metrics.regime_btc
    $regimeOk = ($assetBull -or $btcBull)
    $sharpeOk = ([double]$Metrics.sharpe_30d -ge 1.0)
    $tradesOk = ([int]$Metrics.n_trades -ge 5)
    return ($regimeOk -and $sharpeOk -and $tradesOk)
}


function Invoke-LivingWhitelistScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Tickers,
        [Parameter(Mandatory)] [string] $PipelinePath,
        [Parameter(Mandatory)] [scriptblock] $MetricsProvider,
        [double]$MinVolumeUsd = 1000000,
        [int]$TopN = 30,
        [switch]$BullStrongAutoAdd   # Modo auto-add: BULL_STRONG -> DESCOBERTA + OBSERVATION
    )
    $newCandidates = @()
    $alreadyTracked = @()
    $filteredOut = @()
    $autoAdded = @()
    $regimeCounts = @{}

    $liquid = Filter-LiquidMarkets -Tickers $Tickers -MinVolumeUsd $MinVolumeUsd -TopN $TopN

    foreach ($t in $liquid) {
        $mkt = $t.market
        if (-not (Test-ShouldDiscover -Market $mkt -PipelinePath $PipelinePath)) {
            $alreadyTracked += $mkt
            continue
        }
        $metrics = & $MetricsProvider $mkt
        if (-not $metrics) {
            $filteredOut += $mkt
            continue
        }
        # Track regime distribution
        $regime = [string]$metrics.regime_asset
        if ($regime) {
            if (-not $regimeCounts.ContainsKey($regime)) { $regimeCounts[$regime] = 0 }
            $regimeCounts[$regime]++
        }

        if ($BullStrongAutoAdd) {
            # Modo auto-add: only BULL_STRONG entra
            if ($regime -eq "BULL_STRONG") {
                $newCandidates += $mkt
                # Auto-cria DESCOBERTA + promote pra OBSERVATION (state 1)
                Add-PromotionEvent -Path $PipelinePath -Market $mkt -Event "discovered" `
                    -Source "living_whitelist_auto" -Notes ("auto-add BULL_STRONG mom_20d=" + $metrics.mom_20d) | Out-Null
                Add-PromotionEvent -Path $PipelinePath -Market $mkt -Event "promoted" `
                    -TierState 1 -Source "living_whitelist_auto" -UserDecision "auto" `
                    -Notes "auto-promote to OBSERVATION" | Out-Null
                $autoAdded += $mkt
            } else {
                $filteredOut += $mkt
            }
        } else {
            # Modo strict (default): gate Sharpe + bull
            if (Test-LivingWhitelistGate -Metrics $metrics) {
                $newCandidates += $mkt
            } else {
                $filteredOut += $mkt
            }
        }
    }

    return @{
        new_candidates   = $newCandidates
        already_tracked  = $alreadyTracked
        filtered_out     = $filteredOut
        auto_added       = $autoAdded
        regime_counts    = $regimeCounts
        scanned_count    = $liquid.Count
    }
}


# ── Get-LivingWhitelistMetrics ────────────────────────────────────────────────
# Busca closes diarios da CoinEx, computa regime via Compute-AssetRegime,
# retorna hashtable com campos obrigatorios. Fail-soft: qualquer erro retorna
# defaults com regime_asset="UNKNOWN".
function Get-LivingWhitelistMetrics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market
    )
    $defaults = @{
        regime_asset = "UNKNOWN"
        regime_btc   = "UNKNOWN"
        mom_20d      = 0.0
        sharpe_30d   = 0.0
        n_trades     = 0
    }
    try {
        # Tenta buscar closes diarios via CoinEx API
        $url = "https://api.coinex.com/v2/spot/kline?market=$Market&period=1day&limit=250"
        $r = Invoke-RestMethod -Uri $url -Method GET -TimeoutSec 15 -ErrorAction Stop
        if (-not $r.data -or @($r.data).Count -lt 200) {
            return $defaults
        }
        $closes = [double[]]@($r.data | ForEach-Object { [double]$_.close })
        $regimeResult = Compute-AssetRegime -Closes $closes
        $mom = if ($null -ne $regimeResult.mom_20d) { [double]$regimeResult.mom_20d } else { 0.0 }

        # Tenta regime BTC do cache (fail-soft)
        $regimeBtc = "UNKNOWN"
        try {
            if (Get-Command Get-MarketRegimeFromCache -ErrorAction SilentlyContinue) {
                $cached = Get-MarketRegimeFromCache -Market "BTCUSDT"
                if ($cached) { $regimeBtc = $cached }
            }
        } catch {}

        return @{
            regime_asset = [string]$regimeResult.regime
            regime_btc   = $regimeBtc
            mom_20d      = $mom
            sharpe_30d   = 0.0
            n_trades     = 0
        }
    } catch {
        return $defaults
    }
}



function Format-RegimeDistribution {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Counts)
    $order = @("BULL_STRONG","BULL_WEAK","SIDEWAYS","TRANSITION","BEAR_WEAK","BEAR_STRONG","NO_HIST")
    if ($Counts.Count -eq 0) { return "(sem regime data)" }
    $maxLabel = 12
    $bar = [char]9612  # blocco
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("Distribuicao regime")
    foreach ($k in $order) {
        if (-not $Counts.ContainsKey($k)) { continue }
        $n = [int]$Counts[$k]
        $bars = New-Object string $bar, ([Math]::Min($n, 60))
        [void]$sb.AppendLine(("  {0,-12} {1,3}  {2}" -f $k, $n, $bars))
    }
    return $sb.ToString()
}
