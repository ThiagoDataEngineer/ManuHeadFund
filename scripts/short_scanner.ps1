# short_scanner.ps1 -- SHORT signal scanner - CROSS-PLATFORM (Windows/Linux)
# Tier 2 Block 1 D.1 (2026-05-23): habilita SHORT observatory.
# Backtest T6 validou: 505 signals, EV +2.85pp, hit 60% -- POSITIVE EDGE.
#
# Universe: config/short_universe.json (git-tracked) -- 22 futures liquidos no
# observatorio, tier_a_live = 15 majors liquidos (ver live_enabled abaixo)
# Cadencia: HOURLY (mesma logica vol_climax)
# Output:
#   - journal/short_alerts.jsonl (append-only)
#   - TG alert Tier S apenas (Tier B silent log)
#   - Forward tracker registra cada Tier S signal pra audit posterior
#
# Modo: LIVE desde 2026-07-09 (config/short_universe.json live_enabled=true).
# Tier S + market em tier_a_live + Test-ShortEntryReady (plano valido + gate
# live + sem cluster cap + sem posicao + capital safety + funding-squeeze
# guard 2026-07-25) -> ordem real via CoinEx-PlaceOrder. Nao e so observatorio
# ha tempo; este comentario ficou desatualizado ate ser corrigido nesta data.
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

    # 2026-08-02: RADAR DINAMICO -- ate aqui o universo SHORT/FUTURES era 100%
    # a curadoria manual (config/short_universe.json, tier_a_live = 15 majors,
    # ultima atualizacao 2026-07-09). Owner percebeu real ("diminuiu futures,
    # aumentou spot") -- confirmado: o gem_executor.ps1 ganhou radar dinamico
    # ontem (commit f3fdef4) mas so roteia SPOT (sem leverage, por design);
    # este lado (FUTURES real) continuava travado na lista fixa. Soma os
    # movers dinamicos de 24h direto no tier_a_live (owner decidiu: confiar
    # nos gates de seguranca ja existentes -- Tori >=80, Mesa, Mentor, sizing
    # cap, funding-squeeze guard -- em vez de criar uma classe paper-only
    # separada). $__curatedTierALive/$__expandedUniverse ficam disponiveis
    # pro resto do script reusar (evita reler o arquivo cru 2x mais abaixo).
    $__curatedTierALive = @(); if ($cfgShort -and $cfgShort.tier_a_live) { $__curatedTierALive = @($cfgShort.tier_a_live) }
    $__expandedUniverse = [PSCustomObject]@{ markets = $markets; tier_a_live = $__curatedTierALive }
    try {
        . (Join-Path $agentsDir "lib_market_movers.ps1")
        . (Join-Path $agentsDir "lib_coinex.ps1") 2>$null
        if ((Get-Command CoinEx-GetAllFuturesTickers -ErrorAction SilentlyContinue) -and (Get-Command Get-DynamicShortUniverseWithTierALive -ErrorAction SilentlyContinue)) {
            $__allFutTickers = @(CoinEx-GetAllFuturesTickers)
            $__expandedUniverse = Get-DynamicShortUniverseWithTierALive -CuratedMarkets $markets -CuratedTierALive $__curatedTierALive -RawTickers $__allFutTickers
            $__newDynamic = @($__expandedUniverse.markets | Where-Object { $markets -notcontains $_ })
            if ($__newDynamic.Count -gt 0) {
                Log ("  [Radar dinamico SHORT] +$($__newDynamic.Count) movers de 24h direto no tier_a_live: " + ($__newDynamic -join ", "))
            }
            $markets = $__expandedUniverse.markets
        }
    } catch {
        Log "  [Radar dinamico SHORT] WARN: falhou, seguindo so com curadoria manual -- $_"
    }

    # TDD Sprint 1 (2026-05-23): Regime-specific thresholds
    # Detect current regime for adaptive thresholds
    $currentRegime = "BEAR_WEAK"  # Default fallback
    # 2026-07-04 CONTRATO: Get-CurrentRegime NUNCA existiu -> scanner rodava
    # regime-cego (sempre no fallback) desde a criacao. Fonte real:
    # $global:CURRENT_REGIME ou journal/regime_state.json (refresh_regime_state).
    #
    # 2026-07-23 FIX: journal/regime_state.json e escrito por regime_change_monitor.py
    # (processo Python que NAO roda em nenhum job do GitHub Actions -- nada no
    # workflow chama Python) E gitignored (nunca chega no runner isolado da nuvem).
    # Cadeia inteira desconectada: o scanner sempre caia no fallback hardcoded
    # "BEAR_WEAK", nunca uma medicao real -- so nao virava sintoma visivel porque
    # bateu por coincidencia com o regime real de 2026-07 (bear). Se o mercado
    # virasse BULL/BEAR_STRONG, os thresholds ficariam errados silenciosamente.
    # Fix: usar Get-MarketScenario (candles reais CoinEx, ja corrigido no mesmo
    # dia pra considerar SMA200) como fonte real -- bear_severity WEAK/STRONG
    # mapeia direto pro contrato de Get-ShortThresholdsForRegime.
    if ($global:CURRENT_REGIME) {
        $currentRegime = [string]$global:CURRENT_REGIME
    } else {
        try {
            if (-not (Get-Command Get-MarketScenario -ErrorAction SilentlyContinue)) {
                . (Join-Path $agentsDir "lib_market_scenario.ps1")
            }
            $scen = Get-MarketScenario
            if ($scen -and $scen.scenario -eq "BULL") {
                $currentRegime = "BULL"
            } elseif ($scen -and $scen.bear_severity -eq "STRONG") {
                $currentRegime = "BEAR_STRONG"
            } elseif ($scen -and $scen.bear_severity -eq "WEAK") {
                $currentRegime = "BEAR_WEAK"
            } elseif ($scen -and $scen.scenario -eq "BEAR") {
                $currentRegime = "BEAR_WEAK"
            } elseif ($scen -and $scen.scenario -in @("NEUTRO", "CAPITULACAO", "UNKNOWN")) {
                # Sem bear confirmado -- default conservador de Get-ShortThresholdsForRegime
                # (ClimaxMult=3.0 RSI>70), nao o hardcode BEAR_WEAK deste script.
                $currentRegime = $scen.scenario
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
                    # 2026-07-25: mensagem antiga sempre dizia "paper observatory /
                    # PAPER ONLY", mesmo para mercados live (tier_a_live) que vao
                    # executar ordem real logo abaixo -- enganoso. So promete
                    # paper-only quando o mercado de fato nao esta elegivel a live.
                    # 2026-08-02: usa $__expandedUniverse.tier_a_live (curados + movers
                    # dinamicos) em vez de reler o arquivo cru -- senao um mover dinamico
                    # (fora do JSON) nunca apareceria como "candidato a execucao real" aqui.
                    $__cfgSLPreview = $null
                    $__cfgSLPreviewPath = Join-Path $projectRoot "config/short_universe.json"
                    if (Test-Path $__cfgSLPreviewPath) { try { $__cfgSLPreview = Get-Content $__cfgSLPreviewPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }
                    $__tierAPreview = @($__expandedUniverse.tier_a_live)
                    $__liveEligible = ($__cfgSLPreview -and $__cfgSLPreview.live_enabled -eq $true -and ($__tierAPreview -contains $mkt))
                    $__execTag = if ($__liveEligible) { "candidato a execucao real (ver mensagem SHORT LIVE EXECUTADO a seguir se todos os gates passarem)" } else { "paper observatory (fora do tier_a_live)" }
                    $msg = "$bearIco [SHORT TIER S] $mkt $shortIco`nWSS=$wssScore ($__execTag)`nstrength=$($r.strength) vol_ratio=$($r.vol_ratio)x break=$($r.break_pct)% RSI=$($r.rsi)`nBTC DD=$([math]::Round($btcRegime.drawdown_pct,1))% vol_20d=$([math]::Round($btcRegime.vol_20d,2))%`nT6 backtest: EV +2.85pp em 505 signals."
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
                        # 2026-08-02: usa $__expandedUniverse.tier_a_live (curados + movers
                        # dinamicos de 24h) em vez de reler so o JSON cru -- senao um mover
                        # dinamico nunca passaria no gate de execucao real abaixo.
                        $tierA  = @($__expandedUniverse.tier_a_live)

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
                            # 2026-07-25: protecao contra short squeeze coordenado (knowledge/MANIPULATION.md
                            # -- funding muito negativo = shorts lotados = risco de squeeze). Nunca checado
                            # neste fluxo ate agora. Fail-closed: funding indisponivel tambem bloqueia.
                            $__fundingRate = $null
                            if (Get-Command CoinEx-GetFundingRate -ErrorAction SilentlyContinue) {
                                try { $__fundingRate = CoinEx-GetFundingRate $mkt } catch {}
                            }
                            $fundingCheck = Test-ShortFundingSafe -FundingRate $__fundingRate
                            $ready = Test-ShortEntryReady -PlanValid $plan.valid -GateAllow $gate.allow -Tier $tier `
                                        -ClusterExceeded ([bool]($cluster -and $cluster.exceeded)) -HasPosition $hasPos -CapitalSafe ([bool]$cs.passes) `
                                        -FundingSafe ([bool]$fundingCheck.safe)

                            # Log SEMPRE (auditoria), dispara ordem so se gate.allow (live_enabled+tier) e ready.
                            $liveTag = if ($liveOn) { "LIVE" } else { "DRY(live_off)" }
                            Log "  [SHORT $liveTag] $mkt plan: entry=$entryPx stop=$($plan.stop) target=$($plan.target) size=$usd_size cs_pass=$($cs.passes) pos=$hasPos -> ready=$($ready.ready) ($($ready.reason))"

                            if ($ready.ready -and $capital -gt 0 -and $usd_size -gt 0) {
                                # 2026-07-17 FIX (mesmo achado de gem_executor.ps1/faro_v3_entry.ps1:
                                # CoinEx-PlaceOrder abre FUTURES sem controle de leverage -- herda o
                                # que ja estiver configurado NA CONTA pro par). Terceiro caminho de
                                # execucao real achado pelo Oracle Detector 15. Fail-closed: se o
                                # ajuste falhar, pula a ordem.
                                . (Join-Path $agentsDir "lib_coinex_position_management.ps1") 2>$null
                                . (Join-Path $agentsDir "lib_leverage_cap.ps1") 2>$null
                                $__safeLeverage = if (Get-Command Get-SafeLeverage -ErrorAction SilentlyContinue) {
                                    [int](Get-SafeLeverage -ConvictionPercent ([int]$wssScore) -Mode "STANDARD")
                                } else { 2 }
                                $__levResult = if (Get-Command CoinEx-AdjustPositionLeverage -ErrorAction SilentlyContinue) {
                                    CoinEx-AdjustPositionLeverage -Market $mkt -Leverage $__safeLeverage -MarginMode "isolated"
                                } else { [PSCustomObject]@{ success = $false; error_msg = "CoinEx-AdjustPositionLeverage indisponivel" } }
                                if ($__levResult.success) {
                                    $amount = [math]::Round($usd_size / $entryPx, 6)
                                    $order = CoinEx-PlaceOrder $mkt "sell" "market" $amount $null $plan.stop $plan.target
                                    Log "  [SHORT LIVE] $mkt ORDEM SHORT ENVIADA amount=$amount (~$usd_size USDT) stop=$($plan.stop) target=$($plan.target) leverage=${__safeLeverage}x"
                                    try { Send-TelegramAlert -Message "[SHORT LIVE EXECUTADO] $mkt`namount=$amount (~$usd_size USDT)`nstop=$($plan.stop) target=$($plan.target)`nleverage=${__safeLeverage}x isolated`nWSS=$wssScore Tier S (tier_a_live, config/short_universe.json)" | Out-Null } catch {}
                                } else {
                                    Log "  [SHORT LIVE] $mkt BLOQUEADO -- falha ao fixar leverage segura (${__safeLeverage}x): $($__levResult.error_msg)"
                                }
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
