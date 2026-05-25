# sent_agent.ps1 — SentAgent: sentimento, Fear&Greed, funding, noticias
# Persona: Willy Woo + Santiment + Glassnode Research (ver PERSONAS.md)
# APIs gratuitas: alternative.me, CryptoCompare news, CoinGlass

. (Join-Path $PSScriptRoot "config.ps1")
. (Join-Path $PSScriptRoot "lib_claude.ps1")
. (Join-Path $PSScriptRoot "lib_coinex.ps1")

$SENT_SYSTEM_PROMPT = @'
Voce e especialista em psicologia de mercado e analise de sentimento em crypto.
Formado na intersecao entre behavioral finance e dados on-chain.

Voce sabe que:
- Extremos de Fear e Greed sao os melhores pontos de entrada e saida
- Funding rate muito positivo (>0.1%) = excesso de longs = risco de liquidacao
- Long/Short ratio > 60% long = mercado excessivamente otimista = contrarian bearish
- FOMO na midia mainstream = proximo de topo
- "Crypto morreu" na midia = proximo de fundo

Voce e cetico com FOMO e alerta quando o mercado parece "certo demais".
Voce usa dados para identificar extremos emocionais, nao opinioes.

Responda APENAS com JSON valido no formato especificado.
'@

function Get-FearGreed {
    try {
        $r = Invoke-RestMethod -Uri "https://api.alternative.me/fng/?limit=3" -Method GET -ErrorAction Stop
        $latest = $r.data[0]
        $prev   = $r.data[1]
        return [PSCustomObject]@{
            value         = [int]$latest.value
            classification= $latest.value_classification
            yesterday     = [int]$prev.value
            change        = [int]$latest.value - [int]$prev.value
        }
    } catch { return $null }
}

function Get-CryptoNews {
    param([int]$Limit = 5)
    try {
        $r = Invoke-RestMethod -Uri "https://min-api.cryptocompare.com/data/v2/news/?lang=EN&sortOrder=latest" -Method GET -ErrorAction Stop
        return $r.Data | Select-Object -First $Limit | ForEach-Object {
            "[$(([DateTime]'1970-01-01').AddSeconds($_.published_on).ToString('HH:mm'))] $($_.title)"
        }
    } catch { return @("Noticias indisponiveis") }
}

function Get-CoinGlassData {
    param([string]$Market = "BTCUSDT")
    # CoinGlass API publica para alguns endpoints
    try {
        $base = $Market -replace "USDT$",""
        $r = Invoke-RestMethod -Uri "https://open-api.coinglass.com/public/v2/funding?symbol=$base" -Method GET -ErrorAction Stop
        if ($r.code -eq "0" -and $r.data) {
            $binance = $r.data | Where-Object { $_.exchangeName -eq "Binance" } | Select-Object -First 1
            if ($binance) { return [double]$binance.fundingRate }
        }
    } catch {}
    return $null
}

function Get-LongShortRatio {
    param([string]$Market = "BTCUSDT")
    try {
        $base = $Market -replace "USDT$",""
        $r = Invoke-RestMethod -Uri "https://open-api.coinglass.com/public/v2/lsr?symbol=$base&interval=h1&limit=1" -Method GET -ErrorAction Stop
        if ($r.code -eq "0" -and $r.data -and $r.data.Count -gt 0) {
            $latest = $r.data | Select-Object -Last 1
            return [PSCustomObject]@{
                longRatio  = [double]$latest.longRatio
                shortRatio = [double]$latest.shortRatio
            }
        }
    } catch {}
    return $null
}

# Score algoritmico de sentimento quando Claude indisponivel.
# Funcao pura — sem I/O, sem chamadas externas. Testavel isoladamente.
function Invoke-SentFallback {
    param($Fg, $FundingRate, $Lsr)

    $fgVal = if ($Fg -and $Fg.value) { [int]$Fg.value } else { 50 }

    $sentimento  = if ($fgVal -ge 75) { "BULLISH" } elseif ($fgVal -le 25) { "BEARISH" } else { "NEUTRO" }
    $intensidade = [math]::Min(100, [math]::Max(0, [int](50 + ($fgVal - 50) * 1.0)))
    $contrarian  = ($fgVal -le 20) -or ($fgVal -ge 80)
    $recomendacao = if ($fgVal -le 25) { "COMPRAR_MEDO" } elseif ($fgVal -ge 75) { "VENDER_EUFORIA" } else { "AGUARDAR" }

    $fundingSinal = "NEUTRO"
    if ($FundingRate) {
        if     ($FundingRate -gt $FUNDING_EXTREME)  { $fundingSinal = "EXCESSO_LONGS" }
        elseif ($FundingRate -lt -$FUNDING_EXTREME) { $fundingSinal = "EXCESSO_SHORTS" }
        elseif ($FundingRate -gt 0)                 { $fundingSinal = "FAVORAVEL_LONG" }
        elseif ($FundingRate -lt 0)                 { $fundingSinal = "FAVORAVEL_SHORT" }
    }

    Write-Host "  [SentAgent] FALLBACK algoritmico - Claude indisponivel | F&G=$fgVal sentimento=$sentimento funding=$fundingSinal" -ForegroundColor DarkYellow
    return [PSCustomObject]@{
        sentimento               = $sentimento
        intensidade              = $intensidade
        fear_greed_interpretacao = if ($Fg -and $Fg.classification) { $Fg.classification } else { "N/D" }
        funding_sinal            = $fundingSinal
        contrarian_signal        = $contrarian
        contrarian_razao         = if ($contrarian) { "F&G extremo ($fgVal/100)" } else { "" }
        recomendacao_sentimento  = $recomendacao
        alertas                  = @("Fallback algoritmico - Claude indisponivel")
        narrativa_dominante      = "Fallback - sem analise de noticias"
    }
}

