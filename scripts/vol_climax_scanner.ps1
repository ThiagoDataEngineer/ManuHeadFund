# vol_climax_scanner.ps1 -- Scanner dedicated LONG_vol_climax (edge +8.6pp validado).
#
# Filosofia: backtest unified mostrou que LONG_vol_climax eh UNICO pattern com edge
# real (n=278 hit 58.3% vs baseline 49.6%, +14.4% avg outcome wins). Outros patterns
# (Tori predicate, RSI div, candlestick) tem edge zero em historico.
#
# Output: journal/vol_climax_alerts.jsonl (append-only, dedup TTL via market+ts)
# TG alert quando market dispara climax LONG.
#
# Cadencia: HOURLY (daily candles atualizam 1x/dia UTC, mas CoinEx extended bar
# pode mover durante o dia. Hourly = catch-up generoso sem desperdicio de API).
# Dedup interno: 1 alert/market/dia. Universe: TIER_A_LIVE + TIER_B_PAPER (~11 markets).

param([switch] $DryRun)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
Set-Location $projectRoot

. (Join-Path (Join-Path $projectRoot "agents") "config.local.ps1")
. (Join-Path (Join-Path $projectRoot "agents") "lib_coinex.ps1")
. (Join-Path (Join-Path $projectRoot "agents") "lib_capital_context.ps1")
. (Join-Path (Join-Path $projectRoot "agents") "lib_telegram.ps1")
. (Join-Path (Join-Path $projectRoot "agents") "lib_chart_patterns.ps1")
. (Join-Path (Join-Path $projectRoot "agents") "lib_cluster_filter.ps1")
. (Join-Path (Join-Path $projectRoot "agents") "lib_wyckoff_spring_score.ps1")
. (Join-Path (Join-Path $projectRoot "agents") "lib_signal_trigger_bus.ps1")  # fast-path: enfileira trigger vol_climax
. (Join-Path (Join-Path $projectRoot "agents") "lib_signal_combo.ps1")
. (Join-Path (Join-Path $projectRoot "agents") "lib_regime_position_sizing.ps1")
. (Join-Path (Join-Path $projectRoot "agents") "lib_hybrid_orchestrator.ps1")
. (Join-Path (Join-Path $projectRoot "agents") "lib_market_context_engine.ps1")
# Caminho 2 (2026-05-23): forward validation tracker â€” captura Tier S signals pra audit real
if (Test-Path (Join-Path (Join-Path $projectRoot "agents") "lib_wss_forward_tracker.ps1")) {
    . (Join-Path (Join-Path $projectRoot "agents") "lib_wss_forward_tracker.ps1")
}

$logFile = Join-Path $projectRoot ("logs\vol_climax_" + (Get-Date -Format "yyyyMMdd") + ".log")
$logDir = Split-Path $logFile -Parent
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
function Log { param($M) "[$((Get-Date).ToString('HH:mm:ss'))] $M" | Tee-Object -FilePath $logFile -Append }

$alertsPath = Join-Path $projectRoot "journal\vol_climax_alerts.jsonl"

