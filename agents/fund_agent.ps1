# fund_agent.ps1 — FundAgent: macro + tokenomics + ciclos
# Persona: Lyn Alden + Raoul Pal + Messari Research (ver PERSONAS.md)
# APIs gratuitas: CoinGecko, alternative.me

. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\lib_claude.ps1"
. "$PSScriptRoot\lib_coinex.ps1"

$FUND_SYSTEM_PROMPT = @'
Voce e um analista fundamentalista macro especializado em ativos digitais.
Combina a visao macro de Lyn Alden (ciclos de liquidez, M2, dolar) com
analise profunda de protocolos da Messari Research.

Voce entende que crypto nao e uma ilha:
- DXY forte = BTC fraco (correlacao -0.7)
- M2 global crescendo = bullish para todos os ativos de risco
- FED hawkish = capital foge de risco = bearish crypto
- Halving: choque de oferta com efeito 6-18 meses depois

Voce distingue "bom projeto" de "bom trade" — nem sempre sao a mesma coisa.
Voce e honesto quando o macro esta contra, mesmo em bons projetos.

Responda APENAS com JSON valido no formato especificado.
'@

function Get-CoinGeckoData {
    param([string]$CoinId = "bitcoin")
    try {
        $r = Invoke-RestMethod -Uri "https://api.coingecko.com/api/v3/coins/$CoinId`?localization=false&tickers=false&community_data=false&developer_data=false" -Method GET -ErrorAction Stop
        return [PSCustomObject]@{
            name              = $r.name
            symbol            = $r.symbol
            price             = $r.market_data.current_price.usd
            marketCap         = $r.market_data.market_cap.usd
            volume24h         = $r.market_data.total_volume.usd
            priceChange24h    = $r.market_data.price_change_percentage_24h
            priceChange7d     = $r.market_data.price_change_percentage_7d
            priceChange30d    = $r.market_data.price_change_percentage_30d
            ath               = $r.market_data.ath.usd
            athChange         = $r.market_data.ath_change_percentage.usd
            circulatingSupply = $r.market_data.circulating_supply
            maxSupply         = $r.market_data.max_supply
            rank              = $r.market_cap_rank
        }
    } catch {
        return $null
    }
}

# Fallback quando CoinGecko rate-limit: usa CoinEx ticker + candles diarios
function Get-CoinExPriceFallback {
    param([string]$Market = "BTCUSDT")
    try {
        $ticker  = CoinEx-GetTicker $Market
        $candles = CoinEx-GetFuturesCandles $Market "1day" 31
        $price   = [double]$ticker.last
        $open24h = [double]$ticker.open

        $ch24h = if ($open24h -gt 0) { [math]::Round(($price - $open24h) / $open24h * 100, 2) } else { $null }

        $ch7d  = $null
        $ch30d = $null
        if ($candles -and $candles.Count -ge 8) {
            $p7d  = [double]($candles | Select-Object -Last 8  | Select-Object -First 1).close
            $ch7d = if ($p7d -gt 0) { [math]::Round(($price - $p7d) / $p7d * 100, 2) } else { $null }
        }
        if ($candles -and $candles.Count -ge 31) {
            $p30d  = [double]($candles | Select-Object -First 1).close
            $ch30d = if ($p30d -gt 0) { [math]::Round(($price - $p30d) / $p30d * 100, 2) } else { $null }
        }

        $base = $Market -replace "USDT$",""
        Write-Host "  [FundAgent] CoinGecko indisponivel — usando CoinEx como fallback de preco ($base)" -ForegroundColor DarkYellow
        return [PSCustomObject]@{
            name              = $base
            symbol            = $base.ToLower()
            price             = $price
            marketCap         = $null
            volume24h         = [double]$ticker.value
            priceChange24h    = $ch24h
            priceChange7d     = $ch7d
            priceChange30d    = $ch30d
            ath               = $null
            athChange         = $null
            circulatingSupply = $null
            maxSupply         = $null
            rank              = $null
        }
    } catch { return $null }
}

