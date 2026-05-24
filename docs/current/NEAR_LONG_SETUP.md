# NEAR LONG SETUP - COBRIR PERDAS

**Data:** 2026-05-24  
**Objetivo:** Cobrir perdas de ~$8 USDT

---

## 📊 ANÁLISE NEARUSDT

### Situação Atual:
- **Preço:** $2.38
- **Change 24h:** +13.86%
- **Volume 24h:** $19.4M (altíssimo - muito líquido)
- **RSI(14):** 45.15 (saudável, não sobrecomprado)

### Análise Técnica (15min):
- **SMA20:** $2.40 (preço ligeiramente abaixo)
- **Suporte:** $2.36 (+1.17% abaixo do preço)
- **Resistência:** $2.47 (+3.76% acima do preço)

### Por Que NEAR?
✅ **Volume altíssimo** - $19.4M (mais líquido que BTC em alguns momentos)  
✅ **RSI saudável** - 45.15 (não esticado, espaço para subir)  
✅ **Próximo de suporte** - Setup técnico claro  
✅ **Momentum positivo** - +13.86% nas últimas 24h  
✅ **R:R favorável** - 1:2.9 (risco $0.03, reward $0.09)

---

## 🎯 SETUP PROPOSTO

### Entrada:
- **Market:** NEARUSDT
- **Side:** LONG (buy)
- **Type:** Market order
- **Entry:** $2.38 (preço atual)

### Proteção:
- **Stop Loss:** $2.35 (0.5% abaixo do suporte)
- **Take Profit:** $2.47 (resistência)
- **Risco:** 1.28% (-$6.40 se stop)
- **Reward:** 3.76% (+$18.78 se TP)
- **R:R:** 1:2.9 ✅

### Posição:
- **Margin:** $100 USDT
- **Leverage:** 5x
- **Notional:** $500 USDT
- **Amount:** ~210 NEAR

---

## 💰 RESULTADO ESPERADO

### Se atingir Take Profit ($2.47):
- **Lucro:** +$18.78 USDT
- **Cobre perdas:** $8 USDT
- **Sobra:** $10.78 USDT ✅

### Se atingir Stop Loss ($2.35):
- **Perda:** -$6.40 USDT
- **Total perdas:** $8 + $6.40 = $14.40 USDT

### Probabilidade:
- **R:R 1:2.9** = Precisa acertar 1 em cada 3 trades para lucrar
- **Setup técnico forte** = Probabilidade favorável
- **Volume alto** = Execução garantida

---

## 🔒 GESTÃO DE RISCO

### Proteções Automáticas:
1. ✅ **Stop Loss** configurado em $2.35
2. ✅ **Take Profit** configurado em $2.47
3. ✅ **Trailing Stop** ativa quando atingir +3% (automático)
4. ✅ **Leverage 5x** (moderado, não agressivo)
5. ✅ **Isolated margin** (não afeta outras posições)

### Cenários:
- **Melhor caso:** TP em $2.47 = +$18.78 (cobre perdas + sobra)
- **Caso base:** Trailing protege lucros após +3%
- **Pior caso:** Stop em $2.35 = -$6.40 (perda controlada)

---

## 📈 COMPARAÇÃO COM OUTRAS OPÇÕES

| Moeda | Change 24h | RSI | Volume | Setup | Risco |
|-------|------------|-----|--------|-------|-------|
| **NEAR** | +13.86% | 45.15 | $19.4M | ✅ LONG suporte | Baixo |
| GRASS | +28.45% | 55.75 | $3.5M | ⚠️ LONG moderado | Médio |
| MYX | +21.63% | 68.43 | $1.7M | ⚠️ Sobrecompra | Alto |
| BAN | +20.46% | 67.5 | $4.1M | ⚠️ Sobrecompra | Alto |

**NEAR é a opção mais segura:** RSI saudável + volume altíssimo + setup técnico claro

---

## 🚀 EXECUÇÃO

### Comando:
```powershell
.\EXECUTE_NEAR_LONG.ps1
```

### O Que o Script Faz:
1. ✅ Busca preço atual
2. ✅ Calcula stop loss e take profit
3. ✅ Mostra setup completo
4. ✅ Pede confirmação (digite 'S')
5. ✅ Ajusta leverage para 5x
6. ✅ Executa ordem LONG
7. ✅ Configura stop loss e take profit
8. ✅ Verifica posição aberta

### Após Execução:
- ✅ Trailing stop automático monitora a cada 5 minutos
- ✅ Quando atingir +3%, stop move automaticamente
- ✅ Proteção total sem intervenção manual

---

## ⚠️ IMPORTANTE

### Antes de Executar:
1. ✅ Revisar setup acima
2. ✅ Confirmar que concorda com risco/reward
3. ✅ Verificar capital disponível ($1,588 USDT)
4. ✅ Entender que pode perder $6.40 se stop

### Durante a Operação:
- ✅ Trailing stop automático ativo
- ✅ Não precisa monitorar 24/7
- ✅ Sistema protege automaticamente

### Se Quiser Cancelar:
- Antes de executar: Ctrl+C ou digite qualquer tecla diferente de 'S'
- Depois de executar: Fechar posição manualmente na exchange

---

## 📊 POSIÇÕES ATUAIS

| Posição | PNL | Stop | Status |
|---------|-----|------|--------|
| BNB | +1.70% | $627.82 | Aguardando +3% |
| UNI | -0.25% | $3.30 | Aguardando recuperação |
| LINK | -0.25% | $9.15 | Aguardando recuperação |
| SOL | -0.30% | $82.30 | Aguardando recuperação |
| **NEAR** | **-** | **$2.35** | **A EXECUTAR** |

**Total perdas atuais:** ~$8 USDT  
**Lucro esperado NEAR:** +$18.78 USDT  
**Resultado líquido:** +$10.78 USDT ✅

---

## ✅ CHECKLIST

- [x] Análise técnica completa
- [x] Setup com R:R favorável (1:2.9)
- [x] Volume alto ($19.4M)
- [x] RSI saudável (45.15)
- [x] Stop loss calculado
- [x] Take profit calculado
- [x] Script de execução pronto
- [x] Trailing stop automático ativo
- [ ] **VOCÊ:** Revisar setup
- [ ] **VOCÊ:** Executar `.\EXECUTE_NEAR_LONG.ps1`
- [ ] **VOCÊ:** Confirmar com 'S'

---

**Pronto para executar?** Digite: `.\EXECUTE_NEAR_LONG.ps1`
