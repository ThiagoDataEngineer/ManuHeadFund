# CONSTANTS.md — Referência Única de Variáveis Fixas

> Fonte da verdade para todos os parâmetros do sistema.
> Altere aqui e propague para o arquivo indicado em **Fonte**.
> Criado em 2026-05-12.

---

## Capital & Risco Global

> **Fonte primária: CoinEx API** (live).
> Os valores abaixo são fallbacks usados apenas quando a API está indisponível.
> Funções: `CoinEx-GetSpotCapitalUSDT` → `/v2/assets/spot/balance` |
> `CoinEx-GetFuturesCapitalUSDT` → `/v2/assets/futures/balance`

| Constante | Valor (fallback offline) | Fonte |
|-----------|--------------------------|-------|
| `CAPITAL_SPOT` | **100 USDT** — scalp spot residual | `config.ps1` |
| `CAPITAL_FUTURES` | **718 USDT** — GemAgent + Orchestrator | `config.ps1` |
| `CAPITAL_TOTAL` | `CAPITAL_SPOT + CAPITAL_FUTURES` — visão consolidada | `config.ps1` |
| `RISCO_MAXIMO_PCT` | **1%** do capital **do tipo do trade** (spot ou futures) | `config.ps1` |
| `MAX_RISCO_ABERTO` | **3%** risco simultâneo total | `config.ps1` |
| `MAX_TRADES_DIA` | **5** trades/dia | `config.ps1` |
| `ALAVANCAGEM_MAX` | **5×** (futuros) | `config.ps1` |

---

## Risk/Reward

| Constante | Valor | Fonte |
|-----------|-------|-------|
| `RR_MINIMO` | **5.0** (1:5 mínimo absoluto) | `config.ps1` |
| `RR_PREFERIDO` | **5.0** | `config.ps1` |
| `SCORE_MINIMO` | **65** (score combinado mínimo para operar) | `config.ps1` |

---

## Timeframes

| Constante | Valor | Uso |
|-----------|-------|-----|
| `TF_HTF` | `4hour` | Tendência macro |
| `TF_MTF` | `1hour` | Estrutura e setup |
| `TF_LTF` | `15min` | Entrada (execução) |

Fonte: `config.ps1`

---

## Indicadores Técnicos (TechAgent)

| Parâmetro | Valor | Observação |
|-----------|-------|------------|
| EMA curta | **9** | — |
| EMA média | **21** | — |
| EMA longa | **50** | — |
| EMA tendência | **200** | — |
| RSI período | **14** | Padrão |
| RSI2 (Connors) | **2** | Extremos de curto prazo |
| MACD | **12 / 26 / 9** | — |
| Bollinger Bands | **20 / 2σ** | — |
| ATR período | **14** | — |
| ATR stop mult | **2.0×** | Stop = Entry − 2×ATR |
| ADX range threshold | **< 20** | Evitar breakout em range |
| Fibonacci | **38.2% / 50% / 61.8%** | Retracements-chave |
| Stochastic | **14 / 3 / 3** | K, D, suavização |
| Trendline min toques | **3+** (forte) / **2** (fraco) | Gate qualidade A+ |
| Trendline min dist | **6 candles** entre toques | — |
| Trendline grades | A+ / A / B / C / NONE | — |

Fonte: `tech_agent_ai.ps1` (hardcoded nos prompts Claude)

---

## Pesos dos Agentes (Orchestrator)

| Regime | Tech | Chain | Sent | Fund |
|--------|------|-------|------|------|
| BULLISH | **40%** | **30%** | **20%** | **10%** |
| BEARISH | **35%** | **20%** | **25%** | **20%** |
| NEUTRAL (default) | **40%** | **25%** | **20%** | **15%** |

Fonte: `config.ps1` (`WEIGHTS_*`)

---

## Decisão Final (Orchestrator)

| Threshold | Sinal |
|-----------|-------|
| Score ≥ **70** | COMPRA |
| Score ≤ **30** | VENDA |
| Entre 30–70 | AGUARDAR |

