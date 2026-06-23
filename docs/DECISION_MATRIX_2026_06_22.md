# 🎯 DECISÃO FINAL — SPOT PORTFOLIO
**Data**: 2026-06-22 23:30 BRT | **Análise por**: Technical + Macro | **Próximo review**: 2026-06-23

---

## RECOMENDAÇÕES DIRETAS

### **UBUSDT** — 710.91 units | $67.41 | -16%
```
┌─────────────────────────────────────────┐
│  AÇÃO: SPLIT 50/50 (HOJE)               │
│  ───────────────────────────────────────│
│  ✅ VENDA 50%: 355 units                │
│     └─ Realiza -$5.40 loss              │
│     └─ Libera $33.70 capital            │
│                                         │
│  ✅ TRAILING 50%: 355 units             │
│     └─ Stop loss 1% abaixo entry        │
│     └─ Max loss: -$5                    │
│     └─ Upside: unlimited                │
│                                         │
│  ⏱️  TIMING: Agora (antes de pump/dump) │
│  📊 RISCO: Reduzido para -50%           │
│  📈 UPSIDE: 100% mantido                │
└─────────────────────────────────────────┘
```

---

### **PAXGUSDT** — 0.257 units | $1,066.24 | -14%
```
┌─────────────────────────────────────────┐
│  AÇÃO: DECISÃO MACRO OURO               │
│  ───────────────────────────────────────│
│  🔍 PASSO 1: Verificar ouro em $2,300   │
│     IF ouro > $2,300 (suporte mantém)   │
│        → SPLIT 50/50 (acumulação)       │
│        → Upside 15-25% esperado         │
│                                         │
│     IF ouro < $2,300 (suporte quebrou)  │
│        → VENDA 100% (distribuição)      │
│        → Mais queda esperada             │
│                                         │
│  💡 ALTERNATIVA: Ambos uncertain        │
│     → SPLIT 50/50 (hedge)               │
│        Realiza -$85, trailing outra     │
│                                         │
│  ⏱️  TIMING: HOJE após checagem ouro    │
│  🎲 RISCO: IF distribuição pode cair 20%│
│  💪 UPSIDE: IF acumulação sobe 15%      │
└─────────────────────────────────────────┘
```

---

### **TNSR** — 1,499.66 units | $58.93 | -13%
```
┌─────────────────────────────────────────┐
│  AÇÃO: VERIFICAR + ADICIONAR SL         │
│  ───────────────────────────────────────│
│  ✅ CHECK: Está em trailing_positions?  │
│     YES: → Deixar trailing trabalhar    │
│     NO:  → Adicionar SL 1% + TP 5%      │
│                                         │
│  📝 NOTA: TNSR depende de SOL recovery  │
│     SOL breakout >$145 = pump TNSR      │
│                                         │
│  ⏱️  TIMING: TODAY                       │
│  🎯 TARGET: SOL acima $145 (pump 20%)   │
│  🛑 STOP: 1% abaixo entry (perda max)   │
└─────────────────────────────────────────┘
```

---

### **XRPUSDT** — 22.33 units | $25.13 | -19%
```
┌─────────────────────────────────────────┐
│  AÇÃO: VERIFICAR + ADICIONAR SL         │
│  ───────────────────────────────────────│
│  ✅ CHECK: Está em trailing_positions?  │
│     YES: → Deixar trailing trabalhar    │
│     NO:  → Adicionar SL 2% + TP 8%      │
│            (higher volatility)          │
│                                         │
│  🎯 CATALYST: SEC lawsuit XRP           │
│     Resolução = pump 20-30%             │
│                                         │
│  ⏱️  TIMING: TODAY                       │
│  🎲 RISCO: Lawsuit could go either way  │
│  📈 UPSIDE: 30% potential se positive   │
└─────────────────────────────────────────┘
```

---

## EXECUÇÃO

### **Cenário A: EXECUTAR AGORA (Recomendado)**
```bash
# DRY RUN primeiro
pwsh -File scripts/EXECUTE_SPOT_FIXES.ps1 -ExecuteUB -ExecutePAXG -ExecuteTNSR -ExecuteXRP -DryRun:$true

# Revisar e executar
pwsh -File scripts/EXECUTE_SPOT_FIXES.ps1 -ExecuteUB -ExecutePAXG -ExecuteTNSR -ExecuteXRP -DryRun:$false
```

**Resultado esperado**:
- UBUSDT: -$5.40 realizado, $33.70 libero, $33.70 trailing
- PAXGUSDT: -$85 realizado (50%), $533 trailing (ou venda completa se ouro < $2,300)
- TNSR/XRP: Trailing ativo com SL/TP
- **Capital liberado**: ~$600 (para v7 arbitrage)

---

### **Cenário B: CONSERVADOR (Wait & See)**
```
Espera 3-5 dias de confimação antes de vender:
- UBUSDT: Aguarda pump/dump claro, vende na decisão
- PAXGUSDT: Aguarda confirmação suporte ouro $2,300
- TNSR/XRP: Ativar trailing HOJE, leave running

RISK: Pode perder 10% adicional em wait
UPSIDE: 100% confirmação da direção
```

---

## POR QUÊ "SPLIT" E NÃO "VENDA TUDO" OU "HOLD TUDO"?

| Decisão | Melhor se | Risco |
|---------|-----------|-------|
| **VENDA TUDO** | Você 100% certo downtrend | -FOMO se pump 50% amanhã |
| **HOLD TUDO** | Você 100% certo uptrend | -Amargar se cai 30% |
| **SPLIT 50/50** | Você incerto (realista) | ✅ Reduz ambos riscos |

**Matemática SPLIT:**
- Vende 50% → realiza -50% da loss
- Hold 50% → mantém 100% do upside
- **Se cai 50%**: Loss total = -75% (vs -100% hold)
- **Se sobe 50%**: Gain total = +50% (vs +100% hold, mas com 75% de ganho garantido)

→ **Ratio esperado favorável** quando incerteza > 40%

---

## PRÓXIMOS PASSOS

### Hoje (2026-06-22):
- [ ] Executar SPLIT UBUSDT (`-ExecuteUB`)
- [ ] Decidir PAXGUSDT baseado em ouro (`-ExecutePAXG`)
- [ ] Ativar SL/Trailing em TNSR/XRP (`-ExecuteTNSR -ExecuteXRP`)
- [ ] Commit: `feat: SPOT portfolio split + trailing activation`

### Amanhã (2026-06-23):
- [ ] Monitorar primeiras execuções (preço, fill rate)
- [ ] Iniciar v7 Arbitrage prototype (5min cycle scanner)

### Week (2026-06-24 onwards):
- [ ] Daily SPOT audit (trailing harvest, new SL hits)
- [ ] Arbitrage live testing ($2/cycle goal)
- [ ] Consolidar v7 versão estável

---

## DISCLAIMER

**Esta análise é technical + macro, NÃO financial advice.**
- Você é responsável pelas decisões
- Test em pequeno volume primeiro
- Set stops religiosamente (Regra de Ouro #1)

✅ **Ready to execute?** → Use script com `-DryRun:$false`
❌ **Not sure?** → Scenario B (wait 3-5 days, ativar trailing HOJE)
