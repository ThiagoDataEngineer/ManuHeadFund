# 📊 Backtest Analysis & Improvement Roadmap

**Date**: 2026-06-08  
**Status**: ⚠️ Current backtests are **directional but incomplete**

---

## 🔍 AVALIAÇÃO DOS BACKTESTS ATUAIS

### 1. **phase0_vol_climax_backtest.ps1** ⚠️

**O que fez bem:**
- ✓ 3 cenários (agressivo, conservador, realista)
- ✓ Win rates razoáveis (60-65%)
- ✓ Teste rápido de conceito

**Problemas:**
- ❌ **Nenhum slippage/fees** (assume entrada/saída perfeita)
- ❌ **Distribuição uniforme** (todos os wins iguais, todas as perdas iguais)
- ❌ **Sem correlação** com market conditions reais
- ❌ **Apenas 100 trades** (muito pouco para validação)

**Risco**: Win rates podem ser **15-20% otimistas** na realidade.

---

### 2. **phase0_advanced_backtest.ps1** ⚠️⚠️ INFLADO!

**O que fez bem:**
- ✓ Escalação 100→200→500 (bom progressão)

**PROBLEMAS CRÍTICOS:**
- ❌ **ROI 171.5% em 200 trades é absurdo**
  - Esperado: ~4% ROI em 200 trades
  - Actual: Parece estar multiplicando posição cada vez
- ❌ **ROI 4,311% em 500 trades NÃO É REALISTA**
  - Implicaria 5x retorno diário (~0.5% cada)
  - Nenhum sistema scalping mantém isso
- ❌ **Sem fees**: 0.2% entrada + 0.2% saída = 0.4% cost per trade
  - Em 500 trades: 500 × 0.4% = 200% de custo!
  - ROI ajustado: 4,311% - 200% = 4,111% (ainda absurdo)

**Risco**: **Este backtest é ENGANADOR. Ignorar completamente.**

---

### 3. **phase3_evolved_backtest.ps1** ⚠️

**O que fez bem:**
- ✓ Multi-signal ensemble (5 sinais diferentes)
- ✓ Ensemble win rate corrigido: 68.1% (razoável)
- ✓ Regime mapping incluído

**Problemas:**
- ❌ **FARO V3 com 80% WR é suspeito**
  - Frequency: 1% (muito raro)
  - Se real, por que não usar 100% FARO?
  - Likely: Overfitting em 4 pumps validados
- ❌ **Sem validação de frequência**
  - 5 sinais × 500 trades = 2,500 sinal-trades
  - Mas FARO só dispara 1% × 500 = 5 vezes
  - Win rate baseado em N=5 não é confiável
- ❌ **Correlação entre sinais assumida zero**
  - Na realidade: Vol_Climax + Engulfing correlacionados
  - Ensemble weight pode estar inflado

**Risco**: 80% FARO é **definitivamente overfitted**. Real provavelmente 50-60%.

---

### 4. **phase_regime_backtest.ps1** ✓ Este é honesto

**O que fez bem:**
- ✓ Vol_Climax SOLO em 4 regimes
- ✓ Mostra degradação realista em BEAR
- ✓ BEAR_STRONG 49% é honesto (não está sendo vendido como bom)

**Insights:**
- Vol_Climax sozinho: 49-65% (range grande)
- Combo corrige para 60-71% (muito melhor)

---

### 5. **phase_regime_refined_backtest.ps1** ✓ MELHOR

**O que fez bem:**
- ✓ Valida combo em 4 regimes
- ✓ Todos ≥60% (robusto)
- ✓ Realista e honesto

**Pequeno problema:**
- ⚠️ Ainda sem slippage/fees
- ⚠️ Distribuição ainda artificial

---

### 6. **preintegration_backtest_bundle.ps1** ⚠️

**Problemas:**
- ❌ **Apenas 31 trades em stress test**
  - 4% DD em 31 trades não é significante
  - Precisa de 100-200 trades
- ❌ **Capital growth lento projetado**
  - 76.5% falta para $5k em 100 trades
  - Sugere win rate <62% na realidade
