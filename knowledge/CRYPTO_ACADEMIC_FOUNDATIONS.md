# CRYPTO_ACADEMIC_FOUNDATIONS.md — Pesquisa Peer-Reviewed que Fundamenta Crypto Trading

> Onde a academia rigorosa estuda crypto. Filtro: peer-reviewed ou citações ≥ 50,
> com aplicação direta ao projeto.
>
> Complementa `LOPEZ_DE_PRADO.md` (que é genérico) com material crypto-specific.

---

## 1. Filosofia

### 1.1 Por que academia crypto-specific importa

Lopez de Prado, Simons, Bailey são genéricos (equity, futures, commodities). Funcionam em crypto mas ignoram:
- Mercado 24/7 (sem fechamento)
- Fragmentação cross-exchange (20+ venues)
- On-chain transparency (whale tracking possível)
- Halving cycles (BTC supply schedule conhecido)
- DeFi liquidity (AMM mechanics)
- Stablecoin dependence (USDT/USDC podem despegar)

Academia crypto-specific cobre o que esses gaps requerem.

### 1.2 Tier de evidência (Cochrane/Hill adaptado para finance)

| Tier | Tipo de evidência | Confiabilidade |
|---|---|---|
| **A+** | Replicação cross-period + cross-author + RCT | Inexistente em finance |
| **A** | Causal inference rigorosa (DAGs, IV) | Muito raro |
| **B+** | Peer-reviewed + replicado independentemente | LdP base |
| **B** | Peer-reviewed em journal tier-1 (JFE, JF, RFS, JPM, QJE) | Sólido |
| **C** | Working paper SSRN/arxiv com citações ≥ 50 | Aceitável |
| **D** | Blog post de quant institucional | Inspiração, não citação |
| **F** | Crypto Twitter influencer | Descartar |

Este doc trabalha em **tier B e C**. Aplicação prática direta.

---

## 2. Igor Makarov & Antoinette Schoar — Cross-Exchange Arbitrage

### 2.1 Quem são

- **Igor Makarov**: London Business School, financial economics PhD MIT
- **Antoinette Schoar**: MIT Sloan, professor of finance, ex-AFA president
- Colaboração crypto desde 2018

### 2.2 Paper definitivo: "Trading and Arbitrage in Cryptocurrency Markets" (JFE 2020)

**Citação**: ~700+ Google Scholar

**Findings principais**:

1. **Arbitrage spread persistente cross-country** (US-Korea premium 2017-18 chegou a 40%)
2. **Custo real de arbitrage** = transfer (BTC blockchain) + slippage + exchange fees ≈ 1-3% por roundtrip
3. **Segmentação por capital controls** (US → Korea era difícil para fundos US)
4. **Decline pós-2018**: spreads caíram conforme infra cross-venue melhorou

**Fórmula central** (simplified):

$$\text{Arb}_t^{i,j} = \frac{P_t^j - P_t^i}{P_t^i} - C_t^{i,j}$$

onde $C_t^{i,j}$ é custo total transfer i→j (fees + blockchain + slippage estimado).

Spread persistente se $\text{Arb}_t^{i,j} > 0$ por T+1, T+2... = ineficiência estrutural.

### 2.3 Paper 2 — "Blockchain Analysis of the Bitcoin Market" (NBER 2021)

**Findings**:
1. **~10.000 wallets controlam 90% do supply circulante** (concentração extrema)
2. Cluster analysis identifica exchanges, miners, whales
3. **Volume on-chain ≠ volume "real"** (lavagem 2017-19 estimado em 30-70% do reportado)

**Aplicação CoinEx AI Agent**:
- Whale tracking via cluster analysis (já parcialmente em ONCHAIN_ANALYSIS.md)
- Volume rigor: descontar pelo menos 30% do reportado em CEXs sem KYC
- Cross-exchange spread como sinal (oportunidade ou aviso)

### 2.4 Links

