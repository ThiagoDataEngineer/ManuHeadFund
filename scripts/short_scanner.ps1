# short_scanner.ps1 -- SHORT signal scanner (mirror vol_climax_scanner pra direction SHORT).
#
# Tier 2 Block 1 D.1 (2026-05-23): habilita SHORT observatory.
# Backtest T6 validou: 505 signals, EV +2.85pp, hit 60% — POSITIVE EDGE.
#
# Universe: SHORT_TIER_A_LIVE + SHORT_TIER_B_PAPER do per_asset_whitelist v3.6+
# Cadencia: HOURLY (mesma logica vol_climax)
# Output:
#   - journal/short_alerts.jsonl (append-only)
#   - TG alert Tier S apenas (Tier B silent log)
#   - Forward tracker registra cada Tier S signal pra audit posterior
#
# Modo: OBSERVATORY ONLY (sem trade execution). Block 2 add Mentor + executor.

param([switch] $DryRun)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
Set-Location $projectRoot

. (Join-Path $projectRoot "agents\config.local.ps1") -ErrorAction SilentlyContinue
. (Join-Path $projectRoot "agents\lib_short_signals.ps1")
. (Join-Path $projectRoot "agents\lib_telegram.ps1") -ErrorAction SilentlyContinue
. (Join-Path $projectRoot "agents\lib_wyckoff_spring_score.ps1") -ErrorAction SilentlyContinue
. (Join-Path $projectRoot "agents\lib_cluster_filter.ps1") -ErrorAction SilentlyContinue
. (Join-Path $projectRoot "agents\lib_wss_forward_tracker.ps1") -ErrorAction SilentlyContinue

$logFile = Join-Path $projectRoot ("logs\short_scanner_" + (Get-Date -Format "yyyyMMdd") + ".log")
$logDir = Split-Path $logFile -Parent
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
function Log { param($M) "[$((Get-Date).ToString('HH:mm:ss'))] $M" | Tee-Object -FilePath $logFile -Append }

$alertsPath = Join-Path $projectRoot "journal\short_alerts.jsonl"

# Universe: SHORT tier markets
$markets = @()
$wlFiles = Get-ChildItem (Join-Path $projectRoot "journal") -Filter "per_asset_whitelist_*.json" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($wlFiles) {
    try {
        $wl = Get-Content $wlFiles.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($wl.PSObject.Properties['SHORT_TIER_A_LIVE']) {
            foreach ($e in $wl.SHORT_TIER_A_LIVE) { if ($e.market) { $markets += $e.market } }
        }
        if ($wl.PSObject.Properties['SHORT_TIER_B_PAPER']) {
            foreach ($e in $wl.SHORT_TIER_B_PAPER) { if ($e.market) { $markets += $e.market } }
        }
    } catch {}
}
$markets = @($markets | Select-Object -Unique)

# TDD Sprint 1 (2026-05-23): Regime-specific thresholds
# Detect current regime for adaptive thresholds
$currentRegime = "BEAR_WEAK"  # Default fallback
if (Get-Command Get-CurrentRegime -ErrorAction SilentlyContinue) {
    try {
        $regimeResult = Get-CurrentRegime
        if ($regimeResult -and $regimeResult.regime) {
            $currentRegime = $regimeResult.regime
        }
    } catch {}
}

# Get regime-specific thresholds
$thresholds = Get-ShortThresholdsForRegime -Regime $currentRegime

Log "=== SHORT Scanner (universe=$($markets.Count) markets, regime=$currentRegime) ==="
Log "  Thresholds: ClimaxMult=$($thresholds.ClimaxMultiplier) RSI>$($thresholds.RsiOverboughtMin)"
if ($markets.Count -eq 0) {
    Log "  No SHORT-tier markets in whitelist. Exit."
    exit 0
}

# WSS context — fetch BTC regime once
function _FetchBtcRegime {
    foreach ($mtype in @("futures","spot")) {
        try {
            $url = "https://api.coinex.com/v2/$mtype/kline?market=BTCUSDT&period=1day&limit=200"
            $r = Invoke-RestMethod -Uri $url -Method GET -TimeoutSec 10 -ErrorAction Stop
            if ($r.code -eq 0 -and $r.data -and @($r.data).Count -ge 90) {
                $closes = @($r.data | ForEach-Object { [double]$_.close })
                $n = $closes.Count
                $start = [Math]::Max(0, $n-90)
                $high90 = ($closes[$start..($n-1)] | Measure-Object -Maximum).Maximum
                $dd = ($closes[$n-1] - $high90) / $high90 * 100
                $rets = @()
                for ($i = $n-20; $i -lt $n; $i++) {
                    if ($i -gt 0) { $rets += (($closes[$i] - $closes[$i-1]) / $closes[$i-1]) }
                }
                $mean = ($rets | Measure-Object -Average).Average
                $varSum = 0.0
                foreach ($x in $rets) { $varSum += ($x - $mean) * ($x - $mean) }
                $vol = [math]::Sqrt($varSum / $rets.Count) * 100
                return @{ drawdown_pct = $dd; vol_20d = $vol }
            }
        } catch {}
    }
    return $null
}

$btcRegime = _FetchBtcRegime
$wssQuality = @{}
if (Get-Command Read-WyckoffMarketQuality -ErrorAction SilentlyContinue) {
    $wssQuality = Read-WyckoffMarketQuality (Join-Path $projectRoot "journal\wyckoff_market_quality.json")
}
$wssEnabled = ($null -ne $btcRegime) -and ($wssQuality.Count -gt 0)
Log "  WSS context: BTC DD=$([math]::Round($btcRegime.drawdown_pct,1))% vol=$([math]::Round($btcRegime.vol_20d,2))% qt=$($wssQuality.Count)"

