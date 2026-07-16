param([bool] $DryRun = $false, [int] $TopCount = 200, [int] $ConcurrencyLimit = 3)

$projectRoot = Split-Path $PSScriptRoot -Parent
$agentsDir = Join-Path $projectRoot "agents"
$journalDir = Join-Path $projectRoot "journal"

# Load all libs
# 2026-07-16: lib_faro_whale_onchain.ps1 removida da esteira (sinal desligado,
# ver lib_faro_v3_scoring.ps1); lib_faro_compression.ps1 adicionada (squeeze
# real via Bollinger bandwidth, lib_auto_market_analysis.ps1).
$libs = @(
    "constants_loader.ps1",
    "config.ps1",
    "lib_coinex.ps1",
    "lib_candle_fetcher.ps1",
    "lib_auto_market_analysis.ps1",
    "lib_faro_volume_plus.ps1",
    "lib_faro_pattern_pro.ps1",
    "lib_faro_sentiment.ps1",
    "lib_faro_compression.ps1",
    "lib_faro_momentum.ps1",
    "lib_faro_fingerprint_dna.ps1",
    "lib_faro_entry_timing.ps1",
    "lib_faro_v3_scoring.ps1",
    "lib_signal_trigger_bus.ps1"
)
foreach ($l in $libs) {
    $p = Join-Path $agentsDir $l
    if (Test-Path $p) { . $p }
}

