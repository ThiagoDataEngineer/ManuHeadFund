# INDICATORS REFERENCE — Bíblia dos Indicadores Técnicos

> Referências: Welles Wilder (RSI, ATR, ADX), Gerald Appel (MACD), John Bollinger,
> George Lane (Stochastic), Joe Granville (OBV), Marc Chaikin, Larry Williams.

---

## Princípio de Uso de Indicadores

> Indicadores são derivados do preço — o preço é o dado primário.
> Use indicadores para CONFIRMAR o que o preço já mostra.
> Nunca use indicador isolado. Confluência de 2-3 é o mínimo.
> Menos é mais: 2-3 indicadores bem compreendidos > 10 mal entendidos.

---

## 1. TENDÊNCIA

### EMA (Exponential Moving Average)
```
Configurações mais usadas:
  EMA 9   → curto prazo, muito reativo (scalp/day)
  EMA 21  → médio prazo, pullbacks em tendência
  EMA 50  → tendência primária (day/swing)
  EMA 200 → tendência macro (swing/position)

Interpretação:
  Preço > EMA = bullish no timeframe
  Preço < EMA = bearish no timeframe
  EMAs alinhadas (9>21>50>200) = tendência forte de alta
  Death cross (50 cruza abaixo da 200) = bearish estrutural
  Golden cross (50 cruza acima da 200) = bullish estrutural

EMA vs SMA:
  EMA dá mais peso aos dados recentes → reage mais rápido
  SMA = média simples → mais suave, menos sinais falsos
  Para day/scalp: EMA; para weekly/position: SMA
```

### ADX (Average Directional Index) — Welles Wilder
```
Fórmula: mede força da tendência (não direção)

Leitura:
  ADX < 20   → mercado sem tendência (range) → evitar breakouts
  ADX 20-25  → início de tendência
  ADX 25-50  → tendência presente e operável
  ADX > 50   → tendência muito forte (próximo de exaustão)
  ADX caindo → tendência enfraquecendo

+DI e -DI (direcional):
  +DI > -DI = momentum de alta
  -DI > +DI = momentum de baixa
  Cruzamento de DIs = mudança de momentum

Configuração padrão: 14 períodos
```

### Ichimoku Cloud
```
Componentes:
  Tenkan-sen (9):   média de alta + baixa de 9 períodos
  Kijun-sen (26):   média de alta + baixa de 26 períodos
  Senkou Span A:    média de Tenkan e Kijun, projetada 26 períodos à frente
  Senkou Span B:    média de 52 períodos, projetada 26 à frente
  Chikou Span:      fechamento atual, plotado 26 períodos atrás

Interpretação:
  Preço acima da nuvem = bullish
  Preço dentro da nuvem = consolidação/incerteza
  Preço abaixo da nuvem = bearish
  Nuvem verde (Span A > Span B) = suporte fraco; nuvem vermelha = suporte forte
  TK cross (Tenkan cruza Kijun) = sinal de entrada
```

---

## 2. MOMENTUM

### RSI (Relative Strength Index) — Welles Wilder
```
Fórmula: RSI = 100 - (100 / (1 + RS))
RS = média de ganhos / média de perdas em N períodos

Configurações:
  RSI 14 → padrão (swing/day)
  RSI 7  → mais reativo (scalp)
  RSI 2  → extremamente reativo (Larry Connors strategy)
  RSI 21 → mais suave (swing/position)

Leitura:
  > 70 = sobrecomprado (atenção para reversão)
  < 30 = sobrevendido (atenção para reversão)
  50   = linha de força (acima = bulls controlam; abaixo = bears)

Em mercado de TENDÊNCIA FORTE:
  → RSI pode ficar em 70+ por muito tempo
  → "Sobrecomprado em tendência" = força, não necessariamente reversão
  → Usar zonas 80/20 em vez de 70/30 em tendências fortes

Divergências (mais confiável que sobrecompra/sobrevenda):
  Bullish: preço faz LL, RSI faz HL → reversão iminente de alta
  Bearish: preço faz HH, RSI faz LH → reversão iminente de baixa
  Quanto mais clara a divergência, mais poderosa o sinal
```

### MACD (Moving Average Convergence Divergence) — Gerald Appel
```
Componentes:
  MACD Line:   EMA12 - EMA26
  Signal Line: EMA9 do MACD Line
  Histogram:   MACD Line - Signal Line

Configuração padrão: (12, 26, 9)

Sinais:
  MACD cruza acima do Signal = bullish
  MACD cruza abaixo do Signal = bearish
  Histogram crescendo = momentum crescendo
  Histogram diminuindo = momentum enfraquecendo
  MACD acima de zero = bullish estrutural
  MACD abaixo de zero = bearish estrutural

Divergências (similar ao RSI):
  Bullish: preço faz LL, MACD faz HL → reversão de alta
  Bearish: preço faz HH, MACD faz LH → reversão de baixa

Melhor uso:
  → Não para scalp (lag grande)
  → Excelente para swing trading em 4h/daily
  → Divergências no daily = sinais de alto timeframe muito confiáveis
```

### Stochastic Oscillator — George Lane
```
Componentes:
  %K: posição do fechamento em relação ao range do período
  %D: média móvel de %K (signal line)

Configurações:
  Slow Stochastic (14,3,3) → padrão, menos ruído
  Fast Stochastic (5,3,3)  → mais reativo, mais sinais falsos

Leitura:
  > 80 = sobrecomprado
  < 20 = sobrevendido
  %K cruza acima %D em zona 20 = compra
  %K cruza abaixo %D em zona 80 = venda

Melhor uso:
  → Range trading (mercados laterais)
  → Entradas em pullback durante tendência
  → Evitar como sinal isolado em tendências fortes
```

