# chain_agent.ps1 — ChainAgent: analise on-chain com proxies gratuitos + APIs reais
# Persona: Willy Woo + Glassnode Research + CryptoQuant (ver PERSONAS.md)
# APIs gratuitas: CoinGecko, CoinGlass, alternative.me, blockchain.info,
#                 Whale Alert (free tier), mempool.space, Etherscan (free tier)

. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\lib_claude.ps1"
. "$PSScriptRoot\lib_coinex.ps1"

# V6.5: cycle context (Pi/200WMA/ATH-DD/NUPL) -- mocks idempotentes + composicao.
# Reais (lib_cycle_indicators*.ps1) devem ser dot-sourced ANTES no scan_master,
# para que os ifs em lib_cycle_mocks vejam Get-Command e nao redefinam.
. "$PSScriptRoot\lib_cycle_mocks.ps1"
. "$PSScriptRoot\lib_cycle_context.ps1"

$CHAIN_SYSTEM_PROMPT = @'
Voce e um analista on-chain de elite, formado na intersecao entre Willy Woo,
Glassnode Research e CryptoQuant. Voce entende que o preco e um subproduto
do comportamento dos participantes on-chain.

Seu framework:
- NUPL > 0.75: euforia, zona de distribuicao (historicamente precede topos)
- MVRV Z-Score > 7: territorio de venda extrema pelos holders
- SOPR > 1 em recuperacao: holders voltando ao lucro = sinal de forca
- Exchange Netflow negativo (saida): acumulacao, reducao de sell pressure
- LTH Supply crescendo: maos fortes acumulando = bullish de longo prazo
- STH Cost Basis acima do preco: STH underwater = possivel capitulacao
- Hash Ribbon (MA30 cruzando MA60 pra cima): mineradores saudaveis = buy signal
- Funding Rate persistentemente negativo: shorts dominam = possivel squeeze

Voce distingue sinais on-chain de FUNDO (SOPR < 1, NUPL < 0, MVRV Z < 1)
de sinais de TOPO (NUPL > 0.75, exchange inflows altos, whales distribuindo).

Quando dados diretos nao estao disponiveis, use proxies e seja honesto sobre isso.

Responda APENAS com JSON valido no formato especificado.
'@

function Get-BlockchainStats {
    # blockchain.info API publica - stats da rede Bitcoin
    try {
        $r = Invoke-RestMethod -Uri "https://api.blockchain.info/stats" -Method GET -ErrorAction Stop
        return [PSCustomObject]@{
            hashRate        = $r.hash_rate
            difficulty      = $r.difficulty
            totalBTC        = $r.totalbc / 1e8
            txPerDay        = $r.n_tx
            mempoolSize     = $r.mempool_size
            minutesBetween  = $r.minutes_between_blocks
        }
    } catch { return $null }
}

function Get-CoinGlassChainData {
    param([string]$Market = "BTCUSDT")
    # OI, liquidacoes e dados de futuros como proxy on-chain
    try {
        $base = $Market -replace "USDT$",""
        $oiR  = Invoke-RestMethod -Uri "https://open-api.coinglass.com/public/v2/openInterest?symbol=$base&interval=h4&limit=4" -Method GET -ErrorAction Stop
        $liqR = Invoke-RestMethod -Uri "https://open-api.coinglass.com/public/v2/liquidation_history?symbol=$base&interval=h4&limit=4" -Method GET -ErrorAction Stop

        $oiData  = $null
        $liqData = $null

        if ($oiR.code -eq "0" -and $oiR.data -and $oiR.data.Count -gt 1) {
            $latest   = $oiR.data[-1]
            $previous = $oiR.data[-2]
            $oiChange = if ($previous.openInterest -gt 0) {
                [math]::Round(($latest.openInterest - $previous.openInterest) / $previous.openInterest * 100, 2)
            } else { 0 }
            $oiData = [PSCustomObject]@{
                current    = $latest.openInterest
                change4h   = $oiChange
                signal     = if ($oiChange -gt 5) { "OI_SUBINDO_FORTE" }
                             elseif ($oiChange -gt 2) { "OI_SUBINDO" }
                             elseif ($oiChange -lt -5) { "OI_CAINDO_FORTE" }
                             elseif ($oiChange -lt -2) { "OI_CAINDO" }
                             else { "OI_ESTAVEL" }
            }
        }

        if ($liqR.code -eq "0" -and $liqR.data -and $liqR.data.Count -gt 0) {
            $recent    = $liqR.data[-1]
            $longLiq   = if ($recent.longLiquidationUsd) { [double]$recent.longLiquidationUsd } else { 0 }
            $shortLiq  = if ($recent.shortLiquidationUsd) { [double]$recent.shortLiquidationUsd } else { 0 }
            $liqData = [PSCustomObject]@{
                longLiquidations  = $longLiq
                shortLiquidations = $shortLiq
                dominance         = if (($longLiq + $shortLiq) -gt 0) {
                    if ($longLiq -gt $shortLiq) { "LONGS_LIQUIDADOS" } else { "SHORTS_LIQUIDADOS" }
                } else { "NEUTRO" }
            }
        }

        return [PSCustomObject]@{ oi = $oiData; liquidations = $liqData }
    } catch { return $null }
}

