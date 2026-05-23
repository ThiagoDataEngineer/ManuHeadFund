# CRYPTO_MARKET_MICROSTRUCTURE.md — Onde Edge Retail Sobrevive vs Morre

> Mapa do jogo real onde a gente opera: quem está do outro lado, o que estão
> fazendo, onde sobra espaço pra retail. Insight diretor 2026-05-17: BTC daily
> salvou edge que estava morto em hourly — daily filtra a janela onde MEV +
> MMs operam.
>
> Cruza com [[MANIPULATION]] (stop hunts, Wyckoff Springs), [[LOPEZ_DE_PRADO]]
> (rigor metodológico), [[CRYPTO_ACADEMIC_FOUNDATIONS]] (Daian/MEV + Budish/HFT).

---

## 1. Filosofia

### 1.1 Por que microstructure importa mesmo pra swing trader

Você opera daily — não compete com HFT em milisegundos. **Mas** o preço daily é o output da batalha intraday. Se você não entende **quem move o mercado intra-day**, vai ser surpreendido por:

- Stop hunts em níveis óbvios
- Flash crashes "sem razão aparente"
- Gaps de abertura
- Liquidações cascade

**Insight 2026-05-17**: BTC v2 daily passou 16/16 grid. BTC v2 hourly 0/16. **Mesma estratégia**, mesmo dado, mesma whitelist. Diferença: hourly = MMs/MEV territory; daily = retail safe zone.

### 1.2 Mapa básico de quem está do outro lado

| Layer | Players | Velocidade | Capital |
|---|---|---|---|
| L1 — HFT pure | Jump, DRW, Cumberland, Citadel | Microseconds | $1B+ |
| L2 — MM cross-venue | Wintermute, GSR, B2C2, Amber | Milliseconds | $100M-1B |
| L3 — OTC desks | Galaxy, Genesis (RIP), DCG, FalconX | Seconds-minutes | $100M+ |
| L4 — Quant funds | Pantera, BlockTower, MultiCoin | Minutes-days | $10M-100M |
| L5 — Retail systematic | Robot Wealth, you, us | Days+ | $1k-$100k |
| L6 — Retail discretionary | Twitter traders, "investors" | Variable | varies |

Cada layer compete principalmente com camadas adjacentes. Daily timeframe = retail systematic vs retail discretionary + alguns quant funds. **Não é vs HFT/MMs diretamente.**

---

## 2. MEV — Foundational

### 2.1 Daian et al "Flash Boys 2.0" (2019)

Paper foundational. Definiu **MEV (Maximal Extractable Value)** formalmente.

**Categorias principais**:
1. **Sandwich attack**: bot detecta tx grande pendente → frontrun (compra antes) + backrun (vende depois) = vítima paga slippage extra
2. **Frontrun**: bot copia tx + paga gas maior = executa antes
3. **Backrun**: bot reage instantaneamente a oportunidade criada
4. **Arbitrage**: cross-DEX, cross-pool
5. **Liquidation**: bot disputa quem executa liquidation primeiro (recompensa fixa)

### 2.2 Magnitudes 2024-2025 (atualizadas)

- **MEV extraído** Ethereum mainnet: $370-500M/ano (estimativas Flashbots, EigenPhi)
- **Sandwich attacks**: 125.829 em outubro/2024 sozinho (recordes Solana superam ETH)
- **Top 10 MEV searchers** capturam ~70% do MEV (concentração extrema)
- **Solana MEV** > Ethereum MEV em alguns meses 2024 (Jito boost)

### 2.3 CEX MEV (existe!)

Geralmente discutido como DEX-only, mas CEX também tem mecanismos similares:

1. **Cross-exchange latency arb**: BTC sobe na Binance 50ms antes da Coinbase → bot vende Coinbase, compra Binance
2. **Liquidation cascades coordinated**: MM enxerga grande short position perto de liquidation no order book agregado → drives price down brevemente pra triggerar
3. **Stop level hunting**: cluster de stops em $X.000 (psicológico) → moves intencional pra coletar liquidez

