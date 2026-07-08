# 🎯 Healthy Trading Framework 2026

> **Objetivo:** Operar apenas setups com confluência multi-timeframe + RR ≥ 3:1 + regime alignment.  
> **Regime Atual:** BEAR_WEAK (consolidação pós-queda, recuperação lenta)  
> **Capital per Trade:** 1% (em leverage 3x = 0.33% efetivo)

---

## 1️⃣ CONFLUÊNCIA MULTI-TIMEFRAME (Obrigatória)

### 4h Timeframe — ESTRUTURA
- **Suporte/Resistência:** Níveis verdadeiros (não wicks, closes reais)
- **Tendência:** HMA 200-period ou EMA 21
- **Volume:** Perfil de acumulação (baixo volume, consolidação) ou distribuição clara
- **Entry Point:** Pullback após breakout, NÃO top de consolidação

**Exemplo LDOUSDT (✅ Funcionou):**
```
4h: Breakout de consolidação $0.300-$0.320
4h: RSI 55-62 (momentum crescente)
4h: Volume spike no breakout
→ Setup confirmado em 4h
```

### 1h Timeframe — MOMENTUM
- **RSI:** 40-60 (oversold<30, overbought>70 = risco)
- **MACD:** Convergência ANTES de divergência
- **Volume:** Confirmação do movimento
- **Candle Pattern:** Pin bar, engulfing, hammer (context-dependent)

**Exemplo LDOUSDT (✅ Funcionou):**
```
1h: Candle bullish +1.2%
1h: Rompeu resistência local
1h: Volume crescente
→ Momentum confirmado em 1h
```

### 15m Timeframe — TIMING
- **Entry:** Pullback fino na tendência (não fade)
- **Stop Loss:** Logo abaixo do swing low
- **Take Profit:** Calculado como RR ratio

**Exemplo LDOUSDT (✅ Funcionou):**
```
15m: Pullback natural após spike
15m: Volume diminuindo (acumulação micro)
15m: Múltiplas tentativas up
→ Entry timing confirmado em 15m
```

**Checklist Confluência:**
- [ ] 4h + 1h + 15m alinhados NO MÍNIMO
- [ ] Sem conflitos entre timeframes (ex: 4h down + 1h up = ESPERA)
- [ ] Volume confirma movimento
- [ ] Estrutura respeita suporte/resistência

---

## 2️⃣ RISK:REWARD ≥ 3:1 (Não Negocie Sem)

### Cálculo Antes da Entrada

```
Risk = Entry - StopLoss
Reward = TakeProfit - Entry
RR = Reward / Risk

✓ Mínimo aceitável: 3:1
✓ Ideal: 4:1 ou 5:1
✗ Rejeite: RR < 2.5:1
```

### Exemplo: CRCLXUSDT (❌ Rejeitado)
```
Entry: $69.11
SL: $63.27 (8.4% = $5.84 risk)
TP: $90.78 (31.4% = $21.67 reward)

RR = $21.67 / $5.84 = 3.7:1  ✓ OK

MAS:
- 38h sem movimento (posição morta)
- Tamanho maior ($134.76) vs RR OK
→ DECISÃO: Reduce 50%, free capital
```

### Exemplo: WLDUSDT (❌ Rejeitado)
```
Entry: $0.3858
SL: $0.4209 (9.1% = $0.0351 risk)
TP: $0.265 (31% = $0.1208 reward)

RR = $0.1208 / $0.0351 = 3.4:1  ✓ Numericamente OK

MAS:
- SL apertado (apenas -9%) vs TP distante (31% abaixo)
- SHORT em regime BEAR_WEAK (contracíclico)
- Entrada logo após pump (timing ruim)
- 12h travada
→ DECISÃO: Close com loss minimal, aprende
```

---

## 3️⃣ REGIME-ALIGNED TRADE DIRECTION

### BEAR_WEAK (Estado Atual)
- **Mercado:** Recuperação lenta pós-queda, consolidação
- **Volatilidade:** Controlada (sem crashes, sem ralis explosivos)
- **Direção Preferida:** **LONG** (waits for pullbacks, holds consolidations)
- **SHORTs:** Apenas com confluência 4x (pump-fade patterns, extreme oversold reverses)

**Erro Cometido:** WLDUSDT SHORT logo após pump
```
BEAR_WEAK rejeita SHORTs à menos que:
  ✓ Dump >= -20% + pump H-1 anterior (fade pattern)
  ✓ RSI > 70 (overbought extremo)
  ✓ Volume climax (2.5x+ normal)
  ✓ Múltiplos timeframes aligned

WLDUSDT tinha: Pump recente, nada mais
→ Rejeição correta
```

