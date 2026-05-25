# gem_agent.ps1 -- Agente especializado em micro-caps explosivos na CoinEx
# R:R mínimo 1:20 | Alvo 1:200 | Sizing assimétrico 0.20-0.40%
# Ver: knowledge/GEM_COINS.md, PUMP_FINGERPRINTS.md, MICRO_LIQUIDITY.md, NARRATIVE_CATALYSTS.md

. (Join-Path $PSScriptRoot "lib_journal.ps1")
. (Join-Path $PSScriptRoot "lib_telegram.ps1")

# Promove para global (lido de config.ps1 se disponivel, senao fallback hardcoded)
$global:GEM_VOL_SPIKE_MIN    = if ($GEM_VOL_SPIKE_MIN)    { $GEM_VOL_SPIKE_MIN    } else { 2.0 }
$global:GEM_MCAP_DISCOVERY   = if ($GEM_MCAP_DISCOVERY)   { $GEM_MCAP_DISCOVERY   } else { 2000000.0 }
$global:GEM_MCAP_MOMENTUM    = if ($GEM_MCAP_MOMENTUM)    { $GEM_MCAP_MOMENTUM    } else { 20000000.0 }
$global:GEM_LISTING_DAYS_MAX = if ($GEM_LISTING_DAYS_MAX) { $GEM_LISTING_DAYS_MAX } else { 10 }
$global:GEM_CAPITAL_DISCOVERY= if ($GEM_CAPITAL_DISCOVERY){ $GEM_CAPITAL_DISCOVERY} else { 0.002 }
$global:GEM_CAPITAL_MOMENTUM = if ($GEM_CAPITAL_MOMENTUM) { $GEM_CAPITAL_MOMENTUM } else { 0.004 }
$global:GEM_STOP_DISCOVERY   = if ($GEM_STOP_DISCOVERY)   { $GEM_STOP_DISCOVERY   } else { 0.50 }
$global:GEM_STOP_MOMENTUM    = if ($GEM_STOP_MOMENTUM)    { $GEM_STOP_MOMENTUM    } else { 0.30 }
$global:GEM_TARGET_DISCOVERY = if ($GEM_TARGET_DISCOVERY) { $GEM_TARGET_DISCOVERY } else { 2.00 }
$global:GEM_TARGET_MOMENTUM  = if ($GEM_TARGET_MOMENTUM)  { $GEM_TARGET_MOMENTUM  } else { 0.90 }
$global:GEM_MAX_DAYS_DISC    = if ($GEM_MAX_DAYS_DISC)    { $GEM_MAX_DAYS_DISC    } else { 30 }
$global:GEM_MAX_DAYS_MOM     = if ($GEM_MAX_DAYS_MOM)     { $GEM_MAX_DAYS_MOM     } else { 21 }
$global:GEM_TRAILING_PCT     = if ($GEM_TRAILING_PCT)     { $GEM_TRAILING_PCT     } else { 0.30 }
$global:GEM_SCORE_MIN_DISC   = if ($GEM_SCORE_MIN_DISC)   { $GEM_SCORE_MIN_DISC   } else { 70 }
$global:GEM_SCORE_MIN_MOM    = if ($GEM_SCORE_MIN_MOM)    { $GEM_SCORE_MIN_MOM    } else { 60 }
$global:GEM_CV_ORGANIC_MIN   = if ($GEM_CV_ORGANIC_MIN)   { $GEM_CV_ORGANIC_MIN   } else { 0.5 }
$global:GEM_WASH_MAX_PCT     = if ($GEM_WASH_MAX_PCT)     { $GEM_WASH_MAX_PCT     } else { 0.40 }
$global:GEM_GREEN_RATIO_MIN  = if ($GEM_GREEN_RATIO_MIN)  { $GEM_GREEN_RATIO_MIN  } else { 0.65 }
$global:GEM_WICK_RATIO_MAX   = if ($GEM_WICK_RATIO_MAX)   { $GEM_WICK_RATIO_MAX   } else { 2.5 }
$global:GEM_RANGE_MIN_PCT    = if ($GEM_RANGE_MIN_PCT)    { $GEM_RANGE_MIN_PCT    } else { 0.15 }
$global:CAPITAL_TOTAL        = if ($CAPITAL_TOTAL)        { $CAPITAL_TOTAL        } else { 1000.0 }

# Keywords por tier
$GEM_KEYWORDS_T1 = @(
    # AI / Agents
    "AI","GPT","AGENT","NEURAL","BOT","AGI","LLM","CHAT","CLAUDE","GROK",
    # Memes
    "DOGE","SHIB","PEPE","CAT","WIF","BONK","FLOKI","ELON","TRUMP",
    "GHIBLI","PIXEL","WOJAK","CHAD","BASED","MEME","FROG","APE",
    # Infra narrativa quente
    "ZK","L2","DEPIN","DESCI","RWA","INTENT","RESTAKE"
)
$GEM_KEYWORDS_T2 = @(
    # DeFi / yield
    "YIELD","FARM","STAKE","DEX","SWAP","VAULT","PROTOCOL",
    # GameFi / NFT
    "GAME","PLAY","NFT","META",
    # Real world assets
    "GOLD","SILVER","REAL","BOND"
)
# Tier 3: projetos reais de infraestrutura — sem hype de meme mas com utilidade
# Pontuação menor (5pts) — suficiente para não ser filtrado pelo G4
$GEM_KEYWORDS_T3 = @(
    # Privacy / confidential compute
    "PRIVACY","PRIV","ZEC","XMR","DASH","FIRO","BEAM","GRIN","ROSE","OASIS",
    # Layer 1 / L1
    "LAYER","CHAIN","NETWORK","PROTOCOL","BASE","CORE","ONE","PRIME",
    # Bridges / interop
    "BRIDGE","CROSS","MULTI","OMNI","ANY","ROUTER","RELAY","PORT",
    # Storage / compute
    "STORAGE","STORE","FILE","DATA","NODE","COMPUTE","CLOUD","IPFS",
    # Oracle / data
    "ORACLE","FEED","LINK","BAND","API","INDEX",
    # Rollup / scaling
    "ROLLUP","SHARD","PARALLEL","MODULAR","WASM","EVM","MOVE",
    # Proof systems
    "PROOF","STARK","SNARK","PLONK","GROTH",
    # Cosmos / Polkadot ecosystem
    "COSMOS","ATOM","DOT","PARA","SUBSTRATE","IBC",
    # Infra genérica
    "INFRA","ARCH","BUILD","STACK","SDK","HUB","ZONE"
)