function Get-ExchangeFlowProxy {
    param([string]$CoinId = "bitcoin")
    # CoinGecko exchange volume como proxy de fluxo
    try {
        $r = Invoke-RestMethod -Uri "https://api.coingecko.com/api/v3/coins/$CoinId`?localization=false&tickers=false" -Method GET -ErrorAction Stop
        $vol24h  = $r.market_data.total_volume.usd
        $mcap    = $r.market_data.market_cap.usd
        $volRatio = if ($mcap -gt 0) { [math]::Round($vol24h / $mcap * 100, 2) } else { 0 }
        # Volume/MCap ratio como proxy de atividade on-chain
        $flowSignal = if ($volRatio -gt 15) { "ALTO_VOLUME_RELATIVO - possivel whale activity" }
                      elseif ($volRatio -gt 8) { "VOLUME_ELEVADO" }
                      elseif ($volRatio -lt 2) { "VOLUME_BAIXO - acumulacao silenciosa possivel" }
                      else { "VOLUME_NORMAL" }
        return [PSCustomObject]@{
            volume24h   = $vol24h
            marketCap   = $mcap
            volMcapRatio = $volRatio
            flowSignal  = $flowSignal
            price       = $r.market_data.current_price.usd
            change24h   = $r.market_data.price_change_percentage_24h
            change7d    = $r.market_data.price_change_percentage_7d
        }
    } catch { return $null }
}

function Get-MVRVProxy {
    # MVRV Z-Score proxy usando preco atual vs realized price (estimado)
    # Sem API paga, usamos Fear&Greed + price action como proxy
    try {
        $fg = Invoke-RestMethod -Uri "https://api.alternative.me/fng/?limit=30" -Method GET -ErrorAction Stop
        $values = $fg.data | ForEach-Object { [int]$_.value }
        $avg30  = [math]::Round(($values | Measure-Object -Average).Average, 1)
        $current = $values[0]
        $trend   = if ($current -gt $avg30 + 10) { "ACELERANDO_BULLISH" }
                   elseif ($current -lt $avg30 - 10) { "ACELERANDO_BEARISH" }
                   else { "ESTAVEL" }
        return [PSCustomObject]@{
            current = $current
            avg30d  = $avg30
            trend   = $trend
            nupl_proxy = if ($current -gt ($NUPL_EUFORIA * 100)) { "EUFORIA(>$NUPL_EUFORIA)" }
                         elseif ($current -gt 60) { "OTIMISMO(0.5-0.75)" }
                         elseif ($current -gt 40) { "NEUTRO" }
                         elseif ($current -gt 25) { "ANSIEDADE(0.0-0.25)" }
                         else { "CAPITULACAO(<0)" }
        }
    } catch { return $null }
}

