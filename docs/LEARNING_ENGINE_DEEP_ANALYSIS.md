# 🧠 Learning Engine — Análise Profunda + Predição (2026-06-18)

## I. Estado Atual (Reactive Learning)

### O que temos:
1. **Error Capture** — Parse cloud logs pra BLOCKED/ERROR/SL_HIT
2. **Pattern Classification** — 8 categorias (conviction_low, trendline_weak, etc)
3. **Auto-Adjustment** — Calcula novo threshold baseado em error patterns
4. **Regime Calibration** — Per-regime DSR optimization

### How it works (Ciclo):
```
Cloud logs (6h window)
    ↓
Read + Parse errors
    ↓
Classify patterns (top issue = conviction_low 60%)
    ↓
Calculate adjustment (55 → 50)
    ↓
Validate confidence (need 60%+ to apply)
    ↓
Action: Update conviction.json
    ↓
Wait 6h, repeat
```

### Limitação crítica:
- ⚠️ **REACTIVE**: Aprende DEPOIS de errar
- ⚠️ 24 erros já aconteceram antes de detectar pattern
- ⚠️ 6h lag entre detecção e ação
- ❌ Não previne falhas futuras

---

## II. O Que Falta: PREDICTION (Proativo)

### A. Temporal Analysis — Detectar Trends
```
Observation: Error rate crescendo?
  Day 1: 5% error
  Day 2: 8% error  ← trend up +60%
  Day 3: 12% error ← trend up +50%
  
Predict Day 4: 17% error (extrapolate)
Action: Aumenta threshold ANTES de atingir 20%
```

### B. Signal Degradation Detection
```
Convicção score distribution over time:

Week 1: avg conviction = 72 (σ=8)   ✓ GOOD
Week 2: avg conviction = 68 (σ=12)  ⚠ variance up
Week 3: avg conviction = 64 (σ=15)  ⚠⚠ declining + variance ↑

Predict: Confidence eroding
Action: Loosen threshold (58→60) OR wait for signal clarity
```

### C. Regime Transition Detector
```
Market regime analysis (DSR + momentum):
  Current: BULL_WEAK (DSR=0.95)
  Velocity: declining at -0.05/day
  
Forecast in 3 days: BEAR_WEAK (DSR=0.75)

Action BEFORE transition:
  - Reduce leverage (1.2x → 1.0x)
  - Tighten stops (5% → 3%)
  - Avoid new entries in declining regime
```

### D. Seasonal/Cyclical Patterns
```
Error rate by time of day:
  00:00-06:00 UTC: 15% error (Asian market noise)
  06:00-12:00 UTC: 8% error (EU orderly)
  12:00-18:00 UTC: 20% error (US/EU overlap chaos)
  
Action: Adjust threshold by time-of-day
  (more lenient in quiet hours, strict during chaos)
```

---

## III. Implementação Profunda — PREDICTIVE LEARNING

### Phase A: Temporal Decomposition (Imediato)

```powershell
Analyze-ErrorTrend {
  - Linear regression: error_rate(t) = a*t + b
  - If slope > 0.5% per day → escalating problem
  - Extrapolate: when will error_rate hit 25%?
  
  Example:
    Days 1-7: [5%, 6%, 7%, 9%, 11%, 13%, 15%]
    Slope = +1.43% per day
    Hit 25%? → Day 14
    Action: Adjust BEFORE Day 10
}
```

### Phase B: Signal Quality Tracking (2-3h work)

```powershell
Track-SignalDegradation {
  Per signal type (trendline, conviction, volume, etc):
    - Accuracy over time: did this signal predict winners?
    - Consistency: σ of predictions
    - Predictive power: correlation(signal, outcome)
    
  Example:
    Trendline signal:
      Week 1: 72% accuracy → ✓ STRONG
      Week 2: 65% accuracy → ⚠ declining
      Week 3: 58% accuracy → 🔴 BROKEN
      
    Action: Warn operator, consider removing signal
}
```

### Phase C: Regime Transition Forecast (2-3h work)

```powershell
Forecast-RegimeTransition {
  Input: DSR, momentum, whale flow, macro
  
  Model: Simple state machine
    If (DSR declining 3+ days) → Bear coming
    If (whale accumulation + low DSR) → Bottom?
    If (vol spike + funding high) → Top coming
    
  Output:
    - Probability of transition
    - Days until transition
    - Recommended actions
    
  Action: Pre-adjust 2 days before transition
}
```

### Phase D: Adaptive Thresholds (3-5h work)

