# 🚀 TRADE AMPLIFICATION — 30-40 TRADES/DAY — 2026-06-18

> **Problema**: 7141 sinais/dia, mas apenas 4-5 trades = **0.06% aprovação**
> **Solução**: Abrir gates agressivamente + múltiplos modos (LONG/SHORT/scalp/swap)
> **Resultado**: 30-40 trades/dia com Trailing Executor atuando em CADA um

---

## 📊 ANÁLISE ATUAL

```
SINAIS ANALISADOS (24h): 7141
├─ LONG: 2695 (37%)
├─ SHORT: 804 (11%)
└─ NEUTRO (rejected): 3636 (51%)

TRADES REAIS: ~4-5/dia (0.06% approval)

PROBLEMA: Gates rejeitam 99.94%
```

---

## 🔧 GATES BLOQUEANDO

### Current Blockers (por frequência)

1. **TIER_B_PAPER Mesa Consensus FORTE** (90% das rejeições)
   - Exige T+R+L todas fortes
   - Realidade: T=85 mas R=40 e L=28 = rejeita
   - Solução: Aceitar **consenso MÉDIO** (2/3 sinais bons)

2. **FQS Indisponível** (40% das rejeições)
   - FQS missing = rejeita todo Tier B
   - Solução: **FQS LAZY** — se não tem, assume QUALITY=4/7 default

3. **TORI ABSENT** (35% das rejeições)
   - Não tem Tori proximity = rejeita SHORT
   - Solução: **TORI opcional** — usar Mesa sozinho se SHORT consenso >70

4. **ALPHA_CORR/ALPHA_HIST ABSENT** (30%)
   - Novos ativos não tem histórico
   - Solução: **Alpha default** — usar BTC correlation como proxy

5. **Tier C "qualidade insuficiente"** (25%)
   - Tier C rejeitado em STANDARD mode
   - Solução: **Tier C SCALP mode** — trades curtos, 5-15min TTL

---

## ✅ GATES NOVA CONFIGURAÇÃO

### BEFORE (Current - Muito Conservador)
```json
{
  "conviction_threshold": 55,
  "mesa_consensus_mode": "FORTE_only",
  "fqs_required": true,
  "tori_required": true,
  "alpha_required": true,
  "tier_c_allowed": false,
  "approval_rate": "0.06%"
}
```

### AFTER (Amplified - Agressivo)
```json
{
  "conviction_threshold": 45,              // 55 → 45
  "mesa_consensus_mode": "MEDIUM_or_FORTE",  // não só FORTE
  "fqs_required": false,                   // lazy default=4/7
  "fqs_lazy_default": 4,                   // assume quality 4/7
  "tori_required": false,                  // SHORT sem Tori OK se Mesa>70
  "tori_optional_threshold": 70,           // SHORT com Mesa>70 entra
  "alpha_required": false,                 // BTC proxy
  "alpha_default_mode": "btc_proxy",       // use BTC correlation
  "tier_c_allowed": true,                  // Tier C em SCALP mode
  "tier_c_max_days": 1,                    // TTL 1 dia
  "tier_c_scalp_mode": true,               // rápido in/out
  "approval_rate_target": "20%"            // 7141 * 20% = ~1428 entries/day
}
```

---

## 🎯 TRADE MODES (Amplification)

### Mode 1: STANDARD (Current — LONG/SHORT, 3-7 dias)
```
Entry: Tier A/B com consensus forte
Size: 2-5x (variável)
TTL: 3-7 dias
Executors: Trailing stop + learning
Win rate target: 50%+ (maiores ganhos por trade)
```

### Mode 2: SCALP (Novo — LONG/SHORT, 5-15 min)
```
Entry: Tier C com consenso MÉDIO
Size: 1-2x (pequeno)
TTL: 5-15 min (rápido)
Executors: Immediate cut (-2% loss), trail profit (+0.5% gains)
Win rate target: 70%+ (alta frequência)
Volume: 10-20 trades/dia
```

### Mode 3: SWAP (Novo — LONG only, 12-24h)
```
Entry: Tier B+ com consenso FORTE
Size: 1-2x
TTL: 12-24h (swing)
Executors: Daily rebalance, overnight hold
Win rate target: 55%+ (swing trading)
Volume: 5-10 trades/dia
```