**Cf [[MANIPULATION]] §3-4** — mecânica Wyckoff Spring/UTAD.

### 2.4 Andrew Miller — academic perspective

Cornell professor, MEV foundational research. Argumenta:
- MEV é **inevitável** em sistemas com transação ordering
- Solução não é eliminar mas **redistribuir** (Flashbots Auction style)
- EigenLayer's "shared sequencing" tenta abordar isso

### 2.5 Por que isso importa pro CoinEx retail

CoinEx é CEX. MEV interno opaco (não tem mempool público). Mas:

1. **Stop hunts são MEV-like** (MMs/HFT detectam clusters de stops via order book)
2. **Cross-exchange latency arb** afeta preço BTC/ETH em CoinEx (preço segue líderes Binance/Coinbase)
3. **Onde MEV opera = onde retail perde**: hourly, intraday, scalp

---

## 3. Hasu — Microestrutura Crypto

### 3.1 Quem é

Anônimo. Ex-Paradigm Research (uma das top VCs crypto). Hoje escreve essays gratuitos.

### 3.2 Insights principais

**"Liquidity in crypto is fragmented but improving"** (Hasu, multiple essays):

1. **20+ exchanges principais** = preço discovery distribuído
2. **Maker/taker assimetria** difere por exchange (Binance vs CoinEx vs Bitstamp)
3. **Order routing teoria**: capital institucional usa smart order routing (SOR); retail usa 1 exchange
4. **Edge cross-venue diminuiu** 2020-2024 (Makarov-Schoar confirma)

### 3.3 Cross-Exchange MEV (insight original)

Hasu argumenta MEV não é só DEX:
- Wash trading em exchanges Tier 2/3 = MEV interno do exchange
- Cross-exchange price discovery sniping
- Funding rate arb (long Binance + short Bybit quando spread > 0.01%)

### 3.4 Aplicação CoinEx AI Agent

1. **Não confiar em CoinEx volume isolado** (cross-validate com Coinmetrics TEF)
2. **Cross-exchange arb se vier a operar carry**: latência CoinEx vs Binance importa
3. **Daily timeframe afasta de MEV territory**

### 3.5 Links

- Paradigm Research site
- Hasu Twitter @hasufl

---

## 4. Market Makers Institucionais

### 4.1 Jump Crypto

**Heritage**: Jump Trading (Chicago, top 3 HFT mundial em equity). Spawn Jump Crypto 2021.

**Conhecido publicamente**:
- **Wormhole bailout 2022**: $320M para cobrir hack (relacionamento Solana)
- **SEC settlement maio 2024**: Tai Mo Shan Limited (Jump subsidiary) pagou **$123M** por unregistered offer/sale + fraud em conexão com Terra/UST
- **CFTC investigation 2023-24** sobre operações Terra/UST e LUNA
- **FTX trial 2023-24**: court records SDNY revelaram que Jump tinha relacionamento OTC com Alameda; $264M claim na bankruptcy

**Estratégias inferidas** (não publicadas):
- HFT cross-venue arbitrage
- Market making major pairs (BTC, ETH, SOL)
- Statistical arbitrage
- Heavy Solana ecosystem stake (Jito, etc)

**Aplicação**: Jump opera em escala impossível para retail. Não competir; entender que **eles definem o preço intra-day de majors**.

### 4.2 Wintermute

**Heritage**: 2017, Londres. Yoann Turpin (ex-OTC desks tradicionais).

**Conhecido publicamente**:
- **Hack setembro 2022**: **$160M** perdidos via Profanity wallet vulnerability (vanity address generator gerava chaves recuperáveis)
- **OTC volume record**: $2.24B em dia único 2023
- **LP em 50+ exchanges** (CEX + DEX)
- **Recovery pós-hack** rápida (operações continuaram normal)