# Lista markets: whitelist journal -> fallback git-tracked (journal/ gitignored = vazio no cloud)
. (Join-Path $PSScriptRoot "..\agents\lib_short_universe.ps1")
$wl = $null
$wlFiles = Get-ChildItem (Join-Path $projectRoot "journal") -Filter "per_asset_whitelist_*.json" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($wlFiles) {
    try { $wl = Get-Content $wlFiles.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
}
$cfgLong = $null
$cfgLongPath = Join-Path $projectRoot "config/long_universe.json"
if (Test-Path $cfgLongPath) {
    try { $cfgLong = Get-Content $cfgLongPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
}
$markets = @(Resolve-TierUniverse -Whitelist $wl -TierKeys @('TIER_A_LIVE','TIER_B_PAPER') -ConfigFallback $cfgLong)

Log "=== Vol Climax Scanner (universe=$($markets.Count) markets) ==="

function _FetchBtcRegime {
    # Fetch 200 daily BTC candles, return @{ drawdown_pct, vol_20d, vol_distribution }
    foreach ($mtype in @("futures","spot")) {
        try {
            $url = "https://api.coinex.com/v2/$mtype/kline?market=BTCUSDT&period=1day&limit=200"
            $r = Invoke-RestMethod -Uri $url -Method GET -TimeoutSec 10 -ErrorAction Stop
            if ($r.code -eq 0 -and $r.data -and @($r.data).Count -ge 90) {
                $closes = @($r.data | ForEach-Object { [double]$_.close })
                $n = $closes.Count
                # Drawdown from rolling 90d high
                $start = [Math]::Max(0, $n-90)
                $high90 = ($closes[$start..($n-1)] | Measure-Object -Maximum).Maximum
                $dd = ($closes[$n-1] - $high90) / $high90 * 100
                # Vol 20d (stddev daily returns %)
                $rets = @()
                for ($i = $n-20; $i -lt $n; $i++) {
                    if ($i -gt 0) { $rets += (($closes[$i] - $closes[$i-1]) / $closes[$i-1]) }
                }
                $mean = ($rets | Measure-Object -Average).Average
                $varSum = 0.0
                foreach ($x in $rets) { $varSum += ($x - $mean) * ($x - $mean) }
                $vol = [math]::Sqrt($varSum / $rets.Count) * 100
                # Vol distribution: rolling 20d vol for last ~180 days as percentile reference
                $volDist = @()
                for ($i = 20; $i -lt $n; $i++) {
                    $localRets = @()
                    for ($j = $i-19; $j -le $i; $j++) {
                        if ($j -gt 0) { $localRets += (($closes[$j] - $closes[$j-1]) / $closes[$j-1]) }
                    }
                    $lmean = ($localRets | Measure-Object -Average).Average
                    $lvar = 0.0
                    foreach ($x in $localRets) { $lvar += ($x - $lmean) * ($x - $lmean) }
                    $volDist += [math]::Sqrt($lvar / $localRets.Count) * 100
                }
                return @{
                    drawdown_pct = $dd
                    vol_20d      = $vol
                    vol_distribution = $volDist
                }
            }
        } catch {}
    }
    return $null
}

function _CountClusterToday {
    param([string]$AlertsPath)
    if (-not (Test-Path $AlertsPath)) { return 0 }
    $today = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
    $n = 0
    try {
        $lines = Get-Content $AlertsPath -Encoding UTF8 -ErrorAction Stop
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $obj = $line | ConvertFrom-Json -ErrorAction Stop
                if ($obj.ts_utc -like "$today*") { $n++ }
            } catch {}
        }
    } catch {}
    return $n
}

function _FetchDailyCandles {
    param([string]$Market, [int]$Limit=30)
    foreach ($mtype in @("futures","spot")) {
        try {
            $url = "https://api.coinex.com/v2/$mtype/kline?market=$Market&period=1day&limit=$Limit"
            $r = Invoke-RestMethod -Uri $url -Method GET -TimeoutSec 10 -ErrorAction Stop
            if ($r.code -eq 0 -and $r.data -and @($r.data).Count -ge 20) {
                return @($r.data | ForEach-Object {
                    [PSCustomObject]@{
                        open  = [double]$_.open
                        high  = [double]$_.high
                        low   = [double]$_.low
                        close = [double]$_.close
                        volume= [double]$_.volume
                    }
                })
            }
        } catch {}
    }
    return @()
}

# WSS context â€” fetched once per scan (BTC regime + market quality table).
# Must be AFTER function definitions (PS 5.1 no forward ref).
$btcRegime  = _FetchBtcRegime
$wssQuality = Read-WyckoffMarketQuality (Join-Path (Join-Path $projectRoot "journal") "wyckoff_market_quality.json")
$wssEnabled = ($null -ne $btcRegime) -and ($wssQuality.Count -gt 0)
if ($wssEnabled) {
    Log "  WSS context: BTC DD=$([math]::Round($btcRegime.drawdown_pct,1))% vol_20d=$([math]::Round($btcRegime.vol_20d,2))% quality_table=$($wssQuality.Count) markets"
} else {
    Log "  WSS context: DISABLED (btc fetch failed or quality table empty)"
}