# 2026-07-16: trending CoinGecko real (1 chamada pro scan inteiro, mesma
# funcao/endpoint ja usado em gem_agent.ps1 Get-CoinGeckoTrendingRanks --
# duplicada aqui em vez de dot-source do arquivo inteiro, que tem side-effects
# de globals/keywords fora do escopo do FARO). Sentiment antes usava
# TrendingRank = Get-Random -- ruido puro contando como "confirmacao".
function Get-FaroCoinGeckoTrendingRanks {
    try {
        $r = Invoke-RestMethod -Uri "https://api.coingecko.com/api/v3/search/trending" -Method GET -TimeoutSec 10
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
$faroTrendingRanks = Get-FaroCoinGeckoTrendingRanks
Write-Host "  [Sentiment] CoinGecko trending real: $($faroTrendingRanks.Count) moedas" -ForegroundColor Gray

# 2026-07-16 FIX: o payload real de /v2/spot/ticker NAO tem campos "change" nem
# "24h" (confirmado via curl direto: so open/close/high/low/value/volume/
# volume_buy/volume_sell). $ticker.change e $ticker.'24h' eram SEMPRE $null,
# entao "change" era sempre 0 pra todo mundo -- o Sort-Object -Descending
# nunca ordenava de verdade, "Top200Gainers" na pratica pegava 200 pares em
# ordem arbitraria da API, nao os que mais subiram. Fix: calcula change real
# de open/close, usa "value" (USDT) como vol24h.
function Get-CoinExTop200Gainers {
    param([int] $TopCount = 200, [int] $MinVolumeUSD = 50000)
    try {
        if (-not (Get-Command CoinEx-GetAllSpotTickers -ErrorAction SilentlyContinue)) {
            Write-Host "WARN: CoinEx-GetAllSpotTickers not loaded"
            return @()
        }
        $allTickers = CoinEx-GetAllSpotTickers
        if (-not $allTickers) { return @() }

        $gainers = @()
        foreach ($ticker in $allTickers) {
            if (-not $ticker.market) { continue }

            $lastPrice = [double]$ticker.last
            $vol24h = if ($ticker.value) { [double]$ticker.value } else { 0 }
            $openPx = if ($ticker.open) { [double]$ticker.open } else { 0 }
            $change = if ($openPx -gt 0) { (($lastPrice - $openPx) / $openPx) * 100 } else { 0 }

            if ($vol24h -lt $MinVolumeUSD) { continue }

            $gainers += [PSCustomObject]@{
                market = [string]$ticker.market
                last = $lastPrice
                vol24h = $vol24h
                change = $change
            }
        }

        $gainers = $gainers | Sort-Object -Property change -Descending | Select-Object -First $TopCount
        Write-Host "Found $($gainers.Count) spot gainers (filter: volume > $MinVolumeUSD)" -ForegroundColor Cyan
        return ,$gainers
    } catch {
        Write-Host "WARN: CoinEx-GetAllSpotTickers failed: $_" -ForegroundColor Yellow
        return @()
    }
}

# 2026-07-16 NOVO: espelho do acima mas ordenado por QUEDA -- alimenta
# candidatos SHORT (pre-dump), mesmo raciocinio de pre-pump so invertido.
# Reusa a mesma correcao de campo (change real via open/close).
function Get-CoinExTop200Losers {
    param([int] $TopCount = 200, [int] $MinVolumeUSD = 50000)
    try {
        if (-not (Get-Command CoinEx-GetAllSpotTickers -ErrorAction SilentlyContinue)) { return @() }
        $allTickers = CoinEx-GetAllSpotTickers
        if (-not $allTickers) { return @() }

        $losers = @()
        foreach ($ticker in $allTickers) {
            if (-not $ticker.market) { continue }
            $lastPrice = [double]$ticker.last
            $vol24h = if ($ticker.value) { [double]$ticker.value } else { 0 }
            $openPx = if ($ticker.open) { [double]$ticker.open } else { 0 }
            $change = if ($openPx -gt 0) { (($lastPrice - $openPx) / $openPx) * 100 } else { 0 }
            if ($vol24h -lt $MinVolumeUSD) { continue }
            $losers += [PSCustomObject]@{ market = [string]$ticker.market; last = $lastPrice; vol24h = $vol24h; change = $change }
        }
        $losers = $losers | Sort-Object -Property change | Select-Object -First $TopCount
        Write-Host "Found $($losers.Count) spot losers (filter: volume > $MinVolumeUSD)" -ForegroundColor Cyan
        return ,$losers
    } catch {
        Write-Host "WARN: Get-CoinExTop200Losers failed: $_" -ForegroundColor Yellow
        return @()
    }
}

$timestamp = Get-Date -Format "o"
Write-Host "🔵 FARO V3 Engine started — CoinEx LIVE MODE" -ForegroundColor Green

$gainers = Get-CoinExTop200Gainers -TopCount $TopCount
if (-not $gainers -or $gainers.Count -eq 0) {
    Write-Host "WARN: No gainers found; using fallback whitelist"
    # Fallback to known-good markets
    $knownMarkets = @("BTCUSDT","ETHUSDT","SOLUSDT","BNBUSDT","MATICUSDT","LINKUSDT","AVAXUSDT","LTCUSDT")
    $gainers = @()
    foreach ($m in $knownMarkets) {
        try {
            $ticker = CoinEx-GetTicker -market $m -ErrorAction Stop
            if ($ticker -and $ticker.last) {
                $gainers += [PSCustomObject]@{
                    market = $m
                    last = $ticker.last
                    vol24h = 100000
                    change = 2.0
                }
            }
        } catch {}
    }
}

# 2026-07-16: losers (pre-dump, alimenta SHORT) + mapa de quais mercados tem
# futures (1 chamada pro scan inteiro, evita CoinEx-HasFuturesMarket por
# candidato = 200 chamadas extras). SPOT-only: so LONG (sem venda a descoberto
# possivel). Com futures: avalia LONG e SHORT no mesmo candidato.
$losers = Get-CoinExTop200Losers -TopCount ([int]($TopCount / 2))
$futuresMarketSet = New-Object System.Collections.Generic.HashSet[string]
try {
    $futTickers = CoinEx-GetAllFuturesTickers
    foreach ($ft in $futTickers) { if ($ft.market) { [void]$futuresMarketSet.Add([string]$ft.market) } }
    Write-Host "  [Futures] $($futuresMarketSet.Count) mercados futures disponiveis" -ForegroundColor Gray
} catch { Write-Host "  WARN: falha ao buscar futures tickers (SHORT desabilitado neste ciclo): $_" -ForegroundColor Yellow }

# Merge: gainers avaliados LONG (pre-pump), losers avaliados SHORT (pre-dump)
# quando o par tem futures. Sem dedup por design -- um par pode aparecer nos
# dois lados so se estiver nas duas pontas (raro, ok).
$evalTargets = @()
foreach ($g in $gainers) { $evalTargets += [PSCustomObject]@{ market = $g.market; last = $g.last; vol24h = $g.vol24h; change = $g.change; direction = "LONG" } }
foreach ($l in $losers) {
    if ($futuresMarketSet.Contains($l.market)) {
        $evalTargets += [PSCustomObject]@{ market = $l.market; last = $l.last; vol24h = $l.vol24h; change = $l.change; direction = "SHORT" }
    }
}
Write-Host "  Total a avaliar: $($evalTargets.Count) (LONG=$($gainers.Count), SHORT=$(@($evalTargets | Where-Object { $_.direction -eq 'SHORT' }).Count))" -ForegroundColor Gray

$candidates = @()
$analyzed = 0
foreach ($gainer in $evalTargets) {
    $market = $gainer.market
    $evalDirection = $gainer.direction
    try {
        $analyzed++
        # 2026-07-16: mock de candles REMOVIDO. Sinal calculado com dado
        # fantasioso e pior que nenhum sinal -- inflava signal_count com ruido
        # disfarcado de confirmacao. Se a API falhar, o par e pulado neste
        # ciclo (fail-closed), nao avaliado com preco/volume inventado.
        #
        # Get-CoinExCandles (nao CoinEx-GetCandles) -IsFutures $false: candidatos
        # aqui vem de Get-CoinExTop200Gainers, que le /v2/spot/ticker (sempre
        # spot) -- CoinEx-GetCandles roteia por regex de sufixo USDT e cai no
        # endpoint futures errado pra gemas spot-only (ex: AKEUSDT), confirmado
        # via teste real "code=4004 invalid argument" -- mesmo bug documentado
        # em memoria de sessao anterior (gate_replay_study teve o mesmo problema).
        $candles1h = @()
        try { $candles1h = Get-CoinExCandles -Market $market -Period "1hour" -Limit 24 -IsFutures $false -ErrorAction Stop } catch {}
        if (-not $candles1h -or $candles1h.Count -lt 20) { continue }

        $candles1m = @()
        try { $candles1m = Get-CoinExCandles -Market $market -Period "1min" -Limit 60 -IsFutures $false -ErrorAction Stop } catch {}

        # Candles diarias reais p/ DaysConsolidation (fingerprint) e squeeze
        # historico (compression) -- ambos precisam de janela mais longa que 1h.
        $candles1d = @()
        try { $candles1d = Get-CoinExCandles -Market $market -Period "1day" -Limit 60 -IsFutures $false -ErrorAction Stop } catch {}

        $avgVol = ($candles1h | Measure-Object -Property volume -Average -ErrorAction SilentlyContinue).Average
        if (-not $avgVol -or $avgVol -le 0) { $avgVol = [double]$candles1h[-1].volume }
        $lastVol = [double]$candles1h[-1].volume

        # Volume: real (candles reais).
        $volScore = Get-VolumeSpikePro -Market $market -CurrentVol $lastVol -Avg3dVol $avgVol -BuySideVol ($lastVol * 0.6) -SellSideVol ($lastVol * 0.4)

        # Pattern: real (ATR do 1h + estrutura de preco), sem PatternType/Strength
        # inventados -- so pontua se o proprio range recente sugerir consolidacao.
        $range1h = ($candles1h | Measure-Object -Property high -Maximum).Maximum - ($candles1h | Measure-Object -Property low -Minimum).Minimum
        $midPrice1h = ($candles1h | Measure-Object -Property close -Average).Average
        $atrPct = if ($midPrice1h -gt 0) { $range1h / $midPrice1h } else { 1.0 }
        $patStrength = if ($atrPct -lt 0.08) { [Math]::Round(1.0 - ($atrPct / 0.08), 2) } else { 0 }
        $patScore = if ($patStrength -gt 0) { Get-PatternPro -PatternType "consolidation" -Strength $patStrength } else { 0 }

        # Sentiment: real (CoinGecko trending, 1 chamada pro scan inteiro).
        $baseSymbol = ($market -replace "USDT$", "").ToUpper()
        $sentScore = 0
        if ($faroTrendingRanks.ContainsKey($baseSymbol)) {
            $sentScore = Get-SentimentScore -Market $market -TrendingRank $faroTrendingRanks[$baseSymbol] -MentionsChange 2.0
        }

        # Momentum: real (RSI dos closes 1h). Direction-aware: RSI 30-60 (nao
        # esticado) favorece LONG -- ver lib_faro_momentum.ps1 original. Pra
        # SHORT, o equivalente e RSI 40-70 esticado pra cima mas ainda nao em
        # capitulacao (>70 = ja pode estar exaurindo a favor do short, mas
        # >85 e territorio de possivel bounce/short-squeeze, entao nao
        # premiado aqui) -- leitura espelhada local, sem alterar Get-Momentum
        # (usada por outras partes do sistema so em contexto LONG).
        $closes1h = @($candles1h | ForEach-Object { [double]$_.close })
        $rsiReal = Calculate-RSI -Closes $closes1h -Period 14
        if ($evalDirection -eq "SHORT") {
            $momScore = 0
            if ($rsiReal -ge 60 -and $rsiReal -le 85) { $momScore += 15 }
            elseif ($rsiReal -ge 50 -and $rsiReal -lt 60) { $momScore += 8 }
            # MACD nao recalculado aqui (Get-Momentum so soma +10 com ele; sem
            # MACD real disponivel neste engine, fica de fora tanto LONG qto SHORT)
        } else {
            $momScore = Get-Momentum -Closes $closes1h -RSI $rsiReal
        }

        # Fingerprint: reusa RSI real (nao mais Get-Random). DaysConsolidation
        # real: conta candles diarias consecutivas dentro de +-8% da mediana.
        # Get-FingerprintMatch e simetrica o suficiente (janelas de RSI cobrem
        # oversold E overbought) pra nao precisar de versao SHORT separada.
        $daysConsolidation = 0
        if ($candles1d.Count -ge 10) {
            $closes1d = @($candles1d | ForEach-Object { [double]$_.close })
            $median1d = ($closes1d | Sort-Object)[[int]($closes1d.Count / 2)]
            for ($i = $closes1d.Count - 1; $i -ge 0; $i--) {
                if ([Math]::Abs(($closes1d[$i] - $median1d) / $median1d) -le 0.08) { $daysConsolidation++ } else { break }
            }
        }
        $fpScore = Get-FingerprintMatch -Market $market -CurrentVol $lastVol -Avg3dVol $avgVol -HighWick ([double]$candles1h[-1].high / [double]$candles1h[-1].open) -RSI $rsiReal -DaysConsolidation $daysConsolidation

        # Compression: real (Bollinger bandwidth diario vs historico proprio).
        # Sem direcao -- squeeze precede ignicao em qualquer sentido.
        $compScore = 0
        if ($candles1d.Count -ge 40) {
            $closes1d = @($candles1d | ForEach-Object { [double]$_.close })
            $compScore = Get-CompressionScore -Closes $closes1d
        }

        # Timing: real (candles 1min + hora UTC atual). Get-EntryTiming mede
        # rejeicao de ALTA (wick pra cima + fecha abaixo da MA5) -- serve tanto
        # pra "nao compre aqui" (LONG) quanto pra confirmar entrada SHORT
        # (mesmo padrao = exaustao compradora), entao nao inverte.
        $timingScore = 0
        if ($candles1m -and $candles1m.Count -ge 5) {
            $ma5 = ($candles1m[-5..-1] | Measure-Object -Property close -Average).Average
            $timingScore = Get-EntryTiming -Candles1min ($candles1m[-5..-1] | ForEach-Object { @{ high = [double]$_.high; close = [double]$_.close } }) -MA5 $ma5 -CurrentHourUTC ([double](Get-Date).ToUniversalTime().Hour)
        }

        $score = Get-FaroScoreV3 -VolScore $volScore -PatternScore $patScore -SentimentScore $sentScore -CompressionScore $compScore -MomentumScore $momScore -FingerprintScore $fpScore -TimingScore $timingScore

        $cand = [PSCustomObject]@{
            ts = $timestamp
            market = $market
            direction = $evalDirection
            last = $gainer.last
            vol24h = $gainer.vol24h
            change = $gainer.change
            score = $(if ($null -ne $score.score) { $score.score } else { 0 })
            decision = $(if ($null -ne $score.decision) { $score.decision } else { "SKIP" })
            signal_count = $(if ($null -ne $score.signal_count) { $score.signal_count } else { 0 })
            confidence = $(if ($null -ne $score.confidence) { $score.confidence } else { 0 })
            breakdown = $score.breakdown
        }
        $candidates += $cand

        if (-not $DryRun) {
            $candPath = Join-Path $journalDir "faro_v3_candidates.jsonl"
            Add-Content -Path $candPath -Value ($cand | ConvertTo-Json -Compress) -ErrorAction SilentlyContinue
        }

        if ($score.decision -in "ENTRA","URGENTE") {
            Write-Host "✅ $($score.decision) $evalDirection`: $market | score=$([Math]::Round($score.score, 1)) | $($score.signal_count)/7 signals" -ForegroundColor Yellow
            # Fast-path: enfileira trigger event-driven (mode scan = pode entrar via
            # scan_master full analysis). Coexiste com faro_v3_entry (dedup pelo
            # position-register do scan_master). Conviccao = score normalizado.
            if ((-not $DryRun) -and (Get-Command Add-SignalTrigger -ErrorAction SilentlyContinue)) {
                $faroConv = Get-FaroConviction -Score $score.score -Decision $score.decision
                if ($faroConv -gt 0) {
                    $triggerDir = if ($evalDirection -eq "SHORT") { "short" } else { "long" }
                    try { Add-SignalTrigger -Market $market -Signal "faro" -Conviction $faroConv -Direction $triggerDir -Mode "scan" -Notes "$($score.decision) $($score.signal_count)/7" | Out-Null } catch {}
                }
            }
        }
    } catch {
        # Skip silently and continue
    }
}

$entrySignals = @($candidates | Where-Object { $_.decision -in 'ENTRA', 'URGENTE' })
$entryLongCount = @($entrySignals | Where-Object { $_.direction -eq 'LONG' }).Count
$entryShortCount = @($entrySignals | Where-Object { $_.direction -eq 'SHORT' }).Count
Write-Host "🟢 FARO V3 Engine completed | $($candidates.Count) analyzed, $($entrySignals.Count) entry signals (LONG=$entryLongCount SHORT=$entryShortCount)" -ForegroundColor Green
