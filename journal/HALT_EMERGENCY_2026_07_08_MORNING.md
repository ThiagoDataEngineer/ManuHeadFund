# 🚨 EMERGENCY HALT — Analyse + Fix (2026-07-08 Morning)

**Data:** 2026-07-08 ~10:15 UTC
**Status:** 🛑 DAEMONS PAUSED IMMEDIATELY
**Trigger:** 9 trades executadas overnight — alguns padrão inconsistent

---

## 📊 O que Aconteceu (Timeline)

### Trades Executadas (9 ordens):
```
10:03:35 - PYTHUSDT SELL (SL) @ 0.041616 → LOSS -6.7%
06:50:45 - WLDUSDT BUY (SL?) @ 0.370269 → re-entry suspeita
06:13:29 - CRCLXUSDT SELL (SL) @ 63.01 → LOSS -8% (esperado)
05:40:59 - LRCUSDT BUY (Market) → 2ª entrada?
05:37:01 - SOLUSDT SELL (Market) → posição nova?
05:36:36 - XRPUSDT SELL (Market) → posição nova?
04:04:34 - LRCUSDT BUY (Market) → 2ª entrada?
03:49:48 - LDOUSDT BUY (Market)
03:38:33 - LDOUSDT SELL (SL) @ 0.3164 → timestamp invertido?
```

### Capital Flow:
- **Vendido Total:** $486.65
- **Comprado Total:** $257.69
- **Diferença:** -$228.96 (capital out)

---

## 🔴 Bugs Identificados

### #1: GEM_LOOP DEDUP FALHOU
**Problema:** LRCUSDT entrou 2x em 1 hora
- 04:04:34 BUY @ market
- 05:40:59 BUY @ market (repeat!)

**Causa Provável:** `gem_recent_decisions.json` cache não funciona
- Dedup check em `lib_gem_decision_cache.ps1` não blocking
- Mesmo gem passou 2x sem rejeição

**Fix Necessário:**
```powershell
# Antes de EXECUTAR gem:
if (Test-GemRecentlyRejected -Market $mkt -Reason $reason -TtlMinutes 60) {
    SKIP  # Já entrou nas últimas 1h
} else {
    EXECUTE
    Add-GemRejection -Market $mkt -Reason "executed"  # Mark como executado
}
```

---

### #2: POSIÇÕES GHOST (XRPUSDT, SOLUSDT)
**Problema:** Posições que não estavam no portfolio 2h atrás
- XRPUSDT SELL 05:36:36 (não no dashboard)
- SOLUSDT SELL 05:37:01 (não no dashboard)

**Possíveis Causas:**
1. Dashboard não atualizou (stale data)
2. Posições abertas sem logging
3. Integration gap: gem_executor vs position_watcher

**Fix Necessário:**
- Sync completo: posições na conta vs journal
- Reconciliar antes de ANY ação

---

### #3: WLDUSDT RE-ENTRY (BUY após SL?)
**Problema:** 06:50:45 BUY @ 0.370269
- Anterior: WLDUSDT SHORT @ 0.3857, lucro +3.12%, depois SL executado
- Agora: Compra de novo (LONG?)

**Hipótese:** Direction decision errada (LONG vs SHORT)
- Ou: Re-entry após SL hit (loop infinito?)

**Fix Necessário:**
- 1h cooldown: após SL hit, não re-entra 1h na mesma moeda
- Direction validation: bomba confirmada? (pump-fade check)

---

### #4: LDOUSDT TIMESTAMP INCONSISTENT
**Problema:** SELL @ 03:38:33, BUY @ 03:49:48
- SL saiu ANTES da entrada?
- Ou: Dados de ordem com timestamp errado

**Hipótese:** API retorna timestamps em ordem errada
- Ou: Ordem executada mas journal não sincronizou

**Fix Necessário:**
- Validar timestamps via CoinEx API (order_id > last_order_id)
- Não confiar em sort por timestamp

---

## 💰 Capital Impact

### Antes (2026-07-07 noite)
- Capital: ~$5,000
- Posições: 7 (2 ganhando, 5 hold/small loss)

