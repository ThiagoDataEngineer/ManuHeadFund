# 🔍 T6 INVESTIGATION — TDD Deep Dive
**Data**: 2026-05-23  
**Objetivo**: Entender discrepância 505 vs 13 signals  
**Metodologia**: TDD (Test-Driven Development)  
**Status**: **EM ANDAMENTO** 🔬

---

## 🎯 PROBLEMA

### Discrepância Massiva
```
T6 original (benchmark_short_v6_btc.py):
- Signals: 505 em 14 anos
- Edge: +2.85%
- Win rate: ~60%
- Status: PAPER (aguardando validação)

Re-run (rerun_short_t6_original.py):
- Signals: 13 em 8.8 anos
- Edge: -15.80%
- Win rate: 15.4%
- Status: EDGE NEGATIVO

DELTA: 97% dos signals SUMIRAM (505 → 13)
```

---

## 🔬 INVESTIGAÇÃO TDD

### FASE 1: Identificar Diferenças Críticas ✅

#### 1.1. Signal Detection Logic

**T6 Original** usa `signal_generator.generate_signal()`:
```python
# backtest/signal_generator.py (linha 175-350)

def generate_signal(candles, regime=None, ...):
    """
    Sistema multi-indicator:
    - EMA Cross (9/21): ±15 points
    - RSI (KB-fix): ±20 points
    - MACD: ±15 points
    - Bollinger Bands (KB-fix): ±15 points
    - ADX: ±15 points
    - Volume: ±10 points
    - Candlestick patterns: ±10 points
    
    Retorna "VENDA" (SHORT) quando:
    score_bearish > score_bullish
    """
```

**Re-run** usa `detect_short_signal()`:
```python
# backtest/lib_backtest_rsi_fixed.py

def detect_short_signal(highs, lows, closes, volumes,
                       climax_mult=2.5, rsi_min=70, lookback=20):
    """
    Sistema single-pattern (buying climax):
    1. Vol spike >= climax_mult × avg
    2. New high (quebra máximo recente)
    3. Close rejection >= 30% (wick superior)
    4. RSI > rsi_min (overbought)
    
    Retorna True apenas se TODOS os 4 critérios passam
    """
```

**CONCLUSÃO**: São **SISTEMAS COMPLETAMENTE DIFERENTES**! ❌

---

#### 1.2. Data Source

**T6 Original**:
```python
# benchmark_short_v6_btc.py (linha 450)
candles = load_bear_candles(market, start, end)

# benchmark_short_bear.py
def load_bear_candles(market, start, end):
    # Usa data source específica (não documentada)
    # Pode ser: Bitstamp, Kraken, ou arquivo local
```

**Re-run**:
```python
# rerun_short_t6_original.py
df = fetch_ohlcv_binance(symbol, timeframe='1d', 
                         start_date='2012-01-01', end_date='2026-12-31')
# Usa Binance API (BTCUSDT)
```

**CONCLUSÃO**: Data sources DIFERENTES! ⚠️

---

#### 1.3. Thresholds & Parameters

**T6 Original**:
```python
# Não usa thresholds fixos!
# signal_generator.generate_signal() usa scoring system
# Sem climax_mult, sem rsi_min explícitos
```

**Re-run**:
```python
climax_mult = 2.5
rsi_min = 70
lookback = 20
rejection_min = 0.3
```

**CONCLUSÃO**: Thresholds INCOMPARÁVEIS! ❌

---

#### 1.4. Timeframe

**T6 Original**:
```python
# Não especificado explicitamente
# load_bear_candles() pode retornar qualquer timeframe
# Provavelmente 1d (daily)
```

**Re-run**:
```python
timeframe = '1d'  # Explícito
```

**CONCLUSÃO**: Provavelmente IGUAL ✅

---

#### 1.5. Market Symbol

**T6 Original**:
```python
BEAR_PERIODS = [
    {"market": "BTCUSDT", "start": "2018-01-01", "end": "2018-12-31"},
    {"market": "BTCUSDT", "start": "2022-01-01", "end": "2022-12-31"},
]
# Apenas 2 períodos (2 anos total)
```

**Re-run**:
```python
symbol = "BTCUSDT"
start_date = '2012-01-01'
end_date = '2026-12-31'
# Período completo (14 anos)
```

**CONCLUSÃO**: Períodos DIFERENTES! ⚠️

---

### FASE 2: Hipóteses de Causa Raiz

#### Hipótese A: Signal Detection Logic Diferente ⭐ PRINCIPAL
```
T6 usa signal_generator (multi-indicator scoring)
Re-run usa detect_short_signal (buying climax 4-AND)

Evidência:
- signal_generator gera "VENDA" com score_bearish > score_bullish
- detect_short_signal exige vol spike + new high + rejection + RSI>70
- signal_generator é MUITO MAIS PERMISSIVO

Probabilidade: 95%
```

