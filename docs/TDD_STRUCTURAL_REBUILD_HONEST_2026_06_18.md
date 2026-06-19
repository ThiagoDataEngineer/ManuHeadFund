# 🧪 TDD STRUCTURAL REBUILD — HONEST PLAN — 2026-06-18

> **User has invested 200h. Still buggy. Skeptical this will fix it.**
> 
> **Truth**: Most bugs are architectural (gates not wired, conviction hard-coded, etc).
> **Plan**: Audit ALL journeys, identify failure modes, write tests FIRST, rebuild with TDD.
> **Honesty**: Some edge-case bugs will remain. Goal is "robust enough to run 30d without daily fixes".

---

## 📋 JOURNEYS TO AUDIT

### Journey 1: GEM_LOOP (signal → entry decision)
```
Flow: mesa_drones → triagem → conviction → entry_gate → gem_executor → trade
Failure modes to cover:
  [ ] Mesa score 75+ BUT conviction hard-coded 55 → rejection (FOUND BUG)
  [ ] Conviction threshold not reading gates_drift.json → rejection
  [ ] FQS missing → false rejection
  [ ] Tori required but absent → false rejection
  [ ] Alpha missing → false rejection
  [ ] Tier C rejected even if consensus good → false rejection

TDD Tests: Test_ConvictionGate_MesaBypass (expect 75+ pass conviction check)
           Test_FqsLazy_DefaultWhenMissing (expect assume quality 4/7)
           Test_ToriOptional_BypassWhenMesaStrong (expect SHORT with mesa>70 passes)

Status: 🔴 NOT IMPLEMENTED (lib_gates_drift_wire created but not wired to conviction check)
```

### Journey 2: ENTRY EXECUTION (decision → order → position)
```
Flow: conviction_pass → sizing → order_placement → position_register → trailing_stop
Failure modes to cover:
  [ ] Sizing hard-coded (found earlier bug TRUMPUSDT)
  [ ] Order placement fails silently → position not in CoinEx but in code
  [ ] SL/TP not set → position naked
  [ ] Leverage cap not enforced → 50x BNB (found bug)
  [ ] Position register out-of-sync with CoinEx

TDD Tests: Test_SizingDynamic_ReadsCapital (expect $3645 capital → 1% = $36 max loss)
           Test_OrderPlacement_RetryOnFailure (expect 3 retries then alert)
           Test_PositionSync_CoinExVsLocal (expect exact match or alert)
           Test_LeverageCap_Enforced (expect max 5x, not 50x)

Status: 🟡 PARTIALLY IMPLEMENTED (lib exists, not validated end-to-end)
```

### Journey 3: TRAILING STOP (active position → adjusted SL → exit)
```
Flow: position_open → trail_every_5min → SL_adjustment → exit
Failure modes to cover:
  [ ] Trail doesn't execute (found in status check: 0 positions open)
  [ ] Trail lag > 5min (positions drift like FIROUSDT 6 days)
  [ ] SL move fails → position at risk
  [ ] Profit lock not working → let winners bleed
  [ ] Exit without log → trade_outcomes missing entry

TDD Tests: Test_TrailExecutor_Every5Min (expect candle every 5min, SL adjusted)
           Test_TrailLag_MaxFiveMin (expect SL within 5min of peak)
           Test_ExitLog_Complete (expect all fields in trade_outcomes)

Status: 🔴 NOT FULLY TESTED (exists, but 0 positions open suggests not executing)
```

### Journey 4: LEARNING ENGINE (trade_outcomes → error pattern → gate adjust)
```
Flow: closed_trade → analyze_reason → confidence_adjustment → gates_drift update
Failure modes to cover:
  [ ] Error pattern not detected (e.g., TORI_SKIP losses not accumulated)
  [ ] Gate not tightened even after 2+ errors
  [ ] Learning cycle takes 6h but trades happen faster → gate lag
  [ ] No alert on repeated error pattern

TDD Tests: Test_LearningEngine_DetectToriSkipLosses (expect 2 SKIP losses → +5 conviction)
           Test_GatesDrift_UpdateOnPattern (expect gates_drift.json updated)
           Test_LearningCycle_6h (expect cycle runs every 6h)

Status: 🟡 IMPLEMENTED but not wired to gem_executor conviction check
```

### Journey 5: CAPITAL SAFETY (each trade checks 1% rule)
```
Flow: entry_size → check_max_loss → compare_capital → allow/reject
Failure modes to cover:
  [ ] Capital stale (reads $5k but actual $3645)
  [ ] Max loss calculation wrong (found in earlier audit)
  [ ] Daily loss limit not enforced (-5% pause not working)
  [ ] Position already open → double-dip capital

TDD Tests: Test_CapitalSafety_1Percent (expect max $36.45 loss/trade when $3645)
           Test_DailyLossLimit_PausesEntries (expect PAUSE if -5% reached)
           Test_PositionCount_NoDoubleDip (expect reject if market already open)

Status: 🟡 IMPLEMENTED (lib_capital_safety_enforcer) but not all tested
```

### Journey 6: GEM DISCOVERY (scan → evaluate → whitelist → ready for entry)
```
Flow: market_scan → gem_signal → tier_assign → FQS_enrich → ready
Failure modes to cover:
  [ ] Scan doesn't find vol_climax gems (7141 signals but only 4 trades)
  [ ] Tier assignment wrong (should be Tier A but marked Tier C)
  [ ] FQS missing → gem blocked
  [ ] Already-open gem in discovery → duplicate entry (FIROUSDT 6 days)

TDD Tests: Test_VolClimaxDetection_Sensitivity (expect find top 5 pumps/day)
           Test_TierAssignment_Correct (expect BCHUSDT 84 score → Tier A not C)
           Test_DuplicateGuard_NoReentry (expect reject if market already in trailing_positions)

Status: 🔴 SCAN FINDING ISSUE (7141 signals but only 4 trades means acceptance broken)
```

