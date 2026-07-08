# Telegram Message Volume Audit — Reduzir Spam

**Data:** 2026-07-08  
**Status:** Audit completo, recomendações prontas

---

## 📊 Análise Atual

### Fonte de Mensagens (Top 5)

| Arquivo | Count | Categoria | Severidade |
|---------|-------|-----------|-----------|
| **gem_executor.ps1** | 22 | GEM bloqueios + execução | 🔴 CRÍTICO |
| lib_telegram_commands.ps1 | 18 | Comandos Telegram | 🟢 OK |
| lib_trailing_adaptive.ps1 | 14 | Trailing stops | 🟡 Reduzir |
| lib_telegram.ps1 | 7 | Core lib | 🟢 OK |
| lib_telegram_alerts_simple.ps1 | 6 | Alerts simples | 🟡 Reduzir |

**Total estimado:** ~100+ mensagens por ciclo de scan (15-30 min) = **3-8 msg/hora = 72-192 msg/dia**

---

## 🔴 PROBLEMA: gem_executor.ps1 (22 sends)

### Mensagens DESNECESSÁRIAS que podem ser **silenciadas**:

```
1. ✂️ Line 362: CIRCUIT BREAKER
   Status: 🟢 IMPORTANTE (1x/dia máximo)
   Ação: MANTER, mas consolidar com daily summary

2. ✂️ Line 548: MARKET UNSAFE (CoinEx alert)
   Status: 🔴 REDUNDANTE
   Problema: Já logado em gem_recent_decisions.json
   Ação: REMOVER - só log, sem TG

3. ✂️ Line 594: CASCADE BLOCK (leverage limit)
   Status: 🟡 Informativo demais
   Problema: Roda a cada tentativa de Add Position (3-5x/hora)
   Ação: MANTER mas consolidar em heartbeat semanal

4. ✂️ Line 603: CASCADE BLOCK (add position limit)
   Status: 🟡 Informativo demais
   Problema: Mensagem redundante com line 594
   Ação: REMOVER - é mesmo cenário

5. ✂️ Line 624: GEM SAFETY BLOCK
   Status: 🟡 Muito frequente
   Problema: Todo GEM bloqueado por safety = 10-15 msg/ciclo
   Ação: REMOVER daily, enviar weekly consolidado

6. ✂️ Line 633: GEM SAFETY (confirmation required)
   Status: 🟡 Informativo
   Ação: REMOVER - é warning, não crítico

7. ✂️ Line 659: EXPOSURE CAP BLOCK
   Status: 🟡 Muito frequente (todos os ALTs em bear)
   Problema: 5+ msg/ciclo quando cap ativo
   Ação: REMOVER daily, weekly summary

8. ✂️ Line 778: CENARIO BLOCK (BTC scenario)
   Status: 🟡 Muito frequente
   Problema: Todos os LONG bloqueados em BEAR = 20+ msg/ciclo
   Ação: REMOVER daily, mensal summary

9. ✂️ Line 842: Tori unavailable
   Status: 🟢 CRÍTICO (1x se erro)
   Ação: MANTER (indica problema de carregamento)

10. ✂️ Line 863: Tori error
    Status: 🟢 CRÍTICO
    Ação: MANTER (indica crash)

11. ✂️ Line 929: CONVICTION OVERRIDE
    Status: 🟡 Informativo
    Ação: REMOVER - é sucess case, não necessita alerta

12. ✂️ Line 941: Tori skip (bloqueio)
    Status: 🟡 Muito frequente (50%+ das gems)
    Problema: 30-50 msg/ciclo em bear weak
    Ação: REMOVER daily, daily tally

13. ✂️ Line 1231: GEM BLOQUEADO (consolidado)
    Status: 🟡 REDUNDANTE
    Problema: Repete mensagens anteriores (cascade, safety, cenario)
    Ação: REMOVER - consolidar ANTES em 1x summary

14. ✂️ Line 1251: TP validation failed
    Status: 🟢 CRÍTICO (bug na API)
    Ação: MANTER (raro, indica problema)

15. ✅ Line 1260: EXECUTANDO GEM
    Status: 🟢 IMPORTANTE (entrada real)
    Ação: MANTER + BOLD (prioridade alta)

16. ✂️ Line 1288: Multi-TF misalignment
    Status: 🟡 Informativo
    Problema: Roda se multi-TF check ativado
    Ação: REMOVER daily

17. ✂️ Line 1382: PROTEÇÃO OK (SL/TP set)
    Status: 🟡 Informativo
    Ação: REMOVER - é success case

18. ✂️ Line 1385: SL/TP FALHOU (CRÍTICO)
    Status: 🟢 CRÍTICO (coloca ordem SEM proteção!)
    Ação: MANTER + ALERTA (prioridade máxima)

19. ✂️ Line 1389: SL/TP NA LIB NÃO CARREGOU
    Status: 🟢 CRÍTICO (sistema quebrado)
    Ação: MANTER (indica crash)

20. ✅ Line 1416: Trade executed
    Status: 🟢 IMPORTANTE (recap)
    Ação: MANTER

21. ✅ Line 1437: Trade opened highlight
    Status: 🟢 IMPORTANTE (visual confirmation)
    Ação: MANTER

22. ✂️ Line 1450: Auto market analysis
    Status: 🟡 Informativo demais
    Ação: REMOVER (pedantic, não necessário)
```