function Get-MinerSignal {
    param([string]$Market = "BTCUSDT")
    # Proxy de mineradores via blockchain.info + tendencia relativa via mempool.space
    $base = $Market -replace "USDT$",""
    if ($base -ne "BTC") { return $null }

    try {
        $stats = Get-BlockchainStats
        if (-not $stats) { return $null }

        # Tendencia relativa: hashrate atual vs media das ultimas 12 semanas (mempool.space)
        # Evita thresholds absolutos que ficam obsoletos com o crescimento da rede
        $hashSignal = "HASHRATE_SEM_REFERENCIA"
        try {
            $hR = Invoke-RestMethod -Uri "https://mempool.space/api/v1/mining/hashrate/1y" -Method GET -ErrorAction Stop
            if ($hR.hashrates -and $hR.hashrates.Count -ge 12) {
                $last12 = $hR.hashrates | Select-Object -Last 12
                $avg12  = ($last12 | ForEach-Object { [double]$_.avgHashrate } | Measure-Object -Average).Average
                $current = ($hR.hashrates | Select-Object -Last 1).avgHashrate
                $pctVsAvg = if ($avg12 -gt 0) { [math]::Round(($current - $avg12) / $avg12 * 100, 1) } else { 0 }
                $hashSignal = if ($pctVsAvg -gt 10)  { "HASHRATE_ACIMA_DA_MEDIA(+${pctVsAvg}%) - mineradores lucrativos" }
                             elseif ($pctVsAvg -lt -10) { "HASHRATE_ABAIXO_DA_MEDIA(${pctVsAvg}%) - possivel capitulacao" }
                             else { "HASHRATE_NA_MEDIA(${pctVsAvg}% vs 12w avg)" }
            }
        } catch {}

        return [PSCustomObject]@{
            hashRate    = $stats.hashRate
            difficulty  = $stats.difficulty
            txPerDay    = $stats.txPerDay
            hashSignal  = $hashSignal
            networkUsage = if ($stats.txPerDay -gt 400000) { "ALTA" } elseif ($stats.txPerDay -gt 200000) { "NORMAL" } else { "BAIXA" }
        }
    } catch { return $null }
}

# ── Whale Alert — movimentacoes de whales em exchanges ───────────────────────
# Ref: MANIPULATION.md — Exchange Netflow como sinal de acumulacao/distribuicao
# Chave opcional: env WHALE_ALERT_KEY (free tier = 10 req/min, 1000/mes)
function Get-WhaleAlertData {
    param(
        [string]$Market      = "BTCUSDT",
        [int]   $MinValueUSD = 1000000    # $1M minimo para filtrar ruido
    )
    try {
        $key    = if ($env:WHALE_ALERT_KEY) { $env:WHALE_ALERT_KEY } else { "free_demo" }
        $since  = [DateTimeOffset]::UtcNow.AddHours(-2).ToUnixTimeSeconds()
        $url    = "https://api.whale-alert.io/v1/transactions?api_key=$key&min_value=$MinValueUSD&start=$since"
        $r      = Invoke-RestMethod -Uri $url -Method GET -ErrorAction Stop

        $inflow = 0.0; $outflow = 0.0; $count = 0; $topMoves = @()

        if ($r.count -gt 0 -and $r.transactions) {
            foreach ($tx in $r.transactions) {
                $usd = if ($tx.amount_usd) { [double]$tx.amount_usd } else { 0 }
                if ($usd -lt $MinValueUSD) { continue }

                $fromType = if ($tx.from)  { $tx.from.owner_type  } else { "unknown" }
                $toType   = if ($tx.to)    { $tx.to.owner_type    } else { "unknown" }

                # exchange -> nao-exchange = saida = whale retirando para hodl = BULLISH
                if ($fromType -eq "exchange" -and $toType -ne "exchange") { $outflow += $usd }
                # nao-exchange -> exchange = entrada = whale depositando para vender = BEARISH
                elseif ($toType -eq "exchange" -and $fromType -ne "exchange") { $inflow += $usd }

                $count++
                if ($topMoves.Count -lt 3) {
                    $topMoves += "$([math]::Round($usd/1e6,1))M $fromType->$toType"
                }
            }
        }

        $netFlow = $outflow - $inflow
        # Sinal: significativo se netflow > 20% do lado menor
        $whaleSignal = if ($inflow -eq 0 -and $outflow -eq 0) { "NEUTRO" }
                       elseif ($netFlow -gt 0 -and ($inflow -eq 0 -or $netFlow -gt $inflow * 0.2)) { "BULLISH" }
                       elseif ($netFlow -lt 0 -and ($outflow -eq 0 -or [math]::Abs($netFlow) -gt $outflow * 0.2)) { "BEARISH" }
                       else { "NEUTRO" }

        return [PSCustomObject]@{
            whaleSignal = $whaleSignal
            inflowUSD   = $inflow
            outflowUSD  = $outflow
            netFlowUSD  = $netFlow
            txCount     = $count
            topMoves    = $topMoves
        }
    } catch { return $null }
}