function Get-GlobalMarket {
    try {
        $r = Invoke-RestMethod -Uri "https://api.coingecko.com/api/v3/global" -Method GET -ErrorAction Stop
        return [PSCustomObject]@{
            totalMarketCap    = $r.data.total_market_cap.usd
            totalVolume       = $r.data.total_volume.usd
            btcDominance      = [math]::Round($r.data.market_cap_percentage.btc, 2)
            ethDominance      = [math]::Round($r.data.market_cap_percentage.eth, 2)
            marketCapChange24h= $r.data.market_cap_change_percentage_24h_usd
            activeCryptocurrencies = $r.data.active_cryptocurrencies
        }
    } catch { return $null }
}

function Resolve-CoinGeckoId {
    param([string]$Market)
    $base = $Market -replace "USDT$","" -replace "USD$",""
    $map  = @{
        "BTC"="bitcoin";"ETH"="ethereum";"SOL"="solana";"BNB"="binancecoin"
        "XRP"="ripple";"TON"="the-open-network";"DOGE"="dogecoin";"ADA"="cardano"
        "AVAX"="avalanche-2";"DOT"="polkadot";"MATIC"="matic-network";"LINK"="chainlink"
        "UNI"="uniswap";"ATOM"="cosmos";"LTC"="litecoin";"BCH"="bitcoin-cash"
        "SUI"="sui";"APT"="aptos";"ARB"="arbitrum";"OP"="optimism"
    }
    if ($map.ContainsKey($base)) { return $map[$base] }
    return $base.ToLower()
}

function ConvertFrom-DefiLlamaResponse {
    param($Chains)
    if (-not $Chains -or $Chains.Count -eq 0) { return $null }

    $totalTvl    = ($Chains | Measure-Object -Property tvl -Sum).Sum
    $ethChain    = $Chains | Where-Object { $_.name -eq "Ethereum" } | Select-Object -First 1
    $ethTvl      = if ($ethChain) { $ethChain.tvl } else { 0 }
    $ethDominance = if ($totalTvl -gt 0) { [math]::Round($ethTvl / $totalTvl * 100, 1) } else { 0 }
    $top5        = $Chains | Sort-Object -Property tvl -Descending | Select-Object -First 5 |
                   ForEach-Object { "$($_.name):$([math]::Round($_.tvl/1e9,1))B" }

    return [PSCustomObject]@{
        totalTvlB    = [math]::Round($totalTvl / 1e9, 1)
        ethDominance = $ethDominance
        top5Chains   = $top5 -join " | "
    }
}

function Get-DefiLlamaData {
    try {
        $chains = Invoke-RestMethod -Uri "https://api.llama.fi/v2/chains" -Method GET -ErrorAction Stop
        return ConvertFrom-DefiLlamaResponse $chains
    } catch { return $null }
}

function ConvertFrom-MessariResponse {
    param($Data, [string]$CoinId)
    if (-not $Data -or -not $Data.data) { return $null }

    $md          = $Data.data.market_data
    $onchain     = $Data.data.on_chain_data
    $reportedVol = if ($md) { $md.volume_last_24_hours }       else { $null }
    $realVol     = if ($md) { $md.real_volume_last_24_hours }  else { $null }
    $volRatio    = if ($reportedVol -and $reportedVol -gt 0) { [math]::Round($realVol / $reportedVol, 2) } else { $null }
    $activeAddr  = if ($onchain) { $onchain.active_addresses } else { $null }

    return [PSCustomObject]@{
        coinId          = $CoinId
        realVolume24h   = $realVol
        reportedVol24h  = $reportedVol
        realVolRatio    = $volRatio      # < 0.5 = suspeita de wash trading
        activeAddresses = $activeAddr
    }
}

function Get-MessariMetrics {
    param([string]$CoinId = "bitcoin")
    try {
        $r = Invoke-RestMethod -Uri "https://data.messari.io/api/v1/assets/$CoinId/metrics" -Method GET -ErrorAction Stop
        return ConvertFrom-MessariResponse $r $CoinId
    } catch { return $null }
}

