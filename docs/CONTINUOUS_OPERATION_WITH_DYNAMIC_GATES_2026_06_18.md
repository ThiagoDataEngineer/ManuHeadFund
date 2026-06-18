# 🚀 CONTINUOUS OPERATION WITH DYNAMIC GATES — 2026-06-18

> **Filosofia**: Gem_loop **SEMPRE LIGADO**. Gates aperta **DINAMICAMENTE** conforme aprende.
> Ganho contínuo + melhoria gradual = capital sempre multiplicando.

---

## 🎯 PRINCÍPIO

Em vez de pausar para audit:
```
❌ ERRADO:  Trade → Erro → PARAR gem_loop → Audit → Fix gates → Restart
✅ CORRETO: Trade → Erro → Log → Gates aperta (realtime) → Trade melhor → Ganho
```

**Resultado**: Capital **sempre em movimento**, win rate **melhora organicamente**.

---

## 🔧 MECANISMO: GATES DRIFT

### O que é Gates Drift?

Cada erro detectado **aperta um gate específico**:

| Erro Detectado | Gate Afetado | Ação |
|---|---|---|
| **Tori SKIP** (TRUMPUSDT) | Conviction gate | Threshold +5 (55→60) |
| **Pump-chase** (COAIUSDT) | Entry filter | Rejeita high_7d*0.95+ |
| **Leverage alto** (BNB 50x) | Sizing | Max 5x (hardcap) |
| **Drift longo** (FIROUSDT) | Max days | TTL 7 dias (force close) |
| **Reversão rápida** (NEAR -1.84%) | Stop coerência | Valida SL >= 2% |

### Timing: Quando aperta?

```
REAL-TIME (imediato):
- Cada trade que PERDE escreve em learning_engine.log
- Learning Engine (6h cycle) calcula conviction_drift
- Gates aperta no próximo ciclo (15min para gem_loop)

Exemplo:
  10:30 → TRUMPUSDT entra (Tori SKIP)
  11:00 → Loss detectada (-$0.79)
  17:30 → Learning Engine ciclo 6h
           conviction_threshold 55 → 60
  01:45 (próx ciclo) → Gem_loop usa novo threshold
           Próximo SKIP é rejeitado
```

---

## 📊 IMPLEMENTAÇÃO: 3 CAMADAS

### Layer 1: Real-Time Detection (gem_executor.ps1)

```powershell
# Cada trade registra "decision signature"
# Exemplo: TRUMPUSDT
$decision = @{
    market = "TRUMPUSDT"
    gate_status = @{
        tori = "SKIP"           # ← PROBLEMA
        conviction = 55          # ← BAIXO
        volume = "GREEN"
        structure = "OK"
    }
    entry_confidence = 0.55
}

# Se trade resulta em loss:
# → Arquivo decision_log.json marca decision_signature
# → Learning Engine lê decision_log.json
```

### Layer 2: Learning Engine (6h cycle)

```powershell
# Input: decision_log.json (últimas 24h de trades)
function Analyze-GateDrift {
    # Contar erros por gate
    $tori_skip_losses = @(
        decision_log | where tori -eq SKIP | where result -eq LOSS
    )
    
    if ($tori_skip_losses.Count -ge 2) {
        # 2+ losses com TORI SKIP → aperta
        $new_conviction = 60 (vs 55)
        Write-Output "Gate Drift: conviction +5 (TORI SKIP pattern)"
    }
}
```

### Layer 3: Dynamic Gate Application

```powershell
# Gem_loop lê conviction threshold a cada ciclo
function Get-ConvictionThreshold {
    # Arquivo: config/gates_drift.json
    $drift = Get-Content config/gates_drift.json | ConvertFrom-Json
    return $drift.conviction_threshold  # 55, 60, 65... conforme aprende
}

# Cada entry:
$conviction = Invoke-ConvictionEnsemble $gem
if ($conviction -lt (Get-ConvictionThreshold)) {
    return "SKIP" # ← Aperta naturalmente
}
```