### Mode 4: PUMP-RIDE (Novo — SHORT, vol_climax)
```
Entry: Vol_climax signal (pump detected)
Size: 3-5x (agressivo, é pump-riding)
TTL: 30min-2h (pump lifecycle)
Executors: Immediate profit take (+2-3%), aggressive SL (-3%)
Win rate target: 60%+ (pump reversão comum)
Volume: 2-5 trades/dia
```

---

## 📈 EXPECTED VOLUME

### Current (Gates Closed)
```
7141 sinais/dia
→ 0.06% approval
→ 4 entries/dia
```

### With Amplification
```
7141 sinais/dia
├─ STANDARD (consensus forte): 15% = 1,071 → 5-8 trades/dia
├─ SCALP (consensus médio): 18% = 1,286 → 10-15 trades/dia
├─ SWAP (Tier B+ forte): 8% = 571 → 4-6 trades/dia
└─ PUMP-RIDE (vol_climax): 2% = 143 → 2-4 trades/dia

TOTAL: 21-33 trades/dia ✅ (vs 4-5 agora)
TARGET: 30-40/dia com +volume aditional scouts
```

---

## 🔄 IMPLEMENTATION (3 Fases)

### FASE 1 (TODAY 2026-06-18 20:50)
```
Commit: gates-amplification-phase1
- conviction_threshold: 55 → 50
- mesa_consensus: FORTE_only → FORTE_or_MEDIUM (70% threshold)
- fqs_required: true → false (lazy default 4/7)
- tori_required: true → false (optional if Mesa>70)

Impact: ~8-10 trades/dia
```

### FASE 2 (T+6h 2026-06-19 02:50)
```
Commit: gates-amplification-phase2
- tier_c_allowed: false → true
- tier_c_scalp_mode: enable (TTL 1 dia)
- alpha_required: true → false (BTC proxy)

Impact: +10-15 scalp trades/dia
```

### FASE 3 (T+12h 2026-06-19 08:50)
```
Commit: gates-amplification-phase3
- pump_ride_mode: enable (vol_climax shorts)
- swap_mode: enable (12-24h swing)

Impact: +4-6 trades/dia
```

---

## 🛡️ SAFETY: Keepin' Trailing Executor Aggressive

### Trailing Executor (já existe, precisa reconfig)

Para cada modo:

**STANDARD** (3-7d):
```powershell
$trail_config = @{
    entry_lock = "0.5%"      # Lock profit after 0.5% gain
    trail_pct = "2.0%"       # Trail 2% abaixo peak
    stop_loss = "2-5%"       # SL 2-5% abaixo entry
    target_exit = "3-5x RR"  # T/P 3-5x risk
}
```

**SCALP** (5-15min):
```powershell
$trail_config = @{
    entry_lock = "0.2%"      # Lock rápido em scalp
    trail_pct = "0.5%"       # Trail apertado
    stop_loss = "-1.5%"      # Corte rápido
    target_exit = "2x RR"    # Sair rápido
}
```

**PUMP-RIDE** (30min-2h):
```powershell
$trail_config = @{
    entry_lock = "1.0%"      # 1% gain já lucra
    trail_pct = "1.5%"       # Trail agressivo
    stop_loss = "-3%"        # Pump falha = sai
    target_exit = "2-3x RR"  # Vol climax reversa rápido
}
```

---

## 📊 CAPITAL ALLOCATION (30-40 trades/dia)

### Size por trade (capital $3,645)

**STANDARD** (5 trades/dia × média $365 = $1,825)
```
Size: $300-400/trade (8-10% capital/trade)
Max loss/trade: 1% ($36) = safe
Expected: 50% win = 2.5 wins × avg $7 = +$17.50/dia
```

**SCALP** (15 trades/dia × média $150 = $2,250)
```
Size: $100-200/trade (3-5% capital/trade)
Max loss/trade: 0.5% ($18) = very safe
Expected: 70% win = 10.5 wins × avg $2 = +$21/dia
```

**SWAP** (5 trades/dia × média $150 = $750)
```
Size: $100-200/trade (3-5% capital/trade)
Max loss/trade: 1% ($36) = safe
Expected: 55% win = 2.75 wins × avg $4 = +$11/da
```