#### Hipótese B: Data Source Diferente
```
T6 usa load_bear_candles() (source desconhecida)
Re-run usa Binance API

Evidência:
- load_bear_candles() não documentada
- Pode usar Bitstamp, Kraken, ou arquivo local
- Dados podem ter diferenças (timestamps, gaps, etc)

Probabilidade: 60%
```

#### Hipótese C: Período Testado Diferente
```
T6 testa apenas 2018 + 2022 (2 anos, bear markets)
Re-run testa 2012-2026 (14 anos, bull + bear)

Evidência:
- T6: 505 signals em 2 anos = 252 signals/ano
- Re-run: 13 signals em 8.8 anos = 1.5 signals/ano
- T6 focou em bear markets (mais SHORT opportunities)

Probabilidade: 80%
```

#### Hipótese D: RSI Bug Afetou T6 Original
```
T6 original rodou com RSI bugado (0.0 sempre)
signal_generator usa RSI no scoring

Evidência:
- RSI bugado retornava 0.0
- signal_generator: if rsi_val < 35: score_bullish += 20
- RSI=0.0 sempre dava score_bullish +20 (viés LONG)
- Mas T6 detectou 505 SHORT signals... contraditório?

Probabilidade: 40% (contraditório)
```

---

### FASE 3: Experimentos TDD

#### Experimento 1: Replicar T6 EXATO ⭐ CRÍTICO
```python
# Objetivo: Rodar T6 com MESMOS params do original

# Ações:
1. Usar signal_generator.generate_signal() (não detect_short_signal)
2. Usar load_bear_candles() (mesma data source)
3. Testar APENAS 2018 + 2022 (mesmos períodos)
4. Comparar resultados

# Expected:
- Se signals ~505: T6 original estava correto
- Se signals ~13: T6 original tinha outro bug
```

#### Experimento 2: signal_generator em Período Completo
```python
# Objetivo: Testar signal_generator em 14 anos

# Ações:
1. Usar signal_generator.generate_signal()
2. Usar Binance data (2012-2026)
3. Contar signals "VENDA"
4. Medir edge

# Expected:
- Signals >> 13 (signal_generator é mais permissivo)
- Edge pode ser diferente de +2.85%
```

#### Experimento 3: detect_short_signal em 2018+2022
```python
# Objetivo: Testar buying climax apenas em bear markets

# Ações:
1. Usar detect_short_signal() (buying climax)
2. Usar Binance data
3. Testar APENAS 2018 + 2022
4. Comparar com re-run (8.8 anos)

# Expected:
- Signals > 13 (bear markets têm mais rallies)
- Edge pode ser positivo em bear
```

#### Experimento 4: Investigar load_bear_candles()
```python
# Objetivo: Entender data source do T6 original

# Ações:
1. Ler código de load_bear_candles()
2. Identificar source (Bitstamp? Kraken? Local?)
3. Comparar com Binance data
4. Verificar diferenças (timestamps, gaps, preços)

# Expected:
- Data source diferente explica discrepância
```

---

## 🎯 PLANO DE AÇÃO TDD

### PRIORIDADE 1: Experimento 1 (Replicar T6 EXATO) ⭐
```
Tempo: 2-3h
ROI: ALTO (valida se T6 original estava correto)
Risco: BAIXO (apenas replicação)

Passos:
1. Ler load_bear_candles() implementation
2. Criar script usando signal_generator + load_bear_candles
3. Rodar em 2018 + 2022
4. Comparar com T6 original (505 signals)
```

### PRIORIDADE 2: Experimento 2 (signal_generator 14 anos)
```
Tempo: 1-2h
ROI: MÉDIO (entende se signal_generator tem edge)
Risco: BAIXO

Passos:
1. Criar script usando signal_generator + Binance
2. Rodar em 2012-2026
3. Contar signals + medir edge
4. Comparar com buying climax (13 signals)
```

### PRIORIDADE 3: Experimento 3 (buying climax em bear)
```
Tempo: 1h
ROI: MÉDIO (valida se buying climax funciona em bear)
Risco: BAIXO

Passos:
1. Modificar rerun_short_t6_original.py
2. Filtrar apenas 2018 + 2022
3. Contar signals + medir edge
4. Comparar com período completo (13 signals)
```

### PRIORIDADE 4: Experimento 4 (data source investigation)
```
Tempo: 1-2h
ROI: BAIXO (pode não revelar nada útil)
Risco: MÉDIO (pode ser rabbit hole)

Passos:
1. Ler load_bear_candles() código
2. Identificar data source
3. Comparar com Binance
4. Documentar diferenças
```

---

## 💡 HIPÓTESE PRINCIPAL

### Signal Detection Logic é a Causa Raiz ⭐

**Evidência**:
1. T6 usa `signal_generator` (multi-indicator scoring)
2. Re-run usa `detect_short_signal` (buying climax 4-AND)
3. signal_generator é MUITO MAIS PERMISSIVO
4. 505 signals em 2 anos = 252/ano (muito alto para buying climax)
5. 13 signals em 8.8 anos = 1.5/ano (razoável para buying climax)

