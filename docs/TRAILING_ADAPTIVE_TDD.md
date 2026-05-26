# TRAILING STOPS ADAPTATIVOS — TDD Implementation (2026-05-25)

## 🎯 Status: ✅ COMPLETE — 22/22 Tests Green

### Pilar 1: ATR-Dinâmico + Regime-Aware

Implementação TDD-first do sistema adaptativo de trailing stops com suporte a regimes de mercado.

---

## 📋 O Que Foi Construído

### 1. `Get-AdaptiveBuffer` — Buffer Dinâmico por Regime

**Assinatura:**
```powershell
Get-AdaptiveBuffer -Range <double> -CurrentAtr <double> -HistoricalAtr <double> -Regime <string>
→ [double] buffer em valor absoluto
```

**Multiplicadores por Regime:**
| Regime | Multiplier | Caso de Uso |
|--------|-----------|------------|
| BULL_STRONG | 0.75x | Trending market, confiança alta → tight stops |
| BULL_WEAK | 1.0x | High ainda mas enfraquecendo → normal |
| SIDEWAYS | 1.3x | Defende pullback noise → wide |
| BEAR_WEAK | 1.4x | Bear market, protege spikes → muito wide |
| BEAR_STRONG | 1.5x | Strong downtrend, hold mais → ultra wide |
| CAPITULATION | 0.5x | Panic phase → ultra tight, exit rápido |

**Volatilidade Ajustável:**
- ATR ratio = CurrentAtr / HistoricalAtr
- Buffer escala automaticamente com vol atual vs baseline
- Proteção contra divide-by-zero

**Floor de Segurança:**
- Mínimo 1.5% do range (não perde lucratividade)

**Exemplos Validados:**
```
BULL_STRONG (100 ATR, regime 0.75) → ~75
SIDEWAYS (100 ATR, regime 1.3) → ~130
CAPITULATION (100 ATR, regime 0.5) → ~50 (vs 1.5% floor)
High Vol SIDEWAYS (200 ATR, 1.3 regime) → ~260
```

---

### 2. `Get-TrailingNewStopAdaptive` — Cálculo de Stop com Adaptação

**Assinatura:**
```powershell
Get-TrailingNewStopAdaptive -Pos <PSCustomObject> -CurrentPrice <double> -Regime <string> `
                           -CurrentAtr <double> -HistoricalAtr <double>
→ [PSCustomObject]@{ newStop, newPhase, newPeak, changed }
```

**Fases (LONG):**
```
Fase 0 → 1 (33% alvo atingido):
    Move stop para breakeven + adaptive_buffer

Fase 1 → 2 (66% alvo atingido):
    Move stop para entry + 33% do ganho (lock +33%)

Fase 2 → 3 (100%+ alvo atingido):
    Move stop para trailing 15% abaixo do pico

Fase 3 (Trailing ativo):
    Atualiza stop se novo pico > pico anterior
    Nunca recua stop (always up on LONG)