function Invoke-SentAgent {
    param(
        [string]$Market = "BTCUSDT",
        [switch]$Verbose
    )

    Write-Host "  [SentAgent] Coletando sentimento: $Market..." -ForegroundColor DarkMagenta

    $fg     = Get-FearGreed
    $news   = Get-CryptoNews 6
    $lsr    = Get-LongShortRatio $Market
    $cgFunding = Get-CoinGlassData $Market
    $coinexFunding = $null
    try { $coinexFunding = CoinEx-GetFundingRate $Market } catch {}

    $fundingRate = if ($cgFunding) { $cgFunding }
                  elseif ($coinexFunding) { $coinexFunding }
                  else { $null }

    $context = @"
PAR: $Market
TIMESTAMP: $(Get-Date -Format "yyyy-MM-dd HH:mm") UTC

=== FEAR & GREED INDEX ===
$(if ($fg) {
"Valor atual: $($fg.value)/100 ($($fg.classification))
Ontem: $($fg.yesterday)/100
Variacao: $($fg.change) pontos"
} else { "Indisponivel" })

=== FUNDING RATE (sentimento de futuros) ===
$(if ($fundingRate) {
$fr = [math]::Round($fundingRate * 100, 4)
$frAbs = [math]::Abs($fundingRate)
$frInterp = if ($frAbs -lt $FUNDING_NEUTRAL_MAX) { 'NEUTRO' }
            elseif ($fundingRate -gt $FUNDING_EXTREME)  { 'LONGS PAGANDO MUITO - risco de liquidacao de longs' }
            elseif ($fundingRate -lt -$FUNDING_EXTREME) { 'SHORTS PAGANDO MUITO - risco de short squeeze' }
            elseif ($fundingRate -gt 0) { 'LEVEMENTE BULLISH' }
            else { 'LEVEMENTE BEARISH' }
"Funding Rate: ${fr}%
Interpretacao: $frInterp"
} else { "Indisponivel" })

=== LONG/SHORT RATIO ===
$(if ($lsr) {
$lsrInterp = if ($lsr.longRatio -gt $LSR_LONG_EXTREME)   { 'MERCADO EXCESSIVAMENTE LONG - contrarian bearish' }
             elseif ($lsr.longRatio -lt $LSR_SHORT_EXTREME) { 'MERCADO EXCESSIVAMENTE SHORT - contrarian bullish' }
             else { 'BALANCEADO' }
"Long: $([math]::Round($lsr.longRatio * 100, 1))% | Short: $([math]::Round($lsr.shortRatio * 100, 1))%
Interpretacao: $lsrInterp"
} else { "Indisponivel" })

=== NOTICIAS RECENTES ===
$($news -join "`n")
"@

    if ($Verbose) { Write-Host $context -ForegroundColor DarkGray }

    $question = @"
$context

Analise o sentimento atual do mercado e responda em JSON:
{
  "sentimento": "BULLISH" | "BEARISH" | "NEUTRO",
  "intensidade": 0-100,
  "fear_greed_interpretacao": "texto",
  "funding_sinal": "NEUTRO" | "EXCESSO_LONGS" | "EXCESSO_SHORTS" | "FAVORAVEL_LONG" | "FAVORAVEL_SHORT",
  "narrativa_dominante": "texto descrevendo o tema principal das noticias",
  "alertas": ["lista de alertas de sentimento extremo se houver"],
  "contrarian_signal": true | false,
  "contrarian_razao": "texto se contrarian_signal for true",
  "recomendacao_sentimento": "COMPRAR_MEDO" | "VENDER_EUFORIA" | "NEUTRO" | "AGUARDAR"
}
"@

    $provLabel = if ($env:AGENT_SENT_PROVIDER -eq "groq") { "Groq Llama 70B (free)" } else { "Claude (Haiku)" }
    Write-Host "  [SentAgent] Consultando $provLabel..." -ForegroundColor DarkMagenta
    $result = Invoke-AgentLLM -SystemPrompt $SENT_SYSTEM_PROMPT -UserContent $question -Agent "sent" -AnthropicModel $CLAUDE_MODEL_CHEAP -Temperature 0.4

    if (-not $result) {
        return Invoke-SentFallback -Fg $fg -FundingRate $fundingRate -Lsr $lsr
    }

    Write-Host "  [SentAgent] $($result.sentimento) | Intensidade=$($result.intensidade) | F&G=$($fg.value)" -ForegroundColor DarkMagenta
    return $result
}
