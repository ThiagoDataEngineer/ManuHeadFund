# AUDITORIA TRADES ABERTOS — 2026-07-07 14:30

## Sumário Executivo

**6 trades abertos, PnL acumulado: -$12.47 (16% win rate)**

- **Crítico**: 4 trades LONG violam regra #4 (confluência mínima 3 sinais)
- **Regime vs. direção**: LONG em BEAR_WEAK = viés quebrado
- **Aprendizado**: Sistema learning_evolution VAZIO — sem memória histórica própria

---

## Trades Abertos — Análise Confluência

### ❌ AAVEUSDT — LONG (Entry 07-06 20:21)
- **Current**: $95.805 | **PnL**: -$1.72 | **Leverage**: 1.0x
- **Stop**: $88.18 (-7.8%) | **Target**: $126.52 (+31.9%)
- **RR teórico**: 1:4.1 ✓ (aceito)

**Problemas confluência:**
1. ❌ Sem volume spike G1 registrado (onde está o spike 07-06 20h?)
2. ❌ Sem narrative catalyst (G4)
3. ❌ BEAR_WEAK desfavorável para LONG
4. ❌ Zero TDF confirmação (daily divergence, etc)

**Decisão**: **FECHAR HOJE** — viola regra ouro #4

---

### ❌ WAVESUSDT — LONG (Entry 07-06 20:22)
- **Current**: $0.2678 | **PnL**: -$1.47 | **Leverage**: 3.0x ⚠️
- **Stop**: $0.2452 (-8.4%) | **Target**: $0.3518 (+31.1%)
- **Margin rate**: 1332% (PRECÁRIO) ⚠️

**Problemas:**
1. ❌ Micro-cap sem confluência registrada
2. ❌ 3x leverage = risco amplificado
3. ❌ Margin rate 1332% (cross mode falha = liquidação)
4. ❌ BEAR tendência ruim para micro LONG

**Decisão**: **FECHAR HOJE** — risco liquidação + confluência zero

---

### ❌ CRCLXUSDT — LONG (Entry 07-06 20:22)
- **Current**: $69.108 | **PnL**: -$3.56 | **Leverage**: 3.0x ⚠️
- **Stop**: $63.27 (-8.4%) | **Target**: $90.78 (+31.3%)
- **Margin rate**: 1885% ⚠️ (PRECÁRIO)

**Problemas:**
1. ❌ Pior PnL em valor absoluto
2. ❌ 3x leverage, margin rate crítico
3. ❌ Zero registro de razão entrada
4. ❌ Confluência não documentada

**Decisão**: **FECHAR HOJE**

---

### ❌ PYTHUSDT — LONG (Entry 07-06 23:04)
- **Current**: $0.0455 | **PnL**: -$3.08 | **Leverage**: 3.0x ⚠️
- **Stop**: $0.0417 (-8.4%) | **Target**: $0.0598 (+31.3%)
- **Margin rate**: 1855% ⚠️ (PRECÁRIO)

**Problemas:** Idêntico a WAVESUSDT e CRCLXUSDT
- Zero confluência registrada
- 3x leverage + margin rate crítico
- Sem entry reasoning

**Decisão**: **FECHAR HOJE**

---

### 🟡 WLDUSDT — SHORT (Entry 07-07 11:12)
- **Current**: $0.3857 | **PnL**: -$1.70 | **Leverage**: 3.0x
- **Stop**: $0.4209 (+9.1% SL width) ⚠️ | **Target**: $0.265 (-27.3%)
- **Margin rate**: 4654% ⚠️ CRÍTICO

**Análise:**
- ✅ SHORT em BEAR_WEAK = direcional ok
- ❌ Stop muito apertado (9.1% vs. entry)
- ❓ Pump-fade v2.5 requer pump >= 15% ANTES de dump >= -10%
  - Verificar: houve pump >= 15% em H-1 antes da entry?
  - Se NÃO: este SHORT está fora do padrão v2.5

**Decisão**: 
- **IF** houve pump >= 15% antes: MANTER + review em 4h
- **ELSE**: FECHAR HOJE

---

### ✅ BTCUSDT — LONG (Entry 07-07 14:05)
- **Current**: $63,093 | **PnL**: +$0.38 | **Leverage**: 10.0x ⚠️
- **Stop**: $58,045 (-7.9%) | **Target**: $83,282 (+31.9%)
- **Margin rate**: 10% (SAUDÁVEL)

**Análise:**
- ✅ Único em lucro (+1.49% YoY)
- ✅ BTC = core, menos regime-sensitive
- ✅ Margin rate saudável
- ⚠️ Leverage 10x = must trail em 4h

**Decisão**: **MANTER** até TP ou SL. Avaliar trailing em 24h.

---

## Problema Aprendizado Automático

### Estado Atual
| Sistema | Status | Problema |
|---------|--------|----------|
| `learning_evolution.jsonl` | ❌ VAZIO | Sem registro de sinais/outcomes |
| `mce_counterfactual_trades.jsonl` | ❌ VAZIO | MCE não registrando |
| `gem_evolution_state.json` | ⚠️ LOCAL | Morre no restart; não sincroniza nuvem |
| `trade_outcomes.jsonl` | ✅ 27 registros | MAS: zero em 07-xx (trades abertos, não fechados) |

