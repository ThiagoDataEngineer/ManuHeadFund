# ON-CHAIN ANALYSIS — Métricas, Ferramentas e Interpretação

> Referências: Willy Woo, Glassnode Research, CryptoQuant, Santiment, Chainalysis.
> On-chain é o diferencial exclusivo de crypto: dados que não existem em nenhum outro mercado.

---

## Por que On-Chain é Alpha?

- **Blockchain não mente** — cada transação é pública, imutável e verificável
- Revela o que whales e instituições FAZEM (não o que FALAM)
- Identifica acumulação antes dos movimentos de preço
- Detecta distribuição antes das quedas
- Complementa análise técnica com dados fundamentais objetivos

---

## 1. Métricas de Supply e Holders

### HODL Waves
```
Conceito:
  → Classifica todos os UTXOs (BTC) pelo tempo desde a última movimentação
  → Mostra quanto supply está "dormindo" (long-term holders) vs. ativo

Interpretação:
  → Supply dormindo cresce em bear market = acumulação
  → Supply dormindo diminui em bull = long-term holders vendendo ao varejo
  → Quando "hot supply" (< 1 semana) cresce muito = peak de atividade = tops

Fonte: Glassnode
```

### SOPR (Spent Output Profit Ratio)
```
Fórmula: SOPR = preço na venda / preço na compra

Interpretação:
  SOPR > 1  → holders vendendo com lucro (pressão vendedora inteligente)
  SOPR < 1  → holders vendendo com prejuízo (capitulação / panic selling)
  SOPR = 1  → breakeven

Uso prático:
  → SOPR < 0.95 por dias consecutivos = capitulação = zona de compra
  → SOPR rejeita o nível 1 (de cima para baixo) em bear market = resistência de preço
  → SOPR cruza acima de 1 e mantém = início de tendência de alta
```

### NUPL (Net Unrealized Profit/Loss)
```
Fórmula: NUPL = (Market Cap - Realized Cap) / Market Cap

Zonas:
  > 0.75   → Euforia/Ganância (VENDA — histórico de tops)
  0.50-0.75 → Crença/Negação
  0.25-0.50 → Otimismo/Ansiedade
  0-0.25   → Esperança/Medo
  < 0      → Capitulação (COMPRA — histórico de bottoms)

Histórico:
  → BTC bottoms ocorreram em NUPL < 0 (2015, 2018-19, 2022)
  → BTC tops ocorreram em NUPL > 0.7 (2013, 2017, 2021)
```

### LTH vs STH Supply
```
Long-Term Holders (LTH): coins paradas > 155 dias
Short-Term Holders (STH): coins paradas < 155 dias

LTH acumulando + STH distribuindo = fase early bull (comprar)
LTH distribuindo + STH acumulando = fase late bull (cuidado)
LTH em perda e distribuindo = capitulação = fundo próximo
```

---

## 2. Métricas de Exchanges

### Exchange Netflow
```
Netflow = inflow - outflow

Positivo (coins entrando na exchange):
  → Holders planejando vender
  → Bearish para preço de curto prazo

Negativo (coins saindo da exchange):
  → Holders retirando para custódia = confiança / HODL
  → Bullish para preço de curto prazo

Atenção:
  → Exchange inflow grande único pode ser custódia (Coinbase → Coinbase Prime)
  → Contexto importa: inflow + preço subindo = distribuição; inflow + preço caindo = stop loss
```

### Exchange Reserve
```
Reserve = quantidade total de BTC/ETH em carteiras de exchanges

Queda do reserve ao longo do tempo = acumulação global = bullish
Crescimento do reserve = pressão de venda potencial = bearish

Referência: Glassnode, CryptoQuant
```

### Stablecoin Supply Ratio (SSR)
```
SSR = Market Cap do BTC / Supply de stablecoins

SSR baixo = muito poder de compra em stablecoins = bullish (combustível disponível)
SSR alto = pouco poder de compra relativo = bearish (stablecoins usadas)

Fonte: Glassnode
```

