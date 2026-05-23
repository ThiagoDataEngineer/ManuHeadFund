# BARBELL_ALLOCATION.md -- Policy Taleb Antifragile aplicada ao CoinEx AI Agent

> Crystallizado 2026-05-18 apos user confirmar net worth real: $200k fora + $2.6k CoinEx.
> Ja vivemos um barbell extremo (99/1). Esta policy formaliza intencionalmente.

---

## 1. Filosofia

Nassim Taleb (Antifragile, 2012; Skin in the Game, 2018): convexidade real vem
de **alocacao asimetrica**, nao de "moderacao balanceada". Portfolio "diversificado"
classico de Markowitz (60/40 stocks/bonds) eh subotimo em mundos com fat tails.

Modelo correto:
- **90-99% ULTRA-SAFE** (cash equiv, fixed income proximas, BTC HODL cold wallet)
- **1-10% ULTRA-ASYMMETRIC** (high-variance bets com payoff convexo)

**Por que funciona em crypto:**
- Crypto tem **fat-tail returns** (kurtosis 10x+ vs equity)
- Edge BTC daily backtested = Sharpe 5.04, mas DD pode chegar 60% em bear cycles
- Slot safe protege contra ruina; slot asimetrico captura tail upside
- Combinacao maximiza E[U(x)] sob preferencia log-utility (Kelly fracionario)

---

## 2. Aplicacao concreta — alocacao atual (2026-05-18)

| Slot | Allocation | Conteudo | Risk profile | Status |
|------|-----------|----------|--------------|--------|
| **A SAFE** | **~99%** ($200k fora) | Cold wallet, exchanges grandes regulamentadas, fiat | Cash equiv / BTC HODL | Conservador |
| **B ASYMMETRIC** | **~1%** ($2.6k CoinEx) | Trading futures + spot CoinEx | Sharpe 5 backtested + GemAgent micro-caps | Operacional |

**Observacao:** ja estamos em barbell extremo (1% asymmetric). Taleb sugere 10% como teto razoavel; 1% e ULTRA-conservador (sub-optimal upside).

---

## 3. Sub-divisao do Slot B (trading capital)

Dentro dos $2.6k operacionais:

| Sub-slot | % do trading capital | Strategy | Source |
|---|---|---|---|
| **B1 Sistematico Tier A** | 70% | Whitelist v3 LIVE (ZEC + BTCUSDT + BTCUSD-Bitstamp params) | Backtest 14.7y Bitstamp + 2.7y CoinEx |
| **B2 Tier B observation** | 20% | XMR, BCH, XRP-CoinEx, ETH-Bitstamp, SUI, LTC, AAVE (paper-only ate validar) | Cross-asset matrix curada |
| **B3 GemAgent micro-caps** | 10% | DISCOVERY/MOMENTUM micro-caps via GemScan + Mentor | Asymmetric upside extremo |

**Total exposure simultanea max** = 3% capital trading (Risk-of-Ruin Kelly fracionario)

---

## 4. Triggers para REBALANCEAR slot B

### 4.1 Aumentar slot B (passar para 2-5% do net worth)

- Mode 2 LIVE micro completou 30+ dias COM:
  - N trades real >= 15
  - Win rate real >= backtest * 0.85
  - DD real <= backtest * 1.3
  - 0 incidentes custodial/operational
- Sharpe real annualized >= 1.5

### 4.2 Reduzir slot B (voltar para 0.5%)

- DD real > backtest * 1.5
- Win rate real < backtest * 0.6
- Qualquer incidente CoinEx (withdrawal delay, sistema indisponivel >12h)
- Cambio de regime: halving phase BEAR_TERRITORY + mining capitulation

### 4.3 Mover capital ENTRE slot A e B

- Sempre via cold wallet intermediary (nunca direto exchange-exchange)
- Single transfer max = 20% do que esta movendo
- Wait 24-48h confirmation antes de operar capital novo

---

## 5. Por que NAO 50/50 ou "diversificar mais"

| Suposicao classica | Realidade crypto |
|---|---|
| Returns ~ Normal distribution | Returns crypto = power-law / Pareto |
| Volatility = risk | Volatility = oportunidade ASIMETRICA |
| Diversificar reduz risk | Diversificar fora do edge = perder edge |
| Bond/equity correlation negativa | Crypto cycles diferentes de equity cycles |

Taleb (2018, Black Swan): "I am not interested in **average** results.
I am interested in protecting against **bad surprises** while keeping
**good surprises** open."

Barbell extremo = exatamente isso.

---

## 6. Implicacoes operacionais imediatas

### 6.1 NAO transferir mais capital pra CoinEx ate validar Mode 2

Atual $2.6k = ~99% safe / 1% asymmetric. ULTRA-conservador. Ate 30d Mode 2 validar
edge real, mantem assim. Nao "psicologar" colocando mais.

### 6.2 Sizing Mode 2 dentro do slot B

Learning phase (2026-05-18 a 2026-06-18):
- Min $25/trade
- Max $100/trade
- 5 trades/semana max
- Total risk weekly = $500 = ~0.25% net worth = irrelevante

### 6.3 Cold wallet hygiene

- 70%+ do slot A em cold wallet (BTC majors)
- 20% em exchanges grandes regulamentadas (Binance, Coinbase) com saldo distribuido
- 10% fiat liquido (BRL/USD conta)

---

## 7. Referencias

- Taleb, N. (2012). **Antifragile: Things That Gain from Disorder**
- Taleb, N. (2018). **Skin in the Game: Hidden Asymmetries in Daily Life**
- Bernoulli, D. (1738). **Exposition of a New Theory on the Measurement of Risk** (St. Petersburg paradox)
- Kelly, J. (1956). **A New Interpretation of Information Rate** (Kelly criterion)
- CRYPTO_MARKET_MICROSTRUCTURE.md secao §7.4 (custodial cap 30%)

---

## 8. Cruza com

- [[PER_ASSET_OPTIMIZATION_PLAYBOOK]] — slots B1/B2 definidos por per-asset tiers
- [[RISK_MANAGEMENT]] — Kelly fracionario implicito
- [[MENTOR]] — "Conservation > maximization" (Stanley Druckenmiller)
- [[CRYPTO_MARKET_MICROSTRUCTURE]] — custodial risk FTX-style