---

## 3. VOLATILIDADE

### Bollinger Bands — John Bollinger
```
Componentes:
  Middle Band: SMA 20
  Upper Band:  SMA 20 + (2 × desvio padrão)
  Lower Band:  SMA 20 - (2 × desvio padrão)

Interpretação:
  Bandas largas = alta volatilidade
  Bandas estreitas (squeeze) = baixa volatilidade → breakout iminente
  Preço toca banda superior = sobrecomprado intraday
  Preço toca banda inferior = sobrevendido intraday

Walking the Bands:
  Em tendência forte, preço "caminha" pela banda externa
  → Não fazer fade de tendência apenas porque está na banda

Bollinger Squeeze:
  → Bandas mais estreitas que os últimos 6 meses = compressão extrema
  → Breakout do squeeze geralmente é grande
  → Direção incerta — aguardar confirmação
```

### ATR (Average True Range) — Welles Wilder
```
Fórmula: média do maior entre:
  → Máxima - Mínima atual
  → |Máxima - Fechamento anterior|
  → |Mínima - Fechamento anterior|

Configuração padrão: ATR(14)

Usos:
  → Dimensionar stop: stop = entrada - (1.5 a 2× ATR)
  → Avaliar volatilidade: ATR crescendo = mais volátil = ajustar tamanho
  → Confirmar breakouts: breakout > 1× ATR = significativo
  → Alvos realistas: alvo = entrada + (2-3× ATR)
```

### Keltner Channels
```
Similar ao Bollinger mas usa ATR em vez de desvio padrão
EMA 20 ± (2× ATR)

Comparação com Bollinger:
  → Preço fora do Bollinger mas dentro do Keltner = volatilidade normal
  → Preço fora do Keltner = volatilidade anormal = sinal forte
  → Squeeze: Bollinger dentro do Keltner = compressão extrema (John Carter setup)
```

---

## 4. VOLUME

### OBV (On Balance Volume) — Joe Granville
```
Fórmula:
  Dia de alta: OBV = OBV anterior + volume
  Dia de baixa: OBV = OBV anterior - volume

Interpretação:
  OBV subindo + preço subindo = confirmação de alta
  OBV caindo + preço subindo = divergência bearish (acumulação falha)
  OBV subindo + preço caindo = divergência bullish (acumulação oculta)

OBV prevê o preço:
  → Quando OBV diverge do preço, o preço frequentemente segue o OBV
```

### VWAP (Volume Weighted Average Price)
```
Fórmula: soma(preço × volume) / soma(volume) — intraday

Interpretação:
  Preço > VWAP = buyers no controle intraday
  Preço < VWAP = sellers no controle intraday
  VWAP = referência de preço justo para fundos e instituições

Usos:
  → Scalp: fade de extensões extremas do VWAP
  → Confluência: suporte/resistência no VWAP
  → Não usar em gráficos semanais/mensais (perde significado)
```

### Volume Profile
```
Conceito:
  → Plota volume por NÍVEL DE PREÇO (não por tempo)
  → Mostra onde mais transações ocorreram

Componentes:
  POC (Point of Control): nível com maior volume = zona de maior interesse
  VAH (Value Area High): 70% das transações abaixo deste nível
  VAL (Value Area Low): 70% das transações acima deste nível

Interpretação:
  → Preço tende a retornar ao POC (magnetismo)
  → VAH e VAL = zonas de suporte/resistência fortes
  → Acima do VAH = price discovery (sem suporte de volume acima)
  → Abaixo do VAL = price discovery de baixa

Ferramentas: TradingView (Volume Profile), Sierra Chart
```

### Chaikin Money Flow (CMF)
```
Mede o fluxo de dinheiro entrando/saindo do ativo

CMF > 0 = mais dinheiro entrando = bullish
CMF < 0 = mais dinheiro saindo = bearish
Divergência CMF vs preço = alerta de reversão
```

---

## 5. INDICADORES COMPOSTOS (uso avançado)

### SuperTrend
```
Baseado no ATR para definir tendência dinâmica
Excelente como filtro: só comprar quando SuperTrend é bullish
Configuração: (10, 3) padrão ou (7, 3) para mais sensibilidade
```

### Squeeze Momentum (John Carter / LazyBear)
```
Combina Bollinger Bands + Keltner Channels + Momentum
Squeezes (pontos no zero) = baixa volatilidade → breakout iminente
Histograma: verde = momentum comprando; vermelho = momentum vendendo
```

### Parabolic SAR (Welles Wilder)
```
Pontos acima do preço = bearish; abaixo = bullish
Troca de lado = sinal de reversão
Útil como trailing stop em tendências
```

---

## 6. Configurações por Estilo

```
SCALPING (1m-5m):
  → EMA 9, 21
  → VWAP
  → RSI 7 ou Stochastic Fast
  → Volume + Delta

DAY TRADING (15m-1h):
  → EMA 9, 21, 50
  → VWAP
  → RSI 14
  → Bollinger Bands
  → Volume Profile (sessão)

SWING TRADING (4h-daily):
  → EMA 21, 50, 200
  → RSI 14
  → MACD (12,26,9)
  → Volume Profile (semanal)
  → ADX

POSITION (weekly):
  → SMA 50, 200
  → RSI 14
  → MACD mensal
  → Volume Profile (anual)
  → On-chain (MVRV, NUPL, ciclos)
```
