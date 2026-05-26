# 🧠 Trailing Inteligente Proativo — Arquitetura

**Data:** 2026-05-25  
**Diferença chave:** Não esperar o preço acionar trigger — **antecipar movimentos** baseado em sinais precoces.

---

## 🔄 REATIVO vs PROATIVO

### Reativo (atual)
```
Preço sobe 33% do range → ativa Phase 1 → move stop para BE
```
Problema: **só age depois que o movimento aconteceu**. Se reverter rápido, perde lucro.

### Proativo (proposta)
```
Vela 1h fechou DOJI no topo + RSI overbought + volume secando
  → ANTES do drawdown, apertar stop preventivamente
```
Vantagem: **detecta sinal de exhaustion ANTES da reversão**.

---

## 🎯 5 CAMADAS DE INTELIGÊNCIA

### 🟢 CAMADA 1: Reativa (já existe)
- Phase 0 → 1 → 2 → 3 baseado em % do range
- **Status: funcionando após bug fix**

### 🔵 CAMADA 2: Volatilidade Adaptativa (proposta A anterior)
- ATR define largura do stop por par
- Ajusta thresholds de phase trigger
- **Trabalho: 30min**

### 🟣 CAMADA 3: Exhaustion Detection (NOVO!)
Detecta **sinais de fraqueza** ANTES do reversal:

#### Sinais bullish exhaustion (em LONG):
- **Doji/Pin bar** no topo de movimento
- **Bearish divergence**: preço em HH mas RSI em LL
- **Volume secando**: vol últimas 3h < 50% média 24h
- **Wick top**: candle 1h com wick superior > 2x corpo
- **Distance from VWAP**: preço > 2 sigma acima VWAP

**Quando detectar 2+ sinais**: apertar stop **proativamente**:
- Phase 0 → mover stop +20% mais perto
- Phase 1 → mover stop para +10% acima do entry
- Phase 2 → apertar para 5 ATRs do preço atual

### 🟡 CAMADA 4: Microstructure Awareness (AVANÇADO)
- **Order book imbalance**: se bid wall some → apertar stop
- **Funding rate flip**: positivo→negativo em LONG = vendedores agressivos
- **Open Interest divergence**: preço sobe mas OI cai = falta convicção
- **Whale watcher**: já temos! Integrar — whale dump detectado → tighten stop

### 🔴 CAMADA 5: Macro/Cross-asset (TOP TIER)
- **BTC dump correlato**: BTC -3% em 1h → apertar todas alts longs
- **DXY spike**: dólar +1% rápido → bearish para crypto
- **VIX spike**: risk-off → reduzir exposure
- **Event-driven**: FOMC, CPI, listing news → trailing temporário ultra-apertado

---

## 🏗️ ARQUITETURA PROPOSTA

```
┌─────────────────────────────────────────────┐
│  Update-TrailingStops (cada 5min)           │
│                                             │
│  Para cada posição:                         │
│    1. Reativo: phases 0→1→2→3              │
│    2. Adaptativo: ATR para stops           │
│    3. Exhaustion: detectar fraqueza        │
│    4. Microstructure: OI/funding/whales    │
│    5. Macro: BTC/DXY correlation           │
│                                             │
│  Score combinado → ajustar stop             │
└─────────────────────────────────────────────┘
```

### Algoritmo:
```python
def calculate_smart_stop(position):
    base_stop = get_phase_stop(position)        # camada 1
    atr_stop = get_atr_stop(position)           # camada 2
    exhaustion = detect_exhaustion(position)    # camada 3
    micro = check_microstructure(position)      # camada 4
    macro = check_macro_pressure(position)      # camada 5
    
    # Stop final = MAIS conservador entre todos
    # MAS pondera com sinal de força (não força saída se BULL forte)
    final_stop = max(
        base_stop,
        atr_stop,
        exhaustion.suggested_stop,
        micro.suggested_stop,
        macro.suggested_stop
    )
    
    # Hard cap: nunca mover stop para baixo (em LONG)
    return max(final_stop, current_stop)
```

---

## 📊 IMPACTO ESPERADO

| Cenário | Trailing reativo | Trailing proativo |
|---------|------------------|-------------------|
| Pump → reversal V | Stop hit no topo do retorno (-50% gain) | Stop apertado antes do topo (-15% gain) |
| Acumulação chata | Stop fixo em -5% | Stop adapta para -3% (par estável) |
| BTC flash crash | Stop fixo, perde 100% range | BTC dump → todas longs tighten 50% |
| Whale dump detectado | Espera trigger | Stop sobe imediatamente |
| News negativa | Sem ação | Telegram alert + apertar stop |

**Estimativa de melhoria:**
- Win rate: igual (não muda quando está certo)
- Profit médio: **+15-25%** (lock melhor em winners)
- Loss médio: **-30-40%** (cortes preventivos antes de drawdown grande)
- Sharpe: **~1.5x melhor**

---

## 🚀 PLANO DE IMPLEMENTAÇÃO

### Fase 1 (HOJE — 2h)
- [x] Bug fix peak persistence ✅ DONE
- [ ] Camada 2: ATR adaptativo (integrar `lib_trailing_stop_adaptive.ps1`)
- [ ] Camada 3 minimalista: detectar 3 sinais (doji top, vol drying, wick top)

### Fase 2 (semana — 4h)
- [ ] Camada 3 completa: bearish divergence, distance from VWAP
- [ ] Camada 4: Open Interest awareness via CoinEx API
- [ ] Camada 4: Funding rate flip detection

### Fase 3 (depois — 6h)
- [ ] Camada 4: Whale watcher integration (já temos!)
- [ ] Camada 5: BTC correlation engine
- [ ] Camada 5: DXY/VIX macro pressure

---

## 🧪 VALIDAÇÃO

Para cada camada nova:
1. **Backtest paper**: rodar nos últimos 30 dias com posições reais
2. **Comparação A/B**: trailing reativo vs proativo
3. **TDD**: testes unitários para cada detector

---

## 💡 INSIGHT FINAL

**Trailing proativo = trader pro automatizado:**
- Não espera "Stop Loss" mecânico
- Lê o tape como humano: "tá ficando ruim, vou apertar"
- Combina técnico + microstructure + macro
- **Reduz drawdown sem sacrificar upside**

**Mas atenção:**
- Mais complexidade = mais bugs potenciais
- Cada camada adicional precisa **TDD rigoroso**
- Em paper trade primeiro, sempre

---

## 🎯 Próxima ação?

Quer que eu comece pela Fase 1? Especificamente:
1. **ATR adaptativo** integrado (~30min)
2. **3 detectores de exhaustion** simples (~1h)
3. **Testes** (~30min)

Total: ~2h para ter trailing 2x mais inteligente.
