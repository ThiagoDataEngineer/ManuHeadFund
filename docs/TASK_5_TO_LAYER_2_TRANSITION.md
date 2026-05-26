# Task 5 → Layer 2 Transition Plan

**Status:** ✅ Task 5 (Layer 1) COMPLETE — Ready for 48h Paper Validation  
**Date:** 2026-05-25  
**Next Phase:** Layer 2 (Mentor Reflection) — Starts 2026-05-27 (post-validation)

---

## 📋 Task 5 Deliverables Checklist

### Code
- ✅ `agents/lib_trailing_adaptive.ps1` (372 lines, 3 functions)
- ✅ `scripts/scan_master.ps1` (modified line 75 + 540)
- ✅ `scripts/collect_paper_metrics.ps1` (NEW — metrics collector)
- ✅ All legacy functions coexist (fallback available)

### Tests
- ✅ `tests/lib_trailing_adaptive.Tests.ps1` (22/22 GREEN)
- ✅ `tests/lib_trailing_adaptive_integration.Tests.ps1` (15/15 GREEN)
- ✅ **37/37 TOTAL** (0 failures, 0 warnings)

### Documentation
- ✅ `docs/TRAILING_ADAPTIVE_TDD.md` (Layer 1 design + algorithm)
- ✅ `docs/TRAILING_ADAPTIVE_INTEGRATION.md` (integration guide)
- ✅ `docs/TASK_5_COMPLETION_SUMMARY.md` (exec summary)
- ✅ `docs/PILAR_1_LAYERS_2_TO_5_ROADMAP.md` (4-week plan)
- ✅ `docs/48H_PAPER_VALIDATION_GUIDE.md` (validation playbook)
- ✅ `docs/TASK_5_TO_LAYER_2_TRANSITION.md` (this file)

### Bugs Fixed
- ✅ Duplicate `-Verbose` parameter
- ✅ Fase 3 stop travado (Max logic)
- ✅ Test expectation mismatch (phase 3 calculation)

---

## 🚀 How to Start 48h Paper Validation

### Quick Start (5 minutes)

```powershell
# Terminal 1: Start paper loop
cd c:\Users\thiag\Coinex_AI_USER_API\scripts
.\scan_master.ps1 -SkipOrchestrator

# Terminal 2: Monitor (new PowerShell window)
cd c:\Users\thiag\Coinex_AI_USER_API
Get-Content .\journal\trades.csv -Wait | Select-Object -Last 3

# Terminal 3: Collect metrics (after 48h, or on-demand)
.\scripts\collect_paper_metrics.ps1 -Verbose
```

### What to Expect

| Metric | Expected | Range |
|--------|----------|-------|
| Trades | 15-25 | 10-30 |
| Win Rate | 65-70% | >60% (pass) |
| Stops Updated | 20-35 | >10 (pass) |
| Crashes | 0 | 0 (must) |
| Phase Dist | 30/25/15/20% | Balanced |

---

## 📊 Paper Validation Timeline

```
2026-05-25 14:00  → Start (Hour 0)
2026-05-25 20:00  → First metrics batch (Hour 6)
2026-05-26 02:00  → Metrics batch 2 (Hour 12)
2026-05-26 14:00  → Metrics batch 3 (Hour 24)
2026-05-27 02:00  → Metrics batch 4 (Hour 36)
2026-05-27 14:00  → **FINAL ANALYSIS** (Hour 48)
```

**After Final Analysis:**
- ✅ If PASS → Proceed to Layer 2 immediately
- ⚠️ If MARGINAL → Tune config, run 24h more
- ❌ If FAIL → Debug, fix, retest

---

## 🎯 Success Criteria (Layer 1)

### Blocking (Must Have)
```
[ ] 0 crashes in 48h
[ ] Win rate >= 60%
[ ] >= 10 trades executed
[ ] >= 5 stop updates visible
[ ] No stuck stops (fases transitioning)
```

### Target (Should Have)
```
[ ] Win rate >= 65%
[ ] Peak persistence visible
[ ] Regime detection working
[ ] Buffer variance observed
```

### Stretch (Nice to Have)
```
[ ] Win rate >= 70%
[ ] 0 false alerts
[ ] <0.3 stops/trade
```

---

## 📈 Metrics to Collect

After each 6-hour cycle, run:

```powershell
.\scripts\collect_paper_metrics.ps1 `
  -StartTime "2026-05-25 14:00" `
  -EndTime "2026-05-25 20:00" `
  -OutputDir ".\metrics\batch_1" `
  -Verbose
```