---

## 3. Métricas de Mineradores (BTC específico)

### Miner Revenue
```
Queda na receita de mineradores → stress financeiro → podem vender BTC
Eventos críticos: hash ribbon (quando hashrate despenca) → capitulação dos mineradores
→ Historicamente, hash ribbon recovery = excelente ponto de compra
```

### Puell Multiple
```
Fórmula: Puell = emissão diária em USD / média de 365 dias da emissão em USD

> 4.0 → mineradores muito lucrativos → vendem mais → pressão vendedora → top
< 0.5 → mineradores em stress → capitulação de mineradores → bottom

Histórico: bottoms de 2015, 2018-19, 2022 todos com Puell < 0.5
```

### Hash Ribbon
```
Sinal bullish (compra):
  → Hash rate cai (mineradores desligam máquinas = capitulação)
  → Hash rate se recupera (voltam a ligar = pior passou)
  → MA 30 do hash rate cruza acima da MA 60
  → Sinal histórico de 90%+ de precisão para compra
```

---

## 4. Métricas de Avaliação (Valuation)

### MVRV Z-Score
```
MVRV = Market Value / Realized Value
Z-Score = (MVRV - média) / desvio padrão

Zona verde (compra):    Z-Score < 0 (historicamente = bottoms)
Zona vermelha (venda):  Z-Score > 7 (historicamente = tops)

Realized Value = preço médio pelo qual cada coin foi movida pela última vez
→ Representa o "custo médio" do mercado todo
```

### Realized Price
```
Realized Price = Realized Cap / Supply em circulação

Preço abaixo do Realized Price = mercado no geral está no prejuízo
→ Historicamente = fundo de bear market (ocorreu em 2015, 2018-19, 2022)

Preço acima do Realized Price = mercado no geral está no lucro = bull market
```

### Stock-to-Flow (Plan B)
```
Conceito:
  → S2F = Supply circulante / produção anual nova
  → Quanto maior o S2F, mais escasso o ativo

BTC S2F após cada halving:
  → 2012 halving: S2F ≈ 25
  → 2016 halving: S2F ≈ 50
  → 2020 halving: S2F ≈ 56
  → 2024 halving: S2F ≈ 120

Modelo prevê aumento de preço proporcional à escassez
Criticado: não considera demanda, só oferta
Útil como contexto macro, não para timing preciso
```

---

## 5. Métricas de Sentimento On-Chain

### Fear & Greed Index
```
0-25:   Extreme Fear   → historicamente = oportunidade de compra
25-45:  Fear
45-55:  Neutral
55-75:  Greed
75-100: Extreme Greed  → historicamente = risco de topo

Composto de: volatilidade, momentum, social media, dominância, trends
Fonte: alternative.me/crypto/fear-and-greed-index
```

### Funding Rate (Futuros Perpétuos)
```
Positivo → longs pagando shorts → mercado mais long que short → bullish short-term
Muito positivo (> +0.1%) → excesso de longs → risco de liquidação = shorting oportunidade

Negativo → shorts pagando longs → mercado mais short que long → bearish short-term
Muito negativo (< -0.1%) → excesso de shorts → risco de short squeeze = buying oportunidade

Fonte: Coinglass, Binance, Bybit
```

### Long/Short Ratio
```
> 60% long → mercado excessivamente otimista → contrarian = bearish
< 40% long → mercado excessivamente pessimista → contrarian = bullish
```

### Open Interest (OI)
```
OI crescendo + preço subindo = tendência saudável (novos comprados entrando)
OI crescendo + preço caindo = tendência bearish saudável (novos vendidos entrando)
OI caindo + preço subindo = short squeeze (fechamento de posições vendidas)
OI caindo + preço caindo = long liquidation (fechamento de posições compradas)
OI muito alto = sistema alavancado demais = risco de volatilidade explosiva
```

---

## 6. Whale Tracking