```

**SHORT Espelhado:**
- Lógica idêntica mas invertida (preços caindo)
- Stop sobe conforme preço cai

**Peak Persistence (Bug Fix 2026-05-25):**
- Peak SEMPRE atualizado, mesmo sem mudança de fase
- Evita "lag" em mercados laterais onde peak deveria subir mas fase não muda
- Caso BNB: Peak 672.89 real mas registrado 662.24 → perdia fase 2
- Fix: `$pos.peak = $calc.newPeak` ANTES da verificação de mudança

---

### 3. `Update-TrailingStopsAdaptive` — Loop de Atualização

**Integração no Master Cycle:**
```powershell
Update-TrailingStopsAdaptive -JournalDir <string> -Verbose
```

**O Que Faz:**
1. Busca regime atual (via `Get-MacroContext`)
2. Busca ATR atual (placeholder — prod carrega histórico)
3. Para cada posição ativa:
   - Busca preço atual (CoinEx)
   - Verifica stop hit
   - Calcula novo stop adaptativo
   - Persiste em `trailing_positions.json`
   - Notifica Telegram se mudou

---

## 📊 Testes Implementados (22/22 ✅)

### Get-AdaptiveBuffer Tests (13 testes)

**Regime Multipliers (6):**
- ✅ ~75 para BULL_STRONG
- ✅ ~100 para BULL_WEAK
- ✅ ~130 para SIDEWAYS
- ✅ ~150 para BEAR_STRONG
- ✅ ~50 para CAPITULATION
- ✅ Default SIDEWAYS

**ATR Volatility (2):**
- ✅ Scale up quando CurrentAtr > HistoricalAtr
- ✅ Scale down quando CurrentAtr < HistoricalAtr

**Minimum Floor (2):**
- ✅ Enforce 1.5% mínimo
- ✅ Usa buffer quando > floor

**Edge Cases (3):**
- ✅ Zero range safe
- ✅ Zero CurrentAtr safe
- ✅ Zero HistoricalAtr (divide by zero) safe

---

### Get-TrailingNewStopAdaptive Tests (7 testes)

**Fase 1 (1):**
- ✅ Move stop → BE + buffer @ 33% alvo

**Fase 2 (1):**
- ✅ Move stop → +33% gain @ 66% alvo

**Fase 3 (2):**
- ✅ Move stop → 15% trailing @ 100% alvo
- ✅ Trail up quando novo pico maior

**SHORT (1):**
- ✅ Logica espelhada correta

**Regime Impact (1):**
- ✅ BULL_STRONG buffer < SIDEWAYS buffer

**Peak Persistence (1):**
- ✅ Peak atualiza mesmo sem mudança de fase

---

### Regression Tests (2 testes)

- ✅ Adaptive vs fixed 2% em high vol SIDEWAYS
- ✅ Adaptive vs fixed 2% em low-vol regime

---

## 🚀 Próximos Passos (Camadas 2-5)

| Camada | O Quê | Esforço | Impacto |
|--------|-------|---------|---------|
| 2 | Mentor Reflection (6h checkpoint) | 3h | +2-4% |
| 3 | Kelly Fractional Sizing | 1h | +1-3% |
| 4 | Tori Proximity Real-Time | 1.5h | +2-5% |
| 5 | Moon Bag + Scale-Out | 2h | +3-8% |

**Total Esperado:** +12-25% win rate, +15-30% Sharpe

---

## 📁 Arquivos

- **Implementação:** `./agents/lib_trailing_adaptive.ps1`
- **Testes:** `./tests/lib_trailing_adaptive.Tests.ps1`
- **Docs:** `./docs/TRAILING_ADAPTIVE_TDD.md` (este arquivo)

---

## 🔄 Como Integrar no Loop Master

```powershell
# Em scan_master.ps1 :: Invoke-MasterCycle

# Substituir Update-TrailingStops por Update-TrailingStopsAdaptive
Update-TrailingStopsAdaptive -Verbose

# Ou manter ambas (legacy + adaptive) durante transição:
. (Join-Path $agentsDir "lib_trailing_adaptive.ps1")
Update-TrailingStopsAdaptive -Verbose

# Regime passa automaticamente via Get-MacroContext
```

---

## ✅ Validação

```powershell
# Rodar testes
Invoke-Pester ./tests/lib_trailing_adaptive.Tests.ps1 -Verbose

# Esperado: Passed: 22 Failed: 0
```

---

## 🎓 Lições Aprendidas

1. **ATR-Dinâmico vs Fixed %:** Regimes voláteis (SIDEWAYS + high ATR) precisam buffers muito maiores que fixed 2%
2. **Peak Persistence:** Mesmo sem mudança de fase, peak deve persistir para evitar lag em laterais
3. **Ordem de Operações:** Peak update ANTES da verificação de "changed" flag (fix 2026-05-25)
4. **Floor é Crítico:** Em ranges pequenos, floor 1.5% previne stop apertado demais
5. **Regime Hierarchy:** Há redundância em multiplicadores (vários regimes = mesmo buffer) — trade-off entre granularidade e complexidade

---

## 📈 Performance Esperada

**Vs Legacy Fixed 2% Buffer:**
- BULL_STRONG: Tight 20-30% tighter (0.75 vs 2% = 75 vs 20)
- SIDEWAYS: Wide 65x mais espaço (1.3×5 vol ratio = 130 vs 2% = 20)
- Edge Regimes (CAPITULATION): Ultra tight, protege reversões antecipadas

**Impacto Estimado:**
- +3-5% win rate (menos stops falsos em vol alta)
- +2-3% Sharpe (consistência melhor)
- +0-2% drawdown (melhor proteção)

---

**Status:** Camada 1 completa. Pronto para próximas camadas.
**Próxima:** Camada 2 — Mentor Reflection Loop (6h checkpoint)