**Key metrics in output JSON:**
- `performance.win_rate` — Actual vs 65% target
- `trailing.total_updates` — Stops adapting?
- `trailing.by_regime` — Regime distribution
- `phases` — Phase 0/1/2/3 split
- `trades` — Individual trade details

---

## 🔄 If Validation Succeeds (Most Likely)

### Day 1 (2026-05-27)
- [ ] Analyze final metrics (1h)
- [ ] Confirm win_rate >= 65% (pass condition)
- [ ] Archive results to `metrics/LAYER_1_FINAL.json`
- [ ] Update summary doc with actual numbers

### Day 2-3 (2026-05-28 to 2026-05-29)
- [ ] **Start Layer 2 (Mentor Reflection) TDD**
  - Create test file: `tests/mentor_review.Tests.ps1`
  - Design: 6h checkpoint detection
  - Tests: early warning detection, regime shift, tight stop logic
- [ ] **Layer 2 Implementation** (1-1.5 days)
  - `agents/mentor_review.ps1` (wrapper)
  - `agents/lib_mentor_reflection.ps1` (core logic)
  - Integration into `scan_master.ps1`

### Day 4 (2026-05-30)
- [ ] **Layer 2 Paper Validation (24h)**
  - Run: `.\scan_master.ps1 -Layers 1,2`
  - Monitor: Mentor reviews per trade
  - Collect metrics: `collect_paper_metrics.ps1`

**Timeline Summary:**
- 2026-05-27: Layer 1 final validation ✅
- 2026-05-30: Layer 2 ready for paper ✅
- 2026-06-02: Layer 3 (Kelly) starts
- 2026-06-07: Layer 4 (Tori) starts
- 2026-06-12: Layer 5 (Moon) starts
- 2026-06-24: All 5 layers validated, ready for LIVE

---

## ⚠️ If Validation Needs Tuning

### Marginal (Win Rate 60-65%)

**Root Cause:**
- Could be: ATR placeholder, regime detection, buffer multipliers

**Fix (same day):**
1. Check which regime most common during 48h
2. If mostly BULL_STRONG: lower multiplier 0.75 → 0.65
3. If mostly BEAR_STRONG: raise multiplier 1.5 → 1.7
4. Retest 12h with tuned config

**Expected Outcome:** +3-5pp improvement (should hit 65%+)

---

### Significant Issue (Win Rate <60%)