# Score algoritmico fundamental quando Claude indisponivel.
# Funcao pura — sem I/O, sem chamadas externas. Testavel isoladamente.
function Invoke-FundFallback {
    param($Coin, $Defi, $Messari, $CyclePhase)

    $score = 50

    # Ciclo halving (maior driver fundamental)
    $score += switch -Wildcard ($CyclePhase) {
        "*BULL*"         { 15 }
        "*CONSOLIDACAO*" { 5  }
        "*DISTRIBUICAO*" { -10 }
        "*BEAR*"         { -20 }
        default          { 0  }
    }

    # Qualidade de volume — wash trading penaliza
    if ($Messari -and $null -ne $Messari.realVolRatio) {
        if     ([double]$Messari.realVolRatio -gt 0.5) { $score += 5  }
        elseif ([double]$Messari.realVolRatio -lt 0.2) { $score -= 10 }
    }

    # TVL DeFi — saude do ecossistema
    if ($Defi -and $Defi.totalTvlB) {
        if     ([double]$Defi.totalTvlB -gt 100) { $score += 5 }
        elseif ([double]$Defi.totalTvlB -lt 50)  { $score -= 5 }
    }

    # Momentum de preco 7d
    if ($Coin -and $Coin.priceChange7d) {
        $ch7d = [double]$Coin.priceChange7d
        if     ($ch7d -gt 10)  { $score += 5 }
        elseif ($ch7d -lt -10) { $score -= 5 }
    }

    $score    = [math]::Min(100, [math]::Max(0, $score))
    $outlook  = if ($score -ge 65) { "BULLISH" } elseif ($score -le 35) { "BEARISH" } else { "NEUTRO" }
    $rec      = if ($score -ge 70) { "ACUMULAR" } elseif ($score -ge 50) { "MANTER" } elseif ($score -ge 35) { "REDUZIR" } else { "EVITAR" }

    Write-Host "  [FundAgent] FALLBACK algoritmico - Claude indisponivel | Score=$score ciclo=$CyclePhase" -ForegroundColor DarkYellow
    return [PSCustomObject]@{
        score_fundamental       = $score
        macro_outlook           = $outlook
        fase_ciclo              = $CyclePhase
        btc_dominancia_sinal    = "NEUTRO"
        catalysadores_positivos = @("Fallback algoritmico")
        riscos_fundamentais     = @("Claude indisponivel - analise sem IA")
        horizonte_favoravel     = "MEDIO(semanas)"
        contexto_macro_resumo   = "Fallback algoritmico baseado em ciclo halving e dados brutos. Claude indisponivel."
        recomendacao            = $rec
    }
}