**Estratégias declaradas** (entrevistas Yoann Turpin):
- Cross-venue market making
- OTC institutional block trades
- DEX liquidity provision (Uniswap V3 active)

**Lição estrutural**: mesmo top MM teve hack de $160M via dependency (Profanity). Operational risk é tão importante quanto trading risk.

### 4.3 GSR (Global Crypto MM)

**Heritage**: 2013, Hong Kong + Londres. Cristian Gil (ex-Goldman/JPMorgan FX prop). **A mais antiga das três**.

**Conhecido publicamente**:
- **Publicam research notes regularmente** (gsr.io/reports) — diferenciador
- **Options market making focus** (mais raro vs spot/perp)
- **CD20 index** trade collaborations

**Estratégias declaradas**:
- Options market making (BTC/ETH options Deribit + CME)
- Algorithmic spot/perp MM
- OTC block trades
- Quantitative strategies

**Aplicação retail**:
- GSR public research é leitura de qualidade (raro do lado MM)
- Options theory aplicada a crypto (relevante se CoinEx vier oferecer options)

### 4.4 DRW Cumberland

**Heritage**: DRW Trading Group (Chicago, top 5 prop firm). Don Wilson founder, legendary equity HFT. Cumberland = crypto arm desde 2014.

**Conhecido publicamente**:
- **Major OTC desk BTC/ETH** (institutional clients: hedge funds, family offices)
- **NYS BitLicense 2024** (regulamentação Wall Street-grade)
- **SEC action 2024** (settlement não disclosed publicly)
- **Clientela**: Goldman Sachs, Bloomberg LP, family offices

**Estratégias inferidas**:
- Statistical arbitrage intensivo cross-venue (DRW core competence)
- OTC block trades
- Stat arb pairs (BTC vs futures basis, perp vs spot)

**Aplicação**: DRW = stat arb mestre. Pairs trading em crypto é território deles. Retail não compete diretamente; aprende mecânica.

### 4.5 Tabela comparativa

| MM | Foco | Capital est. | Heritage | Public research |
|---|---|---|---|---|
| Jump Crypto | HFT majors + ecosystem | $5-10B | Jump Trading equity HFT | Mínima |
| Wintermute | Cross-venue MM + OTC | $1-3B | Crypto-native | Alguma |
| GSR | Options MM + spot | $1-3B | Goldman/JPMorgan FX | **Sim, regular** |
| DRW Cumberland | Stat arb + OTC | $3-5B | DRW prop equity | Mínima |

---

## 5. Edge Survival Map — onde retail ainda ganha

### 5.1 Por timeframe

| Timeframe | MM dominance | Retail edge | Verdict |
|---|---|---|---|
| Sub-second (microsegundos) | 100% MM/HFT | 0% | ❌ não tenta |
| Second-minute | 99% MM | 1% | ❌ raramente |
| 1-15min | 80-90% MM | 10-20% | ⚠️ event-driven only |
| 1h | 50-70% MM | 30-50% | ⚠️ noise-prone |
| 4h | 30-50% MM | 50-70% | ✅ retail viable |
| **Daily** | **10-20% MM** | **80-90% retail safe** | ✅ **recomendado** |
| Weekly+ | <5% MM | 95% retail | ✅ swing-friendly |

**Insight 2026-05-17 confirmado**: BTC daily salvou edge porque sai do MEV/HFT territory.

### 5.2 Por asset class

| Asset | MM attention | Retail edge | Verdict |
|---|---|---|---|
| BTC, ETH | Máxima | Marginal (daily+ ok) | Cuidado |
| Top-10 (SOL, BNB, XRP) | Alta | OK em daily | Validar per-asset |
| Mid-cap ($100M-1B) | Média | Maior | Tier B candidatos |
| Small-cap ($10-100M) | Baixa | **Maior** (ZEC é exemplo) | Tier A possíveis |
| Micro-cap (<$10M) | Mínima | Alta mas liquidez baixa | GemAgent territory |

