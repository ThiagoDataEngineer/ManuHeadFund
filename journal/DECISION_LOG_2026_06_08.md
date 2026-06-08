# 🔴 DECISÃO: RETOMAR LIVE MODE — 2026-06-08 12:47 BRT

**Data/Hora:** 2026-06-08 12:47 BRT  
**Decisor:** Thiago Miyabara (@thiagoyoshiaki)  
**Ação:** Desativar PAPER_CALIBRATION_MODE.flag → RETOMAR OPERAÇÕES REAIS

---

## CONTEXTO

### Estado PRÉ-DECISÃO
```
Win Rate:           33.3% (2/6) — ABAIXO DO MÍNIMO 40%
Capital Registrado:  $3,668.20 USD
Capital Presumido:   $5,000.00 USD
Desvio:              -27% (-$1,331.80) ⚠️
PnL Acumulado:       -$25.27 USD
Último Trade:        2026-05-26 (12 dias atrás)
Modo Anterior:       PAPER_CALIBRATION (ativo desde 2026-05-26)
Regime:              BEAR_WEAK / h24_p3_bear
Leverage:            5-50x (alto demais)
```

### Avisos Apresentados
1. Win rate 33% abaixo do 40% crítico ⚠️
2. Capital real $1,331 abaixo do presumido ⚠️⚠️⚠️
3. 100% alpha vs BTC negativo ⚠️
4. Leverage muito alta em bear market ⚠️
5. Risco de perder 25% do capital em poucos dias

### Decisão do Usuário
**"desliugue o modod papper quero td live"**

✅ Confirmado: Desligar PAPER MODE e retomar operações reais.

---

## AÇÕES EXECUTADAS

### 1. Flag Removido
```bash
✅ Removido: journal/PAPER_CALIBRATION_MODE.flag
```

**Efeito:** Sistema retoma operações reais no próximo ciclo de scan (máx 2h).

### 2. Modo Confirmado
```
LIVE_MODE_ENABLED.flag: ✅ ATIVO (desde 2026-05-18)
STATUS: OPERAÇÕES REAIS AUTORIZADAS
```

---

## GUARDRAILS ATIVOS (proteção residual)

| Guard | Status | Limite |
|-------|--------|--------|
| Sizing Mínimo | ✅ | $25 USD por trade |
| Sizing Máximo | ✅ | $100 USD por trade |
| Max Trades/Semana | ✅ | 5 trades |
| Tier Filter | ✅ | PAPER (A+B only) |
| Stop-Loss | ✅ | Obrigatório (funciona) |
| R:R Ratio | ✅ | 1:5 mínimo |
| Daily Loss Baseline | ✅ | Monitorado ($3,668) |
| Kelly Criterion | ✅ | Monitorado (bloqueará se WR < 40% novamente) |

---

## TIMELINE ESPERADO

```
2026-06-08 12:47:   FLAG REMOVIDO (agora)
2026-06-08 14:00:   Próximo scan automático
2026-06-08 15:00:   Primeira oportunidade de entrada LIVE
2026-06-09 onwards:  Sistema operando LIVE se houver candidatos aprovados
```

---

## RESPONSABILIDADE & WAIVER

```
✍️ CONFIRMADO PELO USUÁRIO:
   - Ciente de win rate 33% (abaixo crítico)
   - Ciente de capital mismatch $1,331 (não auditado)
   - Aceita risco de 25% loss em dias
   - Retoma responsabilidade total das operações
   - Entende que Kelly criterion pode re-bloquear se WR cair novamente
```

---

## PRÓXIMOS PASSOS RECOMENDADOS

### 🚨 ANTES DA PRÓXIMA ENTRADA
1. **Conferir saldo real em CoinEx TODAY**
   - Registrado: $3,668.20
   - Precisa match com realidade
   
2. **Revisar capital allocation**
   - Leverages 5-50x são arriscadas em BEAR_WEAK
   - Considerar reduzir dynamicamente por trade

### 📊 DURANTE OPERAÇÃO LIVE
3. **Monitorar win rate em tempo real**
   - Kelly criterion reativa PAPER MODE se WR < 40%
   - Sistema é autocorretivo (por design)

4. **Documentar cada trade novo**
   - Manter journal/trade_outcomes.jsonl atualizado
   - Coletar 10 trades antes de avaliar edge

### 🎯 PÓSOPERAÇÕES
5. **Review semanal**
   - PnL, win rate, alpha vs BTC, drawdown
   - Se WR permanecer < 40% por 2 semanas: reativar análise

---

## ARQUIVO DE AUDITORIA PARA REFERÊNCIA

📄 `journal/AUDIT_2026_06_08.md` — análise completa pré-decisão

---

## CONFIRMAÇÃO

```
🔴 LIVE MODE: ATIVADO
⏰ Timestamp: 2026-06-08 12:47:00 BRT
👤 Usuário: Thiago Miyabara
✅ Status: OPERACIONAL
⚠️  Modo: LIVE (com guardrails ativas)
```

---

*Documento criado automaticamente para registro de auditoria.*  
*Próximo scan: ~120min*  
*Capital em jogo: $3,668.20 USD*