```powershell
Adaptive-ConvictionThreshold {
  Base: 55
  
  Time-of-day adjustment:
    Asian hours: +5 (more noise)
    EU hours: -3 (orderly market)
    US hours: +3 (volatile)
    
  Regime adjustment:
    BULL_STRONG: -5 (trending, easier)
    BULL_WEAK: 0 (neutral)
    BEAR_WEAK: +3 (mean-reversion, hard)
    BEAR_STRONG: +8 (dangerous)
    
  Signal quality adjustment:
    If trendline accuracy < 60%: +5 (require more proof)
    If volume degraded: +3
    
  Real-time: conviction_threshold = 55 + adjustments
}
```

---

## IV. Predicted Gains

### Current (Reactive)
- Erro é descoberto 6h depois
- 24+ sinais maus já passaram
- Win rate = 33% (OEIS data)

### Com Prediction (Proativo)
| Métrica | Atual | Esperado | Ganho |
|---------|-------|----------|-------|
| Error detection lag | 6h | 30min | 12x faster |
| Win rate | 33% | 45-50% | +12-17pp |
| Max DD | -2% per event | -0.5% | 4x safer |
| False positives | 20% | 10% | 50% fewer |

### ROI Estimado
- Desenvolvimento: 8-10h
- Testing: 4-5h
- Total: ~15h (~$100-150)
- Expected PnL gain: $50-100/month
- Break-even: 1-2 months

---

## V. Mapa de Implementação

### Sprint 1 (THIS WEEK) — Temporal Analysis
```
[✓] lib_learning_engine.ps1 (reactive, done)
[ ] Add Analyze-ErrorTrend (linear regression)
[ ] Add Classify-TrendDegradation
[ ] TDD 15 tests
Time: 3-4h
```

### Sprint 2 (NEXT WEEK) — Signal Quality
```
[ ] Track-SignalQualityMetrics
[ ] Per-signal accuracy history
[ ] Degradation detector
[ ] TDD 12 tests
Time: 3h
```

### Sprint 3 (FOLLOWING WEEK) — Regime Forecast
```
[ ] Forecast-RegimeTransition (state machine)
[ ] Probability calculator
[ ] Pre-adjustment logic
[ ] TDD 10 tests
Time: 3-4h
```

### Sprint 4 (EOB) — Adaptive Thresholds
```
[ ] Adaptive-ConvictionThreshold
[ ] Time-of-day + regime + signal-quality adjustments
[ ] Wire to gem_executor
[ ] TDD 8 tests
Time: 3h
```

---

## VI. Criticalidade

### Must-Have (Learning Engine + Prediction)
1. ✅ Detect error patterns (DONE)
2. ✅ Adjust conviction (DONE)
3. 🔴 **Forecast degradation trend** (CRITICAL)
4. 🔴 **Predict regime transitions** (HIGH)
5. 🔴 **Adaptive thresholds by context** (MEDIUM)

### Nice-to-Have
- Signal quality per asset
- Correlation with macro events
- Backtesting prediction accuracy

---

## VII. Segurança & Validação

### Guardrails
```
conviction_threshold = 55  # Base
adjustments = []

# Apply adjustments
if (error_trend.slope > 1%/day) {
  adjustments += 5  # Don't exceed +15
}
if (regime == BEAR_STRONG) {
  adjustments += 8
}

final = Clamp(55 + sum(adjustments), 45, 100)

# Confidence check
if (prediction_confidence < 70%) {
  # Don't apply, wait more data
}
```

### Validation Before Apply
- Backtest: Did this adjustment help in past?
- Sensitivity: ±1% adjustment on past data = what ROI?
- Conflict: Any contradictory signals?

---

## VIII. Recomendação Final

### JÁ ENTREGUE (Reactive Learning):
✅ lib_learning_engine.ps1 + TDD 22 tests
✅ Funciona, ajusta conviction em 6h ciclos
✅ Reduces error spike detection from infinite → 360min

### PRÓXIMO (Predictive Learning):
🚀 Implement Analyze-ErrorTrend (3h) — **HIGHEST ROI**
🚀 Add regime transition forecast (4h)
🚀 Wire adaptive thresholds (3h)

### Timeline
- Start: **TOMORROW** (fase 1)
- Phase 1 complete: **+3 days** (EOW)
- Full prediction suite: **+2 weeks**

---

**Avaliação: Learning Engine é sólido mas REATIVO. Adicionar PREDICTION torna-o PROATIVO. Ganho estimado: +12-17pp win rate, 4x safer stops.**

**Pronto pra implementar Prediction? Vamos?**