**Insight ZEC** (Tier A único em 2026-05-17): privacy mid-cap, MMs ignoram, retail edge sobrevive.

### 5.3 Por strategy

| Strategy | MM presença | Retail viable? |
|---|---|---|
| HFT scalping | 100% | ❌ NUNCA |
| Mean reversion intraday majors | 95% | ❌ |
| Trend following daily majors | 30% | ✅ |
| Event-driven (announcements, halvings) | 50% | ✅ se rápido o suficiente |
| On-chain whale tracking | 20% | ✅ |
| Funding rate arb / carry | 70% MM | ⚠️ retail tem nicho |
| Cross-exchange arb | 99% MM | ❌ |
| Long-term position trading | <10% | ✅ |

---

## 6. Coinbase Research & Genesis (Acheson)

### 6.1 Coinbase Institutional Research

**Equipe**: David Duong (Head), Conor Ryder, Brian Cubellis

**Output**:
- Weekly research notes (gratuitas)
- Quarterly deep dives
- Institutional-grade analysis

**Diferenciação**: Coinbase tem data interna real (não inferred). Pontos de vista bem fundamentados.

**Aplicação CoinEx**:
- Macro framework crypto (correlação BTC/equity, regimes)
- Institutional flow data
- Comentário ETF inflows (relevant para BTC/ETH dynamics)

### 6.2 Noelle Acheson — "Crypto Is Macro Now"

**Background**: ex-Genesis Trading (pré-collapse), ex-Coindesk. Independente agora.

**Newsletter**: "Crypto Is Macro Now" (Substack gratuito + paid tier)

**Qualidade**: **Top 3 commentary crypto-macro em qualidade**. Mistura rigor macro tradicional + crypto-native understanding.

**Frequência**: 5x/semana, ~1500-3000 palavras

**Aplicação**:
- Macro context para decisões de regime
- Fed/M2/DXY interpretation aplicada a crypto
- Sanity check qualitativo

### 6.3 Outros que valem mention

- **Glassnode** (Rafael Schultze-Kraft): on-chain, mas marketing-heavy
- **CryptoQuant** (Ki Young Ju): Korean angle, OTC desk flows
- **Pantera Capital research**: thesis-driven, macro
- **Multicoin Capital**: VC perspective

---

## 7. Insights do FTX Trial (SDNY)

### 7.1 Court records públicos

US v. Sam Bankman-Fried + bankruptcy proceedings revelaram **operações internas** de MMs/exchanges normalmente opacas.

### 7.2 Findings principais

1. **CFTC judgment $12.7B** contra FTX (out 2024) — disgorgement + civil penalty
2. **Alameda backdoor** na FTX: linha de crédito ilimitada permitia uso de customer funds
3. **Jump <> Alameda relationship**: SRM (Serum) tokens, Jump tinha exposição grande
4. **Bahamas → Cayman → US** estrutura legal que protegia partes

### 7.3 Lições estruturais

Pra trader retail:
1. **Não confiar em custodial** (mantenha em cold wallet exceto trading capital)
2. **OTC desks têm relacionamento com exchanges** (cross-pollination de risk)
3. **Stablecoins centralizadas têm contraparte risk** (USDT, USDC)
4. **MMs nem sempre são "neutros"** (Jump tinha posições direcionais Alameda-style pré-collapse)

### 7.4 Aplicação CoinEx AI Agent

1. **Manter < 50% capital em CoinEx exchange a qualquer momento** (custodial risk)
2. **Sair em flash crashes anormais** (pode ser exchange-specific solvency issue)
3. **Monitor news exchange-specific** (insurance fund changes, withdrawal delays)

---

## 8. Aplicação ao CoinEx AI Agent

### 8.1 Por que daily salvou BTC (microstructure explanation)

Em hourly:
- MM/HFT operam continuamente
- Stop hunts em níveis óbvios
- Wick longas que estouram stop -1×ATR antes do alvo +5×ATR
- 85% das entries hourly batem stop antes do target