# ── mempool.space — Hash Ribbon real (BTC only) ───────────────────────────────
# Ref: MANIPULATION.md + ONCHAIN_ANALYSIS.md — Hash Ribbon (Capriole Investments)
# MA30 = media das ultimas 5 semanas (~35d) | MA60 = media das ultimas 10 semanas (~70d)
# BUY_SIGNAL: MA30 cruza acima de MA60 (fim da capitulacao de mineradores)
function Get-MempoolHashRibbon {
    param([string]$Market = "BTCUSDT")

    $base = $Market -replace "USDT$",""
    if ($base -ne "BTC") { return $null }   # Hash Ribbon so para BTC PoW

    try {
        $r = Invoke-RestMethod -Uri "https://mempool.space/api/v1/mining/hashrate/1y" -Method GET -ErrorAction Stop
        $data = $r.hashrates
        if (-not $data -or $data.Count -lt 10) { return $null }

        # Pega ultimas 10 semanas para calcular ambas as MAs
        $last10 = $data | Select-Object -Last 10
        $last5  = $data | Select-Object -Last 5

        $ma60 = [double](($last10 | ForEach-Object { [double]$_.avgHashrate } | Measure-Object -Average).Average)
        $ma30 = [double](($last5  | ForEach-Object { [double]$_.avgHashrate } | Measure-Object -Average).Average)

        if ($ma60 -le 0) { return $null }

        $ribbonPct = [math]::Round(($ma30 - $ma60) / $ma60 * 100, 2)

        $signal = if ($ribbonPct -gt 2)  { "BUY_SIGNAL" }
                  elseif ($ribbonPct -lt -2) { "BEARISH" }
                  else { "NEUTRO" }

        return [PSCustomObject]@{
            signal      = $signal
            hashRate30d = [math]::Round($ma30 / 1e18, 2)   # EH/s
            hashRate60d = [math]::Round($ma60 / 1e18, 2)
            ribbonPct   = $ribbonPct
        }
    } catch { return $null }
}

# ── Etherscan — concentracao de holders ERC-20 ───────────────────────────────
# Ref: MANIPULATION.md Sec 3.1 — concentracao alta = manipulacao trivial
# Chave opcional: env ETHERSCAN_API_KEY (free tier = 5 req/seg)
# Ativos suportados: ERC-20 com contrato mapeado. BTC/SOL/ETH nativo = null.
function Get-EtherscanConcentration {
    param([string]$Market = "UNIUSDT")

    $base = $Market -replace "USDT$","" -replace "USD$",""

    # Ativos nao-ERC20 ou natives — nao aplicavel
    $nonERC20 = @("BTC","ETH","SOL","BNB","XRP","ADA","DOGE","AVAX","DOT",
                  "ATOM","LTC","BCH","TON","TRX","ICP","APT","SUI","NEAR")
    if ($nonERC20 -contains $base) { return $null }

    # ERC-20 na Ethereum mainnet com contratos conhecidos
    $contractMap = @{
        "UNI"   = "0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984"
        "LINK"  = "0x514910771AF9Ca656af840dff83E8264EcF986CA"
        "AAVE"  = "0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9"
        "MATIC" = "0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0"
        "ARB"   = "0xB50721BCf8d664c30412Cfbc6cf7a15145234ad1"
        "OP"    = "0x4200000000000000000000000000000000000042"
        "MKR"   = "0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2"
        "SNX"   = "0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F"
        "CRV"   = "0xD533a949740bb3306d119CC777fa900bA034cd52"
        "LDO"   = "0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32"
    }
    if (-not $contractMap.ContainsKey($base)) { return $null }

    $contract = $contractMap[$base]
    $key = if ($env:ETHERSCAN_API_KEY) { $env:ETHERSCAN_API_KEY } else { "YourApiKeyToken" }

    try {
        $holdersR = Invoke-RestMethod `
            -Uri "https://api.etherscan.io/api?module=token&action=tokenholderlist&contractaddress=$contract&page=1&offset=10&apikey=$key" `
            -Method GET -ErrorAction Stop
        if ($holdersR.status -ne "1") { return $null }

        $supplyR = Invoke-RestMethod `
            -Uri "https://api.etherscan.io/api?module=stats&action=tokensupply&contractaddress=$contract&apikey=$key" `
            -Method GET -ErrorAction Stop
        if ($supplyR.status -ne "1") { return $null }

        $totalSupply = [double]$supplyR.result
        if ($totalSupply -le 0) { return $null }

        $top10Sum = ($holdersR.result | ForEach-Object { [double]$_.TokenHolderQuantity } | Measure-Object -Sum).Sum
        $top10Pct = [math]::Round($top10Sum / $totalSupply * 100, 2)

        $risk = if ($top10Pct -gt 80) { "CRITICAL" }
                elseif ($top10Pct -gt 50) { "HIGH" }
                else { "NORMAL" }

        return [PSCustomObject]@{
            concentrationRisk = $risk
            top10Pct          = $top10Pct
            holderCount       = $holdersR.result.Count
            marketLabel       = $base
        }
    } catch { return $null }
}

