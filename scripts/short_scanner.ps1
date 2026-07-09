# short_scanner.ps1 -- SHORT signal scanner - CROSS-PLATFORM (Windows/Linux)
# Tier 2 Block 1 D.1 (2026-05-23): habilita SHORT observatory.
# Backtest T6 validou: 505 signals, EV +2.85pp, hit 60% â€” POSITIVE EDGE.
#
# Universe: SHORT_TIER_A_LIVE + SHORT_TIER_B_PAPER do per_asset_whitelist v3.6+
# Cadencia: HOURLY (mesma logica vol_climax)
# Output:
#   - journal/short_alerts.jsonl (append-only)
#   - TG alert Tier S apenas (Tier B silent log)
#   - Forward tracker registra cada Tier S signal pra audit posterior
#
# Modo: OBSERVATORY ONLY (sem trade execution). Block 2 add Mentor + executor.
# 2026-05-24: Refatorado para cross-platform (Windows/Linux)

param([switch] $DryRun)

$ErrorActionPreference = "Stop"

# ============================================================================
# Setup Cross-Platform
# ============================================================================

$projectRoot = Split-Path -Parent $PSScriptRoot
$agentsDir = Join-Path $projectRoot "agents"
$crossPlatformLib = Join-Path $agentsDir "lib_cross_platform.ps1"
. $crossPlatformLib

# Carregar config.local.ps1 se existir
$configLocal = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocal) { . $configLocal }

# Inicializar ambiente
$cpEnv = Initialize-CrossPlatformEnvironment

Write-CrossPlatformLog "=== SHORT SCANNER START ===" -LogFile "short_scanner.log"
Write-CrossPlatformLog "OS: $(if ($cpEnv.IsLinux) { 'Linux' } else { 'Windows' })" -LogFile "short_scanner.log"

# ============================================================================
# Validar Credenciais
# ============================================================================

if (-not (Test-CrossPlatformCredentials)) {
    Write-CrossPlatformLog "ERROR: Credentials not configured" -Level ERROR -LogFile "short_scanner.log"
    exit 1
}

# ============================================================================
# Carregar Bibliotecas
# ============================================================================

try {
    Write-CrossPlatformLog "Loading libraries..." -LogFile "short_scanner.log"
    . (Join-Path $agentsDir "lib_short_signals.ps1")
    . (Join-Path $agentsDir "lib_telegram.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_wyckoff_spring_score.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_cluster_filter.ps1") -ErrorAction SilentlyContinue
    . (Join-Path $agentsDir "lib_wss_forward_tracker.ps1") -ErrorAction SilentlyContinue
    Write-CrossPlatformLog "Libraries loaded" -LogFile "short_scanner.log"
} catch {
    Write-CrossPlatformLog "ERROR loading libraries: $_" -Level ERROR -LogFile "short_scanner.log"
    exit 1
}

# Helper function for logging
function Log { 
    param($M) 
    Write-CrossPlatformLog $M -LogFile "short_scanner.log"
}

# ============================================================================
# Executar Scanner
# ============================================================================

