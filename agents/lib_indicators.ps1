# lib_indicators.ps1 — Wrapper do TechAgent existente
# Chama tech_agent.ps1 em modo silencioso e retorna dados estruturados
# Dot-source: . (Join-Path $PSScriptRoot "lib_indicators.ps1")

$_TECH_AGENT_PATH = (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "scripts") "tech_agent.ps1")

function Get-TechData {
    param(
        [string]$Market = "BTCUSDT",
        [switch]$Verbose
    )
    if (-not (Test-Path $_TECH_AGENT_PATH)) { throw "tech_agent.ps1 nao encontrado em $_TECH_AGENT_PATH" }

    # Roda tech_agent.ps1 em modo silencioso e captura o objeto resultado
    $result = & $_TECH_AGENT_PATH -Market $Market -Once -Quiet

    if ($Verbose) {
        Write-Host "=== TechData: $Market ===" -ForegroundColor Cyan
        $result | ConvertTo-Json -Depth 5
    }
    return $result
}

# Formata o resultado do TechAgent como texto estruturado para o Claude
function Format-TechDataForClaude {
    param([object]$Data, [string]$Market)

    if (-not $Data) { return "TechData indisponivel para $Market" }

    $tf = $Data
    return @"
=== ANALISE TECNICA: $Market ===

PRECO ATUAL: $($tf.close) USDT
TIMEFRAME PRIMARIO: $($tf.timeframe)

TENDENCIA E ESTRUTURA:
- Estrutura de mercado: $($tf.structure)
- Fase Weinstein: $($tf.weinstein)
- EMA 9: $($tf.ema9) | EMA 21: $($tf.ema21) | EMA 50: $($tf.ema50) | EMA 200: $($tf.ema200)
- Ichimoku: $($tf.ichimoku.bias) | Nuvem: $($tf.ichimoku.cloud)
- SuperTrend: $($tf.supertrend.trend)

MOMENTUM:
- RSI 14: $($tf.rsi) | RSI 2 (Connors): $($tf.rsi2)
- MACD: $($tf.macd.macd) | Linha sinal: $($tf.macd.ema12) vs $($tf.macd.ema26)
- Stochastic: K=$($tf.stoch.k) D=$($tf.stoch.d) | Sinal: $($tf.stoch.signal)
- ADX: $($tf.adx.adx) (+DI=$($tf.adx.pdi) / -DI=$($tf.adx.ndi))

VOLATILIDADE:
- ATR (14): $($tf.atr)
- Bollinger: Upper=$($tf.bb.upper) | Mid=$($tf.bb.mid) | Lower=$($tf.bb.lower)
- Keltner: Upper=$($tf.keltner.upper) | Lower=$($tf.keltner.lower)
- Squeeze: $($tf.squeeze)

VOLUME:
- Volume signal: $($tf.vol.signal) ($($tf.vol.ratio)x media)
- OBV trend: $($tf.obv.trend)
- VSA: $($tf.vsa)

PADROES IDENTIFICADOS:
- Candles: $($tf.patterns -join ", ")
- Divergencia RSI: $($tf.divergence)
- Pullback: $($tf.pullback)
- NR7/Inside Bar: $($tf.nr7)
- Wyckoff: $($tf.wyckoff)
- SMC Order Blocks: Bull OB=$($tf.smc.bullOB) | Bear OB=$($tf.smc.bearOB) | $($tf.smc.signal)
- Donchian/Turtle: $($tf.donchian.signal)
- ORB: $($tf.orb.signal)

NIVEIS CHAVE:
- VWAP: $($tf.vwap.vwap) | +1SD=$($tf.vwap.upper1) | -1SD=$($tf.vwap.lower1)
- Fibonacci: 38.2%=$($tf.fib.f382) | 50%=$($tf.fib.f500) | 61.8%=$($tf.fib.f618)
- Volume Profile: POC=$($tf.vp.poc) | VAH=$($tf.vp.vah) | VAL=$($tf.vp.val)
- Parabolic SAR: $($tf.sar.sar) ($($tf.sar.trend))

CONTEXTO:
- Power of 3 (ICT): $($tf.po3)
- Ciclo pos-halving: $($tf.cycle.phase) ($($tf.cycle.monthsPostHalving) meses)
- Sazonalidade: $($tf.cycle.seasonal)
- Funding Rate: $($tf.funding.rate)% | $($tf.funding.signal)

SCORE TECNICO HARDCODED: $($tf.score) / $($tf.scoreMax)
"@
}