**Root Cause Analysis:**
1. Are stops too tight? (can't reach targets)
2. Are stops too loose? (hit too often)
3. Is regime detection broken? (always SIDEWAYS?)
4. Is ATR calculation wrong? (not adapting?)

**Debug Steps:**
```powershell
# 1. Check regime detection
Get-MacroContext | fl

# 2. Check stop buffer values
Get-TrailingPositions | select market, entry, target, stop, phase

# 3. Run unit tests
Invoke-Pester .\tests\lib_trailing_adaptive.Tests.ps1

# 4. Debug specific position
$pos = [PSCustomObject]@{ entry=100; target=110; stop=95; peak=100; phase=0 }
Get-TrailingNewStopAdaptive -Pos $pos -CurrentPrice 103
```

**Fix (1-2 days):**
- Identify issue (which component failing?)
- Fix implementation or config
- Re-run tests (all 37 should still pass)
- Validation 24h (not full 48h)

---

## 🧪 Red Flags (Rollback Condition)

If ANY of these occur:
- ❌ Crash/exception every cycle
- ❌ Memory leak (PS memory grows unbounded)
- ❌ Exchange order fails repeatedly
- ❌ 0 trades executed (gate not opening)

**Action:**
1. Stop scan_master immediately
2. Revert to git last-known-good
3. Debug in isolated test environment
4. Do NOT proceed to Layer 2 until fixed

---

## 📁 File Structure After Task 5

```
Coinex_AI_USER_API/
  agents/
    ├─ lib_trailing.ps1                          (legacy)
    ├─ lib_trailing_adaptive.ps1 ✨              (NEW Layer 1)
    └─ ...
  
  scripts/
    ├─ scan_master.ps1                           (modified)
    └─ collect_paper_metrics.ps1 ✨              (NEW)
  
  tests/
    ├─ lib_trailing_adaptive.Tests.ps1 ✨        (22 tests)
    ├─ lib_trailing_adaptive_integration.Tests.ps1 ✨  (15 tests)
    └─ ...
  
  docs/
    ├─ TRAILING_ADAPTIVE_TDD.md ✨
    ├─ TRAILING_ADAPTIVE_INTEGRATION.md ✨
    ├─ TASK_5_COMPLETION_SUMMARY.md ✨
    ├─ PILAR_1_LAYERS_2_TO_5_ROADMAP.md ✨
    ├─ 48H_PAPER_VALIDATION_GUIDE.md ✨
    └─ TASK_5_TO_LAYER_2_TRANSITION.md ✨       (this file)
  
  metrics/
    └─ LAYER_1_FINAL_20260527.json ✨           (after validation)
```

---

## 🎓 Lessons Learned (For Layer 2+)

### What Worked Well
1. **TDD first:** Red → Green → Refactor caught bugs early
2. **Integration tests:** Validated coexistence with legacy
3. **Incremental validation:** Tests before production changes
4. **Documentation:** Design + algorithm + examples clear

### Apply to Layer 2
1. **Create test file first** (Layer 2 tests before impl)
2. **Test integration** (Layer 2 + Layer 1 together)
3. **Paper validate** (24h minimum before moving to Layer 3)
4. **Document as you code** (comments, design patterns)

---

## ✅ Go/No-Go Decision Point

**After 48h metrics collection (2026-05-27 14:00):**

```
Decision Tree:

win_rate >= 65%
  ├─ YES → ✅ GO to Layer 2
  │         (start Mentor Reflection TDD immediately)
  │
  └─ NO (60-65%) → ⚠️ CONDITIONAL GO
                   (tune config, run 24h more)
                   
win_rate < 60%
  ├─ Crashes/errors → ❌ NO-GO (debug first)
  │
  └─ Bad win rate → ⚠️ NO-GO (investigate root cause)
                    (could be: ATR, regime, buffer multipliers)
```

---

## 📞 Contact Points

**If issues during validation:**

1. **Code/function questions:**
   - Check: `docs/TRAILING_ADAPTIVE_TDD.md` (design)
   - Check: `agents/lib_trailing_adaptive.ps1` (implementation)
   - Run: unit tests (`./tests/lib_trailing_adaptive.Tests.ps1`)

2. **Integration questions:**
   - Check: `docs/TRAILING_ADAPTIVE_INTEGRATION.md`
   - Check: `scripts/scan_master.ps1` (lines 75, 540)
   - Run: integration tests (`./tests/lib_trailing_adaptive_integration.Tests.ps1`)

3. **Metrics/validation questions:**
   - Check: `docs/48H_PAPER_VALIDATION_GUIDE.md` (troubleshooting section)
   - Run: `./scripts/collect_paper_metrics.ps1 -Verbose`
   - Review output JSON structure

---

## 🚀 Ready?

### Before Starting Paper Validation

- [ ] Review `docs/48H_PAPER_VALIDATION_GUIDE.md` (15 min read)
- [ ] Verify all 37 tests GREEN (5 min)
  ```powershell
  Invoke-Pester .\tests\lib_trailing_adaptive.Tests.ps1
  Invoke-Pester .\tests\lib_trailing_adaptive_integration.Tests.ps1
  ```
- [ ] Backup current trades.csv (for clean slate)
  ```powershell
  Copy-Item .\journal\trades.csv .\journal\trades.csv.backup.pre_layer1
  ```
- [ ] Verify scan_master integration (2 min)
  ```powershell
  Select-String "Update-TrailingStopsAdaptive" .\scripts\scan_master.ps1
  ```
- [ ] Create metrics output directory
  ```powershell
  mkdir .\metrics -Force
  ```

### Start Paper Loop

```powershell
cd c:\Users\thiag\Coinex_AI_USER_API\scripts
.\scan_master.ps1 -SkipOrchestrator -Verbose

# Monitor in separate terminal
Get-Content ..\journal\trades.csv -Tail 5 -Wait
```

### After 48 Hours

```powershell
# Collect final metrics
.\collect_paper_metrics.ps1 `
  -StartTime "2026-05-25 14:00" `
  -EndTime "2026-05-27 14:00" `
  -OutputDir "..\metrics\LAYER_1_FINAL" `
  -Verbose

# Review results
Get-Content "..\metrics\LAYER_1_FINAL\paper_metrics_*.json" | ConvertFrom-Json | fl
```

---

## 📅 Next Review Date

**2026-05-27 15:00** — Task 5 Go/No-Go Decision

If ✅ GO → Start Layer 2 TDD immediately  
If ⚠️ CONDITIONAL → Tune and re-validate  
If ❌ NO-GO → Debug and escalate

---

**Status:** ✅ TASK 5 COMPLETE — ALL SYSTEMS GO FOR LAYER 1 PAPER VALIDATION

**Estimated Live Date (all 5 layers):** 2026-06-24  
**Current:** 2026-05-25 (Day 0 of 30)