Fonte: `orchestrator.ps1` (hardcoded)

---

## Sentiment Agent (SentAgent)

| Constante | Valor | Fonte |
|-----------|-------|-------|
| F&G BEARISH | **< 25** | `config.ps1` |
| F&G BULLISH | **> 75** | `config.ps1` |
| F&G extremo contrarian | **≤ 20** ou **≥ 80** | `config.ps1` |
| `FUNDING_NEUTRAL_MAX` | **0.0001** (0.01%) | `config.ps1` |
| `FUNDING_EXTREME` | **0.0005** (0.05%) | `config.ps1` |
| `LSR_LONG_EXTREME` | **0.65** (65% longs) | `config.ps1` |
| `LSR_SHORT_EXTREME` | **0.35** (35% shorts) | `config.ps1` |

---

## On-Chain Agent (ChainAgent)

| Constante | Valor | Fonte |
|-----------|-------|-------|
| `NUPL_EUFORIA` | **0.75** (F&G proxy ≥ 75) | `config.ps1` |
| OI spike up forte | **> +5%** | `chain_agent.ps1` (hardcoded) |
| OI spike up | **> +2%** | `chain_agent.ps1` |
| OI queda forte | **< −5%** | `chain_agent.ps1` |
| OI queda | **< −2%** | `chain_agent.ps1` |
| Whale min valor | **$1,000,000** | `chain_agent.ps1` |
| Whale lookback | **2 horas** | `chain_agent.ps1` |
| Concentração CRITICAL | top-10% > **80%** | `chain_agent.ps1` |
| Concentração HIGH | top-10% > **50%** | `chain_agent.ps1` |
| Hash ribbon buy | **> +2%** recovery | `chain_agent.ps1` |
| Hash ribbon bear | **< −2%** capitulação | `chain_agent.ps1` |

---

## Fundamental Agent (FundAgent)

| Constante | Valor | Fonte |
|-----------|-------|-------|
| `HALVING_DATE` | **2024-04-19** | `config.ps1` |
| `CYCLE_CONSOLIDATION_MONTHS` | **6** | `config.ps1` |
| `CYCLE_BULL_MONTHS` | **18** | `config.ps1` |
| `CYCLE_DISTRIBUTION_MONTHS` | **24** | `config.ps1` |
| Score base fallback | **50** | `fund_agent.ps1` |
| Bonus BULL cycle | **+15** | `fund_agent.ps1` |
| Bonus CONSOLIDACAO | **+5** | `fund_agent.ps1` |
| Penalty DISTRIBUICAO | **−10** | `fund_agent.ps1` |
| Penalty BEAR cycle | **−20** | `fund_agent.ps1` |
| Vol real ratio OK | **> 0.5** → +5 | `fund_agent.ps1` |
| Vol real ratio suspeito | **< 0.2** → −10 | `fund_agent.ps1` |
| TVL alto | **> $100B** → +5 | `fund_agent.ps1` |
| TVL baixo | **< $50B** → −5 | `fund_agent.ps1` |
| Outlook BULLISH | score **≥ 65** | `fund_agent.ps1` |
| Outlook BEARISH | score **≤ 35** | `fund_agent.ps1` |
| Rec. ACUMULAR | score **≥ 70** | `fund_agent.ps1` |
| Rec. MANTER | score **≥ 50** | `fund_agent.ps1` |
| Rec. REDUZIR | score **≥ 35** | `fund_agent.ps1` |
| Rec. EVITAR | score **< 35** | `fund_agent.ps1` |

---

## GemAgent — Micro-Caps

### Volume & Spike (Gate G1 / G1B)

| Constante | Valor | Fonte |
|-----------|-------|-------|
| `GEM_VOL_SPIKE_MIN` | **2.0×** média 3d | `config.ps1` |
| G1B BEARISH threshold | **≤ −10%** no dia | `gem_agent.ps1` |
| G1B BULLISH threshold | **≥ +5%** no dia | `gem_agent.ps1` |
| `GEM_RANGE_MIN_PCT` | **15%** range diário mínimo | `config.ps1` |

