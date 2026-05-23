# SCALP E DAY TRADING — Estratégias Testadas

> Referências: Larry Connors, Andrew Aziz, John Carter, Toby Crabel, Linda Raschke,
> Ross Cameron (Warrior Trading), Al Brooks, ICT Michael Huddleston.

> **ATENÇÃO — AMBIENTE 2024-2025:** O mercado crypto agora tem participação relevante de
> HFT e market makers algorítmicos. Isso significa: spreads menores mas stop hunts mais
> precisos, falsos breakouts mais frequentes em níveis redondos e níveis óbvios de S/R,
> e janelas de momentum mais curtas antes do mean reversion. Scalp abaixo de 5 minutos
> compete diretamente com algoritmos — prefira 15m ou superior para setups estruturais.

---

## 1. Fundamentos Antes de Qualquer Estratégia

### O que define um edge real?
```
Edge = P(ganho) × Ganho_médio - P(perda) × Perda_média > 0

Exemplo:
  Win rate: 40%
  Ganho médio: $150 (3R)
  Perda média: $50 (1R)
  Edge = 0.40 × 150 - 0.60 × 50 = 60 - 30 = +$30 por trade
  → Lucrativo com só 40% de acerto
```

### Regras de Sessão
```
Não operar:
  ├── Primeiros 5 min após abertura (spread alto, descoberta de preço)
  ├── Horário de almoço (baixo volume, movimentos falsos)
  ├── Últimos 15 min antes de dado econômico relevante
  ├── Após 3 perdas seguidas no dia (resetar mentalmente)
  └── Quando P&L positivo está em risco (proteger dia positivo)

Melhores janelas:
  ├── BTC/crypto: London Open (07-09 UTC) e NY Open (12-14 UTC)
  ├── Primeiros 30-60 min de qualquer sessão nova
  └── Após saída de range da sessão asiática
```

---

## 2. SCALPING

### 2.1 VWAP Scalp (mais institucional)

**Conceito:**
O VWAP (Volume Weighted Average Price) é a referência de preço justo para fundos e instituições.
Rejeições do VWAP são previsíveis e repetíveis.

```
Setup COMPRA:
  1. Preço em downtrend intraday → toca o VWAP por baixo
  2. Candle de rejeição no VWAP (hammer, engulfing)
  3. Volume acima da média no candle de rejeição
  4. Bias do dia é de alta (preço > VWAP na maior parte do dia)
  → Entrada: acima do candle de rejeição
  → Stop: abaixo da mínima da rejeição
  → Alvo: extensão do range anterior (1:2 mínimo)

Setup VENDA:
  Espelho exato — rejeição do VWAP por cima em dia de viés baixista
```

**VWAP Bands:**
```
VWAP + 1 desvio padrão = first standard deviation upper
VWAP + 2 desvios = second standard deviation (extremo)
→ Preço em +2σ = sobrecomprado intraday → fade
→ Preço em -2σ = sobrevendido intraday → fade
```

### 2.2 Order Flow Scalp (profissional)

**Ferramentas necessárias:** Bookmap ou Jigsaw Trader

```
Conceito:
  Icebergs: ordens grandes escondidas no book que absorvem fluxo
  Delta: diferença entre contratos comprados vs vendidos
  CVD (Cumulative Volume Delta): acumulação de pressão compra/venda

Setups:
  ABSORPTION: price tenta romper nível, volume alto mas não avança
  → Profissionais absorvendo → reversal iminente

  IMBALANCE: muito mais compra que venda em um nível
  → Preço vai testar zona de desequilíbrio

  EXHAUSTION: volume decresce na direção da tendência
  → Momento acabando → reversal ou pausa
```

### 2.3 Momentum Scalp (abertura)

**Referência:** Andrew Aziz — "How to Day Trade for a Living"