function Invoke-FundAgent {
    param(
        [string]$Market = "BTCUSDT",
        [switch]$Verbose
    )

    Write-Host "  [FundAgent] Coletando dados fundamentais: $Market..." -ForegroundColor DarkBlue

    $coinId  = Resolve-CoinGeckoId $Market
    $coin    = Get-CoinGeckoData $coinId
    if (-not $coin -or -not $coin.price) { $coin = Get-CoinExPriceFallback $Market }
    $global  = Get-GlobalMarket
    $defi    = Get-DefiLlamaData
    $messari = Get-MessariMetrics $coinId
    $funding = $null
    try { $funding = CoinEx-GetFundingRate $Market } catch {}

    # Ciclo halving — data e thresholds em config.ps1
    $monthsPost  = [math]::Round(([DateTime]::UtcNow - $HALVING_DATE).TotalDays / 30.4, 1)
    $cyclePhase  = if ($monthsPost -lt $CYCLE_CONSOLIDATION_MONTHS) { "CONSOLIDACAO-POS-HALVING" }
                   elseif ($monthsPost -lt $CYCLE_BULL_MONTHS)      { "BULL-HISTORICO($($CYCLE_CONSOLIDATION_MONTHS)-$($CYCLE_BULL_MONTHS)m)" }
                   elseif ($monthsPost -lt $CYCLE_DISTRIBUTION_MONTHS) { "POSSIVEL-DISTRIBUICAO" }
                   else { "POSSIVEL-BEAR" }

    $context = @"
PAR: $Market | COIN ID: $coinId
TIMESTAMP: $(Get-Date -Format "yyyy-MM-dd HH:mm") UTC

=== DADOS DO ATIVO ===
$(if ($coin) {
"Preco atual: $($coin.price) USD
Rank CMC: #$($coin.rank)
Market Cap: $('{0:N0}' -f $coin.marketCap) USD
Volume 24h: $('{0:N0}' -f $coin.volume24h) USD
Volume/MarketCap: $(if($coin.marketCap -gt 0){[math]::Round($coin.volume24h/$coin.marketCap*100,2)}else{0})%
Mudanca 24h: $($coin.priceChange24h)%
Mudanca 7d: $($coin.priceChange7d)%
Mudanca 30d: $($coin.priceChange30d)%
ATH: $($coin.ath) USD (agora $($coin.athChange)% do ATH)
Supply circulante: $('{0:N0}' -f $coin.circulatingSupply)
Supply maximo: $(if($coin.maxSupply){'{0:N0}' -f $coin.maxSupply}else{'Inflacionario'})"
} else { "Dados do ativo indisponiveis" })

=== MERCADO GLOBAL ===
$(if ($global) {
"Total Market Cap: $('{0:N0}' -f $global.totalMarketCap) USD
BTC Dominancia: $($global.btcDominance)%
ETH Dominancia: $($global.ethDominance)%
Market Cap Change 24h: $($global.marketCapChange24h)%"
} else { "Dados globais indisponiveis" })

=== CICLO MACRO (Rekt Capital + Lyn Alden) ===
Meses pos-halving (Abr/2024): $monthsPost meses
Fase do ciclo: $cyclePhase
Mes atual: $((Get-Date).ToString("MMMM")) -> Sazonalidade historica BTC varia

=== DEFI (DefiLlama) ===
$(if ($defi) {
"TVL Total DeFi: $($defi.totalTvlB)B USD
ETH Dominancia DeFi: $($defi.ethDominance)%
Top chains: $($defi.top5Chains)"
} else { "Dados DeFi indisponiveis" })

=== QUALIDADE DE VOLUME (Messari) ===
$(if ($messari) {
"Volume reportado 24h: $('{0:N0}' -f $messari.reportedVol24h) USD
Volume real (ajustado) 24h: $('{0:N0}' -f $messari.realVolume24h) USD
Ratio real/reportado: $($messari.realVolRatio) $(if($messari.realVolRatio -and $messari.realVolRatio -lt 0.5){'⚠ alto wash trading'}else{'OK'})
Enderecos ativos: $(if($messari.activeAddresses){'{0:N0}' -f $messari.activeAddresses}else{'N/D'})"
} else { "Dados Messari indisponiveis" })

=== FUTUROS ===
Funding Rate: $(if ($funding) { "$([math]::Round($funding*100,4))%" } else { "N/D" })
"@

    if ($Verbose) { Write-Host $context -ForegroundColor DarkGray }

    $question = @"
$context

Com base nesses dados fundamentais e macroeconomicos, responda em JSON:
{
  "score_fundamental": 0-100,
  "macro_outlook": "BULLISH" | "BEARISH" | "NEUTRO",
  "fase_ciclo": "texto descrevendo a fase atual",
  "btc_dominancia_sinal": "ALTSEASON" | "BTC_LIDERANDO" | "NEUTRO",
  "catalysadores_positivos": ["lista de catalisadores que podem impulsionar"],
  "riscos_fundamentais": ["lista de riscos relevantes"],
  "horizonte_favoravel": "CURTO(dias)" | "MEDIO(semanas)" | "LONGO(meses)" | "DESFAVORAVEL",
  "contexto_macro_resumo": "2 frases sobre o ambiente macro atual para crypto",
  "recomendacao": "ACUMULAR" | "MANTER" | "REDUZIR" | "EVITAR"
}
"@

    $provLabel = if ($env:AGENT_FUND_PROVIDER -eq "groq") { "Groq Llama 70B (free)" } else { "Claude (Haiku)" }
    Write-Host "  [FundAgent] Consultando $provLabel..." -ForegroundColor DarkBlue
    $result = Invoke-AgentLLM -SystemPrompt $FUND_SYSTEM_PROMPT -UserContent $question -Agent "fund" -AnthropicModel $CLAUDE_MODEL_CHEAP -Temperature 0.4

    if (-not $result) {
        return Invoke-FundFallback -Coin $coin -Defi $defi -Messari $messari -CyclePhase $cyclePhase
    }

    Write-Host "  [FundAgent] Score=$($result.score_fundamental) | Macro=$($result.macro_outlook) | $($result.recomendacao)" -ForegroundColor DarkBlue
    return $result
}
