# 🗺️ SHORT vol_climax Journey — Visual Timeline

```
2026-06-02 (NOW)
    ↓
    🔍 PHASE 1: OBSERVE + COLLECT (Days 1-14)
    ├─ gate: RSI≥80 + vol≥2.5x + ADX>60
    ├─ mode: OBSERVATION ONLY (no trades)
    ├─ target: 50+ signals
    └─ daily action: monitor (2 min)
    
    Expected signals/day: 1-3
    Total by 2026-06-09: 20-30
    Total by 2026-06-16: 40-50+
    
2026-06-16
    ↓
    📊 PHASE 2: VALIDATE + ANALYZE (Days 15-21)
    ├─ action: check each signal 24h later
    │          "price fell ≥1%?" → TRUE_POS or FALSE_POS
    ├─ target: ≥60% hit rate
    └─ output: validation_report.csv
    
    Validation example:
    ┌─────────────────────────────────────────┐
    │ BTCUSDT   | RSI=82 vol=2.8x ADX=68      │
    │ Next 24h: price fell 2.3% → TRUE_POS  ✅│
    │                                         │
    │ ETHUSDT   | RSI=81 vol=3.1x ADX=65      │
    │ Next 24h: price +1.5% → FALSE_POS     ❌│
    │                                         │
    │ Final: 38 TRUE_POS, 12 FALSE_POS       │
    │ Hit rate: 76% → READY FOR DEPLOY      │
    └─────────────────────────────────────────┘

2026-06-23
    ↓
    ⚙️ PHASE 3: PREPARE + WIRE (Days 22-23)
    ├─ action: test SHORT entry/exit logic (TDD)
    ├─ confirm: regime BEAR_STRONG detection
    ├─ verify: risk sizing ($30 per SHORT)
    └─ status: READY FOR DEPLOYMENT
    
    TDD requirements:
    ✅ lib_enhanced_short_entry.Tests.ps1 (15/15 GREEN)
    ✅ lib_short_execution.Tests.ps1 (12/12 GREEN)  
    ✅ short_capital_safety.Tests.ps1 (10/10 GREEN)

2026-06-24 onwards
    ↓
    🚀 PHASE 4: EXECUTE (when BEAR_STRONG detected)
    ├─ trigger: Get-HalvingPhase returns "BEAR_STRONG"
    ├─ mode: LIVE SHORT execution
    ├─ per-signal: $30 at risk, 1:5 R:R minimum
    └─ target: ≥50% win rate, <3% max drawdown
    
    First week metrics:
    ┌──────────────────────────────────────────┐
    │ Entries executed: 2-4 SHORTs            │
    │ Win rate: ≥50% (price falls ≥1%)       │
    │ False positives: ≤1                      │
    │ Max drawdown: <3%                        │
    │ Status: ✅ KEEP RUNNING                 │
    │         or ❌ BACK TO OBSERVATION       │
    └──────────────────────────────────────────┘
    
    If win rate <40% during BEAR_STRONG:
    → Rollback to observation
    → Adjust gate (raise RSI to 82, vol to 3x)
    → Collect another 30 signals
    → Revalidate

    If win rate ≥50%:
    → Continue execution
    → Iterate: maybe scale to 2% per trade
    → Track for next cycle
```

---

## 📈 Success Path (what "working great" looks like)

```
Week 1-2: Observation collecting
  Daily: 2-3 vol_climax signals appear in observations.csv
  ✅ Gate firing consistently
  ✅ Metrics stable (RSI 81-85, vol 2.6-3.2x, ADX 64-70)

Week 3: Validation
  Manual review: pick 50 signals → check 24h outcomes
  Result: 76% hit rate (38 TRUE_POS / 12 FALSE_POS)
  ✅ Exceeds 60% threshold → DEPLOY READY

Week 4+: Live execution
  BEAR_STRONG detected
  First SHORT: BTCUSDT RSI=82 vol=3.1x → enters SHORT
  Price falls 2.3% in 24h → exit at profit
  Win rate after 4 trades: 3/4 = 75%
  ✅ KEEP RUNNING → scale up or continue

Month 2+: Optimization
  Collect another cycle of signals
  Adjust parameters based on learnings
  Maybe lower to RSI=80 (catch earlier?)
  Or raise to RSI=82 (fewer false positives?)
```

---

## ⚠️ Failure Path (what could go wrong + recovery)