### BEAR_STRONG (Caso Futuro)
- **Direção Preferida:** **SHORT** (waits for rallies, fades bounces)
- **LONGs:** Apenas daytrading + momentum scalps

### BULL_STRONG (Caso Futuro)
- **Direção Preferida:** **LONG** (qualquer pullback)
- **SHORTs:** Praticamente proibidas

---

## 4️⃣ TRADE LIFECYCLE & MONITORING

### Entry Checklist (Antes de Clicar)
```
[ ] 4h + 1h + 15m confluência?
[ ] RR ≥ 3:1?
[ ] Regime-aligned (LONG em BEAR_WEAK)?
[ ] Tamanho = 1% capital?
[ ] Stop-Loss fixo ANTES da ordem?
[ ] TP calculado de forma clara?
```

### During Trade (A Cada 4h)
```
[ ] Posição ainda alinhada com 4h/1h structure?
[ ] Novo suporte/resistência surgiu? (adjust SL?)
[ ] Volume confirmando ou fraco?
[ ] PnL > +20% → considere TP 50% + trailing 50%
[ ] PnL < -5% + sem momentum altista → CONSIDERE CLOSE
```

### Dead Position Rule (❌ Mortas)
```
Após 24h SEM MOVIMENTO:
  - Sem volume
  - Sem breakout
  - Sem pullback

→ CLOSE (independente de PnL)
→ Libera capital para setup com confluência REAL
```

### Trailing Stops (Proteção de Lucro)
```
Quando PnL > +10%:
  - Mova SL para break-even
  - Rode trailing stop (2-5% abaixo highs)
  - Deixe correr até TP nominal ou SL ativa

Exemplo LDOUSDT:
  Quando acima $0.335 → SL $0.310 (lucro protegido)
  Rode até $0.38 (próximo nível)
```

---

## 5️⃣ POSITION SIZING & CAPITAL ALLOCATION

### Micro-Sizing Advantage
```
Cada trade: $25-30 USD
Leverage: 3x (efetivo ~$75-90 USD)
Total portfolio: ~$5k

Vantagens:
  ✓ Psychological: Perda $5-10 é absorvível
  ✓ Technical: Permite 3-5x leverage sem crash
  ✓ Flexibility: 10-15 trades simultâneos
  ✓ Learning: Cada erro custa pouco, aprende muito

Risco máximo per trade: 1% capital = $50
Perda aceita: $5-10 (normal em trading)
Win rate esperado: +15-20% (disciplina + confluência)
```

### Capital Allocation (Current)
```
FUTURES:  ~$500 (micro sizing, 3-10x leverage)
SPOT:     ~$2.4k (holdings: XRP, AIN, QUBIC, etc)
USDT:     ~$2.4k (reserved for entries + exits)
Total:    ~$5.3k
```

---

## 6️⃣ ENTRY TRIGGERS (Específicos por Regime)

### BEAR_WEAK Entry Triggers
1. **Pullback em Suporte Macro**
   - Preço toca suporte (não quebra)
   - RSI <50 (sem crash)
   - Bounce candle em 1h/15m

2. **Breakout de Consolidação**
   - Preço sai do range
   - Volume spike (20%+ acima média)
   - 4h/1h momentum confirmando

3. **Bounce após Wick Down**
   - Lower wick (spike down + recover)
   - Próxima vela tenta ir UP
   - RSI em oversold (20-40)

### Exemplo: LDO vs PYTH (Contraste)

**LDO (✅ Entrada Saudável):**
```
Entry: Pullback em consolidação LOW
Confluência: 4h breakout + 1h spike + 15m bounce
Volume: Confirmando movimento
Result: +0.44% em 3h, momentum UP
→ Setup excelente
```

**PYTH (⚠️ Entrada Risky):**
```
Entry: Recém-aberta, ainda em momentum DOWN
Confluência: Só 15m setup, sem 4h confirmação
Volume: Fraco
Result: -0.13% inicialmente, ainda testando SL
→ Setup risky, requer monitoramento 4h
```

---

## 7️⃣ EXIT RULES (Quando Sair)

### Profitable Exit (quando PnL > +5%)
```
Opção 1: TP Nominal
  Venda 100% no alvo calculado

Opção 2: Parcial + Trailing
  TP 50% no first target (ex: $0.375 em LDO)
  Trailing SL 50% até next target (ex: $0.42)

Opção 3: Breakeven + Run
  PnL > +10% → SL break-even
  Deixa correr com trailing stop
```

### Stop-Loss Exit (proteção obrigatória)
```
Quando SL atingido:
  EXIT 100%, SEM EMOÇÃO
  Log: Razão do stop (regime changed? support broke?)
  Evolução aprende: Não repetir entrada nesse nível
```