try {
    $alertsPath = Join-Path $cpEnv.JournalDir "short_alerts.jsonl"

    # Universe: SHORT tier markets. journal/ e gitignored (vazio no cloud) -> fallback
    # git-tracked config/short_universe.json garante universo. Logica pura testada.
    . (Join-Path $agentsDir "lib_short_universe.ps1")
    $wl = $null
    $wlFiles = Get-ChildItem $cpEnv.JournalDir -Filter "per_asset_whitelist_*.json" -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($wlFiles) {
        try { $wl = Get-Content $wlFiles.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
    }
    $cfgShort = $null
    $cfgShortPath = Join-Path $projectRoot "config/short_universe.json"
    if (Test-Path $cfgShortPath) {
        try { $cfgShort = Get-Content $cfgShortPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
    }
    $markets = @(Resolve-ShortUniverse -Whitelist $wl -ConfigFallback $cfgShort)

    # TDD Sprint 1 (2026-05-23): Regime-specific thresholds
    # Detect current regime for adaptive thresholds
    $currentRegime = "BEAR_WEAK"  # Default fallback
    # 2026-07-04 CONTRATO: Get-CurrentRegime NUNCA existiu -> scanner rodava
    # regime-cego (sempre no fallback) desde a criacao. Fonte real:
    # $global:CURRENT_REGIME ou journal/regime_state.json (refresh_regime_state).
    if ($global:CURRENT_REGIME) {
        $currentRegime = [string]$global:CURRENT_REGIME
    } else {
        try {
            $rsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "journal\regime_state.json"
            if (Test-Path $rsPath) {
                $rs = Get-Content $rsPath -Raw | ConvertFrom-Json
                if ($rs.regime) { $currentRegime = [string]$rs.regime }
            }
        } catch {}
    }

    # Get regime-specific thresholds
    $thresholds = Get-ShortThresholdsForRegime -Regime $currentRegime

    Log "=== SHORT Scanner (universe=$($markets.Count) markets, regime=$currentRegime) ==="
    Log "  Thresholds: ClimaxMult=$($thresholds.ClimaxMultiplier) RSI>$($thresholds.RsiOverboughtMin)"
    if ($markets.Count -eq 0) {
        Log "  No SHORT-tier markets in whitelist. Exit."
        Write-CrossPlatformLog "=== SHORT SCANNER END ===" -LogFile "short_scanner.log"
        exit 0
    }

    # WSS context â€” fetch BTC regime once
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
        $wssQuality = Read-WyckoffMarketQuality (Join-Path $cpEnv.JournalDir "wyckoff_market_quality.json")
    }
    $wssEnabled = ($null -ne $btcRegime) -and ($wssQuality.Count -gt 0)
    Log "  WSS context: BTC DD=$([math]::Round($btcRegime.drawdown_pct,1))% vol=$([math]::Round($btcRegime.vol_20d,2))% qt=$($wssQuality.Count)"

    function _FetchDailyCandles {
        param([string]$Market, [int]$Limit=30)
        foreach ($mtype in @("futures","spot")) {
            try {
                $url = "https://api.coinex.com/v2/$mtype/kline?market=$Market&period=1day&limit=$Limit"
                $r = Invoke-RestMethod -Uri $url -Method GET -TimeoutSec 10 -ErrorAction Stop
                if ($r.code -eq 0 -and $r.data -and @($r.data).Count -ge 21) {
                    # 2026-07-09 FIX RAIZ detected=0: ultimo candle da API = DIA EM ANDAMENTO
                    # (parcial). Detect-VolClimax avalia $Volumes[n-1] -> vol_ratio subestimado
                    # o dia inteiro -> climax >=2.5x quase nunca dispara em live, enquanto o
                    # backtest (505 sinais, EV +2.85pp) usa candles FECHADOS. Descarta o
                    # parcial: sinal avaliado no CLOSE do dia = mesma semantica do backtest.
                    $data = @($r.data)
                    $data = $data[0..($data.Count - 2)]
                    return @($data | ForEach-Object {
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

                    # ===== SHORT LIVE (rollout seguro, opt-in via config) =====
                    # So dispara com config live_enabled=true + market em tier_a_live + Tier S.
                    # Stack: plano (stop/target ATR, R:R 1:5) + capital safety + dedup posicao.
                    # Sizing ~0.5% notional (mesma convencao do LONG; passa no cap 1%).
                    try {
                        . (Join-Path $agentsDir "lib_short_executor.ps1")
                        . (Join-Path $agentsDir "lib_capital_safety_enforcer.ps1")
                        . (Join-Path $agentsDir "lib_atr_stop.ps1")
                        . (Join-Path $agentsDir "lib_coinex.ps1") 2>$null
                        if (Get-Command Get-ExecutorSize -ErrorAction SilentlyContinue) { } else { . (Join-Path $agentsDir "lib_executor_sizing.ps1") 2>$null }

                        $cfgSL = $null
                        $cfgSLPath = Join-Path $projectRoot "config/short_universe.json"
                        if (Test-Path $cfgSLPath) { try { $cfgSL = Get-Content $cfgSLPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }
                        $liveOn = ($cfgSL -and $cfgSL.live_enabled -eq $true)
                        $tierA  = @(); if ($cfgSL -and $cfgSL.tier_a_live) { $tierA = @($cfgSL.tier_a_live) }

                        # So computa/loga p/ markets do tier_a_live (relevantes p/ live).
                        if ($tierA -contains $mkt) {
                            $gate    = Test-ShortLiveGate -Market $mkt -FlagPresent $liveOn -ShortTierA $tierA
                            $entryPx = [double]$closes[-1]
                            $atr = Get-AtrFromHighLow -Highs $highs -Lows $lows -Period 14
                            $capital = 0.0; try { $capital = [double](CoinEx-GetFuturesCapitalUSDT) } catch {}
                            $plan = Build-ShortOrderPlan -EntryPrice $entryPx -Capital ([math]::Max($capital,1)) -Atr $atr
                            # sizing notional ~0.5% (convencao do LONG; passa no cap 1% do capital_safety)
                            $usd_size = [math]::Round($capital * 0.005, 2)
                            if (Get-Command Get-ExecutorSize -ErrorAction SilentlyContinue) {
                                try { $usd_size = [double](Get-ExecutorSize -Market $mkt -Mode "GEM" -Capital $capital -BasePct 0.005).size_usd } catch {}
                            }
                            $cs = Invoke-CapitalSafetyCheck -AccountBalanceUsd $capital -EntryPrice $entryPx `
                                    -StoplossPrice $plan.stop -TargetPrice $plan.target -ProposedSizeUsd $usd_size -Market $mkt
                            $pos = $null; try { $pos = CoinEx-GetPosition $mkt } catch {}
                            $hasPos = ($pos -and @($pos).Count -gt 0)
                            $ready = Test-ShortEntryReady -PlanValid $plan.valid -GateAllow $gate.allow -Tier $tier `
                                        -ClusterExceeded ([bool]($cluster -and $cluster.exceeded)) -HasPosition $hasPos -CapitalSafe ([bool]$cs.passes)

                            # Log SEMPRE (auditoria), dispara ordem so se gate.allow (live_enabled+tier) e ready.
                            $liveTag = if ($liveOn) { "LIVE" } else { "DRY(live_off)" }
                            Log "  [SHORT $liveTag] $mkt plan: entry=$entryPx stop=$($plan.stop) target=$($plan.target) size=$usd_size cs_pass=$($cs.passes) pos=$hasPos -> ready=$($ready.ready) ($($ready.reason))"

                            if ($ready.ready -and $capital -gt 0 -and $usd_size -gt 0) {
                                $amount = [math]::Round($usd_size / $entryPx, 6)
                                $order = CoinEx-PlaceOrder $mkt "sell" "market" $amount $null $plan.stop $plan.target
                                Log "  [SHORT LIVE] $mkt ORDEM SHORT ENVIADA amount=$amount (~$usd_size USDT) stop=$($plan.stop) target=$($plan.target)"
                                try { Send-TelegramAlert -Message "[SHORT LIVE EXECUTADO] $mkt`namount=$amount (~$usd_size USDT)`nstop=$($plan.stop) target=$($plan.target)`nWSS=$wssScore Tier S (rollout BTC/ETH)" | Out-Null } catch {}
                            }
                        }
                    } catch { Log "  [SHORT LIVE] erro ${mkt}: $($_.Exception.Message)" }
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
    Write-CrossPlatformLog "=== SHORT SCANNER END ===" -LogFile "short_scanner.log"
    exit 0
    
} catch {
    Write-CrossPlatformLog "CRITICAL ERROR: $_" -Level ERROR -LogFile "short_scanner.log"
    Write-CrossPlatformLog $_.ScriptStackTrace -Level ERROR -LogFile "short_scanner.log"
    exit 1
}
