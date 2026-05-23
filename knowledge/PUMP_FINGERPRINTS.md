# PUMP_FINGERPRINTS.md — Biblioteca de Assinaturas de Pump

> Padrões de volume/preço identificados em pumps históricos confirmados.
> Base para o sistema de fingerprint matching do GemAgent.
> Fontes: Binance data.binance.vision (1s/1min), CoinEx klines (5min/1H).

---

## O Que é uma Fingerprint de Pump

Uma **fingerprint** é o conjunto de características quantificáveis que precedem um pump real.
Não é "preço subiu rápido" — é o padrão específico de como o volume se comporta ANTES do pump principal.

Características extraíveis:
- Distribuição de volume entre candles (heterogeneidade)
- Padrão de wicks (comprimento relativo aos candles bodies)
- Sequência de retração após spike inicial
- Aceleração ou desaceleração de volume nas 6H anteriores à explosão
- Amplitude dos candles verdes vs vermelhos no dia do spike

---

## Fingerprints Confirmadas

### FP-001: PEPE — Meme de Primeira Onda (Abril 2023)
```
Timeframe de análise: 1H Binance (PEPEUSDT)
Janela: 7 dias antes do pump principal (+4.200% em 10 dias)

Características pré-pump (dias -7 a -2):
  - Volume diário: 3x–4x acima da média dos 30 dias anteriores
  - Candles 1H: alternância irregular verde/vermelho (não é direcional ainda)
  - Wicks: predominantemente inferiores (compradores absorvendo vendas)
  - Range diário: expandindo progressivamente (+5% → +8% → +12% → +18%)
  - Retração máxima intraday: nunca ultrapassa 40% do último impulso positivo

Características do dia do pump:
  - Volume 1H: primeiros 3 candles com volume crescente (1x → 1.8x → 3.2x)
  - Body/wick ratio: candles verdes com body > 70% do range total
  - Sem candle de exaustão (doji/spinning top) nos primeiros 4H

Score de similaridade: se padrão atual > 70% desta fingerprint → FORTE sinal
```

### FP-002: WIF — Meme de Segunda Onda + Exchange Listing (Dezembro 2023)
```
Timeframe de análise: 1H Binance (WIFUSDT)
Janela: 72H antes do pump +800%

Características únicas do WIF:
  - Pump PRECEDIDO por retração de 30-40% (armadilha de baixa antes da explosão)
  - Volume na retração: MENOR que no pump anterior (stops limpos, não distribuição)
  - Fingerprint chave: 3 candles 1H de volume decrescente na queda → inversão abrupta
  - Listing em exchange major (Binance) como catalisador final — mas acumulação começa antes

Sinal de entrada WIF pattern:
  - Vol spike inicial → retração -35% com volume baixo → segundo vol spike > primeiro
  - Este padrão = reacumulação, não distribuição
  - GemAgent: detecta pela sequência [spike → retração baixo vol → spike maior]
```

### FP-003: BONK — First Dog of Solana (Janeiro 2023)
```
Timeframe: 1H (BONKUSDT)

Fingerprint de acumulação lenta:
  - 14 dias de volume acima da média, mas sem movimento de preço relevante
  - Padrão "compressão": range diário encolhendo progressivamente
  - Wicks de baixo cada vez menores (suporte se consolidando)
  - Quebra: candle 1H com volume 8x da média das últimas 24H

Este padrão é mais difícil de detectar em tempo real (14 dias de espera).
GemAgent usa como referência para MOMENTUM mode (quando já há histórico).
```

### FP-004: SKYAI — New Listing Organic (2024, CoinEx)
```
Timeframe: 1H CoinEx (SKYAIUSDT)
Janela: 4 dias após listagem

Fingerprint de new listing orgânico:
  Dia 1-2: volume baixo, spreads largos, poucos trades
  Dia 3:   primeiro teste de interesse — vol 1.5x do dia 1
  Dia 4:   ENTRADA — vol 4.2x avg_3d, range +35%, AI narrative ativa
  
Características do candle de entrada (5min):
  - Volume heterogêneo (não repetitivo → orgânico)
  - Body ratio > 60% nos candles verdes
  - Retração entre spikes < 20% (compradores agressivos)
  
Dias seguintes:
  - Consolidação por 3-5 dias (range -15% a +5% do spike)
  - Segundo pump (days 10-15) leva ao máximo absoluto
```

### FP-005: AIDOGE — Armadilha Clássica de Dois Spikes
```
Timeframe: 1H CoinEx (AIDOGEUSDT)

SPIKE FALSO (dia 1):
  - Volume alto mas características de wash trading
  - Candles 5min com volume repetitivo (±5% entre candles consecutivos)
  - Wicks superiores longos (pressão vendedora absorvendo cada impulso)
  - Range fechado perto da abertura (body pequeno)

PUMP REAL (dia 8):
  - Volume orgânico heterogêneo
  - Candles verdes com bodies dominantes
  - Wicks inferiores (suporte forte)
  - Narrativa consolidada no Twitter/Telegram

Lição: o PRIMEIRO spike de AIDOGE marcaria score BAIXO no detector orgânico.
O SEGUNDO spike marcaria score ALTO. Sistema funcionaria corretamente.
```