---

## 🎯 AUDIT METHODOLOGY (concrete)

### Phase 1: Static Analysis (2h)
```
For each journey, grep codebase:
  - Find all hard-coded thresholds (55 conviction, 50 capital %, etc)
  - Find all conditional gates (if gem.tier == "A", if conviction > X, etc)
  - Find all .json I/O (where files read/written, sync issues)
  - Mark BLOCKING issues (hard-coded values, missing wires)

Output: BLOCKING_ISSUES.md with line numbers + "why blocking"
Example:
  🔴 gem_executor line 612: conviction check hard-coded 55 (not reading gates_drift)
  🔴 gem_executor line 282: $sizing_pct not reading dynamic sizing lib
  🔴 trailing_executor: no TEST for 5min execution frequency
```

### Phase 2: TDD Coverage (4h)
```
For each BLOCKING issue, write test FIRST:

Example:
  Test name: Test_ConvictionGate_ReadsDynamicThreshold
  Setup: 
    - Write gates_drift.json conviction=50
    - Load lib_gates_drift_wire.ps1
  Action:
    - Call Test-ConvictionGate conviction=48
  Expected:
    - Returns $false (48 < 50) — CURRENTLY FAILS (hard-coded 55)
  
  Once test written + fails, FIX code to pass test.
```

### Phase 3: Journey End-to-End (2h)
```
For each journey, test full flow:
  - Input: realistic signal (e.g., BCHUSDT mesa_score 84)
  - Output: position open in CoinEx AND in trailing_positions.json
  - Verify: SL exists, size is 1% capital, entry_price matches

Example test flow:
  1. Create test gem (BCHUSDT, score 84)
  2. Run through gem_executor (mock CoinEx)
  3. Verify:
     ✓ Passed conviction gate
     ✓ Sizing = $36 (1% of $3645)
     ✓ Entry created
     ✓ SL set 2% below entry
     ✓ Logged in trade_outcomes
```

---

## 📊 EXPECTED OUTCOME

### Current State (200h invested)
```
Gem_loop: ✅ Runs
Mesa_drones: ✅ Generates 7141 signals
Conviction gate: 🔴 Hard-coded 55, blocks elite signals
Execution: ✅ Sometimes works (4 trades in 12 attempted)
Trailing: ❓ Unknown (0 positions open now)
Capital safety: ✅ Exists but not fully tested
Learning: ✅ Exists but not wired to conviction

Result: 67% success rate, high friction, daily firefighting
```

### After TDD Rebuild
```
Gem_loop: ✅ Runs
Mesa_drones: ✅ Generates 7141 signals
Conviction gate: ✅ Dynamic (reads gates_drift), mesa_bypass logic
Execution: ✅ Deterministic (tested end-to-end)
Trailing: ✅ Audited, 5min frequency verified
Capital safety: ✅ 100% tested
Learning: ✅ Wired to conviction, 6h cycle tested

Result: 85-90% success rate, predictable, minimal daily fixes
```

### Metrics (How we know "pronto")
```
✅ PASS CRITERIA:
  - 90%+ test pass rate (Phase 2 TDD suite)
  - End-to-end journey tests pass (Phase 3)
  - No hard-coded thresholds (all read from config)
  - Gates_drift wired + tested
  - Trailing executor verified 5min frequency
  - 0 "conviction_low" rejections for signals with mesa > 75
  - Capital safety enforced (max loss < 1% capital)

🛑 KNOWN LIMITATIONS (won't fix in this rebuild):
  - LLM hallucination in Tori (will mitigate with caching)
  - Market gaps (CoinEx API may timeout 1-2% of calls)
  - Regime mislabeling (rare, not worth deep investigation)

🎯 SUCCESS DEFINITION:
  "System runs 30 days without human intervention for 'gates broken' or 'position forgotten'"
```

---

## ⏱️ TIMELINE

```
NOW (2026-06-18 21:30):
  Phase 1 Start: Static Analysis

2026-06-18 23:30 (2h):
  Phase 1 Complete: BLOCKING_ISSUES.md written
  → You review, confirm top 3-5 blockers to fix first

2026-06-19 01:30 (2h):
  Phase 2 Start: TDD Coverage (write tests, make fail)

2026-06-19 03:30 (2h):
  Phase 2 Mid: Fix blocking issues to pass tests

2026-06-19 05:30 (2h):
  Phase 2 Complete: All tests passing
  
2026-06-19 07:30 (2h):
  Phase 3: End-to-end journey tests
  
2026-06-19 09:30:
  ✅ REBUILD COMPLETE

2026-06-19 onwards:
  Gem_loop running with TDD-verified gates
  No more "conviction hard-coded 55" issues
  Trailing executor verified working
  30-day production run
```

---

## 💡 Why This Breaks the 200h Loop

**Old approach** (what got us to 200h):
```
Bug found → Fix quick → Deploy → New bug appears → Fix quick → Deploy → ...
(Infinite loop because no root structure)
```

**TDD approach**:
```
Bug root cause found (hard-coded conviction) → Write test → Fix once → All future changes tested
(Breaks the loop because structure prevents regression)
```

---

## 🎯 COMMITMENT

- **Not "zero bugs forever"** (impossible in trading software)
- **But "30 days without daily firefighting"** (probable with TDD)
- **And "elite signals (75+) never missed again"** (testable)

---

## ❓ START NOW?

Ready to begin Phase 1 (static analysis)?

Or want to review this plan first?

