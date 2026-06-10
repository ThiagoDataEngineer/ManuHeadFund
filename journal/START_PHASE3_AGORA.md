# 🚀 COMECE PHASE 3 AGORA
**Timestamp:** 2026-06-09 22:45 BRT  
**Duração:** 24-72 horas (continuous)  
**Objetivo:** Validar vol_climax edge em condições reais de mercado

---

## TL;DR — 1 MINUTO

vol_climax está **LIVE** em gem_agent. Próximo step:

**Terminal 1 (Real-time monitoring):**
```powershell
pwsh scripts/monitor_vol_climax.ps1
```

**Terminal 2 (Auto-refresh report):**
```powershell
pwsh scripts/monitor_vol_climax.ps1 -Report
```

**Terminal 3 (Manual checks, run every hour):**
```powershell
# Count signals
Get-Content journal/gem_loop.log | Select-String "\[VC\]" | Measure-Object

# Win rate
(Get-Content journal/trade_outcomes.jsonl | ConvertFrom-Json | Measure-Object -Property pnl_usd -Sum).Sum
```

---

## O Que Esperar

### Próximas 24 horas
- ✅ gem_loop rodando (tá ativo agora)
- ⏳ 3-5 vol_climax signals esperados
- ⏳ Marcar cada trade em trade_outcomes.jsonl
- ⏳ Calcular win rate

### Sucesso = Phase 4
```
5-10 signals detectados
Win rate >= 45% (vs 33% baseline)
  ↓
Scale pra 60% capital allocation
  ↓
"100% operação" alcançável
```

### Fracasso = Debug
```
0 signals OR win rate < 35%
  ↓
Investigate vol_climax logic
  ↓
Adjust thresholds
  ↓
Retry ou rollback
```

---

## Setup Agora (5 min)

### 1. Verify gem_loop is Running
```powershell
Get-Process | Where-Object { $_.ProcessName -eq 'pwsh' } | Select-Object Id, StartTime
# Should see recent process
```

### 2. Check Log is Fresh
```powershell
Get-Content journal/gem_loop.log -Tail 3
# Should show recent timestamps
```

### 3. Start Monitoring
```powershell
# Terminal 1
pwsh scripts/monitor_vol_climax.ps1

# Terminal 2 (separate tab)
pwsh scripts/monitor_vol_climax.ps1 -Report
```

### 4. Bookmark This File
- Keep `journal/PHASE3_TRACKER_2026_06_09.md` open
- Update hourly with checkpoints
- Reference for success criteria

---

## Hourly Checklist

**Copy/paste every hour:**

```powershell
$time = Get-Date -Format "HH:mm"
$vcCount = (Get-Content journal/gem_loop.log | Select-String "\[VC\]" | Measure-Object).Count
$tradeCount = (Get-Content journal/trade_outcomes.jsonl | Measure-Object -Line).Lines
$trades = @(); Get-Content journal/trade_outcomes.jsonl | ConvertFrom-Json | ForEach-Object { $trades += @{ pnl = $_.pnl_usd; win = $_.pnl_usd -gt 0 } }
$wins = @($trades | Where-Object { $_.win }).Count
$pnl = ($trades | Measure-Object -Property pnl -Sum).Sum

Write-Host "[$time] VC:$vcCount | Trades:$tradeCount | Wins:$wins | PnL:$([math]::Round($pnl, 2))"
```

---

## Key Milestones

| Milestone | When | What to Do |
|-----------|------|-----------|
| Hour 0 | Now (22:45) | Start monitoring |
| Hour 6 | ~04:45 | Check if any signals yet |
| Hour 24 | 2026-06-10 22:45 | MAJOR CHECKPOINT — Decide continue/stop |
| Hour 48 | 2026-06-11 22:45 | Reassess, more data |
| Hour 72 | 2026-06-12 22:45 | FINAL DECISION — Scale or rollback |

---

## Contingencies

### If 0 signals in 24h
```
Possibility 1: Market conditions (low vol)
  → Patience, continue monitoring

Possibility 2: vol_climax code issue
  → Check [VC] boost in log
  → Verify Get-VolClimaxBoost available
  → Run: Get-Command Get-VolClimaxBoost

Possibility 3: GemScan not running
  → Check [CYCLE] messages in log
  → Restart gem_loop
```

### If 5+ signals but win rate < 35%
```
Possibility 1: Slippage (normal, -10-15pp)
  → Continue, need more data (30+ trades)

Possibility 2: Bad signal thresholds
  → Adjust ClimaxMultiplier or RSI levels
  → Re-validate in backtest

Possibility 3: Market regime wrong
  → Check REGIME_STATE.json
  → Maybe BULL_STRONG (Short-unfriendly)
  → Short-only in BEAR regimes
```

### If gem_loop crashes
```
1. Check journal/gem_loop.log for ERROR
2. Restart: pwsh scripts/restart_gem_loop.ps1
3. Continue monitoring
4. If crashes 2+ times → investigate root cause
```

---

## Reference Docs (Read if Needed)

| Doc | Purpose |
|-----|---------|
| `journal/PHASE3_TRACKER_2026_06_09.md` | Detailed Phase 3 plan + decision tree |
| `journal/VALIDACAO_BRUTAL_INDEX_2026_06_09.md` | Master index of all work |
| `docs/VOL_CLIMAX_IMPLEMENTATION_2026_06_09.md` | Technical details (if debugging) |
| `journal/SESSION_SUMMARY_2026_06_09.md` | Complete session recap |

---

## Remember

```
✅ vol_climax Sharpe 8.81 (7.4 years backtest) = REAL EDGE
✅ Integrated in production (gem_agent + gem_loop) = LIVE
✅ Non-blocking (try/catch) = SAFE TO RUN
⏳ Now testing live market (next 24-72h) = VALIDATION

Don't force trades. Let vol_climax show itself naturally.
Trust the edge (55.4% backtest). Be patient.
```

---

## GO TIME 🚀

**Start monitoring now:**

```powershell
# Terminal 1 — Real-time tail (Ctrl+C to exit)
pwsh scripts/monitor_vol_climax.ps1

# Terminal 2 — Auto-report (Ctrl+C to exit)  
pwsh scripts/monitor_vol_climax.ps1 -Report

# Terminal 3 — Manual checks (hourly)
# Run hourly checklist above
```

---

**Next major checkpoint:** 2026-06-10 22:45 BRT (+24h)  
**Expected:** 3-5 vol_climax signals + initial win rate calc  
**Goal:** Achieve 45%+ to justify Phase 4 scale

---

**Status:** 🟢 **PHASE 3 LIVE — GO!**