- [SSRN abstract Makarov-Schoar 2020](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=3171204)
- [NBER 2021](https://www.nber.org/papers/w29396)
- LBS Igor Makarov profile

---

## 3. Tarun Chitra & Gauntlet — DeFi Risk Simulation

### 3.1 Quem é

- **Tarun Chitra**: PhD Physics (Cornell), founder Gauntlet Networks (~$15M ARR)
- Clientes: Aave, Compound, Uniswap, MakerDAO (top DeFi)
- Colaborações com Hal Varian (ex-Chief Economist Google), Vitalik Buterin, Dan Robinson

### 3.2 Contribuições principais

1. **Agent-based simulation** para AMM design (Uniswap V3 concentrated liquidity)
2. **Liquidation threshold modeling** (Compound, Aave)
3. **Stress-test methodology** para DeFi protocols
4. **Papers acadêmicos** em conferências (ACM Conference on Economics and Computation)

### 3.3 Paper relevante: "Improving Proof of Stake Economic Security via MEV Redistribution" (com Vitalik et al)

Mostra que MEV concentrado em validators pode ser redistribuído de forma a melhorar segurança. Relevante para EigenLayer-style restaking.

### 3.4 Aplicação CoinEx AI Agent

1. **Pre-live simulation**: antes de capital real, rodar Gauntlet-style agent-based simulation (cada agente = um trader com comportamento heterogêneo) para estressar a estratégia
2. **Liquidation calibration** (futuro): se operar futures alavancados, modelo Gauntlet para set leverage ideal
3. **Inspiração**: agent-based simulation > backtest histórico isolado quando regime change é possível

### 3.5 Links

- Gauntlet Research: `https://gauntlet.network/research`
- Twitter Chitra: @tarunchitra
- ACM EC papers

---

## 4. Wenpin Liu & Aleh Tsyvinski — Factor Analysis Crypto

### 4.1 Quem são

- **Liu**: Yale PhD finance
- **Tsyvinski**: Arthur M. Okun Professor of Economics, Yale (top-tier)

### 4.2 Paper: "Risks and Returns of Cryptocurrency" (Review of Financial Studies 2021)

**Citação**: 500+ Google Scholar
**Journal**: RFS = top-3 finance globalmente

**Findings**:

1. **3 fatores explicam 80%+ dos retornos cross-sectional crypto**:
   - **Market factor** (análogo CAPM)
   - **Size factor** (small-cap outperform large-cap em alguns períodos)
   - **Momentum factor** (vencedores 1w continuam ganhando ~1m)

2. **Fama-French aplicado a crypto**: parcialmente funciona; HML (value) NÃO funciona em crypto (não tem book value)

3. **Network effect** como proxy para "fundamental": número de wallets ativas, transaction count

### 4.3 Paper 2: "Common Risk Factors in Cryptocurrency" (Journal of Finance 2022)

**Citação**: 200+
**Journal**: JF = #1 finance

**Findings adicionais**:
- Momentum factor mais forte em crypto que equity (psychology + lower institutional dampening)
- Long-short market-neutral portfolio sobre os 3 fatores = Sharpe ~1.5 anual

### 4.4 Aplicação CoinEx AI Agent

1. **Feature engineering**: incluir market, size, momentum factors no score
2. **Cross-sectional ranking** (futuro multi-asset): rankear por momentum cross-asset, escolher top-N
3. **Hedge construction**: long-short pairs por momentum factor pode ter edge

### 4.5 Links

- [RFS 2021](https://academic.oup.com/rfs/article/34/6/2689/5912481)
- [JF 2022](https://onlinelibrary.wiley.com/doi/abs/10.1111/jofi.13139)

---

## 5. Ariah Klages-Mundt — Stablecoin Stability

### 5.1 Quem é

- PhD Cornell (Applied Math/Operations Research)
- Foco: math rigorosa em stablecoin mechanisms
- Publicou papers **antes** do colapso Terra/UST (previu fragilidade)

### 5.2 Papers principais

1. **"Stablecoins 2.0: Economic Foundations and Risk-based Models"** (2020)
2. **"While Stability Lasts"** (2020) — análise modelos endógenos vs exógenos
3. **"Vulnerabilities in Decentralized Stablecoin Systems"** (2021) — pré-Terra

### 5.3 Insights cruciais

1. **Algorithmic stables (UST estilo)** têm equilíbrio instável: depende de feedback positivo continuo
2. **Crisis dynamics**: pequena perturbação pode disparar cascade de re-pricing
3. **Modelagem como sistema dinâmico não-linear** (não fluxo linear)
4. **Reserve-backed (USDC, USDT) ≠ algorithmic (UST, DAI semi)** — risk profile fundamentalmente diferente

### 5.4 Aplicação CoinEx AI Agent

1. **Risk gate em hedge com stables**: se hedge envolver USDT ou USDC, monitor depeg risk
2. **Pre-emptive exit** se peg afasta-se > 1% por > 2h
3. **Não usar algorithmic stables** em hedge (UST, FRAX, etc) — risco assimétrico
4. **Considerar em backtest stress test**: depeg event de 24h (já aconteceu USDC março 2023)

### 5.5 Links

- arxiv author profile Klages-Mundt
- [Stablecoins 2.0 paper](https://arxiv.org/abs/2006.12388)

---

## 6. Sreeram Kannan & EigenLayer Economics

### 6.1 Quem é

- PhD Information Theory (Cornell)
- Professor UWashington (electrical engineering)
- Founder EigenLayer

### 6.2 Contribuição

- **Restaking mechanism**: ETH validators podem "re-stake" para garantir múltiplos serviços (oracles, DA, sidechain finality)
- Math: economic security crypto-derived com information theory bounds

### 6.3 Aplicação CoinEx AI Agent

Limitada hoje (CoinEx não opera restaking). Mas:
1. **Asset class novo**: ETH + restaking yield (~5-10% extra) muda risk profile ETH
2. **Mecanismo design**: lessons sobre crypto-economic security aplicam a tokenomics analysis (GemAgent)

### 6.4 Status

Importante conhecer existência. Operacionalmente baixo impacto agora.

---

## 7. Philip Daian + Andrew Miller — MEV Foundational

### 7.1 Paper: "Flash Boys 2.0: Frontrunning, Transaction Reordering, and Consensus Instability in Decentralized Exchanges" (arxiv 2019)

**Citação**: 800+

### 7.2 Findings

1. **MEV (Maximal Extractable Value)** definido formalmente
2. **Estimativa**: $6M+ extraído de DEXs até 2019 (hoje é $370-500M anual)
3. **Consensus instability**: se MEV > block reward, miners têm incentivo a reorg (vulnerabilidade real)
4. **Categorias MEV**: sandwich attacks, frontrun, backrun, arbitrage, liquidation

### 7.3 Aplicação CoinEx AI Agent

CoinEx é CEX, não tem MEV direto. **MAS**:
1. **MEV cross-exchange existe**: latency arb entre exchanges captura MEV-like
2. **Stop hunts** em majors hourly têm mecânica similar (MMs/HFT operam o liquidity sweep)
3. **Por que daily salvou BTC**: filtra a janela onde MEV/stop-hunt operam (microstructure noise)

### 7.4 Links

- [arxiv original Flash Boys 2.0](https://arxiv.org/abs/1904.05234)

---

## 8. Eric Budish — HFT Theory aplicável a Crypto

### 8.1 Quem é

- Chicago Booth, Professor of Economics
- Pioneer em design de mercado pós-HFT

### 8.2 Paper relevante: "The High-Frequency Trading Arms Race" (Quarterly Journal of Economics 2015)

**Citação**: 1000+
**Journal**: QJE = #1 economics

### 8.3 Findings

1. **Continuous limit order book é design ruim** (latency arms race destrutivo)
2. **Frequent batch auctions** seriam superiores
3. **Latency edge é zero-sum**: ganho de HFT = perda de retail

### 8.4 Aplicação CoinEx AI Agent

1. **Por que retail tem menos chance em majors líquidos**: continuous limit order book = HFT edge
2. **Por que ZEC passou** (Tier A): menos atrativo para HFT → retail edge sobrevive
3. **Daily timeframe é defesa**: latency irrelevante quando decisão é diária

### 8.5 Links

- [Budish 2015 QJE](https://academic.oup.com/qje/article-abstract/130/4/1547/1916146)

---

## 9. Data quality — Coinmetrics e Kaiko

### 9.1 Coinmetrics (Nic Carter, Jacob Franek, Lucas Nuzzi)

**Produto**:
- Community API (free) — métricas on-chain básicas
- Premium API (paid) — datasets institucionais

**Methodology rigor**:
- Trusted Volume Framework (TEF 2.0) — exclui exchanges fake
- "Bitcoin Yardstick" (NVT-style)
- Cross-validated on-chain metrics

**Aplicação**:
- Volume "rigorous" para regime detection (não fake volume)
- NVT alternative ao Willy Woo (que é blog post)

### 9.2 Kaiko (Paris, NYC)

**Produto**:
- Tick data L1/L2 multi-exchange (institucional, ~$10k+/mês)
- Research papers gratuitos

**Research highlights**:
- Cross-exchange ranking metodologia
- Market quality scoring
- Liquidity fragmentation analysis

**Aplicação CoinEx**:
- Kaiko research blog gratuito (relatórios mensais sobre crypto market quality)
- Para tick data, custo proibitivo retail — usar só se escalar institucional

### 9.3 Comparação

| Fonte | Qualidade | Custo | Aplicação retail |
|---|---|---|---|
| **Coinmetrics community** | Alta | Free (rate limited) | ✅ Use |
| **Kaiko research blog** | Alta | Free | ✅ Use |
| **CoinGecko / CMC** | Média | Free | Volume reportado (não filtrado) |
| **Glassnode** | Média-alta (mas marketing) | $30-500/mês | Útil mas Coinmetrics > |
| **CryptoQuant** | Variável | $30-500/mês | Korean perspective valiosa |

---

## 10. Outras menções breves

### 10.1 Cong, He, Li — Mining Economics

Papers sobre proof-of-work mining pools, security economics. Relevante para entender BTC supply dynamics.

### 10.2 Andrei Kirilenko — Microstructure HFT

Ex-CFTC chief economist, agora Cambridge. Microstructure equity + crypto. Crossover acadêmico.

### 10.3 Hal Varian — Co-authored com Chitra

Ex-Chief Economist Google. Co-autor de papers DeFi com Chitra. Crossover entre econometria clássica e crypto.

---

## 11. Mapping pros gaps do projeto

| Gap atual | Paper responde | Como aplicar |
|---|---|---|
| Como medir cross-exchange arb rigorosamente | Makarov-Schoar JFE 2020 | Aplicar fórmula spread − custo > 0 sustained |
| Validar volume real vs fake | Makarov-Schoar 2021 + Coinmetrics TEF | Descontar 30%+ do reportado em CEX sem KYC |
| Cross-sectional momentum cross-asset | Liu-Tsyvinski RFS 2021 | Rankear momentum 1w/1m, top quantile |
| Stress test edge antes de live | Chitra agent-based simulation | Rodar Gauntlet-style sim |
| Risk de hedge com stables | Klages-Mundt | Gate depeg + descartar algorithmic |
| Por que daily filtra stop hunts | Daian (MEV) + Budish (HFT) | Confirma teoria: daily = MEV-free zone |
| Datasets rigorosos | Coinmetrics + Kaiko | Cross-validate com fontes próprias |

---

## 12. Critical evaluation

### 12.1 Limites comuns desses papers

1. **Sample bias**: maior parte dos papers cobrem 2017-2020 (poucos pós-2022)
2. **Sobrevivência**: papers que dão "edge X funciona" são publicados; nulos não são
3. **Replicação fraca**: poucos papers replicados por terceiros independentes
4. **Escala**: academia opera em escala diferente do retail (não consideram fees ou liquidez retail)

### 12.2 Onde academia diverge da prática

- **Latência**: papers acadêmicos assumem execução perfeita; retail tem 200-500ms slippage
- **Custos**: papers usam fees institucionais (0.01%); retail 0.05-0.1%
- **Acesso a data**: paper usa Bloomberg/Reuters; retail tem CoinGecko/CMC

### 12.3 Quem cita quem (consensus map)

- **Makarov ↔ Schoar ↔ Liu ↔ Tsyvinski**: cluster MIT/Yale, consenso strong
- **Daian ↔ Miller**: cluster Cornell, MEV foundational
- **Chitra ↔ Varian ↔ Vitalik**: cluster industry/academy bridge
- **Coinmetrics ↔ Kaiko**: cluster data quality, complementares

---

## 13. Sources

### Papers principais
- [Makarov & Schoar 2020 JFE — Trading and Arbitrage](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=3171204)
- [Makarov & Schoar 2021 NBER — Blockchain Analysis](https://www.nber.org/papers/w29396)
- [Liu & Tsyvinski 2021 RFS — Risks and Returns](https://academic.oup.com/rfs/article/34/6/2689/5912481)
- [Liu & Tsyvinski 2022 JF — Common Risk Factors](https://onlinelibrary.wiley.com/doi/abs/10.1111/jofi.13139)
- [Klages-Mundt 2020 — Stablecoins 2.0](https://arxiv.org/abs/2006.12388)
- [Daian et al 2019 — Flash Boys 2.0](https://arxiv.org/abs/1904.05234)
- [Budish 2015 QJE — HFT Arms Race](https://academic.oup.com/qje/article-abstract/130/4/1547/1916146)

### Sites
- [Gauntlet Networks Research](https://gauntlet.network/research)
- [Coinmetrics Research](https://coinmetrics.io/insights)
- [Kaiko Research](https://research.kaiko.com)

### Cross-refs internos
- [[LOPEZ_DE_PRADO]] — metodologia genérica (DSR, PBO, triple barrier)
- [[SIMONS_RENTECH]] — filosofia
- [[ONCHAIN_ANALYSIS]] — métricas on-chain (Makarov-Schoar 2021 informa)
- [[PER_ASSET_OPTIMIZATION_PLAYBOOK]] — aplicação operacional
- [[CRYPTO_MARKET_MICROSTRUCTURE]] — Daian/MEV + Budish/HFT estendidos
