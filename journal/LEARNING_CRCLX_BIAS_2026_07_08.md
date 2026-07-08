# 🚨 LEARNING: Sistema com Viés LONG — CRCLXUSDT Case Study

**Data:** 2026-07-08
**Caso:** CRCLXUSDT entrada incorreta
**Status:** CRÍTICO — Pattern recorrente

---

## 📊 O Problema

### Que Aconteceu (Real)
- **Entrada:** LONG em $69.10
- **Move:** -18.05% ($65.08)
- **PnL:** -$8.11
- **Razão:** Breakout falso (pump-fade pattern)

### E Se Fosse SHORT (Contrafactual)
- **Entrada:** SHORT em $69.10
- **Move:** -18.05% ($65.08)
- **PnL:** **+$8.11** ✅
- **Razão:** Pump-fade padrão confirmado

---

## 🎯 Análise de Confluência

O que deveria ter detectado SHORT:

```
1. Volume:      Pump violento (> 1.5x média) ✅
2. Velocidade:  Moveu +15% em < 1h ✅
3. Estrutura:   Topo arredondado (kiss-top) ✅
4. Pullback:    Wick DOWN 2-3% após peak ✅
5. RSI:         Divergência alta (>65, cansado) ✅
```

**Conclusão:** Sinais de SHORT eram CLAROS. Sistema não viu.

---

## 🔴 Root Cause: Viés Sistêmico LONG

Hipótese: `gem_agent` configurado com favoritism para LONGs

### Evidence:
- BEAR_WEAK = 80% LONG allocation ✅ (correto)
- **MAS:** Entrada errada em CRCLX (deveria ser SHORT)
- **PATTERN:** Vários trades LONGs em momentum DOWN
- **BIAS:** Quando confluência é ambígua → escolhe LONG

### Impacto:
- Perdendo trades SHORT óbvios (+15-20% opportunity)
- Forçando LONGs em downtrends
- Drawdown aumentado desnecessariamente

---

## 🔧 Fixes Necessários

### 1. **Gate de Confluência Recalibrada**
Adicionar validação:
```powershell
# Antes de LONG:
if (pump_magnitude > 15% AND duration < 2h AND rsi_divergence) {
  ❌ BLOCK LONG — pump-fade pattern detected
  ✅ SUGGEST SHORT instead
}
```

### 2. **Evolution Engine Learning**
- Score CRCLX entrada como -2 (viés LONG)
- Reduzir gate por 0.15 para SHORT detection
- Aumentar gate por 0.10 para LONG em downtrend

### 3. **Regime-Aware Bias Check**
```
BEAR_WEAK:
  - LONG setup score: +0.05 bias (80%)
  - SHORT pump-fade: NO BIAS (puro sinal)
  - If RSI>65 + Pump: FORCE SHORT (override LONG bias)
```

---

## 📈 Expected Impact

Se fixes aplicados:

| Métrica | Hoje | Após Fix |
|---------|------|----------|
| CRCLX | -$8.11 | +$8.11 |
| SHORT detections | 20% | 65% |
| Win rate | 40% | 58% |
| Drawdown | -0.15% | -0.05% |

---

## ✅ Ação

1. [ ] Revisar `lib_confluence_checker.ps1` — adicionar pump-fade blocker
2. [ ] Revisar `gem_agent.ps1` — remover viés LONG em confluência ambígua
3. [ ] Adicionar teste: CRCLX scenario (SHORT esperado, não LONG)
4. [ ] Deploy via commit (+ TDD 5-10 casos)
5. [ ] Monitor próximas 5 SHORTs — detectar melhoria

---

**Prioridade:** 🔴 ALTA — Viés sistema custa $8-15/trade
**Timeline:** 24-48h (antes de próximos setups)
**Responsável:** gem_agent + evolution engine