```
Condições:
  1. Pre-market: ativo subiu/caiu +3% ou mais
  2. Volume pré-abertura acima do normal
  3. Catalisador claro (notícia, earnings, listing, tweet relevante)

Setup (Opening Drive):
  → Primeiros 5 min formam a faixa (high e low)
  → Rompimento da faixa com volume = entrada na direção
  → Stop: oposto da faixa
  → Alvo: 2:1 a 3:1 da faixa

Regra de saída:
  → Nunca segurar momentum scalp além de 10-15 min
  → Se não for para seu lado em 5 min, saída na abertura
```

### 2.4 Liquidity Sweep Scalp (SMC)

```
Setup:
  1. Identificar Equal Lows ou Equal Highs no 5m/15m
  2. Aguardar sweep (quebra rápida + rejeição)
  3. Confirmar CHoCH no 1m após o sweep
  4. Entrar na direção oposta ao sweep
  → Stop: abaixo do sweep
  → Alvo: próxima zona de liquidez no lado oposto
```

---

## 3. DAY TRADING

### 3.1 Opening Range Breakout (ORB)

**Referência:** Toby Crabel — "Day Trading with Short Term Price Patterns"

```
Construção:
  → Marca a máxima e mínima dos primeiros 15 ou 30 minutos
  → Esse é o "Opening Range" (OR)

Setup:
  → Break da máxima do OR + volume = compra
  → Break da mínima do OR + volume = venda
  → Stop: oposto do OR (ou dentro do OR com 50% de distância)
  → Alvo: 1x a 2x a altura do OR

Filtros:
  → Dia com gap na mesma direção do break = mais forte
  → OR estreito = breakout mais explosivo
  → Evitar em dias com dados econômicos no meio da sessão

Win rate histórico (Crabel): ~58-62% com RR 1:1.5
```

### 3.2 Pullback em Tendência (mais consistente)

**Referência:** Stan Weinstein, John Carter, múltiplos backtests

```
Identificação de tendência:
  → EMA 9 > EMA 21 > EMA 50 no timeframe operacional
  → ADX > 25
  → Preço fazendo HH/HL

Setup de compra:
  1. Tendência de alta confirmada (daily/4h)
  2. Pullback para zona: EMA 21, Fibonacci 50-61.8%, ou S/R relevante
  3. Volume diminui no pullback (sem vendedores agressivos)
  4. Candle de reversão na zona (hammer, engulfing, pin bar)
  5. Volume cresce no candle de entrada
  → Entrada: acima da máxima do candle de reversão
  → Stop: abaixo da mínima do candle de reversão
  → Alvo 1: último topo (R:R mínimo 1:2)
  → Alvo 2: extensão 127.2% do último movimento

Win rate histórico com filtros: 55-65%
```

### 3.3 Bull Flag / Bear Flag

**Referência:** Thomas Bulkowski — taxa de acerto 67% (bull flag em uptrend)

```
Bull Flag:
  1. Impulso forte de alta (mastro da bandeira) com volume alto
  2. Consolidação em canal descendente leve (a bandeira)
  3. Volume diminui durante a bandeira
  4. Rompimento da resistência da bandeira com volume
  → Entrada: no rompimento ou primeiro reteste
  → Stop: abaixo do suporte da bandeira
  → Alvo: início da bandeira + altura do mastro

Qualidade do setup:
  → Mastro: movimento > 3% em 1-3 candles
  → Bandeira: consolidação de 4-10 candles
  → Ângulo da bandeira: contra o mastro (pullback leve)
  → Nunca operar flags que corrijam mais de 50% do mastro
```

### 3.4 Mean Reversion (Reversão à Média)

**Referência:** Larry Connors & Cesar Alvarez — "Short Term Trading Strategies That Work"

```
RSI(2) Strategy (testada por Connors):
  → Comprar quando RSI(2) < 10 em uptrend de médio prazo
  → Vender quando RSI(2) > 90 em downtrend de médio prazo

  Condições:
  → Para compra: preço acima da SMA 200 (macro bullish)
  → RSI(2) < 10 (extremo sobrevendido de curto prazo)
  → Saída: quando RSI(2) cruza acima de 65

  Win rate histórico: ~68% em ações (Connors)
  Aplicável em crypto com ajustes (mais volatilidade)

Bollinger Band Reversal:
  → Preço toca a banda inferior (2σ) em mercado lateral
  → Confirma com estocástico ou RSI sobrevendido
  → Entrada no fechamento do candle de rejeição
  → Stop: fechamento abaixo da banda inferior
  → Alvo: banda do meio (SMA 20) ou banda superior
```