### Market Cap (Gate G3)

| Constante | Valor | Fonte |
|-----------|-------|-------|
| `GEM_MCAP_DISCOVERY` | **$2,000,000** | `config.ps1` |
| `GEM_MCAP_MOMENTUM` | **$20,000,000** | `config.ps1` |
| `GEM_LISTING_DAYS_MAX` | **10 dias** (novidade) | `config.ps1` |

### Sizing por Modo

| Constante | DISCOVERY | MOMENTUM | Fonte |
|-----------|-----------|----------|-------|
| `GEM_CAPITAL_*` | **0.2%** do capital | **0.4%** | `config.ps1` |
| `GEM_STOP_*` | **−50%** | **−30%** | `config.ps1` |
| `GEM_TARGET_*` | **+200%** | **+90%** | `config.ps1` |
| `GEM_MAX_DAYS_*` | **30 dias** | **21 dias** | `config.ps1` |
| `GEM_TRAILING_PCT` | **30%** trailing stop | ← mesmo | `config.ps1` |
| Moon bag | **50%** da posição | ← mesmo | `config.ps1` |

### Score Mínimos (Gates)

| Constante | Valor | Fonte |
|-----------|-------|-------|
| `GEM_SCORE_MIN_DISC` | **70** | `config.ps1` |
| `GEM_SCORE_MIN_MOM` | **60** | `config.ps1` |

### Pontuação por Gate

| Gate | Pontos | Critério |
|------|--------|----------|
| G1 vol spike | **+25** | spike ≥ 2.0× |
| G2 range | **+15** | range ≥ 15% |
| G3 mcap | **+15** | mcap ≤ $20M |
| G4 narrativa (Tier 1) | **+15** | keyword AI/MEME/ZK etc. |
| G4 narrativa (Tier 2) | **+8** | keyword YIELD/GAME etc. |
| G4 trending ≤ 200 | **+15** | CoinGecko rank |
| G4 trending ≤ 350 | **+12** | — |
| G4 trending ≤ 500 | **+8** | — |
| G5 estrutura | **+10** | candles 1h confirmam |
| G6 orgânico | **+10** / **−10** | CV volume, wash % |
| G7 fingerprint | **+10** / **+5** | similaridade ≥ 70 / ≥ 40 |

### Organic Accumulation (Gate G6)

| Constante | Valor | Fonte |
|-----------|-------|-------|
| `GEM_CV_ORGANIC_MIN` | **0.5** (CV mínimo para heterogeneidade) | `config.ps1` |
| `GEM_WASH_MAX_PCT` | **40%** candles suspeitos max | `config.ps1` |
| `GEM_GREEN_RATIO_MIN` | **65%** candles bullish mínimo | `config.ps1` |
| `GEM_WICK_RATIO_MAX` | **2.5×** wick superior/inferior | `config.ps1` |

### Narrative Keywords

| Tier | Keywords |
|------|----------|
| **Tier 1** (+15 pts) | AI, GPT, AGENT, NEURAL, BOT, AGI, LLM, CHAT, CLAUDE, GROK, DOGE, SHIB, PEPE, CAT, WIF, BONK, FLOKI, ELON, TRUMP, GHIBLI, PIXEL, WOJAK, CHAD, BASED, MEME, FROG, APE, ZK, L2, DEPIN, DESCI, RWA, INTENT, RESTAKE |
| **Tier 2** (+8 pts) | YIELD, FARM, STAKE, DEX, SWAP, GAME, PLAY, NFT, META, GOLD, SILVER, REAL, BOND, VAULT, PROTOCOL |

Fonte: `gem_agent.ps1` (array hardcoded)

---

## Macro Context (lib_macro.ps1)

