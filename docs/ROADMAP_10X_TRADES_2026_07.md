# ROADMAP 10X TRADES — Julho 2026

> Objetivo: 130+ trades/mês com edge real (scalp/long/short, spot/futures)
> Critério: não "mais trades ruins" — mais trades COM edge validado
> Timeline: 30-90 dias, em fases paralelas

---

## ESTADO ATUAL (baseline para 10x)

| Tipo | Trades/mês | Win% | PnL mediano | Edge |
|---|---|---|---|---|
| LONG (quality gates) | 13-26 | ~70% | +2-3% | ✅ validado |
| SHORT (futures) | 0 | — | — | 🔬 backtest v1 reprovou |
| SCALP spot (Layer 5) | ~130 exits | ~63% | -4.6% saved | ✅ validado (exit rule) |
| **TOTAL** | **~160** | — | — | 10% quality-only |

Para 10x: precisa de 1.600+ trades/mês. **Impossível só com quality gates** (universo tem ~11 pumps/dia, gates aprovam 3-5%).

---

## A SOLUÇÃO: 4 FRENTES PARALELAS

### Frente 1: REVERSAL INTRADAY (v2 SHORT ou LONG scalp)
**Status:** Backtest em P&D (52-58% win, média ~0)
**Problema:** média ~0 significa não é "grande ganho" ainda.

**Solução:** Refinar entry/exit rules na hora 1h
- v1: entra D+1 open, stop high+buf%, sai D+1 close
- **v2.5:** entra reversão confirmada (close < high*0.95), stop scalp-width (0.5-1%), sai momentum break
- Teste em dados reais 1h (próximos 5 dias)
- Se win% ≥55% + média>0: LIVE com sizing 0.5%/trade

**Ganho esperado:** 150-200 reversal trades/mês x 55% x ~1% avg = 0.8-1.1% PnL mensal (pequeno mas escalável)

---

### Frente 2: FINGERPRINT PRÉ-PUMP (entrada INTRA, não D+1)
**Status:** Anatomia validada (1h H-1 = vol 1.26x, ret +0.84%)

**Problema:** só 41 dias 1h dados; 1 regime (BEAR_WEAK); precision/recall desconhecidos.

**Solução:** Coleta 1h contínua + pattern matching realtime
- Coleta automática: 15min/1h klines de 921 pares (infraestrutura nova)
- Pattern detector: vol > 1.2x MA5 + ret > +0.5% H-1 = WATCH flag
- Entrada 1h real: após flag, entra pullback (não no wick)
- Exit: time-stop 4h OU profit target 5-10%

**Ganho esperado:** 200+ watch-flags/mês x ~30% precision x ~8% avg (se signal real) = 0.5% PnL + muita downside se false-positive

**Timing:** Infraestrutura 1-2 semanas; backtest/refine 2-3 semanas; live pequeno 3-4 semanas

---

### Frente 3: SHORT PÓS-PUMP V2 (com stop inteligente)
**Status:** v1 reprovou (-4% wick stop); v2 win 52-58% mas média ~0

**Problema:** stop no high intraday = estopa 55% dos trades; entrada D+1 open é fraca.

**Solução:** Stop ancorado na entry, entrada por confirmação 1h
- Stop = entry * 1.01 (3% buffer apenas, não 2-5%)
- Entrada: pump D0, D+1 H-1..H-4 (espera 4h melhor, não open)
- Exit: time-stop 24h OU profit target 3-5% OU stop

**Ganho esperado:** 120 dump-events/mês x 55% x ~2-3% avg = 1.3-2% PnL

**Timing:** Backtest refinado 1 semana; live pequeno 2 semanas

---

### Frente 4: SCALP INTRADAY (spot timing agressivo)
**Status:** Layer 5 harvest colhe D+1 reversão; nada intraday

**Problema:** SYN +970%, TAIKO +167% — você quer entrar EM CIMA da onda, não depois.

**Solução:** Micro-scalp intraday no pump em curso
- Entrada: pump confirmado 1h (vol spike + close no topo)
- Exit: +5-15% (não espera +50%)
- Size: 0.5-1% por trade (risco pequeno)

**Ganho esperado:** 300+ pump-events/mês x ~40% (scalp precision) x ~6% avg = 0.7% PnL

**Timing:** Wire direto (usa scanner já existente); live 1 semana

---

## PLANO DE AÇÃO (próximas 8 semanas)

### Semana 1 (hoje):
- [ ] Backtest SHORT v2.5 (stop 1%, entrada confirmada 1h)
- [ ] Coleta 1h comece (paralelo): 921 pares, 15min/1h
- [ ] Design scalp intraday rules (entrada spike, exit 5-15%)

### Semana 2:
- [ ] Validar SHORT v2.5: win% >= 55%, média > 0? → LIVE 0.5%
- [ ] Backtest fingerprint (dados 41d 1h): precision/recall pre-pump
- [ ] Scalp intraday: 1-3 dias live small (0.5% sizing)

### Semana 3-4:
- [ ] Fingerprint live (se backtest OK): 1-2% sizing
- [ ] Reversal v2.5 live: paralelo com SHORT v2.5
- [ ] Monitor: todas 3 frentes em pequeno, acumular dados

### Semana 5-6:
- [ ] Scale UP (1% → 2%) se win% confortável (52%+)
- [ ] Refine entry rules (dados reais 1h acumulado)
- [ ] Integração LAYER5: paralelo com novos scalps

### Semana 7-8:
- [ ] Full scale: até 3-4% sizing se tudo passar
- [ ] Learning engine: integra 4 frentes + refina thresholds
- [ ] Medição 10x: contar trades únicos + validar PnL real

---

## EXPECTATIVA 10X

| Frente | Trades/mês | Precision | Avg PnL | Net |
|---|---|---|---|---|
| SHORT v2.5 | 120 | 55% | 2-3% | 1.3-2% |
| Fingerprint | 200 | 30% | 8% | 0.5% |
| Scalp intraday | 300 | 40% | 6% | 0.7% |
| LONG quality | 20 | 70% | 3% | 0.4% |
| **TOTAL** | **640** | — | — | **3-4% PnL/mês** |

**10x trades:** 160 → 640 (4x realmente operando)
**Ganho tipo:** 3-4% PnL/mês compound = 40-50%/ano (vs 0% atual)

---

## RISCO & GUARDRAILS

❌ **Não fazer:**
- Relaxar gates (gera perdas, não oportunidades)
- Aumentar sizing sem 2 semanas de live (learning curve)
- Operar SHORT/fingerprint sem fundos reais 1h (pointless)

✅ **Guardrails:**
- Tudo começa em 0.5% sizing (learn mode)
- No trade entra sem stop (tight ou mental)
- Win% < 50% → investigar, não aumentar size
- Diário: monitorar correlação entre 4 frentes (não quero 4x pior trades)

---

## PRÓXIMOS PASSOS IMEDIATOS

**Hoje (você):**
1. Ler este roadmap
2. Decidir: vai pra 10x-trades mesmo (é agressivo, risco +) ou continua quality-only?
3. Prioridade entre 4 frentes ou todas paralelo?

**Amanhã (se GO):**
1. Agent: backtest SHORT v2.5 refinado (stop 1%, entrada confirmada)
2. Agent: coleta 1h contínua infraestrutura (paralelo)
3. Agent: fingerprint pattern detector (paralelo)