function Resolve-ChainCoinId {
    param([string]$Market)
    $base = $Market -replace "USDT$","" -replace "USD$",""
    $map  = @{
        "BTC"="bitcoin";"ETH"="ethereum";"SOL"="solana";"BNB"="binancecoin"
        "XRP"="ripple";"DOGE"="dogecoin";"ADA"="cardano";"AVAX"="avalanche-2"
        "DOT"="polkadot";"LINK"="chainlink";"UNI"="uniswap";"ATOM"="cosmos"
    }
    if ($map.ContainsKey($base)) { return $map[$base] }
    return $base.ToLower()
}

# Score algoritmico on-chain quando Claude indisponivel.
# Funcao pura — sem I/O, sem chamadas externas. Testavel isoladamente.
function Invoke-ChainFallback {
    param($Whale, $HashRibbon, $EthConc, $Nupl, $DaysPostHalv)

    $score = 50

    # Whale signal (sinal mais direto de acumulacao/distribuicao)
    if ($Whale) {
        $score += switch ($Whale.whaleSignal) {
            "BULLISH" { 15 } "BEARISH" { -15 } default { 0 }
        }
    }

    # Hash Ribbon — capitulacao/recuperacao de mineradores BTC
    if ($HashRibbon) {
        $score += switch ($HashRibbon.signal) {
            "BUY_SIGNAL" { 10 } "BEARISH" { -10 } default { 0 }
        }
    }

    # Concentracao ERC-20 — risco estrutural de manipulacao
    if ($EthConc) {
        $score += switch ($EthConc.concentrationRisk) {
            "CRITICAL" { -15 } "HIGH" { -5 } default { 0 }
        }
    }

    # NUPL proxy via Fear & Greed — contrarian nas extremidades
    if ($Nupl -and $Nupl.current) {
        $fgVal = [int]$Nupl.current
        if     ($fgVal -le 20) { $score += 10 }   # medo extremo = fundo historico
        elseif ($fgVal -ge 80) { $score -= 10 }   # euforia = topo historico
    }

    $score    = [math]::Min(100, [math]::Max(0, $score))
    $bias     = if ($score -ge 65) { "BULLISH" } elseif ($score -le 35) { "BEARISH" } else { "NEUTRO" }
    $whaleSig = if ($Whale)      { $Whale.whaleSignal }           else { "NEUTRO" }
    $hashSig  = if ($HashRibbon) { $HashRibbon.signal }           else { "N/A" }
    $concRisk = if ($EthConc)    { $EthConc.concentrationRisk }   else { "N/A" }
    $whaleComp = switch ($whaleSig) { "BULLISH"{"ACUMULANDO"} "BEARISH"{"DISTRIBUINDO"} default{"NEUTRO"} }
    $minerSig  = if ($HashRibbon) { if ($HashRibbon.signal -eq "BUY_SIGNAL") {"SAUDAVEIS"} else {"CAPITULANDO"} } else { "N/A" }
    $supplyFase = if ($DaysPostHalv -lt 180) { "CHOQUE INICIAL" } elseif ($DaysPostHalv -lt 540) { "REDUCAO ATIVA" } elseif ($DaysPostHalv -lt 730) { "POSSIVEL TOPO" } else { "POS-TOPO" }

    Write-Host "  [ChainAgent] FALLBACK algoritmico - Claude indisponivel | Score=$score bias=$bias whale=$whaleSig hash=$hashSig" -ForegroundColor DarkYellow
    return [PSCustomObject]@{
        chain_score          = $score
        comportamento_whales = $whaleComp
        exchange_flow        = "NEUTRO"
        nupl_fase            = "NEUTRO"
        oi_sinal             = "NEUTRO"
        liquidation_risk     = "BAIXO"
        miner_signal         = $minerSig
        hash_ribbon          = $hashSig
        whale_alert          = $whaleSig
        concentracao_holders = $concRisk
        supply_fase          = $supplyFase
        alertas_chain        = @("Fallback algoritmico - Claude indisponivel")
        chain_bias           = $bias
        horizonte_chain      = "MEDIO"
        resumo               = "Fallback algoritmico. Whale=$whaleSig, Hash=$hashSig, Conc=$concRisk."
        limitacoes_dados     = "Fallback sem Claude - NUPL/SOPR/MVRV nao analisados"
    }
}

