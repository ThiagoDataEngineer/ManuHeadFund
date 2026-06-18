# EVOLUÇÃO SHORT VOL_CLIMAX — SUMÁRIO SIMPLES

## 🎯 O caminho até BEAR_STRONG deployment

```
HOJE (2026-06-02)
  └─ Observation ativa
     "quando vol_climax gate passa → log em observations.csv"
     Sem execução, sem trade real
     

SEMANA 1 (por 2026-06-09)
  ├─ Esperado: 20-30 sinais coletados
  ├─ Ação: conferir 1-2 min/dia
  │        pwsh .\scripts\weekly_metrics_faro_short.ps1
  └─ Resultado: sinais fluindo? SIM → continua


SEMANA 2 (por 2026-06-16)
  ├─ Esperado: 40-50+ sinais total
  ├─ Ação: ANÁLISE
  │        Para cada sinal, checar 24h depois:
  │        "Preço caiu 1%+?" → TRUE_POS
  │        "Preço subiu?" → FALSE_POS
  └─ Resultado: ≥60% hit rate? SIM → deploy ready


SEMANA 3 (por 2026-06-23)
  ├─ Esperado: testes prontos (TDD 100%)
  ├─ Ação: testar SHORT entry/exit logic
  │        confirmar regime BEAR_STRONG detection
  │        validar risk sizing ($30/trade)
  └─ Resultado: tudo verde? SIM → deployment ready


SEMANA 4+ (2026-06-24 quando BEAR_STRONG)
  ├─ Trigger: Get-HalvingPhase retorna "BEAR_STRONG"
  ├─ Ação: scan_master.ps1 começa execução SHORT automática
  │        vol_climax signal passa → SHORT real
  │        stop loss automático protege
  │        trailing stop gerencia exit
  └─ Resultado: win rate ≥50%? SIM → keep running
```

---

## 🔑 3 COISAS QUE PRECISAM ACONTECER

### 1️⃣ COLETA (semanas 1-2)
```
observations.csv cresce dia a dia
├─ 1-3 sinais/dia é normal
├─ 0 sinais 3+ dias = problema (investigar)
└─ Meta: 50+ sinais by 2026-06-16
```

### 2️⃣ VALIDAÇÃO (semana 3)
```
Depois de coleta, verificar: sinais que funcionam?
├─ Pega cada um dos 50+ sinais
├─ Checa: preço caiu 24h depois?
│   SIM = TRUE_POS ✅ (conta pra hit rate)
│   NÃO = FALSE_POS ❌ (desconta)
└─ Meta: ≥60% hit rate (38+/50 sinais acertaram)
```

### 3️⃣ EXECUÇÃO (a partir 2026-06-24)
```
Quando BEAR_STRONG ativo + vol_climax signal:
├─ Abre SHORT automático
├─ Entry: preço atual
├─ Stop loss: 1% acima (segurança)
├─ Target: 3.3% abaixo (1:3 mínimo)
└─ Exit: quando atingir RSI<30 OU target
```

---

## 📋 CHECKLIST SEMANAL (2 MINUTOS)

**SEGUNDA de manhã:**
```
☐ run: pwsh .\scripts\weekly_metrics_faro_short.ps1
  → Procura por: "Signals collected: X"
  
☐ Esperado para essa semana?
  • Week 1 (6/9): ≥20
  • Week 2 (6/16): ≥40
  • Week 3 (6/23): ≥50+
  
☐ Se número baixo:
  • Check: scan_master.ps1 running?
  • Check: mercado com volatilidade (RSI 80+)?
```

---

## 🚨 SINAIS DE ALERTA

| Problema | Causa | Fix |
|----------|-------|-----|
| 0 sinais 3 dias | Gate muito strict | Lower RSI: 80→78 |
| Muitos sinais, mas preço sobe (false pos) | Gate muito loose | Raise RSI: 80→82, vol 2.5→3.0 |
| Observation.csv não cresce | scan_master offline | Restart script |
| BEAR_STRONG detectado mas SHORTs não executam | Regime gate broken | Check: Get-HalvingPhase return value |

---

## 💡 PERGUNTAS COMUNS

**P: Preciso fazer algo manual na fase 1?**  
R: Não. Collection é automática. Só rodar: `pwsh .\scripts\weekly_metrics_faro_short.ps1` 1x/semana.

**P: E na fase 2, validação?**  
R: Manual. Ler 50 sinais, checar cada um (5 min/signal × 50 = 4h total).  
Ou automático se tiver dados históricos de price (mais complexo).

**P: Posso testar antes de BEAR_STRONG chegar?**  
R: Sim, paper mode ou override: `$env:OVERRIDE_REGIME="BEAR_STRONG"` (test only).

**P: E se BEAR_STRONG nunca chegar?**  
R: Fica em observation. Quando mudar pra BEAR_STRONG em qualquer ponto, execution auto-ativa.

**P: Win rate ruim (30%) na primeira semana de BEAR_STRONG?**  
R: Pause: `$env:SHORT_VOL_CLIMAX_LIVE = 0`  
Voltar observation, ajustar gate, revalidar.

---

## 🎬 PRÓXIMO PASSO (TODAY)

✅ **Feito:**
- Observation ativa
- weekly_metrics script pronto
- Documentação completa

⏰ **Próxima semana (2026-06-09):**
- Check sinais crescendo (≥20)
- Se SIM → continua para validação
- Se NÃO → investigate gate

---

**Status:** Automatic, just monitor  
**Effort:** 2 min/semana  
**Outcome:** SHORT vol_climax deployment ready by 2026-06-24