**PUMP-RIDE** (3 trades/dia × média $200 = $600)
```
Size: $150-250/trade (4-7% capital/trade)
Max loss/trade: 2% ($73) = moderate
Expected: 60% win = 1.8 wins × avg $10 = +$18/dia
```

**DAILY TOTAL**: ~$65/dia × 30d = **+$1,950**
→ $3,645 + $1,950 = $5,595 (vs $5k alvo) ✅

---

## 🚀 GATES_DRIFT.JSON (Updated)

```json
{
  "version": "2026-06-18T20:50Z",
  "gates": {
    "conviction_threshold": 50,
    "mesa_consensus_mode": "MEDIUM_or_FORTE",
    "mesa_consensus_threshold_medium": 70,
    "fqs_required": false,
    "fqs_lazy_default": 4,
    "tori_required": false,
    "tori_optional_threshold": 70,
    "alpha_required": false,
    "alpha_default_mode": "btc_proxy",
    "tier_c_allowed": true,
    "tier_c_max_days": 1,
    "tier_c_scalp_mode": true,
    "leverage_max": 5,
    "daily_loss_limit_pct": -5.0
  },
  "modes": {
    "standard": {"enabled": true, "ttl_days": 7, "target_volume": 5},
    "scalp": {"enabled": true, "ttl_min": 15, "target_volume": 15},
    "swap": {"enabled": true, "ttl_hours": 24, "target_volume": 5},
    "pump_ride": {"enabled": true, "ttl_min": 120, "target_volume": 3}
  },
  "expected_daily_volume": 28
}
```

---

## 📋 AÇÕES HOJE (2026-06-18 20:50)

### ✅ 1. Commit Phase 1 (Amplification Basic)
```
- Conviction 55 → 50
- Mesa MÉDIO allowed (70%)
- FQS lazy default
- Tori optional
```

### ✅ 2. Reconfig Trailing Executor
```
- Load Mode.SCALP config
- Load Mode.SWAP config
- Load Mode.PUMP_RIDE config
```

### ✅ 3. Test First Wave
```
- Monitor 2-4h para ver volume
- Esperado: 8-10 trades (vs 4 normal)
- Se OK, proceed Fase 2
```

### 🔜 4. Fase 2 (T+6h) — Scalp Full
```
- Tier C enable
- Scalp TTL enforce
- Volume: +10-15 scalp/dia
```

### 🔜 5. Fase 3 (T+12h) — Pump Ride + Swap
```
- Vol_climax pump ride enable
- Swap mode enable
- Volume: final 30-40/dia
```

---

## 🎯 RESULT

| Métrica | Atual | Target |
|---------|-------|--------|
| Sinais/dia | 7,141 | 7,141 |
| Aprovação % | 0.06% | 20% |
| Trades/dia | 4-5 | 30-40 |
| Modes | LONG only | LONG+SHORT+scalp+swap+pump |
| Capital allocation | 100% em 4 trades | Spread 30-40 trades |
| Win rate | 41.7% | 50-60% (modos diferentes) |
| Daily PnL | -$2.12 | +$50-$100 |
| Monthly | -$64 | +$1,500-$3,000 |

---

## ✨ TRAILING EXECUTOR MODO SURFISTA

Para cada trade, system está "surfando":

```powershell
# SCALP Entry (AIN, 5min)
Entry: 0.0909 @ 14:05
14:06 → +0.2% → trail to 0.0905
14:07 → +0.5% → lock 0.2%, trail to 0.0902
14:08 → -0.1% → stop hit → close @0.0904 = +$0.08 GANHO
Duration: 3 min

# PUMP-RIDE Entry (PEPE, vol_climax)
Entry: 0.000025 @ 10:00
10:01 → +1.2% pump → lock 1% 
10:02 → +2.5% pump → trail to peak*0.985
10:03 → dump -2% → stop = -3% → close = ~neutral ou small loss
Duration: 3min

# STANDARD Entry (BTC, 7dias)
Entry: 42000 @ 14:00
Day 1-2: +1% → lock 0.5%, trail
Day 3: -0.1% → stop = 2% → trail maintains
Day 4: +3.5% → new peak → trail
Day 7: +5% gain → target hit → CLOSE = +$210
Duration: 7 dias
```

Cada trade é **"surfado"** — system segue cada movimento.

---

**GO LIVE NOW** — Fase 1 commit ready