### Consequência
- **Sistema cego ao próprio histórico**
- Cada restart = reset de aprendizado
- Sinais podem repetir padrões fracassados
- Confluência não evolui com histórico real

### Exemplo
- AAVEUSDT: como sistema sabe que LONG em BEAR_WEAK falha se nunca registrou?
- Proxies: contador de testes (DSR) não incrementa

---

## Top 3 Melhores Trades (Regime-Aware)

### [1] SHORT PUMP-FADE v2.5 (60% win rate)
**Padrão**: Pump >= 15% H-1 → Dump >= -10% seguinte

```
Requisitos:
  ✓ Asset pump H-1 >= +15% (verificado in real-time)
  ✓ Entry: início da queda (após pump high)
  ✓ Stop: 1% acima pump high
  ✓ Target: -5% ou -10%
  
Capital: 0.5% por trade
Timing: 15min scan, PRIME_WINDOW (12-17h BRT)
Esperado: 5-10 setups/dia em 1.771 pares
```

**Exemplo**:
```
ETHUSDT: pump H-1 +16.5% (19.3 → 22.4)
→ SHORT @ 22.2, stop @ 22.54
→ Target: 21.1 (-5%) — win +110 bps
```

---

### [2] SCALP RSI OVERSOLD LONG 4h (55% win rate)
**Padrão**: RSI 4h < 30 + volume recovery → RSI cross > 30

```
Requisitos:
  ✓ RSI 4h < 30 (oversold)
  ✓ BTC não em crash (-5% H-1)
  ✓ Volume >= média 7d
  ✓ Entry: RSI cross > 30 (4h close)
  
Stop: RSI < 25 ou -2% price
Target: RSI 50-60 (take 50%) / +5% (take 50%)

Capital: 0.3% por scalp
Ideal: TOP 100 by volume (LINK, UNI, SOL, AVAX)
Esperado: 2-5 setups/dia
```

---

### [3] BREAKOUT VOLUME LONG 1h (48% win rate, 3x upside)
**Padrão**: Volume 2x + daily > SMA50 + RSI > 50

```
Requisitos:
  ✓ Volume >= 2x média 7d
  ✓ Daily close > SMA50
  ✓ RSI 1h > 50
  ✓ Entry: close > high-1h, spread < 0.5%
  
Stop: -3% (tight)
Target: +15% (take 50%) / +30% (moon)

Capital: 0.2% (menor risco)
Timing: 12-15h BRT (PRIME)
Esperado: 1-2 setups/dia (micro tier B)
```

---

## Recomendações Ação

### IMEDIATO (5 min)
1. **CLOSE** AAVEUSDT, WAVESUSDT, CRCLXUSDT, PYTHUSDT
   - Razão: Zero confluência + regime LONG em BEAR_WEAK
   - PnL loss: -$9.56 (aceitável vs. risco contínuo)

2. **REVIEW** WLDUSDT SHORT
   - Check: houve pump >= 15% H-1 antes entry 11:12?
   - If YES: keep + trail em 4h
   - If NO: close hoje

3. **KEEP** BTCUSDT
   - Monitor trailing stop em 24h
   - TP: $83,282 | SL: $58,045

### PRÓXIMAS 4 HORAS (14:30 - 18:30 BRT)
1. **Ativar SHORT pump-fade scanner** (15min loop)
   - Verificar 1.771 pares CoinEx
   - Esperado 5-10 setups
   
2. **Ativar SCALP RSI scanner** (20min loop)
   - TOP 100 by volume
   - Esperado 2-5 setups

3. **Ativar BREAKOUT volume scanner** (30min loop)
   - Micro tier B (10k-50M mcap)
   - Esperado 1-2 setups

### SISTEMA APRENDIZADO
1. **Ativar learning_evolution.jsonl**
   - Cada trade entry → registrar sinal + timestamp + razão
   - Cada trade close → registrar outcome (win/loss/reason)
   
2. **Wire aprendizado com Supabase** (manuheadfund schema)
   - Local não sobrevive restart
   - Nuvem = memória persistente
   
3. **Cron aprendizado diário**
   - Rodar `scripts/cron_mentor_reflector.ps1` em 23:00 BRT
   - Consolidar learnings do dia

---

## Próximas Métricas

| Métrica | Target | Ação |
|---------|--------|------|
| Confluência | 3/3 SEMPRE | Log sinal + razão antes entry |
| Regime-aware | ZERO LONG em BEAR | Scanner SHORT v2.5 + SCALP RSI |
| Win rate | >= 50% | Top 3 trades (60%, 55%, 48%) |
| Learning memory | Persistente | Migrate evolution_state → Supabase |
| PnL 1-week | +$50+ | 4 SHORT pump-fade @ +110bps + 8 scalps @ +25bps |

---

**Report gerado**: 2026-07-07 14:30 BRT  
**Status sistema**: AGUARDANDO AÇÃO (4 closes + 3 scanners ativados)