function _FetchDailyCandles {
    param([string]$Market, [int]$Limit=30)
    foreach ($mtype in @("futures","spot")) {
        try {
            $url = "https://api.coinex.com/v2/$mtype/kline?market=$Market&period=1day&limit=$Limit"
            $r = Invoke-RestMethod -Uri $url -Method GET -TimeoutSec 10 -ErrorAction Stop
            if ($r.code -eq 0 -and $r.data -and @($r.data).Count -ge 20) {
                return @($r.data | ForEach-Object {
                    [PSCustomObject]@{
                        open = [double]$_.open; high = [double]$_.high
                        low  = [double]$_.low;  close = [double]$_.close
                        volume = [double]$_.volume
                    }
                })
            }
        } catch {}
    }
    return @()
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

$detected = 0
foreach ($mkt in $markets) {
    try {
        $candles = _FetchDailyCandles -Market $mkt -Limit 30
        if (@($candles).Count -lt 20) { continue }
        $vols   = @($candles | ForEach-Object { $_.volume })
        $highs  = @($candles | ForEach-Object { $_.high })
        $lows   = @($candles | ForEach-Object { $_.low })
        $closes = @($candles | ForEach-Object { $_.close })

        $r = Detect-ShortSignal -Volumes $vols -Highs $highs -Lows $lows -Closes $closes `
            -ClimaxMultiplier $thresholds.ClimaxMultiplier -RsiOverboughtMin $thresholds.RsiOverboughtMin
        if (-not $r.detected) { continue }

        $detected++
        $today = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
        # Dedup intra-day per market (same as vol_climax_scanner)
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
            side         = "SHORT"
            pattern      = $r.pattern_name
            strength     = $r.strength
            vol_ratio    = $r.vol_ratio
            break_pct    = $r.break_pct
            rsi          = $r.rsi
            current_high = $highs[-1]
            current_close= $closes[-1]
        }

        # Cluster filter (risk control)
        $cluster = $null
        if (Get-Command Test-ClusterCapExceeded -ErrorAction SilentlyContinue) {
            $cluster = Test-ClusterCapExceeded -AlertsPath $alertsPath -MaxPerDay 1 -MaxPerWeek 3
            $entry.cluster_day_count  = $cluster.day_count
            $entry.cluster_week_count = $cluster.week_count
            $entry.cluster_suppressed = $cluster.exceeded
        }

        # WSS scoring + tier classification
        $tier = "U"
        $wssScore = 0
        if ($wssEnabled) {
            $clusterToday = _CountClusterToday -AlertsPath $alertsPath
            $wssResult = Get-ShortSignalWss `
                -Market $mkt -Volumes $vols -Highs $highs -Lows $lows -Closes $closes `
                -BtcDrawdown $btcRegime.drawdown_pct -BtcVol20d $btcRegime.vol_20d `
                -NowUtc (Get-Date).ToUniversalTime() `
                -ClusterSize ($clusterToday + 1) `
                -QualityTable $wssQuality
            if ($wssResult) {
                $tier = $wssResult.tier
                $wssScore = $wssResult.wss
                $entry.wss = $wssScore
                $entry.wss_tier = $tier
            }
        }

        if (-not $DryRun) {
            Add-Content -Path $alertsPath -Value ($entry | ConvertTo-Json -Compress) -Encoding UTF8

            if ($cluster -and $cluster.exceeded) {
                Log "  $mkt CLUSTER_CAP SHORT -- suppress TG ($($cluster.reason))"
            } elseif ($tier -eq "S") {
                $shortIco = if ($global:TG_EMOJI -and $global:TG_EMOJI.shortArrow) { $global:TG_EMOJI.shortArrow } else { "R" }
                $bearIco = if ($global:TG_EMOJI -and $global:TG_EMOJI.bear) { $global:TG_EMOJI.bear } else { "" }
                $msg = "$bearIco [SHORT TIER S] $mkt $shortIco`nWSS=$wssScore (paper observatory)`nstrength=$($r.strength) vol_ratio=$($r.vol_ratio)x break=$($r.break_pct)% RSI=$($r.rsi)`nBTC DD=$([math]::Round($btcRegime.drawdown_pct,1))% vol_20d=$([math]::Round($btcRegime.vol_20d,2))%`nT6 backtest: EV +2.85pp em 505 signals. PAPER ONLY ate Block 2."
                try { Send-TelegramAlert -Message $msg | Out-Null } catch {}

                # Forward tracker SHORT
                if (Get-Command Add-WssSignal -ErrorAction SilentlyContinue) {
                    try {
                        Add-WssSignal -Market $mkt -WssScore $wssScore -EntryPrice $closes[-1] `
                            -BtcDrawdown $btcRegime.drawdown_pct -BtcVol $btcRegime.vol_20d `
                            -WindowBars 3 -Side "SHORT"
                    } catch {}
                }
            } elseif ($tier -eq "A") {
                Log "  $mkt TIER A SHORT obs (no TG, log only)"
            } else {
                # Tier B/U silent
            }
        }
        $tag = ""
        if ($cluster -and $cluster.exceeded) { $tag += " [SUPPRESSED]" }
        if ($wssEnabled) { $tag += " [WSS=$wssScore tier=$tier]" }
        Log "  $mkt SHORT DETECTED $($r.pattern_name) vol=$($r.vol_ratio)x RSI=$($r.rsi)$tag"
    } catch {
        Log "  ERR $mkt -- $($_.Exception.Message)"
    }
}

Log "=== Done -- detected=$detected ==="
exit 0