---

## Algoritmo de Detecção Orgânica vs Wash Trading

### Indicadores de Volume ORGÂNICO (score +)

```python
# Heterogeneidade de volume (Coeficiente de Variação)
cv = std(volumes_5min) / mean(volumes_5min)
# CV > 0.5 → orgânico (alta variação = participantes reais)
# CV < 0.2 → suspeito (volume muito uniforme = bot)

# Dominância dos candles verdes
green_vol = sum(vol para candles onde close > open)
red_vol   = sum(vol para candles onde close < open)
ratio = green_vol / (green_vol + red_vol)
# ratio > 0.65 → compradores dominantes → orgânico

# Body ratio dos candles 5min
body_ratio = abs(close - open) / (high - low)
# média > 0.55 → candles com corpo dominante → momentum real

# Retração controlada
max_retraction = max queda intraday / impulso anterior
# < 0.35 → compradores segurando → sinal positivo
```

### Indicadores de WASH TRADING (score -)

```python
# Volume repetitivo (correlação sequencial)
vol_diff = [abs(v[i] - v[i-1]) / v[i-1] for i in range(1, len(volumes))]
repetitive = sum(1 for d in vol_diff if d < 0.05) / len(vol_diff)
# > 0.40 → 40%+ dos candles têm volume quase idêntico → bot

# Preço flat com volume alto
price_change = abs(close[-1] - open[0]) / open[0]
vol_intensity = mean(volumes) / avg_3d_vol
# vol_intensity > 2.0 e price_change < 0.03 → wash trading clássico

# Wicks superiores excessivos
wick_up = high - max(open, close)
wick_down = min(open, close) - low
# mean(wick_up) > mean(wick_down) * 2.5 → pressão vendedora constante → dump em andamento
```

---

## Score de Similaridade (0–100)

```
Calcular para cada candle de entrada candidato:

ORGANIC_SCORE:
  + 25 pts: CV do volume 5min > 0.5
  + 20 pts: green_vol_ratio > 0.65
  + 15 pts: body_ratio médio > 0.55
  + 15 pts: max_retraction < 0.35
  + 10 pts: volume crescente nos últimos 3 candles (aceleração)
  - 20 pts: repetitive_vol > 0.40
  - 15 pts: wicks superiores > 2.5x inferiores
  - 10 pts: preço flat com vol alto

FINGERPRINT_MATCH (comparação com biblioteca):
  + 10 pts: padrão similar a FP-001 (PEPE range expansion)
  + 10 pts: padrão similar a FP-004 (SKYAI new listing organic)
  + 5 pts: padrão de retração controlada (FP-002 style)
  
  Score 0-100. Threshold: > 70 para entrada plena, 40-70 para sizing reduzido.
```

---

## Construção da Biblioteca Local

### Download via data_collector.py (já implementado)

```bash
# 1s candles dos maiores pumps da Binance
python data_collector.py --market PEPEUSDT --period 1sec --source binance \
    --start 2023-04-14 --end 2023-04-21

python data_collector.py --market WIFUSDT --period 1sec --source binance \
    --start 2023-12-01 --end 2023-12-10

python data_collector.py --market BONKUSDT --period 1sec --source binance \
    --start 2023-01-01 --end 2023-01-15
```

### Pré-computação dos fingerprints

```python
# Script: backtest/compute_fingerprints.py (a criar)
# Lê os 1s candles → agrega em 1min/5min → calcula scores → salva na tabela pump_fingerprints
```

### Schema Supabase (extensão)
```sql
CREATE TABLE pump_fingerprints (
    id              SERIAL PRIMARY KEY,
    name            TEXT NOT NULL,           -- "FP-001-PEPE"
    market          TEXT NOT NULL,
    period          TEXT NOT NULL,           -- "1min"
    window_start    TIMESTAMPTZ,
    window_end      TIMESTAMPTZ,
    cv_volume       FLOAT,
    green_ratio     FLOAT,
    body_ratio      FLOAT,
    max_retraction  FLOAT,
    vol_accel       FLOAT,
    outcome_pct     FLOAT,                   -- resultado do pump
    created_at      TIMESTAMPTZ DEFAULT NOW()
);
```

---

## Limitações Conhecidas

1. **Survivorship bias**: a biblioteca contém APENAS pumps que aconteceram. Pumps que não ocorreram com padrões similares não estão mapeados. O modelo pode ter false positives.

2. **Regime dependente**: FP-001 (PEPE) ocorreu em bull market. O mesmo padrão em bear pode não resultar em pump — contexto macro deve ser checado.

3. **Coins novas vs estabelecidas**: fingerprints de coins CoinEx-only não têm equivalente na Binance. FP-004 (SKYAI) é construída com dados CoinEx 1H, não Binance 1s — resolução menor.

4. **Timing de saída**: as fingerprints identificam a ENTRADA. O ponto de saída ótimo não é mapeado com a mesma precisão — usar trailing stop como fallback.