# ─────────────────────────────────────────────────────────────────────────────
# Get-CoinExVolSpike
# Calcula vol_hoje / avg_3d a partir de candles diários (mais recente é o último)
# ─────────────────────────────────────────────────────────────────────────────
function Get-CoinExVolSpike {
    param(
        [string]   $Market,
        [object[]] $DailyCandles
    )

    $fail = [PSCustomObject]@{
        market           = $Market
        vol_today        = 0.0
        avg_3d           = 0.0
        spike_ratio      = 0.0
        pct_change_today = 0.0
        spike_type       = "UNKNOWN"
        passed           = $false
        reason           = ""
    }

    if ($null -eq $DailyCandles -or $DailyCandles.Count -lt 4) {
        $fail.reason = "candles insuficientes (min 4 necessarios)"
        return $fail
    }

    $today  = [double]$DailyCandles[-1].volume
    $prev3  = $DailyCandles[-4..-2]
    $avg3   = ($prev3 | Measure-Object -Property volume -Average).Average

    if ($avg3 -le 0) {
        $fail.vol_today = $today
        $fail.reason    = "avg_3d = 0"
        return $fail
    }

    $ratio = [math]::Round($today / $avg3, 4)

    # Direcao do preco no dia do spike: vol alto + preco caindo = distribuicao
    $open_today  = [double]$DailyCandles[-1].open
    $close_today = [double]$DailyCandles[-1].close
    $pct_change  = if ($open_today -gt 0) { [math]::Round(($close_today - $open_today) / $open_today * 100, 2) } else { 0.0 }
    $spike_type  = if ($pct_change -le -10) { "BEARISH" } elseif ($pct_change -ge 5) { "BULLISH" } else { "NEUTRAL" }

    [PSCustomObject]@{
        market           = $Market
        vol_today        = $today
        avg_3d           = [math]::Round($avg3, 2)
        spike_ratio      = $ratio
        pct_change_today = $pct_change
        spike_type       = $spike_type
        passed           = $ratio -ge $global:GEM_VOL_SPIKE_MIN
        reason           = if ($ratio -ge $global:GEM_VOL_SPIKE_MIN) { "spike ${ratio}x tipo=$spike_type chg=${pct_change}%" } else { "spike ${ratio}x abaixo de $($global:GEM_VOL_SPIKE_MIN)x" }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Test-NarrativeMatch
# Verifica keyword no nome do par e/ou rank CoinGecko trending
# CoinGeckoRank: $null = sem dados; 1-500 = trending; > 500 = fora do trending
# ─────────────────────────────────────────────────────────────────────────────
function Test-NarrativeMatch {
    param(
        [string] $Market,
        [object] $CoinGeckoRank   # nullable
    )

    $name = $Market.ToUpper() -replace "USDT$",""

    $tier    = 0
    $keyword = ""

    foreach ($kw in $GEM_KEYWORDS_T1) {
        if ($name -like "*$kw*") {
            $tier    = 1
            $keyword = $kw
            break
        }
    }

    if ($tier -eq 0) {
        foreach ($kw in $GEM_KEYWORDS_T2) {
            if ($name -like "*$kw*") {
                $tier    = 2
                $keyword = $kw
                break
            }
        }
    }

    if ($tier -eq 0) {
        foreach ($kw in $GEM_KEYWORDS_T3) {
            if ($name -like "*$kw*") {
                $tier    = 3
                $keyword = $kw
                break
            }
        }
    }

    # score base por keyword
    $score_pts = switch ($tier) {
        1 { 15 }
        2 { 8  }
        3 { 5  }
        default { 0 }
    }

    # bonus/override por CoinGecko trending
    $trending_pts = 0
    if ($null -ne $CoinGeckoRank -and $CoinGeckoRank -le 500) {
        if ($CoinGeckoRank -le 200)     { $trending_pts = 15 }
        elseif ($CoinGeckoRank -le 350) { $trending_pts = 12 }
        else                            { $trending_pts = 8  }
    }

    # score final = max(keyword_pts, trending_pts) -- nao somam, maior vence
    $final_pts = if ($trending_pts -gt $score_pts) { $trending_pts } else { $score_pts }

    $matched = $tier -gt 0 -or ($null -ne $CoinGeckoRank -and $CoinGeckoRank -le 500)


    [PSCustomObject]@{
        matched       = $matched
        tier          = $tier
        keyword       = $keyword
        trending_rank = $CoinGeckoRank
        score_pts     = $final_pts
        reason        = if ($matched) { "keyword=$keyword tier=$tier rank=$CoinGeckoRank" } else { "sem narrativa" }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Test-OrganicAccumulation
# Detecta acumulação orgânica vs wash trading a partir de candles 5min/1min
# ─────────────────────────────────────────────────────────────────────────────
function Test-OrganicAccumulation {
    param(
        [object[]] $Candles5min,
        [object[]] $Candles1min,
        [object[]] $Candles1H = @()   # janela ampla para green_ratio (mais estável)
    )

    $fail = [PSCustomObject]@{
        organic_score = 0
        cv_volume     = 0.0
        green_ratio   = 0.0
        body_ratio    = 0.0
        wash_pct      = 0.0
        wash_detected = $false
        passed        = $false
        uncertain     = $false
        reason        = ""
    }

    $candles = if ($Candles5min.Count -ge $Candles1min.Count) { $Candles5min } else { $Candles1min }
    if ($null -eq $candles -or $candles.Count -lt 3) {
        $fail.reason = "candles insuficientes"
        return $fail
    }

    $vols   = @($candles | ForEach-Object { [double]$_.volume })
    $mean   = ($vols | Measure-Object -Average).Average
    if ($mean -le 0) { $fail.reason = "volume medio zero"; return $fail }

    # 1. Coeficiente de variação do volume (intraday 5min)
    $variance = ($vols | ForEach-Object { [math]::Pow($_ - $mean, 2) } | Measure-Object -Average).Average
    $stddev   = [math]::Sqrt($variance)
    $cv       = [math]::Round($stddev / $mean, 4)

    # 2. Detecção de wash: candles com volume idêntico (±5%)
    $wash_count = 0
    for ($i = 1; $i -lt $vols.Count; $i++) {
        $diff = [math]::Abs($vols[$i] - $vols[$i-1]) / $vols[$i-1]
        if ($diff -lt 0.05) { $wash_count++ }
    }
    $wash_pct = if ($vols.Count -gt 1) { [math]::Round($wash_count / ($vols.Count - 1), 4) } else { 0.0 }

    # 3. Green ratio — usa janela 1H (últimas 12h) se disponível, senão 5min
    # A janela 1H é mais estável: não é distorcida por um pullback temporário de 30min
    $green_source = if ($Candles1H.Count -ge 6) { $Candles1H | Select-Object -Last 12 } else { $candles }
    $green_vol  = ($green_source | Where-Object { [double]$_.close -gt [double]$_.open } | Measure-Object -Property volume -Sum).Sum
    $total_vol1h = ($green_source | Measure-Object -Property volume -Sum).Sum
    $green_ratio = if ($total_vol1h -gt 0) { [math]::Round($green_vol / $total_vol1h, 4) } else { 0.0 }

    # 4. Body ratio
    $body_ratios = $candles | ForEach-Object {
        $range = [double]$_.high - [double]$_.low
        if ($range -gt 0) { [math]::Abs([double]$_.close - [double]$_.open) / $range } else { 0 }
    }
    $body_ratio = [math]::Round(($body_ratios | Measure-Object -Average).Average, 4)

    # 5. Wick ratio (wicks superiores vs inferiores)
    $wick_ups   = @($candles | ForEach-Object { [double]$_.high - [math]::Max([double]$_.open, [double]$_.close) })
    $wick_downs = @($candles | ForEach-Object { [math]::Min([double]$_.open, [double]$_.close) - [double]$_.low })
    $avg_wick_up   = ($wick_ups   | Measure-Object -Average).Average
    $avg_wick_down = if (($wick_downs | Measure-Object -Average).Average -gt 0) { ($wick_downs | Measure-Object -Average).Average } else { 0.001 }
    $wick_ratio    = [math]::Round($avg_wick_up / $avg_wick_down, 4)

    # Score acumulativo (0–100)
    $score = 0
    if ($cv -ge $global:GEM_CV_ORGANIC_MIN)         { $score += 25 }  # volumes heterogêneos
    if ($green_ratio -ge $global:GEM_GREEN_RATIO_MIN){ $score += 20 }  # compradores dominantes (janela 1H)
    if ($body_ratio -ge 0.55)                        { $score += 15 }  # candles com corpo
    if ($wash_pct -lt $global:GEM_WASH_MAX_PCT)      { $score += 20 }  # sem wash
    if ($wick_ratio -le $global:GEM_WICK_RATIO_MAX)  { $score += 20 }  # sem pressão vendedora

    $wash_detected = $wash_pct -ge $global:GEM_WASH_MAX_PCT
    # Zona de incerteza: score 45–54 e sem wash confirmado → não reprova, sinaliza incerteza
    $uncertain = ($score -ge 45 -and $score -lt 55) -and (-not $wash_detected)
    $passed    = ($score -ge 55 -and -not $wash_detected) -or $uncertain

    [PSCustomObject]@{
        organic_score = $score
        cv_volume     = $cv
        green_ratio   = $green_ratio
        body_ratio    = $body_ratio
        wash_pct      = $wash_pct
        wash_detected = $wash_detected
        passed        = $passed
        uncertain     = $uncertain
        reason        = "cv=$cv green=$green_ratio wash=$wash_pct wick_ratio=$wick_ratio$(if($uncertain){' [INCERTO]'})"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Invoke-GemScore
# Consolida todos os gates em score 0-100 e determina modo DISCOVERY/MOMENTUM
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-GemScore {
    param(
        [string] $Market,
        [object] $VolData,
        [object] $NarrativeData,
        [double] $McapUsd,
        [double] $PctRange,
        [bool]   $StructurePassed,
        [object] $OrganicData,
        [double] $FingerprintScore,
        [object] $ListingDays  = $null,
        [object] $LogoUrl      = $null,
        [object] $BtcDominance = $null
    )

    # Narrativa human-readable (Tier1 keyword + trending rank N, Tier1 keyword: KW, trending rank N, ou null)
    $narrative_str = $null
    if ($NarrativeData -and $NarrativeData.matched) {
        $has_kw    = $NarrativeData.tier -gt 0
        $has_trend = $null -ne $NarrativeData.trending_rank -and $NarrativeData.trending_rank -le 500
        if ($has_kw -and $has_trend) {
            $narrative_str = "Tier$($NarrativeData.tier) keyword $($NarrativeData.keyword) + trending rank $($NarrativeData.trending_rank)"
        } elseif ($has_kw) {
            $narrative_str = "Tier$($NarrativeData.tier) keyword: $($NarrativeData.keyword)"
        } elseif ($has_trend) {
            $narrative_str = "trending rank $($NarrativeData.trending_rank)"
        }
    }

    # Fingerprint match human-readable
    $fp_match = if ($FingerprintScore -ge 70) { "strong match ($FingerprintScore)" }
                elseif ($FingerprintScore -ge 40) { "weak match ($FingerprintScore)" }
                else { $null }

    # Organic score (0-100) ou null
    $org_score = if ($OrganicData -and ($OrganicData.PSObject.Properties.Name -contains "organic_score")) { $OrganicData.organic_score } else { $null }

    # Bloco comum de campos auxiliares para retornos de short-circuit
    function _gemExtras {
        param($Gates)
        @{
            mcap_usd          = if ($McapUsd -gt 0) { $McapUsd } else { $null }
            listing_days      = $ListingDays
            narrative         = $narrative_str
            organic_score     = $org_score
            gates_passed      = $Gates
            fingerprint_match = $fp_match
            btc_dominance     = $BtcDominance
            logo_url          = $LogoUrl
        }
    }

    # G1 -- Volume spike
    if (-not $VolData.passed) {
        $o = [ordered]@{ market=$Market; score=0; mode="NONE"; gates_passed=@(); gate_failed="G1"; sizing_pct=0.0; alerta="BLOQUEADO -- G1: vol spike insuficiente" }
        (_gemExtras @()).GetEnumerator() | ForEach-Object { $o[$_.Key] = $_.Value }
        return [PSCustomObject]$o
    }

    # G1B -- Spike bearish: vol alto + preco caindo = distribuicao, nao acumulacao
    if ($VolData.spike_type -eq "BEARISH") {
        $o = [ordered]@{ market=$Market; score=0; mode="NONE"; gates_passed=@("G1"); gate_failed="G1B"; sizing_pct=0.0; alerta="BLOQUEADO -- G1B: spike de distribuicao (chg=$($VolData.pct_change_today)% com spike $($VolData.spike_ratio)x)" }
        (_gemExtras @("G1")).GetEnumerator() | ForEach-Object { $o[$_.Key] = $_.Value }
        return [PSCustomObject]$o
    }

    # G3 -- Mcap (antes de G2 para evitar chamadas desnecessarias)
    # G1 ja passou neste ponto, entao gates_passed contem ao menos G1
    if ($McapUsd -gt $global:GEM_MCAP_MOMENTUM) {
        $o = [ordered]@{ market=$Market; score=0; mode="NONE"; gates_passed=@("G1"); gate_failed="G3"; sizing_pct=0.0; alerta="BLOQUEADO -- G3: mcap acima do limite" }
        (_gemExtras @("G1")).GetEnumerator() | ForEach-Object { $o[$_.Key] = $_.Value }
        return [PSCustomObject]$o
    }

    $gates_passed = @("G1")
    $score = 0

    # G1 -- já passou: +25
    $score += 25

    # G2 -- Range diário
    if ($PctRange -ge $global:GEM_RANGE_MIN_PCT) {
        $score += 15
        $gates_passed += "G2"
    }

    # G3 -- Mcap dentro do limite
    $score += 15
    $gates_passed += "G3"

    # G4 -- Narrativa (obrigatório — sem narrativa = whale dump, não gem)
    if (-not $NarrativeData.matched) {
        $o = [ordered]@{ market=$Market; score=0; mode="NONE"; gates_passed=$gates_passed; gate_failed="G4"; sizing_pct=0.0; alerta="BLOQUEADO -- G4: sem narrativa identificavel" }
        (_gemExtras $gates_passed).GetEnumerator() | ForEach-Object { $o[$_.Key] = $_.Value }
        return [PSCustomObject]$o
    }
    $score += $NarrativeData.score_pts
    $gates_passed += "G4"

    # G5 -- Estrutura intraday
    if ($StructurePassed) {
        $score += 10
        $gates_passed += "G5"
    }

    # G6 -- Orgânico vs wash
    if ($OrganicData.passed -and -not $OrganicData.uncertain) {
        $score += 10
        $gates_passed += "G6"
    } elseif ($OrganicData.uncertain) {
        $score -= 5    # zona de incerteza: penalidade suave, não bloqueio total
        $gates_passed += "G6?"
    } elseif ($OrganicData.wash_detected) {
        $score -= 10   # wash confirmado: penalidade total
    }

    # G7 -- Fingerprint match
    if ($FingerprintScore -ge 70) {
        $score += 10
        $gates_passed += "G7"
    } elseif ($FingerprintScore -ge 40) {
        $score += 5
    }

    # G8 (2026-05-18) -- LATE PUMP PENALTY
    # Tese: pump >40% no dia = late stage (smart money ja vendeu, retail FOMO).
    # GemAgent detecta pumps DEPOIS de iniciados. Score deve refletir entry tardia.
    # Calibracao inicial heuristica (sem backtest formal); ver BACKLOG_TIER4 Item 9.
    $pctToday = 0.0
    try { $pctToday = [double]$VolData.pct_change_today } catch {}
    if ($pctToday -gt 60) {
        $score -= 25            # entry MUITO tardia, blow-off topo
        $gates_passed += "G8-VERY_LATE"
    } elseif ($pctToday -gt 40) {
        $score -= 15            # late stage
        $gates_passed += "G8-LATE"
    } elseif ($pctToday -gt 25) {
        $score -= 5             # mid-stage, alerta leve
        $gates_passed += "G8-MID"
    }

    # C. Tori PROXIMITY confluence 2026-05-22: opt-in flag pra cross-ref
    # vol_spike com snapshot anticipatorio. Zero risco LIVE (flag ausente = no-op).
    # +5 se ripening confluente com direcao do pump; chase_risk_high tag se
    # proximity invalida + price > 15% above qualquer action_line (Mentor pode vetar).
    $chaseRiskHigh = $false
    $confluenceTag = ''
    $confluenceFlag = Join-Path (Split-Path $PSScriptRoot -Parent) "journal\TORI_PROXIMITY_CONFLUENCE.flag"
    if ((Test-Path $confluenceFlag) -and (Get-Command Get-ToriProximityForMarket -ErrorAction SilentlyContinue)) {
        try {
            $statePath = Join-Path (Split-Path $PSScriptRoot -Parent) "journal\tori_proximity_state.json"
            $tp = Get-ToriProximityForMarket -Market $Market -StatePath $statePath -MaxAgeMinutes 30
            if ($tp) {
                if ([bool]$tp.setup_ripening -and ($tp.side -eq "LONG") -and ($pctToday -ge 5)) {
                    # LONG ripening + price subindo no dia = confluente: bump moderado
                    $score += 5
                    $confluenceTag = "G9-TORI-LONG-RIPE"
                } elseif (-not [bool]$tp.valid) {
                    # proximity nao computou (data missing) — neutro, nao tag
                } else {
                    # Tori valid mas nao ripening: se preco MUITO acima de action_line, chase
                    $absProx = [Math]::Abs([double]$tp.proximity_pct)
                    if ($absProx -gt 15.0) {
                        $chaseRiskHigh = $true
                        $confluenceTag = "G9-CHASE-RISK-${absProx}pct"
                    }
                }
                if ($confluenceTag) { $gates_passed += $confluenceTag }
            }
        } catch {}
    }

    $score = [math]::Max(0, [math]::Min(100, $score))

    # Modo e gate_failed
    $mode       = if ($McapUsd -le $global:GEM_MCAP_DISCOVERY) { "DISCOVERY" } else { "MOMENTUM" }
    $threshold  = if ($mode -eq "DISCOVERY") { $global:GEM_SCORE_MIN_DISC } else { $global:GEM_SCORE_MIN_MOM }
    $gate_fail  = if ($score -lt $threshold) {
        if (-not $NarrativeData.matched) { "G4" }
        elseif (-not $OrganicData.passed) { "G6" }
        else { "SCORE" }
    } else { $null }

    $sizing = if ($mode -eq "DISCOVERY") { $global:GEM_CAPITAL_DISCOVERY } else { $global:GEM_CAPITAL_MOMENTUM }

    $out = [ordered]@{
        market          = $Market
        score           = $score
        mode            = $mode
        gates_passed    = $gates_passed
        gate_failed     = $gate_fail
        sizing_pct      = if ($score -ge $threshold) { $sizing } else { 0.0 }
        chase_risk_high = [bool]$chaseRiskHigh   # C 2026-05-22: Mentor le como flag
        alerta          = if ($score -ge $threshold) { "$mode score=$score gates=$($gates_passed -join ',')" } else { "score $score abaixo do threshold $threshold" }
    }
    (_gemExtras $gates_passed).GetEnumerator() | ForEach-Object { $out[$_.Key] = $_.Value }
    [PSCustomObject]$out
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-GemSizing
# Retorna parâmetros de sizing para DISCOVERY ou MOMENTUM
# ─────────────────────────────────────────────────────────────────────────────
function Get-GemSizing {
    param(
        [string] $Mode,
        [double] $BtcDominance,
        [double] $Capital = $global:CAPITAL_TOTAL
    )

    $is_discovery = $Mode -eq "DISCOVERY"

    $sizing_pct  = if ($is_discovery) { $global:GEM_CAPITAL_DISCOVERY } else { $global:GEM_CAPITAL_MOMENTUM }
    $stop_pct    = if ($is_discovery) { $global:GEM_STOP_DISCOVERY    } else { $global:GEM_STOP_MOMENTUM    }
    $target_pct  = if ($is_discovery) { $global:GEM_TARGET_DISCOVERY  } else { $global:GEM_TARGET_MOMENTUM  }
    $max_days    = if ($is_discovery) { $global:GEM_MAX_DAYS_DISC     } else { $global:GEM_MAX_DAYS_MOM     }

    [PSCustomObject]@{
        mode           = $Mode
        sizing_pct     = $sizing_pct
        sizing_usd     = [math]::Round($Capital * $sizing_pct, 2)
        stop_pct       = $stop_pct
        target_pct     = $target_pct
        max_days       = $max_days
        moon_bag_pct   = 0.50
        trailing_pct   = $global:GEM_TRAILING_PCT
        btc_dominance  = $BtcDominance
        regime_note    = if ($BtcDominance -gt 55) { "dominancia $BtcDominance pct -- priorizar DISCOVERY" } else { "dominancia $BtcDominance pct -- ambos os modos ativos" }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-GemSpotTickers
# Busca todos os tickers spot da CoinEx em uma chamada (evita N x 1017 chamadas)
# Retorna apenas pares USDT com vol_24h entre $MinVol e $MaxVol
# ─────────────────────────────────────────────────────────────────────────────
function Get-GemSpotTickers {
    param(
        [double] $MinVol = 5000.0,
        [double] $MaxVol = 5000000.0
    )
    try {
        $r = Invoke-RestMethod -Uri "$global:COINEX_BASE_URL/v2/spot/ticker" -Method GET
        if ($r.code -ne 0) { return @() }
        return $r.data | Where-Object {
            $_.market -match "USDT$" -and
            [double]$_.value -ge $MinVol -and
            [double]$_.value -le $MaxVol
        } | ForEach-Object {
            [PSCustomObject]@{
                market   = $_.market
                last     = [double]$_.last
                vol_24h  = [double]$_.value     # USDT
                high_24h = [double]$_.high
                low_24h  = [double]$_.low
                open_24h = [double]$_.open
            }
        }
    } catch { return @() }
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-GemCoinGeckoData
# Busca mcap e trending rank para um par. Rate-limited: sleep 700ms.
# CoinGeckoRank: 1-7 = top trending daily (free endpoint /search/trending)
# ─────────────────────────────────────────────────────────────────────────────
function Get-GemCoinGeckoData {
    param([string]$Market)
    $coin = $Market -replace "USDT$","" -replace "BTC$","" | ForEach-Object { $_.ToLower() }
    try {
        $r = Invoke-RestMethod -Uri "https://api.coingecko.com/api/v3/coins/$coin`?localization=false&tickers=false&market_data=true&community_data=false&developer_data=false" -Method GET
        Start-Sleep -Milliseconds 700
        $mcap = if ($r.market_data.market_cap.usd) { [double]$r.market_data.market_cap.usd } else { 0.0 }
        # logo_url da MESMA resposta (sem nova chamada HTTP)
        $logo = if ($r.image -and $r.image.small) { [string]$r.image.small } else { $null }
        # listing_days a partir de genesis_date (mesma resposta)
        $listing_days = $null
        if ($r.genesis_date) {
            try {
                $gd = [datetime]::Parse([string]$r.genesis_date)
                $listing_days = [int]((Get-Date) - $gd).TotalDays
            } catch { $listing_days = $null }
        }
        return [PSCustomObject]@{ mcap=$mcap; rank=$null; found=$true; logo_url=$logo; listing_days=$listing_days }
    } catch {
        return [PSCustomObject]@{ mcap=0.0; rank=$null; found=$false; logo_url=$null; listing_days=$null }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-CoinGeckoTrendingRanks
# Retorna hashtable {coinSymbol -> rank} para os top 7 trending do dia.
# Uma chamada para todo o scan (reutilizar).
# ─────────────────────────────────────────────────────────────────────────────
function Get-CoinGeckoTrendingRanks {
    try {
        $r = Invoke-RestMethod -Uri "https://api.coingecko.com/api/v3/search/trending" -Method GET
        $ranks = @{}
        $i = 1
        foreach ($item in $r.coins) {
            $sym = $item.item.symbol.ToUpper()
            $ranks[$sym] = $i
            $i++
        }
        return $ranks
    } catch { return @{} }
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-GemStructureScore
# Gate G5: verifica VWAP intraday (1H) e estrutura HH/HL nascente
# Retorna $true se preço > VWAP e último HH acima do anterior
# ─────────────────────────────────────────────────────────────────────────────
function Get-GemStructureScore {
    param([object[]] $Candles1H)
    if ($null -eq $Candles1H -or $Candles1H.Count -lt 8) { return $false }
    $last = $Candles1H[-8..-1]
    # VWAP = sum(typical_price * volume) / sum(volume)
    $tp_vol = ($last | ForEach-Object { (([double]$_.high + [double]$_.low + [double]$_.close) / 3) * [double]$_.volume } | Measure-Object -Sum).Sum
    $vol    = ($last | Measure-Object -Property volume -Sum).Sum
    if ($vol -le 0) { return $false }
    $vwap   = $tp_vol / $vol
    $close  = [double]$last[-1].close
    # HH/HL: último high > penúltimo high
    $hh = [double]$last[-1].high -gt [double]$last[-2].high
    return ($close -gt $vwap) -and $hh
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-GemFingerprintScore
# Consulta tabela pump_fingerprints no Supabase.
# Retorna 50 (neutro) se biblioteca não configurada.
# ─────────────────────────────────────────────────────────────────────────────
function Get-GemFingerprintScore {
    param(
        [object[]] $Candles1min,
        [string]   $Market
    )

    # Métricas do candidato atual
    $vols = @($Candles1min | ForEach-Object { [double]$_.volume })
    if ($vols.Count -lt 5) { return 50 }
    $mean = ($vols | Measure-Object -Average).Average
    if ($mean -le 0) { return 50 }
    $var  = ($vols | ForEach-Object { [math]::Pow($_ - $mean, 2) } | Measure-Object -Average).Average
    $cv   = [math]::Sqrt($var) / $mean
    $green_vol   = ($Candles1min | Where-Object { [double]$_.close -gt [double]$_.open } | Measure-Object -Property volume -Sum).Sum
    $total_vol   = ($vols | Measure-Object -Sum).Sum
    $green_ratio = if ($total_vol -gt 0) { $green_vol / $total_vol } else { 0 }

    $library = @()

    # Fonte 1: Supabase (se configurado)
    $supabase_url = $env:SUPABASE_URL
    $supabase_key = if ($env:SUPABASE_SERVICE_KEY) { $env:SUPABASE_SERVICE_KEY } else { $env:SUPABASE_ANON_KEY }
    if ($supabase_url -and $supabase_key) {
        try {
            $headers  = @{ "apikey"="$supabase_key"; "Authorization"="Bearer $supabase_key"; "Content-Type"="application/json" }
            $fp_resp  = Invoke-RestMethod -Uri "$supabase_url/rest/v1/pump_fingerprints?select=cv_volume,green_ratio,outcome_pct&order=outcome_pct.desc&limit=20" -Method GET -Headers $headers
            if ($fp_resp -and $fp_resp.Count -gt 0) {
                $library += $fp_resp | ForEach-Object { [PSCustomObject]@{ cv_volume=[double]$_.cv_volume; green_ratio=[double]$_.green_ratio; outcome_pct=[double]$_.outcome_pct } }
            }
        } catch {}
    }

    # Fonte 2: journal local (gem_signals.csv) — gems aprovados com outcome futuro
    # Usa apenas entradas onde gate_failed está vazio (aprovados) como referência positiva
    $journalFile = Join-Path $global:JOURNAL_DIR "gem_signals.csv"
    if (Test-Path $journalFile) {
        try {
            $approved = Import-Csv $journalFile -Encoding utf8 |
                Where-Object { -not $_.gate_failed -and [double]$_.spike_ratio -gt 0 }
            foreach ($row in $approved) {
                # Recalcula cv e green_ratio do spike_ratio como proxy (dados reais não armazenados)
                # Usa spike_ratio normalizado como cv_volume proxy e pct_change_today para green_ratio proxy
                $proxy_cv    = [math]::Min(2.0, [double]$row.spike_ratio / 5.0)
                $proxy_green = if ([double]$row.pct_change_today -gt 0) { 0.65 + ([double]$row.pct_change_today / 100) } else { 0.35 }
                $library += [PSCustomObject]@{ cv_volume=$proxy_cv; green_ratio=[math]::Min(1.0,$proxy_green); outcome_pct=0 }
            }
        } catch {}
    }

    if ($library.Count -eq 0) { return 50 }

    # Similaridade euclidiana normalizada contra a biblioteca
    $scores = @()
    foreach ($fp in $library) {
        $d_cv    = [math]::Abs($cv - $fp.cv_volume)
        $d_green = [math]::Abs($green_ratio - $fp.green_ratio)
        $dist    = [math]::Sqrt($d_cv * $d_cv + $d_green * $d_green)
        $sim     = [math]::Max(0, [math]::Round((1 - ($dist / 1.414)) * 100))
        $scores += $sim
    }
    return [math]::Round(($scores | Measure-Object -Average).Average)
}

# ─────────────────────────────────────────────────────────────────────────────
# Invoke-GemScan
# Pipeline completo: todos os pares CoinEx → 7 gates → alertas ranqueados
#
# Uso:
#   Invoke-GemScan                          # top 5, capital de config
#   Invoke-GemScan -TopN 10 -Capital 5000   # top 10
#   Invoke-GemScan -DryRun                  # sem alertas, apenas logs
#   Invoke-GemScan -SkipCoinGecko           # sem chamadas CoinGecko (mais rápido)
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-GemScan {
    param(
        [int]    $TopN          = 5,
        [switch] $DryRun,
        [double] $Capital       = 0,
        [switch] $SkipCoinGecko,
        [double] $MinVol24h     = 5000.0,
        [double] $MaxVol24h     = 5000000.0
    )
    # Capital FUTURES real (CoinEx-first) — GemAgent opera futures com fallback spot
    if ($Capital -le 0) {
        try   { $Capital = CoinEx-GetFuturesCapitalUSDT }
        catch { $Capital = $global:CAPITAL_FUTURES }
    }

    $sep = "-" * 60
    Write-Host "`n$sep" -ForegroundColor Cyan
    Write-Host "  GemAgent Scan -- $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
    Write-Host $sep -ForegroundColor Cyan

    # ── Fase 0: Trending CoinGecko (uma chamada para o scan inteiro) ──────────
    $trending_ranks = @{}
    if (-not $SkipCoinGecko) {
        Write-Host "  [0/5] Buscando trending CoinGecko..." -ForegroundColor Gray
        $trending_ranks = Get-CoinGeckoTrendingRanks
        Write-Host "        $($trending_ranks.Count) coins trending hoje" -ForegroundColor Gray
    }

    # ── Fase 1: Todos os tickers spot (uma chamada) ───────────────────────────
    Write-Host "  [1/5] Buscando todos os tickers USDT (vol $$MinVol24h -- $$MaxVol24h)..." -ForegroundColor Gray
    $tickers = Get-GemSpotTickers -MinVol $MinVol24h -MaxVol $MaxVol24h
    Write-Host "        $($tickers.Count) pares no universo micro-cap" -ForegroundColor Gray

    # ── Fase 2: Filtro rapido G1+G2 via range do ticker (sem klines extras) ───
    Write-Host "  [2/5] Pre-filtro: range > $($global:GEM_RANGE_MIN_PCT * 100)%..." -ForegroundColor Gray
    $pre_filtered = $tickers | Where-Object {
        $open = $_.open_24h
        if ($open -le 0) { return $false }
        $pct = ($_.high_24h - $_.low_24h) / $open
        $pct -ge $global:GEM_RANGE_MIN_PCT
    }
    Write-Host "        $($pre_filtered.Count) pares com range suficiente" -ForegroundColor Gray

    # ── Fase 3: Candles diarios + spike ratio (G1 real) ──────────────────────
    Write-Host "  [3/5] Calculando vol spike (4 candles diarios por par)..." -ForegroundColor Gray
    $spike_candidates = @()
    foreach ($t in $pre_filtered) {
        try {
            $kr = Invoke-RestMethod -Uri "$global:COINEX_BASE_URL/v2/spot/kline?market=$($t.market)&period=1day&limit=4" -Method GET
            if ($kr.code -ne 0) { continue }
            $daily = $kr.data | ForEach-Object {
                [PSCustomObject]@{ open=[double]$_.open; high=[double]$_.high; low=[double]$_.low; close=[double]$_.close; volume=[double]$_.volume; ts=$_.created_at }
            }
            $vol_data = Get-CoinExVolSpike -Market $t.market -DailyCandles $daily
            if (-not $vol_data.passed) { continue }
            $pct_range = if ($daily[-1].open -gt 0) { ([double]$daily[-1].high - [double]$daily[-1].low) / [double]$daily[-1].open } else { 0 }
            $spike_candidates += [PSCustomObject]@{
                ticker    = $t
                vol_data  = $vol_data
                daily     = $daily
                pct_range = $pct_range
            }
        } catch { }
    }
    Write-Host "        $($spike_candidates.Count) pares com vol spike >= $($global:GEM_VOL_SPIKE_MIN)x" -ForegroundColor Gray
    if ($spike_candidates.Count -eq 0) {
        Write-Host "`n  Nenhum candidato encontrado hoje." -ForegroundColor Yellow
        return @()
    }

    # ── Fase 4: Narrativa G4 + Mcap G3 ──────────────────────────────────────
    Write-Host "  [4/5] Verificando narrativa e mcap..." -ForegroundColor Gray
    $narrative_candidates = @()
    $all_scan_results     = @()   # journal: todos os pares analisados
    foreach ($c in $spike_candidates) {
        $mkt = $c.ticker.market
        $sym = $mkt -replace "USDT$",""

        # G4 keyword (gratis)
        $cg_rank = if ($trending_ranks.ContainsKey($sym)) { $trending_ranks[$sym] } else { $null }
        $narrative = Test-NarrativeMatch -Market $mkt -CoinGeckoRank $cg_rank
        if (-not $narrative.matched) {
            Write-Host "        $mkt -- sem narrativa (bloqueado G4)" -ForegroundColor DarkGray
            $all_scan_results += [PSCustomObject]@{ market=$mkt; score=0; mode="NONE"; gates_passed=@("G1","G2"); gate_failed="G4"; sizing_pct=0.0; alerta="bloqueado G4"; vol_data=$c.vol_data; mcap_usd=0; sizing=$null }
            continue
        }

        # G3 mcap via CoinGecko (com rate limiting)
        # Mesma resposta tambem traz logo (image.small) e listing days (genesis_date)
        $mcap         = 0.0
        $logo_url     = $null
        $listing_days = $null
        if (-not $SkipCoinGecko) {
            $cg = Get-GemCoinGeckoData -Market $mkt
            $mcap         = $cg.mcap
            $logo_url     = $cg.logo_url
            $listing_days = $cg.listing_days
        }

        $narrative_candidates += [PSCustomObject]@{
            ticker       = $c.ticker
            vol_data     = $c.vol_data
            pct_range    = $c.pct_range
            narrative    = $narrative
            mcap         = $mcap
            logo_url     = $logo_url
            listing_days = $listing_days
        }
    }
    Write-Host "        $($narrative_candidates.Count) pares com narrativa confirmada" -ForegroundColor Gray

    # ── Fase 5: Candles intraday + organico + estrutura + score ──────────────
    Write-Host "  [5/5] Analisando estrutura e volume intraday..." -ForegroundColor Gray
    $alerts = @()
    foreach ($c in $narrative_candidates) {
        $mkt = $c.ticker.market
        try {
            # 1H para estrutura (G5)
            $kr1h = Invoke-RestMethod -Uri "$global:COINEX_BASE_URL/v2/spot/kline?market=$mkt&period=1hour&limit=24" -Method GET
            $c1h = @()
            if ($kr1h.code -eq 0) {
                $c1h = $kr1h.data | ForEach-Object {
                    [PSCustomObject]@{ open=[double]$_.open; high=[double]$_.high; low=[double]$_.low; close=[double]$_.close; volume=[double]$_.volume }
                }
            }
            $structure = Get-GemStructureScore -Candles1H $c1h

            # 5min para deteccao organica (G6)
            $kr5 = Invoke-RestMethod -Uri "$global:COINEX_BASE_URL/v2/spot/kline?market=$mkt&period=5min&limit=60" -Method GET
            $c5 = @()
            if ($kr5.code -eq 0) {
                $c5 = $kr5.data | ForEach-Object {
                    [PSCustomObject]@{ open=[double]$_.open; high=[double]$_.high; low=[double]$_.low; close=[double]$_.close; volume=[double]$_.volume }
                }
            }

            # 1min para fingerprint (G7)
            $kr1 = Invoke-RestMethod -Uri "$global:COINEX_BASE_URL/v2/spot/kline?market=$mkt&period=1min&limit=60" -Method GET
            $c1 = @()
            if ($kr1.code -eq 0) {
                $c1 = $kr1.data | ForEach-Object {
                    [PSCustomObject]@{ open=[double]$_.open; high=[double]$_.high; low=[double]$_.low; close=[double]$_.close; volume=[double]$_.volume }
                }
            }

            $organic     = Test-OrganicAccumulation -Candles5min $c5 -Candles1min $c1 -Candles1H $c1h
            $fp_score    = Get-GemFingerprintScore   -Candles1min $c1 -Market $mkt

            $gem = Invoke-GemScore `
                -Market      $mkt `
                -VolData     $c.vol_data `
                -NarrativeData $c.narrative `
                -McapUsd     $c.mcap `
                -PctRange    $c.pct_range `
                -StructurePassed $structure `
                -OrganicData $organic `
                -FingerprintScore $fp_score `
                -ListingDays $c.listing_days `
                -LogoUrl     $c.logo_url `
                -BtcDominance $null

            $gem | Add-Member -NotePropertyName vol_data  -NotePropertyValue $c.vol_data  -Force
            $gem | Add-Member -NotePropertyName mcap_usd  -NotePropertyValue $c.mcap      -Force
            if ($gem.score -gt 0) {
                $sz = Get-GemSizing -Mode $gem.mode -Capital $Capital -BtcDominance 0
                $gem | Add-Member -NotePropertyName sizing -NotePropertyValue $sz -Force
                $alerts += $gem
            }
            $all_scan_results += $gem
        } catch {
            Write-Host "        $mkt -- erro: $($_.Exception.Message)" -ForegroundColor DarkRed
        }
    }

    # ── Journal ────────────────────────────────────────────────────────────────
    if ($all_scan_results.Count -gt 0) {
        Write-GemScanJournal -AllResults $all_scan_results
    }

    # ── Alertas Telegram ──────────────────────────────────────────────────────
    $top = $alerts | Sort-Object score -Descending | Select-Object -First $TopN
    if (-not $DryRun) {
        foreach ($a in $top) {
            $hasFut = CoinEx-HasFuturesMarket $a.market
            $mktType = if ($hasFut) { "FUTURES" } else { "SPOT" }
            Send-GemAlert -Gem $a -MarketType $mktType | Out-Null
        }
    }

    # ── Relatorio ──────────────────────────────────────────────────────────────
    Write-Host "`n$sep" -ForegroundColor Cyan
    Write-Host "  TOP $TopN GEMS -- $(Get-Date -Format 'yyyy-MM-dd')" -ForegroundColor Cyan
    Write-Host $sep -ForegroundColor Cyan

    if ($top.Count -eq 0) {
        Write-Host "  Nenhum gem encontrado com os critérios atuais." -ForegroundColor Yellow
    }
    foreach ($a in $top) {
        $sz    = $a.sizing
        $mode_color = if ($a.mode -eq "DISCOVERY") { "Magenta" } else { "Yellow" }
        $score_color = if ($a.score -ge 70) { "Green" } else { "Yellow" }
        Write-Host ""
        Write-Host "  $($a.market)" -ForegroundColor White -NoNewline
        Write-Host "  [$($a.mode)]" -ForegroundColor $mode_color -NoNewline
        Write-Host "  score=$($a.score)" -ForegroundColor $score_color
        Write-Host "  Gates: $($a.gates_passed -join ', ')" -ForegroundColor Gray
        Write-Host "  Vol spike: $($a.vol_data.spike_ratio)x" -ForegroundColor Gray
        Write-Host "  Sizing: USD $($sz.sizing_usd) | Stop: -$($sz.stop_pct * 100)% | Target: +$($sz.target_pct * 100)% | Max: $($sz.max_days)d" -ForegroundColor Cyan
        if (-not $DryRun) {
            Write-Host "  --> ALERTA: $($a.alerta)" -ForegroundColor Green
        }
    }
    Write-Host $sep -ForegroundColor Cyan

    return $top
}