### Dead Position Exit (após 24h)
```
Quando 24h+ SEM MOVIMENTO:
  - Consolidação morte-lenta
  - Volume seco
  - Nenhuma confluência nova

→ CLOSE (corta perda ou lucro mínimo)
→ Libera capital para setup REAL
```

---

## 8️⃣ LEARNING LOOP (Auto-Improvement)

### Trade Journal (Cada posição registra)
```
trade_id: AAVEUSDT-20260707-160214
entry_price: 95.805
entry_time: 2026-07-06T20:21:26Z
exit_price: 95.80 (closed)
exit_reason: Dead 38h, consolidation, no confluence
pnl_usd: -2.27
pnl_pct: -4.22
learning: "Entry prematura, sem confluência multi-TF. AAVE procíclico"
```

### Evolution Engine (Aprende Padrões)
```
Após 10+ trades com journal completo:
  - Quais setup têm >55% win rate?
  - Qual timeframe é mais decisivo? (4h vs 1h)
  - Quanto RR mínimo vale risco?
  - Regime BEAR_WEAK favorece qual direção exato?

→ Auto-relax gates (favorece setups 85%+ win)
→ Auto-tighten gates (rejeita setups <40% win)
```

### Monthly Review
```
Ao final do mês:
  - Win rate real
  - Avg RR resultado
  - Capital liberado vs bloqueado
  - Regime shifts (BEAR_WEAK → BEAR_STRONG?)
  - Próximo ciclo adjustments
```

---

## 9️⃣ COMMON MISTAKES (Evitar)

| Erro | Situação | Correção |
|------|----------|----------|
| **Early Entry** | Entra antes confluência 4h | Aguarde 4h breakout confirmado |
| **Tight SL** | SL < 5% do entry | Respeite estrutura (7-10% mínimo) |
| **Dead Positions** | Mantém 48h+ sem movimento | Rule: 24h morta = close |
| **Wrong Regime** | SHORT em BEAR_WEAK | LONGs em BEAR_WEAK, SHORTs em BEAR_STRONG |
| **Size Too Big** | Entrada > 1% capital | Micro-size ($25-30) é regra |
| **Revenge Trade** | Após loss, entra emocionado | Espera 1h, aguarda confluência NOVA |
| **No RR Calc** | Entra sem calcular TP | RR ≥ 3:1 OBRIGATÓRIO |

---

## 🔟 QUICK CHECKLIST (Antes de Cada Trade)

```
PRÉ-ENTRADA:
  [ ] 4h + 1h + 15m alinhados?
  [ ] RR ≥ 3:1 calculado?
  [ ] Regime BEAR_WEAK → LONG preferido?
  [ ] SL fixo (não móvel)?
  [ ] Tamanho 1% capital?
  [ ] Volume confirmando?

PÓS-ENTRADA:
  [ ] Posição aberta no exchange?
  [ ] SL + TP ordens criadas?
  [ ] Journal registrado?
  [ ] Telegram alert ativado?

DURANTE (A Cada 4h):
  [ ] Ainda confluência 4h?
  [ ] Sem morte-lenta? (se sim → close)
  [ ] PnL > +20% → considerar TP parcial?
  [ ] PnL < -5% sem momentum → considerar SL curto?

SAÍDA:
  [ ] TP hit? Venda 100% ou parcial?
  [ ] SL hit? Exit 100%, log razão
  [ ] 24h morta? Close, libera capital
```

---

## 📊 Expected Outcomes (After Framework Implementation)

### Current State (2026-07-07 ANTES)
```
Portfolio Health: 79/100
Win Rate: ~30% (mixed confluences)
Capital Locked: ~$188 in dead positions
Avg Trade Duration: 48h+ (inclui mortas)
```

### Target State (2026-07-08+ DEPOIS)
```
Portfolio Health: 88/100
Win Rate: +15-20% (only RR ≥ 3:1 + multi-TF)
Capital Available: ~$188 liberated for confluent trades
Avg Trade Duration: 4-24h (only alive setups)
Regime-Aligned: 100% LONGs in BEAR_WEAK
Monthly Expected PnL: +$50-100 (micro-sizing discipline)
```

---

## 🎓 Final Philosophy

> **Trading is not about predicting price.  
> Trading is about managing confluences and risking small to win big.  
> Discipline > Prediction.  
> Multi-TF Alignment > Single-timeframe opinions.  
> Learning > Winning.**

Execute this framework consistently, log every trade, and let evolution optimize gates over time.

---

**Created:** 2026-07-07  
**Regime:** BEAR_WEAK  
**Framework Version:** 1.0  
**Status:** Active & Monitoring