---

## 🎯 Estratégia: Consolidação Diária

### Proposta 1: **Consolidate Blockers into Daily Summary**

Ao invés de:
```
[15:02] GEM bloqueado ADAUSDT: exposure cap
[15:03] GEM bloqueado BONKUSDT: exposure cap
[15:04] GEM bloqueado DOGEUSDT: cenario
[15:05] GEM bloqueado PEPEUSDT: safety guards
...
```

Enviar **1x por ciclo (30min)**:
```
📊 **SCAN SUMMARY** (15:00-15:30)
├ Bloqueados: 47 gems
│ ├ Exposure cap: 15
│ ├ Safety guards: 12
│ ├ Cenario (bear): 14
│ ├ Tori skip: 6
├ Executados: 2 (BTCUSDT, ETHUSDT)
├ Capital utilizado: $52 / $3000
└ Próxima varredura: 15:30
```

### Proposta 2: **Three-Tier Alert System**

**Tier 1 — INSTANT (crítico, ~2-3 msg/dia)**
- ✅ Trade executado (entrada real)
- ✅ SL/TP falhou (risco de sem proteção!)
- ✅ Lib não carregou (sistema quebrado)
- ✅ Circuit breaker ativado (stop loss diário)

**Tier 2 — HOURLY DIGEST (operacional, 1x/hora)**
- 📊 Consolidado: bloqueios por tipo
- 📊 Executados: count + capital
- 📊 Taxa de sucesso: hits/attempts

**Tier 3 — DAILY REPORT (informativo, 1x/dia 20:00)**
- 📈 Win rate + PnL
- 📈 Maiores bloqueios (top 10 reasons)
- 📈 Capital utilizado histórico

---

## ✂️ Cortes Recomendados

### Remover completamente (16 sends):

1. `Line 548` — MARKET UNSAFE (já em log)
2. `Line 603` — CASCADE BLOCK add position (redundante)
3. `Line 624` — GEM SAFETY BLOCK (muita frequência)
4. `Line 633` — GEM SAFETY requires confirmation (warning)
5. `Line 659` — EXPOSURE CAP BLOCK (muito frequente)
6. `Line 778` — CENARIO BLOCK (20+ msg/ciclo em BEAR)
7. `Line 929` — CONVICTION OVERRIDE (success case)
8. `Line 941` — Tori skip (30-50 msg/ciclo)
9. `Line 1231` — GEM BLOQUEADO consolidado (redundante)
10. `Line 1288` — Multi-TF misalignment (informativo)
11. `Line 1382` — PROTEÇÃO OK (success case)
12. `Line 1450` — Auto analysis (pedantic)

### Consolidar (4 sends → 1 daily digest):

- Bloqueios por categoria
- Execuções count
- Capital status

### Manter críticos (6 sends):

- ✅ Trade executado
- ✅ SL/TP falhou
- ✅ Lib não carregou
- ✅ Circuit breaker
- ✅ Tori critical error
- ✅ TP validation failed

---

## 📉 Impacto Estimado

**Antes:** 100+ msg/dia (caótico)  
**Depois:** 20-30 msg/dia (3x redução)
- Críticos: 2-3 msg/dia (imediato)
- Hourly digest: 24 msg (1 a cada hora)
- Daily report: 1 msg (20:00)

---

## 📋 Implementação

**Arquivo a criar:**
- `lib_telegram_consolidator.ps1` (já existe? verificar)
  - `Write-TgScanSummary()` — hourly digest
  - `Write-TgDailyReport()` — daily consolidado

**Arquivos a modificar:**
- `gem_executor.ps1` — remover 16 sends, adicionar consolidador
- `scan_master.ps1` — chamar `Write-TgScanSummary()` ao final

**Estimativa:** 2-3 horas de trabalho

---

## 💡 Quick Win (5 min)

Remover linhas mais óbvias:
```powershell
# Line 548 - MARKET UNSAFE
- try { Send-TelegramAlert -Message "*GEM BLOQUEADO* -- $mkt..." | Out-Null } catch {}
+ # Já logado em gem_recent_decisions.json

# Line 633 - GEM SAFETY confirmation
- try { Send-TelegramAlert -Message "GEM aviso..." | Out-Null } catch {}
+ # Warning apenas, não crítico

# Line 1382 - PROTEÇÃO OK
- try { Send-TelegramAlert -Message "✅ PROTEÇÃO ATIVA..." | Out-Null } catch {}
+ # Success case, não necessário
```

Reduziria de 22 → 14 sends em gem_executor sozinho.

---

**Status Recomendado:** Implementar Tier 2 (Hourly Digest) + remover 16 sends menos críticos = **3x menos spam**