Em daily:
- 24h de "noise filtering"
- Direção real aparece (trend > noise)
- 37% win rate (vs 14-26% hourly) com mesmo whitelist
- Sharpe 5.04 (vs -0.65)

**Mesma estratégia, dimensão temporal diferente, resultado oposto.**

### 8.2 Quando hourly faz sentido (limitado)

- Event-driven óbvio (halving, Fed announcement, ETF approval)
- Breakout claro de range > 30 dias (não false breakout)
- Pre-positioning antes de evento conhecido (FOMC, halving date)

**NÃO**: trend following puro, mean reversion, scalp.

### 8.3 Onde NÃO competir

- BTC/ETH minute-by-minute (Jump/Wintermute territory)
- Cross-exchange latency arb (DRW/Cumberland territory)
- Options market making (GSR territory)
- New listing flipping primeiros minutos (bots + MMs)

### 8.4 Onde competir

- BTC/ETH daily+ trend following (validado)
- Mid-cap regime-based (validar via cross_asset_matrix)
- Small-cap ignorado por MMs (ZEC tipo)
- Event-driven baixa frequência
- Halving cycle timing (4 anos)
- DoW seasonality (já validado, p=0.0068)

---

## 9. Anti-patterns confirmados

❌ **Scalping em BTC/ETH hourly** — MM-dominated, retail loss
❌ **Mean reversion intraday majors** — same
❌ **Trying to predict daily close intraday** — noise > signal
❌ **Operar em flash crashes "comprando barato"** — sem entender se é exchange-specific
❌ **Confiar em Sharpe sem PBO** (Tier 2 mostrou HYPE/TON)
❌ **Operar tokens com volume 24h < $1M** — liquidity insuficiente

## 10. Pro-patterns confirmados

✅ **Trend following daily majors com triple barrier + PBO**
✅ **Per-asset whitelist** (BTC LONG-only, XRP LONG+SHORT)
✅ **Event-driven baixa freq** (halving + Mon BRT seasonality)
✅ **Small-cap ignorado MMs** (ZEC pattern)
✅ **On-chain whale tracking** (chain agent)
✅ **Macro overlay** (Acheson + Coinbase Research) como sanity check
✅ **Cold wallet > 50% capital** (anti-FTX lesson)

---

## 11. Sources

### MEV Foundational
- [Daian et al "Flash Boys 2.0" arxiv 2019](https://arxiv.org/abs/1904.05234)
- [Flashbots MEV-Boost stats](https://www.mevboost.org/)
- [EigenPhi MEV dashboard](https://eigenphi.io)

### MMs
- [Wintermute Profanity hack post-mortem 2022](https://mirror.xyz/wintermute.eth)
- [GSR research](https://gsr.io)
- [SEC v. Tai Mo Shan settlement May 2024](https://www.sec.gov)
- [CFTC v. FTX final judgment Oct 2024](https://www.cftc.gov)

### Research crypto-quality
- [Coinbase Institutional Research](https://www.coinbase.com/institutional/research-insights)
- [Acheson "Crypto Is Macro Now" Substack](https://cryptoismacronow.substack.com/)
- [Paradigm Research](https://www.paradigm.xyz/research)

### Court records
- FTX bankruptcy SDNY docket (PACER)
- US v. SBF trial transcripts

### Cross-refs internos
- [[MANIPULATION]] — Wyckoff Spring/UTAD, stop hunts (mechanics)
- [[LOPEZ_DE_PRADO]] — triple barrier, PBO, rigor metodológico
- [[CRYPTO_ACADEMIC_FOUNDATIONS]] — Daian/MEV + Budish/HFT academic backing
- [[PER_ASSET_OPTIMIZATION_PLAYBOOK]] — aplicação operacional dos insights
- [[COINEX_REFERENCE]] — limites específicos da venue