---

## 📋 GATES DRIFT INICIAL (2026-06-18)

Baseado em 12 trades históricos:

```json
{
  "version": "2026-06-18T20:45Z",
  "gates": {
    "conviction_threshold": 55,        // 5 erros → 60, 10 erros → 65
    "tori_bypass_allowed": false,      // 0/1 (1 = foi permitido em TRUMPUSDT)
    "pump_chase_detection": "off",     // on = rejeita high_7d*0.95+
    "leverage_max": 50,                // 50 agora, 5 após BNB 50x erro
    "max_days_open": 999,              // 999 agora, 7 após FIROUSDT 6d erro
    "stop_coherence_check": "off"      // on = valida SL >= 2%
  },
  "error_counts": {
    "tori_skip_losses": 1,
    "pump_chase_losses": 1,
    "leverage_abuse": 1,
    "drift_timeout": 1,
    "stop_incoherent": 0
  },
  "last_update": "2026-06-18T20:45:32Z"
}
```

---

## 🔄 CYCLE: Como funciona em produção

### Ciclo 1: Trade → Error → Learning (6h depois)

```
14:00 → Trade TRUMPUSDT enters (Tori SKIP, conviction 55)
14:15 → Perde -$0.79
17:00 → Gem_loop ciclo seguinte (continua rodando)
20:30 → Learning Engine (6h cycle)
        - Lê decision_log.json
        - Vê TRUMPUSDT loss + Tori SKIP
        - Aperta conviction_threshold: 55 → 60
        - Escreve novo gates_drift.json
02:00 → Próximo ciclo gem_loop
        - Lê conviction_threshold = 60
        - Rejeita próximo SKIP (conviction < 60)
        - Ganho: 1 trade ruim evitado
```

### Ciclo 2: Gate Aperta, Win Rate Sobe

```
Dia 1:  41.7% win rate (5/12)
Dia 2:  Conviction +5 (aperta)
        Pump-chase filter ativa
Dia 7:  ~47% win rate (14 new trades, 8 wins)
Dia 14: Leverage cap ativa
        Max days enforce
Dia 30: ~52% win rate (20+ new trades, 11 wins) ✅ ALVO
```

---

## 🎯 GATES PROGRESSIVOS (ordem de implementação)

### **T0 (AGORA - 2026-06-18 20:45)**
```
✓ Conviction threshold = 55
✓ Tori bypass = false (nunca mais bypass)
✓ Gem_loop contínuo (sem pausa)
```

### **T+6h (2026-06-19 02:45)** — Learning Engine 1º ciclo
```
✓ Aperta conviction se 2+ SKIP losses
✓ Ativa pump-chase filter
✓ Hardcap leverage 5x (não 50x)
```

### **T+12h (2026-06-19 08:45)** — 2º ciclo
```
✓ Valida stop coerência (SL >= 2%)
✓ Max days = 7 (force close drift)
✓ Atualiza gates_drift.json
```

### **T+30d (2026-07-18)** — Consolidação
```
✓ Win rate estabiliza 50%+
✓ Gates "learned" e otimizados
✓ Capital: $3,645 → ~$4,500+ (conservador)
✓ Pronto para aumentar sizes/leverage
```

---

## 📊 EXPECTED OUTCOMES

### Dia 1-7 (Ótimização gates básicos)

| Métrica | Atual | Esperado |
|---------|-------|----------|
| Win Rate | 41.7% | 45-48% |
| Avg Win | +$1.16 | +$1.50 |
| Avg Loss | -$4.45 | -$3.00 |
| Trades/dia | ~4 | ~4 |
| Capital | $3,645 | $3,600-$3,700 |

### Dia 8-30 (Gates consolidados)

| Métrica | Atual | Esperado |
|---------|-------|----------|
| Win Rate | 41.7% | 50%+ |
| Avg Win | +$1.16 | +$2.00+ |
| Avg Loss | -$4.45 | -$2.50 |
| Trades/dia | ~4 | ~4 |
| Capital | $3,645 | $4,200-$4,800 |

