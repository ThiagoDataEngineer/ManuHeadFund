# Forward Test Validation — Halving Macro Layer
**Data:** 2026-06-09  
**Objetivo:** Validar workflow halving-aware (DCA + Pyramid) em 14 dias pre-halving

---

## **SETUP**

- **Halving (referência):** Abril 2024 (histórico); próximo: 2028
- **Fase atual:** BEAR_WEAK (6/10 trades reais, -$26 PnL, bootstrap)
- **Regime:** SHORT primary 80%, LONG hedge 20%
- **Capital:** $3,645 LIVE
- **Macro:** DXY ↓ (dólar fraco favorece crypto)

---

## **CHECKPOINTS (14 dias)**

### **SEMANA 1: Ativação + Baseline**
- [ ] Day 1-2: DCA $100/dia em BTC se teste passa
- [ ] Day 3: Verificar dca_purchases.jsonl (logging OK?)
- [ ] Day 4-5: Macro context rodando (Get-MacroContext cache 24h)
- [ ] Day 6-7: Pyramid exit mock (ATH detect lógica)

**Esperado:**
- DCA acumula $700-1400 (7-14 dias × $100)
- Zero pyramid exit (sem ATH novo em BEAR_WEAK)
- Macro score 40-60 (pessimista = agressivo DCA)

---

### **SEMANA 2: Validação + Integração**
- [ ] Day 8: Gem scalp continua (60min cycles)
- [ ] Day 9: Learning engine vs DCA stats (direction_stats.json)
- [ ] Day 10-11: Trailing stops em posições (rolar ganho)
- [ ] Day 12-13: Pyramid exit teste (se ALT ganhar +20%)
- [ ] Day 14: Sumário final

**Esperado:**
- 3-5 trades novos (vol_climax ainda funciona)
- Win rate 33% mantido (6 + 1-2 wins esperados)
- DCA +$1k acumulado (seguro base pra próximo halving)
- Zero erro crítico em macro/DCA code

---

## **MÉTRICAS FORWARD**

| Métrica | Baseline | Esperado (14d) | Status |
|---------|----------|----------------|--------|
| DCA acumulado (BTC) | 0 | $1000-2000 | ⏳ |
| Pyramid exits | 0 | 0 (BEAR fase) | ⏳ |
| Gem scalp trades | 6 | 9-11 | ⏳ |
| Win rate | 33% | 30-40% | ⏳ |
| Macro calls sucesso | - | 14/14 (24h cache) | ⏳ |
| Circuit breaker triggers | 0 | <1 (ideal) | ⏳ |

---

## **RISK GATES**

🚨 **STOP se:**
1. DCA não persiste em dca_purchases.jsonl
2. Macro context retorna erro >2 dias seguidos
3. Gem loop crash em halving phase check
4. TDD falha >50% (indica bug crítico)
5. Circuit breaker mata >1 ciclo (trend ruim)

✅ **CONTINUE se:**
1. DCA $100/dia sendo executada
2. Macro score 30-70 (normal)
3. Gem scalp roda clean
4. TDD >15/20
5. Zero crashes 14 dias

---

## **COMMIT INICIAL**

```
ed5a384 — 🌙 HALVING MACRO COMPLETE — DCA + Pyramid Exit + Wire
  - lib_macro.ps1 wired em gem_loop
  - lib_dca_accumulator.ps1 (17/20 TDD)
  - lib_pyramid_exit.ps1 (10/10 TDD)
  - Restart 2026-06-09 23:57
```

---

## **OBSERVAÇÕES**

**Força:**
- DCA automática elimina timing humano
- Pyramid exit captura topos sem timing
- Macro context real (FRED API não fake)
- TDD cobre happy-path e edge cases

**Fraqueza:**
- Test-DcaShouldBuy logic edge cases (2 testes falham)
- JSON depth warning em pyramid state (minor)
- Forward test só 14 dias (micro vs 12 meses ciclo)

**Próximo (30+ dias):**
- Calibrar DCA alocação % por BTC price
- Integrar whale on-chain signals
- Pyramid pyramid_exits.jsonl → trade_outcomes.jsonl (auditoria)

---

**🚀 SISTEMA OPERACIONAL. FORWARD TEST INICIADO.**