### Como Identificar Movimentos de Whales
```
Endereços BTC > 1.000 BTC: "humpback whales"
Endereços BTC 100-1.000 BTC: "whales"
Endereços ETH > 10.000 ETH: whales

Ferramentas:
  → Whale Alert (Twitter/Telegram): alertas de transações grandes
  → Glassnode: métricas de concentração de supply
  → Arkham Intelligence: identificação de endereços institucionais
  → Nansen: labeling de carteiras (exchanges, protocolos, fundos)
```

### Interpretação de Whale Moves
```
Whale move → exchange:
  → Pode ser venda (bearish)
  → Pode ser depósito de garantia para futuros (neutro)
  → Considerar contexto de preço e outros indicadores

Whale move → cold wallet / self-custody:
  → Confiança no longo prazo (bullish)
  → Acumulação em marcha

Whale para whale (wallet desconhecida):
  → OTC deal possível (compra/venda fora da exchange)
  → Difícil interpretar sem contexto
```

---

## 7. Stack de Ferramentas On-Chain

| Ferramenta | Especialidade | Custo |
|-----------|---------------|-------|
| **Glassnode** | Métricas BTC/ETH mais completas | Pago (freemium) |
| **CryptoQuant** | Exchange flows, futures, mineradores | Pago (freemium) |
| **Coinglass** | Funding rate, OI, liquidações, heatmap | Gratuito |
| **Nansen** | Labels de carteiras, DeFi analytics | Pago |
| **Arkham Intelligence** | Identificação de entidades | Freemium |
| **Santiment** | Sentimento social + on-chain | Pago |
| **DeFiLlama** | TVL por chain/protocolo, outflows, dominância DeFi | **Gratuito — API pública** (`api.llama.fi/v2/chains`) |
| **Messari** | Real vs reported volume, active addresses, tokenomics | **Gratuito sem auth** (`data.messari.io/api/v1/assets/{slug}/metrics`) |
| **Token Terminal** | Métricas de revenue de protocolos | Freemium |
| **Dune Analytics** | Dashboards customizados on-chain | Freemium |
| **Whale Alert** | Alertas de transações grandes | Gratuito |
| **Lookonchain** | Análise de carteiras de whales | Gratuito |
| **mempool.space** | Hashrate BTC, fee market, mempool | **Gratuito** (`mempool.space/api/v1/mining/hashrate/1y`) |
| **Etherscan** | Concentração de holders ERC-20 | **Gratuito** (`api.etherscan.io/api?module=token&action=tokenholderlist`) |

### Fontes integradas nos agentes (dados reais, sem auth)

| Fonte | Agente | Dado extraído |
|-------|--------|---------------|
| `api.llama.fi/v2/chains` | FundAgent | TVL total DeFi, dominância ETH, top 5 chains |
| `data.messari.io/.../metrics` | FundAgent | Real vs reported volume ratio (detecta wash trading) |
| `mempool.space/api/v1/mining/hashrate/1y` | ChainAgent | Hashrate relativo à média 12 semanas (vs absoluto obsoleto) |
| `api.etherscan.io/...tokenholderlist` | ChainAgent | Concentração top-10 holders ERC-20 |
| `api.alternative.me/fng/` | SentAgent | Fear & Greed Index |
| `api.coinex.com/v2/futures/funding-rate` | SentAgent/FundAgent | Funding rate (campo `data[0].latest_funding_rate`) |

---

## 8. Framework de Leitura Rápida (Daily Check)

```
BULLISH: 3+ desses presentes
  □ Exchange outflow (coins saindo)
  □ LTH supply crescendo
  □ Funding rate neutro ou levemente negativo
  □ MVRV Z-Score < 3 (não sobrecomprado)
  □ Fear & Greed < 50 (sem euforia)
  □ Open Interest caindo (sem excesso de alavancagem)

BEARISH: 3+ desses presentes
  □ Exchange inflow significativo
  □ LTH começando a distribuir
  □ Funding rate muito positivo (> +0.05%)
  □ MVRV Z-Score > 6
  □ Fear & Greed > 75 (euforia)
  □ Open Interest crescendo muito rápido
```