```
Scenario 1: No signals appearing
  Problem: 0 vol_climax signals in 7 days
  Cause: Gate too strict? Market too calm?
  Recovery:
    1. Lower RSI: 80 → 78
    2. Lower vol: 2.5x → 2.3x
    3. Backtest change first
    4. Re-deploy → observe for 3 more days

Scenario 2: Too many false positives
  Problem: Validation shows 30% hit rate (20 TRUE_POS / 45 FALSE_POS)
  Cause: Gate catching noise, not real exhaustion
  Recovery:
    1. Raise RSI: 80 → 82
    2. Raise vol: 2.5x → 3.0x
    3. Raise ADX: 60 → 65
    4. Collect 30 more signals with new gate
    5. Revalidate

Scenario 3: Live execution underperforms
  Problem: Only 1/5 SHORTs winning (20% win rate)
  Cause: Gate validated at 60% but market conditions changed
  Recovery:
    1. Immediately: $env:SHORT_VOL_CLIMAX_LIVE = 0 (pause execution)
    2. Active SHORTs stay open (stop losses protect)
    3. Investigate: Did market regime shift? Gate miscalibrated?
    4. Collect new signals in current regime
    5. Revalidate before re-deploying

Scenario 4: System error (gate function breaks)
  Problem: scan_master.ps1 crashes with "Test-VolClimaxGate not found"
  Recovery:
    1. Restart scan_master.ps1
    2. Verify lib_vol_climax_gate.ps1 loaded in runspace
    3. Check logs for actual error
    4. Fix, redeploy
    5. Resume observation collection
```

---

## 🎯 Key Checkpoints

### ✅ Checkpoint 1: 2026-06-09 (After 1 week observation)
```
Must have: ≥20 signals
If YES  → Continue to week 2
If NO   → Debug gate (signals not triggering)
        → Check scan_master.ps1 running
        → Verify market has volatility (RSI hitting 80+)
```

### ✅ Checkpoint 2: 2026-06-16 (After validation)
```
Must have: ≥60% hit rate
If YES  → Proceed to deployment prep
If NO   → Adjust gate parameters
        → Collect another 30 signals
        → Revalidate
```

### ✅ Checkpoint 3: 2026-06-23 (Deployment readiness)
```
Must pass: All TDD 100% GREEN
If YES  → Ready for LIVE SHORT
If NO   → Fix broken tests first
```

### ✅ Checkpoint 4: First week of BEAR_STRONG
```
Must have: ≥50% win rate
If YES  → Continue & optimize
If NO   → Rollback to observation
        → Investigate cause
        → Retry when conditions improve
```

---

## 🔄 Continuous Improvement (after initial deploy)

Every 4 weeks:
1. Review 50+ recent SHORT vol_climax signals
2. Check hit rate still ≥60% (validation)
3. Adjust RSI/vol/ADX thresholds if drifting
4. Collect new calibration data
5. Update gate parameters (if needed)

Example iteration:
```
Iteration 1 (2026-06-23): RSI≥80, vol≥2.5x, ADX>60 → 65% hit rate ✅
Iteration 2 (2026-07-21): RSI≥82, vol≥2.8x, ADX>65 → 72% hit rate ✅✅
Iteration 3 (2026-08-18): RSI≥82, vol≥3.0x, ADX>70 → 80% hit rate ✅✅✅
```

---

## 📞 Support

**Question:** "Is 50+ signals enough to deploy?"  
**Answer:** No. 50+ signals → validate them (check outcomes) → 60%+ hit rate → deploy.

**Question:** "What if market stays BEAR_WEAK forever?"  
**Answer:** Keep collecting signals. Deploy happens when regime changes to BEAR_STRONG. Until then: pure observation.

**Question:** "Can I manually trigger SHORT even in BEAR_WEAK?"  
**Answer:** No. Regime gate is fail-closed. Only BEAR_STRONG = execute. Otherwise = observe.

**Question:** "What if I want to test LIVE execution before BEAR_STRONG?"  
**Answer:** Use paper trading mode: orders sent but not filled. Or set: `$env:OVERRIDE_REGIME="BEAR_STRONG"` (test only, not production).

---

## 🎬 Next Step

1. **This week:** Monitor observations growing (2-3/day target)
2. **Next Monday:** Run `weekly_metrics_faro_short.ps1` → check growth
3. **2026-06-16:** Start validation if ≥50 signals collected
4. **2026-06-23:** Prep deployment (TDD + risk sizing)
5. **2026-06-24+:** Execute when BEAR_STRONG arrives

---

**Timeline:** 22 days from now (2026-06-02 → 2026-06-24)  
**Your work:** ~15 min/week (2 min daily + 10 min weekly check)  
**Potential impact:** $150-500+ per SHORT cycle (if hit rate ≥60%)