function Invoke-ChainAgent {
    param([string]$Market = "BTCUSDT")

    Write-Host "  [ChainAgent] Coletando dados on-chain: $Market..." -ForegroundColor DarkGreen

    $coinId     = Resolve-ChainCoinId $Market
    $flow       = Get-ExchangeFlowProxy $coinId
    $nupl       = Get-MVRVProxy
    $cgData     = Get-CoinGlassChainData $Market
    $miner      = Get-MinerSignal $Market
    $whale      = Get-WhaleAlertData $Market
    $hashRibbon = Get-MempoolHashRibbon $Market
    $ethConc    = Get-EtherscanConcentration $Market
    $base       = $Market -replace "USDT$",""

    # Calcular dias pos-halving para contexto de supply — data em config.ps1
    $daysPostHalv = [math]::Round(([DateTime]::UtcNow - $HALVING_DATE).TotalDays, 0)

    # ── V6.5 Cycle Context (Pi/200WMA/ATH-DD/NUPL) ───────────────────────────
    # Coleta inputs (best-effort): candles diarios, preco atual, F&G, SMA200, funding.
    $cycleCtx = $null
    try {
        $closes = @(); $currentPrice = 0; $smaDist = 0; $funding8h = 0
        if (Get-Command CoinEx-GetCandles -ErrorAction SilentlyContinue) {
            $candles = CoinEx-GetCandles -Market $Market -Period "1day" -Limit 500
            if ($candles) {
                $closes = @($candles | ForEach-Object { [double]$_.close })
                if ($closes.Count -gt 0) { $currentPrice = $closes[-1] }
                if ($closes.Count -ge 200) {
                    $sma200 = ($closes[-200..-1] | Measure-Object -Average).Average
                    if ($sma200 -gt 0) { $smaDist = (($currentPrice - $sma200) / $sma200) * 100 }
                }
            }
        }
        if (Get-Command CoinEx-GetFeeContext -ErrorAction SilentlyContinue) {
            $fctx = CoinEx-GetFeeContext $Market
            if ($fctx -and $fctx.funding8h) { $funding8h = [double]$fctx.funding8h / 100.0 }
        }
        $fgVal = if ($nupl -and $nupl.current) { [int]$nupl.current } else { 50 }
        $cycleCtx = Get-CycleContext -Market $Market `
            -DailyCloses ([double[]]$closes) -Dates @() `
            -CurrentPrice $currentPrice -FearGreed $fgVal `
            -DistanceFromSMA200 $smaDist -FundingRate8h $funding8h
        Write-Host "  [ChainAgent] Cycle: $($cycleCtx.cycle_phase) risk=$($cycleCtx.risk_score) -> $($cycleCtx.recommendation)" -ForegroundColor DarkCyan
    } catch { Write-Host "  [ChainAgent] Cycle context falhou: $_" -ForegroundColor DarkYellow }

    $context = @"
ATIVO: $Market | COIN: $coinId
TIMESTAMP: $(Get-Date -Format "yyyy-MM-dd HH:mm") UTC
AVISO: Dados baseados em proxies gratuitos. NUPL/MVRV/SOPR diretos requerem Glassnode Pro.

=== PROXY NUPL / SENTIMENTO HOLDER (via Fear&Greed 30d) ===
$(if ($nupl) {
"Fear&Greed atual: $($nupl.current)/100
Media 30 dias: $($nupl.avg30d)/100
Tendencia: $($nupl.trend)
NUPL estimado: $($nupl.nupl_proxy)
Interpretacao: $(if($nupl.current -gt ($NUPL_EUFORIA * 100)){'ZONA DE EUFORIA - historicamente proximo de topo'}
elseif($nupl.current -lt 25){'ZONA DE MEDO EXTREMO - historicamente proximo de fundo'}
else{'ZONA INTERMEDIARIA'})"
} else { "Indisponivel" })

=== FLUXO DE EXCHANGE (proxy via Volume/MCap) ===
$(if ($flow) {
"Volume 24h: $('{0:N0}' -f $flow.volume24h) USD
Market Cap: $('{0:N0}' -f $flow.marketCap) USD
Vol/MCap Ratio: $($flow.volMcapRatio)%
Sinal de fluxo: $($flow.flowSignal)
Variacao 24h: $($flow.change24h)% | 7d: $($flow.change7d)%"
} else { "Indisponivel" })

=== OPEN INTEREST (pressao de futuros) ===
$(if ($cgData -and $cgData.oi) {
"OI atual: $('{0:N0}' -f $cgData.oi.current) USD
Variacao 4h: $($cgData.oi.change4h)%
Sinal OI: $($cgData.oi.signal)
Interpretacao: $(if($cgData.oi.signal -eq 'OI_SUBINDO_FORTE'){'Aumento de apostas - volatilidade esperada'}
elseif($cgData.oi.signal -eq 'OI_CAINDO_FORTE'){'Desalavancagem - possivel reducao de volatilidade'}
else{'Estavel'})"
} else { "Indisponivel" })

=== LIQUIDACOES RECENTES ===
$(if ($cgData -and $cgData.liquidations) {
"Liquidacoes LONG: $('{0:N0}' -f $cgData.liquidations.longLiquidations) USD
Liquidacoes SHORT: $('{0:N0}' -f $cgData.liquidations.shortLiquidations) USD
Dominancia: $($cgData.liquidations.dominance)"
} else { "Indisponivel" })

=== MINERADORES / REDE (apenas BTC) ===
$(if ($miner) {
"Hash Rate: $($miner.hashRate) EH/s
Difficulty: $('{0:N2}' -f ($miner.difficulty/1e12))T
TX/dia: $('{0:N0}' -f $miner.txPerDay)
Sinal hashrate: $($miner.hashSignal)
Uso da rede: $($miner.networkUsage)"
} elseif ($base -eq "BTC") { "Dados de mineradores indisponiveis" }
else { "N/A para $base (apenas BTC)" })

=== WHALE ALERT (movimentacoes > USD 1M) ===
$(if ($whale) {
"Inflow exchange (bearish): $('{0:N0}' -f $whale.inflowUSD) USD
Outflow exchange (bullish): $('{0:N0}' -f $whale.outflowUSD) USD
Saldo liquido: $('{0:N0}' -f $whale.netFlowUSD) USD
Sinal whale: $($whale.whaleSignal) | TXs: $($whale.txCount)
Maiores movimentos: $($whale.topMoves -join ' | ')"
} else { "Indisponivel (configure WHALE_ALERT_KEY)" })

=== HASH RIBBON - MINERADORES BTC (mempool.space) ===
$(if ($hashRibbon) {
"MA30 (5 semanas): $($hashRibbon.hashRate30d) EH/s
MA60 (10 semanas): $($hashRibbon.hashRate60d) EH/s
Ribbon: $($hashRibbon.ribbonPct)%
Sinal: $($hashRibbon.signal)
Interpretacao: $(if($hashRibbon.signal -eq 'BUY_SIGNAL'){'Mineradores se recuperando - historicamente forte sinal de fundo'}
elseif($hashRibbon.signal -eq 'BEARISH'){'Capitulacao de mineradores em curso - pressao de venda'}
else{'Neutro - sem sinal claro'})"
} elseif ($base -eq "BTC") { "Hash Ribbon indisponivel (mempool.space)" }
else { "N/A para $base (Hash Ribbon exclusivo BTC PoW)" })

=== CONCENTRACAO DE HOLDERS ERC-20 (Etherscan) ===
$(if ($ethConc) {
"Top 10 holders: $($ethConc.top10Pct)% do supply
Risco de concentracao: $($ethConc.concentrationRisk)
Interpretacao: $(if($ethConc.concentrationRisk -eq 'CRITICAL'){'MANIPULACAO TRIVIAL - poucos wallets controlam o ativo'}
elseif($ethConc.concentrationRisk -eq 'HIGH'){'Concentracao alta - whale pode mover preco com facilidade'}
else{'Distribuicao razoavel'})"
} else { "N/A (BTC/SOL/ETH nativo ou token sem contrato mapeado)" })

=== CYCLE CONTEXT (Pi + 200WMA + ATH-DD + NUPL composto) ===
$(if ($cycleCtx) {
"Phase: $($cycleCtx.cycle_phase) | Risk: $($cycleCtx.risk_score)/100
Pi Cycle: $($cycleCtx.pi_cycle.signal)
ATH DD: $($cycleCtx.ath_dd.drawdown_pct)% ($($cycleCtx.ath_dd.zone))
NUPL proxy: $($cycleCtx.nupl_proxy.score) ($($cycleCtx.nupl_proxy.zone))
200WMA dist: $($cycleCtx.wma_200.distance_pct)% ($($cycleCtx.wma_200.zone))
Recommendation: $($cycleCtx.recommendation)
Summary: $($cycleCtx.summary_line)"
} else { "Cycle context indisponivel" })

=== CONTEXTO DE SUPPLY (Halving) ===
Dias pos-halving (Abr/2024): $daysPostHalv dias
Emissao atual: ~3.125 BTC/bloco (post-halving Abr/2024)
Fase de supply: $(if($daysPostHalv -lt 180){'CHOQUE DE OFERTA INICIAL'}
elseif($daysPostHalv -lt 540){'REDUCAO DE OFERTA ATIVA - historicamente bullish'}
elseif($daysPostHalv -lt 730){'POSSIVEL TOPO DE CICLO'}
else{'POS-TOPO'})
"@

    if ($Verbose) { Write-Host $context -ForegroundColor DarkGray }

    $question = @"
$context

Com base nesses dados on-chain (e proxies) para $Market, responda em JSON:
{
  "chain_score": 0-100,
  "comportamento_whales": "ACUMULANDO" | "DISTRIBUINDO" | "NEUTRO" | "DESCONHECIDO",
  "exchange_flow": "SAINDO_BULLISH" | "ENTRANDO_BEARISH" | "NEUTRO",
  "nupl_fase": "EUFORIA" | "OTIMISMO" | "NEUTRO" | "ANSIEDADE" | "CAPITULACAO",
  "oi_sinal": "ALTA_ALAVANCAGEM" | "DESALAVANCAGEM" | "NEUTRO",
  "liquidation_risk": "ALTO_RISCO_LONGS" | "ALTO_RISCO_SHORTS" | "BAIXO",
  "miner_signal": "CAPITULANDO" | "SAUDAVEIS" | "N/A",
  "hash_ribbon": "BUY_SIGNAL" | "BEARISH" | "NEUTRO" | "N/A",
  "whale_alert": "BULLISH" | "BEARISH" | "NEUTRO",
  "concentracao_holders": "CRITICAL" | "HIGH" | "NORMAL" | "N/A",
  "supply_fase": "texto sobre fase do ciclo de halving",
  "alertas_chain": ["alertas importantes se houver"],
  "chain_bias": "BULLISH" | "BEARISH" | "NEUTRO",
  "horizonte_chain": "CURTO" | "MEDIO" | "LONGO",
  "resumo": "2 frases sobre o estado on-chain atual",
  "limitacoes_dados": "texto sobre o que nao pode ser visto sem dados pagos"
}
"@

    $provLabel = if ($env:AGENT_CHAIN_PROVIDER -eq "groq") { "Groq Llama 70B (free)" } else { "Claude (Haiku)" }
    Write-Host "  [ChainAgent] Consultando $provLabel..." -ForegroundColor DarkGreen
    $result = Invoke-AgentLLM -SystemPrompt $CHAIN_SYSTEM_PROMPT -UserContent $question -Agent "chain" -AnthropicModel $CLAUDE_MODEL_CHEAP -Temperature 0.4

    if (-not $result) {
        return Invoke-ChainFallback -Whale $whale -HashRibbon $hashRibbon -EthConc $ethConc -Nupl $nupl -DaysPostHalv $daysPostHalv
    }

    Write-Host "  [ChainAgent] Score=$($result.chain_score) | Bias=$($result.chain_bias) | NUPL=$($result.nupl_fase)" -ForegroundColor DarkGreen
    return $result
}