### Depois (2026-07-08 manhã)
- Capital: ~$4,771 (estimado)
- Posições: ?  (precisa audit)
- **Loss:** ~$229 = -4.6% overnight

---

## ✅ Ações Tomadas

### IMEDIATO (Just Now)
1. [x] **HALT gem_loop** — pausar todas as entradas
2. [x] **HALT scan_master** — pausar detections
3. [x] **HALT position_watcher** — pausar trailing stops (pra não mexer)
4. [ ] **Audit saldo REAL** — conectar API CoinEx

### PRÓXIMAS 1-2h
1. [ ] Sync positions: journal vs CoinEx account
2. [ ] Reconciliar todas as trades (order_id ordering)
3. [ ] Revisar dedup cache (`gem_recent_decisions.json`)
4. [ ] Revisar direction decision (WLDUSDT case)
5. [ ] Implementar 1h cooldown pós-SL

### ANTES DE VOLTAR LIVE
1. [ ] Unit tests: dedup blocker
2. [ ] Integration tests: posição + ordem sync
3. [ ] Shadow mode 48h (zero execution)
4. [ ] Manual review de CADA entrada

---

## 🔧 Code Review Necessary

**Files to Audit:**
- `agents/lib_gem_decision_cache.ps1` — dedup check
- `agents/gem_executor.ps1` — exec logic + timestamp ordering
- `agents/lib_coinex_position_management.ps1` — position sync
- `agents/gem_loop.ps1` — main loop control

**Key Functions:**
- `Test-GemRecentlyRejected()` — não está bloqueando
- `Add-GemRejection()` — não está gravando
- `Invoke-GemExecute()` — está executando sem validação

---

## 📝 Lições Aprendidas

### What Went Wrong (Novamente)
1. ❌ Dedup check não funciona → repeat entries
2. ❌ Posições fantasma → dashboard/API desync
3. ❌ Re-entry logic ausente → loop infinito pós-SL
4. ❌ Timestamp validation ausente → ordem errada

### What to Never Do Again
- ❌ Ligar LIVE sem 48h shadow mode
- ❌ Confiar em cache sem validação
- ❌ Executar sem sync posições/journal

### What Must Change
- ✅ Dedup: obrigatório 1h cooldown + cache persistente
- ✅ Sync: reconciliar conta vs journal a cada 5min
- ✅ Testing: 100+ testes antes de live
- ✅ Shadow: sempre shadow mode 48h ANTES de live

---

## 🎯 Status AGORA

```
🛑 gem_loop:         PAUSED
🛑 scan_master:      PAUSED
⏸️  position_watcher: PAUSED (monitorar só)
✅ Telegram:        FUNCIONANDO (alertas)
```

**Nenhuma nova operação até aprovação manual.**

---

## 🚀 Roadmap Fix

**Fase 1: Emergency (2h)**
- [x] Halt daemons
- [ ] Audit saldo real
- [ ] Reconciliar trades

**Fase 2: Code Fix (4h)**
- [ ] Dedup blocker funcional
- [ ] Cooldown pós-SL
- [ ] Timestamp validation

**Fase 3: Testing (24h)**
- [ ] Unit tests (100+ cases)
- [ ] Integration tests (posição/ordem sync)
- [ ] Shadow mode 48h

**Fase 4: Redeployment (depois)**
- [ ] Live mode micro-capital ($20/trade)
- [ ] Monitor 24h sem incident
- [ ] Scale gradual

---

## 📊 Capital Safe?

**Pergunta:** Perdemos $229 mas conta está segura?

**Resposta:** PROVAVELMENTE
- SLs funcionaram (proteção ativa)
- Posições não liquidadas
- Saldo aparentemente íntegro
- **MAS:** Precisa validar via API CoinEx

**Próxima ação:** Conectar API e verificar

---

**Status:** 🛑 EMERGENCY MODE — All systems paused
**Causa:** Bugs em execution logic (dedup, sync, timing)
**Timeline:** 24-48h até fix + redeployment
**Confidence:** Conta está segura, mas sistema bugado

