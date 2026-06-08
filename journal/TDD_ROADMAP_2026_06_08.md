# 🚀 TDD ROADMAP — MinMax Surfer System

**Objetivo:** Sistema bidirecional que pega MÍNIMAS (LONG) + MÁXIMAS (SHORT) + surfa movimentos

**Data Início:** 2026-06-08 15:50  
**Status:** 🔄 TDD Em Progresso

---

## FASE 1: TEST SUITES ✅ DONE

### 1️⃣ lib_minmax_detector.Tests.ps1
```
✅ Detecta 24h/7d mínimas e máximas
✅ Identifica zonas de entrada (perto mínima/máxima)
✅ Momentum detection (UP/DOWN trends)
✅ Relative strength (0-100 scale)
✅ Multi-timeframe confirmation
✅ Risk management (Kelly + daily loss)

Tests: 15 casos
```

### 2️⃣ lib_momentum_surfer.Tests.ps1
```
✅ Detecta movimentos em andamento
✅ Entry timing (não espera início)
✅ Momentum strength score (0-100)
✅ Trend confirmation (1h+4h+1d)
✅ Exit signals (profit/stop/momentum-drop)
✅ Kelly sizing adaptation

Tests: 13 casos
```

### 3️⃣ lib_bidirectional_gates.Tests.ps1
```
✅ LONG gate (perto mínima)
✅ SHORT gate (perto máxima)
✅ Simultaneous LONG+SHORT (pares diferentes)
✅ Risk management (stops/targets)
✅ Capital allocation (5 trades/semana)
✅ Regime compatibility (BEAR_WEAK, BULL_STRONG)

Tests: 15 casos
```

### 4️⃣ lib_router_spot_futures.Tests.ps1
```
✅ Market availability check
✅ LONG/SHORT routing decision
✅ Capital allocation (70% FUTURES / 30% SPOT)
✅ Leverage management (1-5x)
✅ Execution order (FUTURES first, SPOT fallback)
✅ Risk parity (L≠S simultâneos)
✅ Fee optimization

Tests: 18 casos
```

**Total Test Cases: 61**

---

## FASE 2: IMPLEMENTATION (PRÓXIMA)

### Libraries a Implementar

```
1. agents/lib_minmax_detector.ps1
   ├─ Get-Min24h / Get-Max24h
   ├─ Get-RelativeStrength
   ├─ Detect-TrendMultiframe
   └─ Evaluate-LongZone / Evaluate-ShortZone

2. agents/lib_momentum_surfer.ps1
   ├─ Get-MomentumScore
   ├─ Detect-ActiveTrend
   ├─ Calculate-EntryTiming
   └─ Evaluate-ExitSignals

3. agents/lib_bidirectional_gates.ps1
   ├─ Test-LongGate
   ├─ Test-ShortGate
   ├─ Check-Simultaneous
   └─ Evaluate-RegimeCompatibility

4. agents/lib_router_spot_futures.ps1
   ├─ Detect-MarketAvailability
   ├─ Route-ToSpotOrFutures
   ├─ Calculate-Leverage
   └─ Allocate-Capital
```

---

## FASE 3: INTEGRATION

```
Workflow:
  1. CoinEx market data (all pairs)
  2. MinMax detector (mínima/máxima por par)
  3. Momentum surfer (momentum score)
  4. Bidirectional gates (LONG/SHORT approval)
  5. Router (SPOT vs FUTURES decision)
  6. Execution (PlaceOrder com direção)

Entry Points:
  - scan_master → calls bidirectional_gates
  - gem_loop → executa via router
  - SHORT detector → entra em parallel
```

---

## FASE 4: DEPLOYMENT

```
Timeline:
  - Phase 1 (TDD): Done ✅
  - Phase 2 (Impl): ~2-3h
  - Phase 3 (Integ): ~1h
  - Phase 4 (Test): ~1h
  - Phase 5 (LIVE): 2026-06-09
```

---

## EXPECTED BEHAVIOR (após implementação)

### Exemplo Real: PIPPIN

```
Histórico:
  Min 24h:   0.01400
  Max 24h:   0.02755
  Agora:     0.02755 (+97% do min)

Sistema detecção:
  ✅ Mínima detectada: 0.01400
  ✅ Máxima detectada: 0.02755
  ✅ Preço na MÁXIMA (0% abaixo)
  ✅ Momentum score: 92 (MUITO ALTO)
  ✅ Trend: UP confirmado (1h+4h+1d)

Gate decision:
  ✅ SHORT aprovado (perto máxima)
  ✅ Momentum 92 > 80 → FUTURES
  ✅ 3x leverage aplicado
  ✅ Size: 0.01 capital (1%)
  ✅ Stop: 0.02755 * 1.05 = 0.02893
  ✅ Target: 0.02755 * 0.95 = 0.02617 (5R)

Execução:
  → placeOrder PIPPINUSDT SHORT 3x leverage
  → trail stop-loss ativo
  → realiza ganho de 4-5% em queda
```

---

## SUCCESS CRITERIA

- ✅ 61/61 testes passando
- ✅ Detecta LONG oportunidades (perto mínima)
- ✅ Detecta SHORT oportunidades (perto máxima)
- ✅ Surfa movimentos em andamento (+10-20% já subido)
- ✅ Executa em SPOT ou FUTURES conforme oportunidade
- ✅ Simultaneidade LONG+SHORT em pares diferentes
- ✅ Todos guardrails mantidos (Kelly, Daily Loss, R:R)

---

*Roadmap TDD — 2026-06-08 15:50 BRT*