### 3.5 Breakout com Volume (tendência)

```
Setup:
  1. Ativo em consolidação por 4+ horas/dias
  2. Resistência clara (testada 2+ vezes)
  3. Volume cresce nos dias anteriores ao break (pressão se acumulando)
  4. Candle de breakout: fecha acima da resistência com volume 2x+ da média

Entrada:
  → Opção 1: no fechamento do candle de breakout
  → Opção 2: primeiro reteste da resistência (agora suporte)
  → Stop: abaixo da resistência rompida
  → Alvo: altura da consolidação projetada acima do break

False Break vs Real Break:
  → Real: volume alto + fechamento decisivo + sem wick longo
  → Falso: wick longo, fecha de volta no range, volume mediano
```

---

## 4. Estratégias Específicas para Crypto

### 4.1 Funding Rate Reversal

```
Conceito:
  → Funding rate positivo alto = mercado excessivamente long
  → Todos comprados = vulnerável a short squeeze reversal

Setup de venda:
  1. Funding rate > +0.1% (extremo)
  2. Preço em resistência relevante ou topo de range
  3. Nenhuma notícia positiva catalisando
  → Entrada short
  → Stop: acima da resistência
  → Alvo: 3-5% de queda (long flush)

Fonte: Coinglass.com → Funding Rate
```

### 4.2 Liquidation Hunt (Cascade)

```
Conceito:
  → Liquidações em cascata criam movimentos explosivos
  → Heatmap mostra onde estão os stops concentrados

Setup:
  1. Identificar zona de liquidações grandes no Coinglass heatmap
  2. Preço se aproximando da zona
  3. Volume crescendo na direção
  → Entrar na mesma direção antes das liquidações
  → Sair parcialmente quando price atinge a zona de liquidação
  → Manter parcial para continuação

Ferramenta: Coinglass → Liquidation Heatmap
```

### 4.3 Altcoin BTC Correlation Setup

```
Conceito:
  → Altcoins seguem BTC com delay de 2-30 minutos
  → BTC faz movimento forte → entrar em altcoin que ainda não reagiu

Setup:
  1. BTC faz impulso forte (>1% em 5-15min)
  2. Altcoin target ainda não reagiu (dentro do range)
  3. Altcoin está em setup técnico válido (não em resistência forte)
  → Entrar na altcoin esperando delayed correlation
  → Stop apertado: se BTC reverter, altcoin também
  → Saída rápida: geralmente 15-30 min

Funciona melhor com: ETH, SOL, BNB (maior correlação com BTC)
Evitar: altcoins com notícia própria (correlação quebra)
```

---

## 5. Gestão Durante o Trade

### Parciais (Scaling Out)

```
Posição de 3 unidades:
  → Alvo 1 (1:1): fechar 1 unidade → garante breakeven
  → Alvo 2 (1:2): fechar 1 unidade → lucro garantido
  → Alvo 3 (1:3+): trailing stop na unidade restante

Benefício:
  → Reduz pressure psicológica no meio do trade
  → Sempre termina com winner ou breakeven
  → Deixa "run" a parte que pode virar grande winner
```

### Trailing Stop

```
ATR Trailing:
  → Mover stop para: preço atual - 1.5x ATR(14)
  → Nunca recuar o stop
  → Só avança na direção lucrativa

EMA Trailing:
  → Usar EMA 9 ou 21 como trailing no LTF
  → Saída quando candle fecha abaixo (long) ou acima (short)
```

### Break Even

```
Regra:
  → Quando preço atinge 1:1 (risco em lucro), mover stop para entrada
  → "Free trade" — zero risco de perda no principal
  → Psicologicamente libera para segurar a posição mais tempo
```
