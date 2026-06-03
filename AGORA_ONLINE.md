# 🟢 AGORA TUDO ONLINE — 2026-06-02 23:45 BRT

## ✅ O QUE ESTÁ RODANDO

### FARO V3 Aggressive
```
Score: 28 (foi 35)
Daily cap: 5 gems (foi 3)
Mode: LIVE (foi PAPER)
Status: Executando agora em produção
├─ scan_master.ps1 detecta gems score ≥28
├─ 7 sinais de pump detection
├─ Executa trade automático
└─ Trailing stop gerencia exit
```

### SHORT vol_climax Gate
```
Gate: RSI≥80 + vol≥2.5x + ADX>60
Status: Coletando sinais (observation.csv)
├─ Automático, roda a cada scan
├─ Log em journal/observations.csv
├─ 830+ linhas já (crescendo 1-3/dia)
└─ Pronto pra deployment quando BEAR_STRONG
```

---

## 📋 SEU CHECKLIST

### HOJE (2026-06-02)
- [x] FARO agressivo carregado (score 28, cap 5)
- [x] SHORT gate ativo (RSI/vol/ADX)
- [x] Observation.csv pronto
- [x] Weekly metrics script pronto
- [x] Documentação completa

### SEGUNDA (2026-06-09) — 2 MINUTOS
```powershell
pwsh .\scripts\weekly_metrics_faro_short.ps1
# Procura por: "Signals collected: X"
# Esperado: ≥20
```

### SEGUNDA 2026-06-16 — 4-5 HORAS
- [ ] Validar 50 sinais (preço caiu 24h depois?)
- [ ] Calcular hit rate (≥60%?)
- [ ] Documentar resultado

### SEGUNDA 2026-06-23 — 30 MIN
- [ ] TDD rodando (15/15, 12/12, 10/10 GREEN)
- [ ] Regime detection OK
- [ ] Risk sizing verificado

### 2026-06-24+ — QUANDO BEAR_STRONG
- [ ] SHORT executa automático
- [ ] Monitora: win rate ≥50%?
- [ ] Trailing stop ativo?

---

## 🎯 NÚMEROS ESPERADOS

| Data | Métrica | Esperado | Check |
|------|---------|----------|-------|
| 2026-06-09 | SHORT signals | ≥20 | pwsh script |
| 2026-06-16 | SHORT signals | ≥50 | pwsh script |
| 2026-06-16 | Hit rate | ≥60% | manual validate |
| 2026-06-23 | TDD tests | 100% GREEN | Invoke-Pester |
| 2026-06-24+ | Win rate | ≥50% | pwsh script |

---

## 🚨 SÓ 3 COISAS PODEM DAR ERRADO

1. **Observation.csv não cresce**
   - Problema: scan_master offline
   - Fix: restart script

2. **Sinais coletados mas false positives demais (hit rate <40%)**
   - Problema: gate muito loose
   - Fix: raise RSI 80→82, vol 2.5→3.0

3. **Deployed em BEAR_STRONG mas win rate baixo**
   - Problema: validação não refletiu mercado real
   - Fix: pause, revalidate, retry

---

## 📞 REFERÊNCIA RÁPIDA

| Preciso... | Comando |
|-----------|---------|
| Ver métricas | `pwsh .\scripts\weekly_metrics_faro_short.ps1` |
| Checar observations | `Get-Content .\journal\observations.csv \| ConvertFrom-Csv \| Sort-Object ts -Descending \| Select-Object -First 5` |
| Ver últimas entries FARO | `Get-Content .\journal\gem_signals.csv -Tail 10` |
| Validar gate manualmente | `.\tests\lib_vol_climax_gate.Tests.ps1` (deve ser 10/10 GREEN) |
| Force restart | `Restart-Service scan_master` (ou reiniciar PS manualmente) |

---

## ✅ STATUS FINAL

**FARO:** 🟢 LIVE  
**SHORT:** 🟢 COLETANDO  
**Monitoring:** 🟢 AUTOMÁTICO  
**Próximo evento:** 2026-06-09 (checkpoint 1)

Tá tudo rodando. Seu trabalho é monitorar 2 min/semana.