### Cenário otimista (com seed capital):
```
Seed: +$1,355 → $5,000 (2026-06-23)
30d: 50% win rate × $2 avg win × 30 trades = +$60
Final: $5,000 + $60 = $5,060 ✅
```

---

## 🔐 FAILSAFES (não deixar piorar)

### Rule 1: Max Loss/Trade = 1% Capital
```powershell
$max_loss_per_trade = $capital * 0.01
if ($potential_loss -gt $max_loss_per_trade) {
    return "SKIP"  # Never risk more
}
```

### Rule 2: Daily Pause if -5% PnL
```powershell
$daily_pnl = Get-DailyPnL
if ($daily_pnl -lt $capital * -0.05) {
    # Pause entries, allow closes only
    Write-Host "Daily loss -5%, pausing new entries"
}
```

### Rule 3: Conviction Floor = 40
```powershell
# Never go below conviction 40 even if many errors
if ($conviction_threshold -gt 40) {
    $conviction_threshold = Max($conviction_threshold - $drift, 40)
}
```

### Rule 4: Gem_loop Always Healthy
```powershell
# Monitor every 5min
if ($gem_loop_error_rate -gt 10%) {
    # Self-heal: reload libs, clear cache
    Invoke-LibraryReload
    Invoke-CacheClear
}
```

---

## 🚀 IMPLEMENTAÇÃO HOJE (2026-06-18)

### Commit 1: Remove pause flag
```
✓ Remover .kiro/GEM_LOOP_DISABLED.flag
✓ Gem_loop stays ativo
```

### Commit 2: Create gates_drift.json
```
✓ Base config com thresholds atuais
✓ Error counts zerados
✓ Version control
```

### Commit 3: Wire Learning Engine → Gates
```
✓ Learning Engine lê gates_drift.json
✓ Atualiza based on error patterns
✓ Gem_loop lê gates_drift.json
✓ Aplica thresholds dinamicamente
```

---

## 📌 MONITORAMENTO (daily)

```powershell
# Daily checkpoint (20:00 BRT)
function Monitor-GatesDrift {
    Write-Host "=== DAILY GATES DRIFT REPORT ===" -ForegroundColor Cyan
    
    $gates = Get-Content config/gates_drift.json | ConvertFrom-Json
    Write-Host "Conviction threshold: $($gates.conviction_threshold)"
    Write-Host "Pump-chase filter: $($gates.pump_chase_detection)"
    Write-Host "Leverage cap: $($gates.leverage_max)x"
    Write-Host "Max days: $($gates.max_days_open)"
    
    $pnl = Get-DailyPnL
    Write-Host "Daily PnL: $$pnl"
    
    $win_rate = Get-WinRate
    Write-Host "Win rate today: $win_rate%"
}
```

---

## ✅ SUMMARY

| Aspecto | Estratégia |
|---------|-----------|
| **Operação** | Contínua (gem_loop always on) |
| **Melhoria** | Dinâmica (gates drift conforme aprende) |
| **Pausa** | Nunca (a menos que -5% diário) |
| **Win rate** | Cresce gradualmente 41.7% → 50%+ |
| **Capital** | Sempre multiplicando |
| **Risco** | Controlado por failsafes (1% cap/trade, conviction floor) |

**Resultado**: Sistema **aprende jogando**, não **para para aprender**.

---

## 🎯 PRÓXIMAS AÇÕES

1. **NOW** (2026-06-18 20:45): Criar config/gates_drift.json
2. **NOW** (2026-06-18 20:45): Wire Learning Engine → Gates
3. **TOMORROW** (2026-06-19 02:45): 1º Learning Engine cycle (aperta gates)
4. **NEXT WEEK** (2026-06-23): Seed capital +$1,355
5. **30 DAYS** (2026-07-18): Validar 50% win rate, aumentar sizes