- ❌ **Nenhuma validação de séries correlacionadas**
  - Assume perdas aleatórias
  - Realidade: Podem vir em sequências

---

## 🚀 MELHORIAS PROPOSTAS

### **Priority 1: Adicionar Slippage + Fees REALISTAS** ⭐⭐⭐

```powershell
# Current (WRONG):
$exitPrice = $entryPrice + $profitPct
$pnl = $exitPrice - $entryPrice

# Should be:
$entryFee = $entryPrice * 0.002  # 0.2% entrada
$exitFee = $exitPrice * 0.002    # 0.2% saída
$slippage = $profitPct * 0.0005  # 0.05% slippage
$netPnL = $exitPrice - $entryPrice - $entryFee - $exitFee - $slippage
```

**Impact**: ROI -0.4% a -0.8% por trade (~20-40% reduction in profitability).

---

### **Priority 2: Distribuição Realista de Wins/Losses** ⭐⭐⭐

```powershell
# Current (WRONG - uniforme):
$winPct = 0.008  # todos os wins exatamente 0.8%
$lossPct = 0.002 # todas as losses exatamente 0.2%

# Should be (lognormal distribution):
# Wins: μ=0.8%, σ=0.3% (alguns +1.5%, alguns +0.1%)
# Losses: μ=0.2%, σ=0.15% (alguns -0.4%, alguns -0.05%)

$winPct = 0.008 + (Get-Random -Minimum -300 -Maximum 300) / 10000
$lossPct = -0.002 + (Get-Random -Minimum -150 -Maximum 50) / 10000
```

**Impact**: Win rates podem cair 3-5% quando distribuição é realista.

---

### **Priority 3: Walk-Forward Validation** ⭐⭐

Testar em períodos diferentes:
```powershell
# Instead of: 1 backtest com 500 trades
# Do: 5 backtests com 100 trades cada, períodos diferentes

$periods = @(
    @{ name = "2024-Q1"; trades = 100 },
    @{ name = "2024-Q2"; trades = 100 },
    @{ name = "2024-Q3"; trades = 100 },
    @{ name = "2024-Q4"; trades = 100 },
    @{ name = "2025-Q1"; trades = 100 }
)

foreach ($p in $periods) {
    $wr = Run-Backtest -Period $p.name -Trades $p.trades
    # Track variance across periods
}
```

**Impact**: Identifica se o edge é REAL vs data snooping.

---

### **Priority 4: Monte Carlo Simulation** ⭐⭐

Permuta ordem dos trades para validar robustez:

```powershell
# Current: 1 sequência de 500 trades
# Should: 1000 permutações aleatórias de 500 trades cada

for ($i = 0; $i -lt 1000; $i++) {
    $shuffledTrades = $allTrades | Get-Random -Count $allTrades.Count
    $wr = Test-WinRate -Trades $shuffledTrades
    $results += $wr
}

# Stats: mean WR, std dev, 5th percentile (worst case)
$meanWR = ($results | Measure-Object -Average).Average
$stdDev = ($results | Measure-Object -StandardDeviation).StandardDeviation
$worst = ($results | Sort-Object)[50]  # 5th percentile
```

**Impact**: Valida se 62.6% é robusta ou cherry-picked.

---

### **Priority 5: Kelly Criterion Sizing** ⭐

Não usar fixo 1%, mas ótimo matemático:

```powershell
# Current:
$positionSize = $capital * 0.01

# Kelly Criterion:
$p = 0.626      # win rate
$q = 1 - $p     # loss rate
$r = 5           # R:R ratio (avg_win / avg_loss)
$f = ($p * $r - $q) / $r  # Kelly fraction
$positionSize = $capital * $f
# Result: ~1.2% (mais agressivo quando edge é claro)
```

**Impact**: Maximiza crescimento sem ruína.

---

### **Priority 6: Drawdown Realista (Streaks)** ⭐

Sequências de perdas consecutivas:

```powershell
# Current (WRONG):
# 20 perdas distribuídas aleatoriamente em 500 trades

# Should (REALISTIC):
# Gerar streaks de perdas (1-3 perdas seguidas)
# porque mercados são correlacionados

function Generate-RealisticDrawdown {
    param([int]$Trades, [double]$WinRate)
    
    $results = @()
    for ($i = 0; $i -lt $Trades; $i++) {
        if ((Get-Random -Minimum 0 -Maximum 100) -lt ($WinRate * 100)) {
            $results += "W"
        } else {
            # 70% chance of another loss coming (streak)
            $results += "L"
            if ((Get-Random -Minimum 0 -Maximum 100) -lt 70) {
                $results += "L"  # Add second loss
            }
        }
    }
    return $results
}
```

**Impact**: Max DD pode ser 2-3x maior que média.

---

### **Priority 7: Validação vs Live** ⭐⭐

Compare backtest esperado vs real:

```powershell
# Backtest esperado: 62.6% WR em BEAR_WEAK
# Live resultado: (será coletado em 30 trades)

# Métrica: divergência aceitável <5pp
$divergence = [Math]::Abs($liveWR - 0.626)

if ($divergence -gt 0.05) {
    Log "⚠️ DIVERGENCE > 5pp: modelo tem erro"
    Log "Possibilidades:"
    Log "  - Slippage real > 0.4%"
    Log "  - Win rate definição diferente"
    Log "  - Regime detection errado"
}
```

---

## 📋 CURRENT BACKTEST RELIABILITY SCORE

| Backtest | Realism | Reliability | Issues |
|----------|---------|-------------|--------|
| phase0_vol_climax | 60% | ⚠️ Medium | No fees, uniform dist |
| phase0_advanced | 20% | 🔴 **REJECT** | ROI absurdo, inflado 10x |
| phase3_evolved | 70% | ⚠️ Medium | FARO 80% overfitted |
| phase_regime | 75% | ✅ Good | Vol_climax honest |
| phase_regime_refined | 80% | ✅ Good | Combo validated |
| preintegration_bundle | 65% | ⚠️ Medium | Small sample size |

---

## 🎯 RECOMENDAÇÃO

### **Trust Level for LIVE:**

```
❌ DO NOT trust: phase0_advanced_backtest.ps1 (ignore completely)

⚠️ CAUTIOUS TRUST: phase0_vol_climax, phase3_evolved
   - Use como direction only
   - Real performance likely 10-15% lower

✅ GOOD TRUST: phase_regime_refined + preintegration_bundle
   - Mais honest
   - Real performance likely 2-5% lower (slippage/fees)
```

### **Action Plan:**

1. **This week**: Run live with conservative expectations (60% WR → likely 55%)
2. **Week 2**: Collect 30 trades, compare vs backtest
3. **Week 3**: If divergence <5pp, expand; else debug
4. **Week 4**: Implement Priority 1-2 improvements (slippage + distribution)
5. **Week 5+**: Monte Carlo + walk-forward validation

---

## 📊 EXPECTED ADJUSTMENT FACTORS

```
Backtest WR         → Live WR (with adjustments)
────────────────────────────────────────────
65% (vol_climax)    → 56-60% (slippage -3pp, correlation -2pp)
62.6% (combo BEAR)  → 57-61% (slippage -2pp, distribution -1pp)
68.1% (ensemble)    → 59-64% (FARO overfitting -4pp, but combo solid)

Safe assumption: Subtract 4-6pp from backtest for live conditions.
```

---

## 💡 QUICK WINS (Implement Now)

```powershell
# 1. Add fees to all backtests
-$entryFee = $entryPrice * 0.002
-$exitFee = $exitPrice * 0.002

# 2. Add realistic distribution
+$winPct = 0.008 + (Get-Random -Minimum -300 -Maximum 300) / 10000
+$lossPct = 0.002 + (Get-Random -Minimum -150 -Maximum 50) / 10000

# 3. Track by period (Q1, Q2, Q3...)
# 4. Compare live vs backtest after 30 trades
```

**Time to implement:** 2-3 hours  
**Impact:** Much more honest backtest results

---

**Bottom Line**: Current backtests are directional but **10-20% optimistic**. Expect live performance **4-6pp lower** than backtest WR due to slippage, fees, and realistic distributions.