$detected = 0
foreach ($mkt in $markets) {
    try {
        $candles = _FetchDailyCandles -Market $mkt -Limit 30
        if (@($candles).Count -lt 20) { continue }
        $vols   = @($candles | ForEach-Object { $_.volume })
        $lows   = @($candles | ForEach-Object { $_.low })
        $highs  = @($candles | ForEach-Object { $_.high })
        $closes = @($candles | ForEach-Object { $_.close })

        # REFINED 2026-05-22: mult=2.5 + RSI<30 confluence (cross-cycle p3_bear +16/+25pp).
        # Modo paper-deploy ate sample n>=30 per phase (gate 3.6).
        $r = Detect-VolumeClimax -Volumes $vols -Lows $lows -Highs $highs -Closes $closes -Side LONG -ClimaxMultiplier 2.5 -RsiOversoldMax 30
        if (-not $r.detected) { continue }

        # Regime-based position sizing (TDD validated 2026-06-08)
        try {
            $regime = Get-HalvingPhase -DateBrt (Get-Date)
        } catch {
            $regime = "BULL_WEAK"
        }

        # FETCH CAPITAL ONCHAIN (não hardcoded)
        $spotBalance = 0
        $futuresBalance = 0
        try {
            # CoinEx SPOT balance
            $spotUrl = "https://api.coinex.com/v2/spot/balance"
            $spotResp = Invoke-RestMethod -Uri $spotUrl -Method GET -TimeoutSec 5 -ErrorAction Stop
            if ($spotResp.code -eq 0 -and $spotResp.data) {
                foreach ($asset in $spotResp.data) {
                    if ($asset.ccy -eq "USDT") { $spotBalance = [double]($asset.available ?? 0) }
                }
            }
        } catch {}

        try {
            # CoinEx FUTURES balance (if available)
            $futUrl = "https://api.coinex.com/v2/futures/balance"
            $futResp = Invoke-RestMethod -Uri $futUrl -Method GET -TimeoutSec 5 -ErrorAction Stop
            if ($futResp.code -eq 0 -and $futResp.data) {
                foreach ($asset in $futResp.data) {
                    if ($asset.ccy -eq "USDT") { $futuresBalance = [double]($asset.available ?? 0) }
                }
            }
        } catch {}

        $capital = [Math]::Max($spotBalance + $futuresBalance, 2700.85)  # Fallback if both fail
        if ($spotBalance -gt 0 -or $futuresBalance -gt 0) {
            Log "  [CAPITAL] SPOT=$([Math]::Round($spotBalance,2)) FUTURES=$([Math]::Round($futuresBalance,2)) TOTAL=$([Math]::Round($capital,2)) USDT"
        }

        $positionSize = Get-RegimePositionSize -Capital $capital -Regime $regime -BasePercentage 0.01

        # HYBRID: Calculate SPOT + FUTURES positions separately (50/50 allocation)
        $spotCapital = $spotBalance -gt 0 ? $spotBalance : (1350.425)
        $futuresCapital = $futuresBalance -gt 0 ? $futuresBalance : (1350.425)
        $spotPositions = Get-HybridPositionSizes -Regime $regime
        $spotPos = $spotPositions.spot_usdt
        $futuresPos = $spotPositions.futures_usdt

        $detected++
        $today = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
        # Dedup: check se ja foi logged hoje pra esse market
        $alreadyLogged = $false
        if (Test-Path $alertsPath) {
            $existing = Get-Content $alertsPath -Encoding UTF8 -ErrorAction SilentlyContinue |
                        ForEach-Object { try { $_ | ConvertFrom-Json } catch { $null } } |
                        Where-Object { $_ -and $_.market -eq $mkt -and $_.ts_utc -like "$today*" }
            if (@($existing).Count -gt 0) { $alreadyLogged = $true }
        }
        if ($alreadyLogged) {
            Log "  SKIP $mkt -- ja logged hoje"
            continue
        }

        $entry = [ordered]@{
            ts_utc       = (Get-Date).ToUniversalTime().ToString("o")
            market       = $mkt
            pattern      = $r.pattern_name
            strength     = $r.strength
            vol_ratio    = $r.vol_ratio
            break_pct    = $r.break_pct
            current_low  = $lows[-1]
            current_close= $closes[-1]
            regime       = $regime
            position_size= [Math]::Round($positionSize, 4)
            spot_position= [Math]::Round($spotPos, 4)
            futures_position= [Math]::Round($futuresPos, 4)
            signal_quality = "vol_climax_solo"
        }
        # Cluster filter (RISK CONTROL, nao edge gate): cap rolling 1/dia, 3/7d.
        $cluster = Test-ClusterCapExceeded -AlertsPath $alertsPath -MaxPerDay 1 -MaxPerWeek 3
        $entry.cluster_day_count  = $cluster.day_count
        $entry.cluster_week_count = $cluster.week_count
        $entry.cluster_suppressed = $cluster.exceeded

        # WSS scoring (Wyckoff Spring Score): tier S/A/B classification.
        # OOS validation 2026-05-22: h20 lift +3.2pp, h24 lift ~0 (avoid loss).
        # Tier S: paper-trade eligible. Tier A: observatory TG. Tier B: silent log.
        $wssResult = $null
        $tier = "N/A"
        if ($wssEnabled) {
            $clusterToday = _CountClusterToday -AlertsPath $alertsPath
            $wssResult = Get-WyckoffSpringScore `
                -Market $mkt `
                -BtcDrawdownPct $btcRegime.drawdown_pct `
                -BtcVol20d $btcRegime.vol_20d `
                -NowUtc (Get-Date).ToUniversalTime() `
                -ClusterSize ($clusterToday + 1) `
                -VolDistribution $btcRegime.vol_distribution `
                -QualityTable $wssQuality
            $tier = $wssResult.tier
            $entry.wss             = $wssResult.wss
            $entry.wss_tier        = $tier
            $entry.wss_components  = $wssResult.components
            $entry.btc_drawdown    = [math]::Round($btcRegime.drawdown_pct, 2)
            $entry.btc_vol_20d     = [math]::Round($btcRegime.vol_20d, 3)
        }

        if (-not $DryRun) {
            # HYBRID: Execute on both SPOT and FUTURES
            $signal = @{
                market = $mkt
                type = "VOL_CLIMAX_ENGULFING"
                confidence = $r.strength
                entry_price = $closes[-1]
                stop_loss_pct = 0.01
                direction = "LONG"
            }
            try {
                $hybridTrade = Execute-HybridSignal -Signal $signal -Regime $regime
                $entry.hybrid_spot_risk = [Math]::Round($hybridTrade.spot_trade.risk_usd, 4)
                $entry.hybrid_futures_risk = [Math]::Round($hybridTrade.futures_trade.risk_usd, 4)
                $entry.hybrid_combined_risk = [Math]::Round($hybridTrade.combined_risk, 4)
                Log "  [HYBRID EXECUTED] $mkt | SPOT risk `$$($entry.hybrid_spot_risk) | FUTURES risk `$$($entry.hybrid_futures_risk)"

                # Log to hybrid_trades.jsonl too
                $hybridPath = Join-Path $projectRoot "journal\hybrid_trades.jsonl"
                $hybridEntry = @{
                    timestamp = (Get-Date).ToUniversalTime().ToString("o")
                    market = $mkt
                    regime = $regime
                    signal_type = "VOL_CLIMAX"
                    spot_position = [Math]::Round($spotPos, 4)
                    futures_position = [Math]::Round($futuresPos, 4)
                    combined_risk = [Math]::Round($hybridTrade.combined_risk, 4)
                    status = "EXECUTED"
                }
                Add-Content -Path $hybridPath -Value ($hybridEntry | ConvertTo-Json -Compress) -Encoding UTF8
            } catch {
                Log "  [HYBRID ERR] $mkt -- $($_.Exception.Message)"
            }

            Add-Content -Path $alertsPath -Value ($entry | ConvertTo-Json -Compress) -Encoding UTF8
            # Fast-path: enfileira trigger event-driven. So Tier S (paper-trade
            # eligible) e nao cluster-suprimido dispara; conviccao = WSS. Consumer
            # (scan_master) roda analise full direcionada sem esperar o ciclo.
            if (Get-Command Add-SignalTrigger -ErrorAction SilentlyContinue) {
                $vcWss = if ($wssResult) { [double]$wssResult.wss } else { 0 }
                $vcConv = Get-VolClimaxConviction -Tier $tier -Wss $vcWss -ClusterSuppressed ([bool]$cluster.exceeded)
                if ($vcConv -gt 0) {
                    try { Add-SignalTrigger -Market $mkt -Signal "vol_climax" -Conviction $vcConv -Direction "long" -ClusterKey "$mkt-$today" -Notes "WSS tier S vol_ratio=$($r.vol_ratio)x" | Out-Null } catch {}
                }
            }
            # Tier-based TG behavior:
            #   - Cluster cap excedido: silent (audit only)
            #   - Tier S: full alert + PAPER_TRADE flag
            #   - Tier A: observatory alert
            #   - Tier B (or wss disabled): silent log only
            if ($cluster.exceeded) {
                Log "  $mkt CLUSTER_CAP -- suppress TG ($($cluster.reason))"
            } elseif ($tier -eq "S") {
                $rsiTag = if ($r.PSObject.Properties['rsi']) { " RSI=$($r.rsi)" } else { "" }
                $msg = "[VOL CLIMAX][TIER S] $mkt`nWSS=$($wssResult.wss) (paper-trade eligible)`nstrength=$($r.strength) vol_ratio=$($r.vol_ratio)x break=$($r.break_pct)%$rsiTag`nBTC DD=$([math]::Round($btcRegime.drawdown_pct,1))% vol_20d=$([math]::Round($btcRegime.vol_20d,2))% mph=$($wssResult.mph)`nOOS validated h20+h24 lift +3.2pp / -0.4pp. Paper only ate forward validation 6-12mo."
                try { Send-TelegramAlert -Message $msg | Out-Null } catch {}
                # Caminho 2 wire: forward tracker (captura signal pra audit real outcome em 3 bars)
                if (Get-Command Add-WssSignal -ErrorAction SilentlyContinue) {
                    try {
                        Add-WssSignal -Market $mkt -WssScore $wssResult.wss -EntryPrice $closes[-1] `
                            -BtcDrawdown $btcRegime.drawdown_pct -BtcVol $btcRegime.vol_20d -WindowBars 3
                    } catch {}
                }
            } elseif ($tier -eq "A") {
                $msg = "[VOL CLIMAX][TIER A obs] $mkt WSS=$($wssResult.wss)`nstrength=$($r.strength) vol_ratio=$($r.vol_ratio)x`nObservatory only (tier A nao paper-trade)."
                try { Send-TelegramAlert -Message $msg | Out-Null } catch {}
            } else {
                # Tier B ou WSS disabled â€” log silent
            }
        }
        $tag = ""
        if ($cluster.exceeded) { $tag += " [CLUSTER_SUPPRESSED]" }
        if ($wssEnabled) { $tag += " [WSS=$($wssResult.wss) tier=$tier]" }
        Log "  $mkt DETECTED pattern=$($r.pattern_name) strength=$($r.strength) vol_ratio=$($r.vol_ratio)x break=$($r.break_pct)%$tag"
    } catch {
        Log "  ERR $mkt -- $($_.Exception.Message)"
    }
}

Log "=== Done -- detected=$detected ==="
exit 0