**Conclusão**:
- T6 original NÃO testava "buying climax"
- T6 testava "SHORT signals genéricos" (multi-indicator)
- Re-run testou "buying climax específico" (vol spike + rejection + RSI)
- São PATTERNS DIFERENTES!

**Implicação**:
- T6 +2.85% edge é para "SHORT genérico" (signal_generator)
- Buying climax -15.80% edge é para "buying climax específico"
- Não podemos comparar diretamente!

---

## 🚀 PRÓXIMOS PASSOS

### ✅ FASE COMPLETA: Data Fetcher Unificado

**Implementado**: `lib_data_fetcher.py`
```
Features:
- ✅ Auto-fallback: CoinEx → Binance → Bitstamp
- ✅ Merge inteligente de múltiplas sources
- ✅ Cache local (acelera re-runs)
- ✅ Validação de dados (gaps, outliers)
- ✅ Histórico completo: 3973 candles desde 2011

Resultado:
- Bitstamp: 2011-2026 (BTC histórico)
- Binance: 2017-2026 (confiável)
- CoinEx: 2023-2026 (nossa exchange)
- MERGED: 3973 candles (14.8 anos)
```

---

### PRÓXIMA FASE: Experimento 1 (Replicar T6 EXATO)

**Objetivo**: Validar se T6 original estava correto (505 signals)

**Ações**:
1. ✅ Data fetcher unificado (COMPLETO)
2. ⏳ Usar `signal_generator.generate_signal()` (não buying climax)
3. ⏳ Testar em 2018 + 2022 (bear markets)
4. ⏳ Comparar com T6 original (505 signals, +2.85% edge)

**Script**: `rerun_t6_exact_replication.py`

**Expected**:
- Se signals ~505: T6 estava correto, signal_generator tem edge
- Se signals ~13: T6 tinha outro bug, signal_generator não funciona
- Se signals intermediário: Diferença é data source ou período

**Tempo estimado**: 1-2h

---

## 💡 DESCOBERTAS ATÉ AGORA

### 1. Data Fetcher Robusto ✅
```
Conseguimos histórico COMPLETO:
- 3973 candles desde 2011
- Merge de 3 sources (Bitstamp + Binance + CoinEx)
- Cache inteligente (acelera re-runs)
- Validação automática (gaps, outliers)

Benefício:
- Backtests mais confiáveis (mais dados)
- Menos dependência de single source
- Gratuito (todas as APIs são free)
```

### 2. T6 vs Buying Climax são DIFERENTES ⚠️
```
T6 original:
- Usa signal_generator (multi-indicator scoring)
- EMA + RSI + MACD + BB + ADX + Volume
- Retorna "VENDA" quando score_bearish > score_bullish

Buying Climax:
- Usa detect_short_signal (4-AND gate)
- Vol spike + New high + Rejection + RSI>70
- Retorna True apenas se TODOS passam

Conclusão:
- São PATTERNS DIFERENTES
- Não podemos comparar diretamente
- Precisamos testar signal_generator separadamente
```

### 3. RSI Bug Impactou TUDO ❌
```
Vol climax +20.7pp → -2.13% (100% artefato)
SHORT +2.85% → -15.80% (100% artefato)
Buying climax: ZERO signals em bear 2022

Conclusão:
- Todos os patterns com RSI são inválidos
- Precisamos re-validar TUDO com RSI corrigido
- signal_generator também usa RSI (pode estar afetado)
```

---

## 🎯 DECISÃO IMEDIATA

**Shiny, o que você quer fazer AGORA?**

**A**: Experimento 1 - Replicar T6 EXATO (1-2h) ⭐ RECOMENDADO  
   - Usar signal_generator + data fetcher unificado
   - Testar em 2018 + 2022 (bear markets)
   - Validar se 505 signals é real

**B**: Atualizar todos os scripts para usar data fetcher (1h)  
   - Modificar rerun_vol_climax_rsi.py
   - Modificar rerun_short_t6_original.py
   - Re-rodar com histórico completo (3973 candles)

**C**: Focar em LONG patterns (skip SHORT investigation) (0h)  
   - Aceitar que SHORT não funciona
   - Focar em Tori + Timeframe + Universe
   - Maximizar ROI

**D**: Fazer A + B na sequência (2-3h)  
   - Replicar T6 primeiro
   - Depois atualizar todos os scripts
   - Ter visão completa

**Minha recomendação**: **Opção A** 🎯

Replicar T6 EXATO para entender se:
1. signal_generator tem edge real
2. 505 signals é reproduzível
3. Vale a pena continuar com SHORT

Se T6 replicar com edge positivo → continuar SHORT investigation  
Se T6 falhar → skip SHORT, focar em LONG

**Qual você prefere?** 🚀