| Parâmetro | Valor | Observação |
|-----------|-------|------------|
| DXY falling → score | **+20** | Favorável a crypto |
| DXY rising → score | **−20** | — |
| M2 expanding → score | **+20** | — |
| M2 contracting → score | **−20** | — |
| Yield normal (10Y > 2Y) | **+10** | — |
| Yield invertido | **−15** | — |
| Fed funds ≤ 3% | **+10** | — |
| Fed funds ≥ 5% | **−10** | — |
| Resultado BULLISH | score **≥ 60** | — |
| Resultado BEARISH | score **≤ 40** | — |
| Cache | **24 horas** | Dados FRED diários |

Fonte: `lib_macro.ps1` (hardcoded)

---

## Ciclo Halving BTC

| Fase | Duração | Início |
|------|---------|--------|
| CONSOLIDACAO | 6 meses | 2024-04-19 |
| BULL | 18 meses | ~2024-10-19 |
| DISTRIBUICAO | 24 meses | ~2026-04-19 |
| BEAR | restante | ~2028-04-19 |

Fonte: `config.ps1`

---

## CoinEx Fees

| Constante | Valor | Fonte |
|-----------|-------|-------|
| `COINEX_FEE_MAKER_FALLBACK` | **0.0003** (0.03%) | `config.ps1` |
| `COINEX_FEE_TAKER_FALLBACK` | **0.0005** (0.05%) | `config.ps1` |
| `COINEX_FEE_ROUNDTRIP_FALLBACK` | **0.0008** (0.08%) | `config.ps1` |

---

## Claude API

| Constante | Valor | Fonte |
|-----------|-------|-------|
| `CLAUDE_MODEL` | `claude-sonnet-4-6` | `config.ps1` |
| `CLAUDE_MAX_TOKENS` | **2048** | `config.ps1` |
| `CLAUDE_TEMP_TRADE` | **0.3** (decisões) | `config.ps1` |
| `CLAUDE_TEMP_STUDY` | **0.7** (exploração) | `config.ps1` |

---

## Rate Limits APIs Externas

| API | Limite | Delay configurado |
|-----|--------|------------------|
| CoinGecko free | ~30 req/min | **700ms** entre calls |
| Whale Alert free | 10 req/min / 1k/mês | — |
| Etherscan free | 5 req/s | — |
| FRED | 120 req/min | — |

---

## Paths

| Constante | Valor | Fonte |
|-----------|-------|-------|
| `JOURNAL_DIR` | `..\journal` | `config.ps1` |
| `JOURNAL_FILE` | `trades.csv` | `config.ps1` |
| `LOG_DIR` | `..\logs` | `config.ps1` |
| `COINEX_BASE_URL` | `https://api.coinex.com` | `config.ps1` |
| `COINEX_MARKET_TYPE` | `FUTURES` | `config.ps1` |

---

## Variáveis Hardcoded Fora do config.ps1

Estas estão espalhadas nos agentes e são candidatas a centralizar em `config.ps1` futuramente:

| Valor | Local | Candidato a constante |
|-------|-------|-----------------------|
| `−10%` / `+5%` G1B | `gem_agent.ps1` | `GEM_G1B_BEARISH_PCT` / `GEM_G1B_BULLISH_PCT` |
| Keywords Tier 1 e Tier 2 | `gem_agent.ps1` | Array em `config.ps1` |
| Score ≥ 70 COMPRA, ≤ 30 VENDA | `orchestrator.ps1` | `ORCH_SCORE_BUY` / `ORCH_SCORE_SELL` |
| OI thresholds +5/+2/−2/−5% | `chain_agent.ps1` | `CHAIN_OI_*` |
| Whale min $1M | `chain_agent.ps1` | `CHAIN_WHALE_MIN_USD` |
| Fund score bonuses/penalties | `fund_agent.ps1` | `FUND_BONUS_*` |
| F&G extremo 20/80 | `sent_agent.ps1` | já parcial em `config.ps1` |
