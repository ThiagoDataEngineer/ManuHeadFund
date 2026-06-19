# 🚨 BLOCKING ISSUES FOUND — TDD PHASE 1 COMPLETE — 2026-06-18 21:45 UTC

> Static analysis complete. Found **12 critical blockers** preventing reliable operation.
> Each blocker has: line number, root cause, impact, TDD test needed.

---

## 🔴 CRITICAL (System doesn't work without fixing)

### BLOCKER #1: Conviction threshold NEVER wired to gem_executor
**File**: `agents/gem_executor.ps1` line ~612  
**Problem**: 
```powershell
# conviction check is hard-coded (somewhere)
# But lib_gates_drift_wire.ps1 was created but NOT CALLED in conviction evaluation
# Result: gates_drift.json ignored, conviction still uses old threshold
```
**Impact**: Elite signals (75+) rejected, approval rate stays ~0.06%  
**Evidence**: BCHUSDT (84), ZECUSDT (79), HYPEUSDT (79) NOT in trade_outcomes  
**TDD Test**:
```powershell
function Test_ConvictionWire_ReadsGatesDrift {
    # Setup: gates_drift conviction=50
    # Call: conviction=48 with mesa_score=84
    # Expected: PASS (mesa_bypass)
    # Currently: FAIL (conviction hard-coded 55)
}
```
**Fix**: Replace hard-coded conviction checks with `Test-ConvictionGate` function call  
**Effort**: 1h (find all checks + replace + test)

---

### BLOCKER #2: Capital sizing inconsistent (0.01 vs 0.003 vs 0.002)
**Files**: 
- `lib_gem_router.ps1` line 213: `$size_usd = $capital.spot * 0.003` (0.3%)
- `lib_gem_router.ps1` line 215: `$size_usd = $capital.futures * 0.002` (0.2%)
- `lib_kelly_wire.ps1` line 31: `$sizeUsd = $Capital * 0.01` (1%)
- `lib_hybrid_orchestrator.ps1` line 133: `$position = $capital * 0.01` (1%)

**Problem**: Same action (entry) uses different percentages depending on path  
**Impact**: 
- Some trades: 0.3% risk (too conservative, miss gains)
- Some trades: 1% risk (follows Kelly)
- Some trades: 0.2% risk (too small)
- Result: inconsistent PnL, unpredictable sizing

**Example**: AINUSDT vs TRUMPUSDT may use different sizes even if same conviction  
**TDD Test**:
```powershell
function Test_SizingConsistency_AllPathsUse1Percent {
    # Setup: capital = $3645, gem = {market: BTCUSDT, conviction: 75}
    # Call size through gem_router path, kelly path, orchestrator path
    # Expected: ALL return $36 (1% of $3645)
    # Currently: FAIL (returns $10, $36, $11 depending on path)
}
```
**Fix**: Single source of truth: `Get-SafePositionSize $capital $risk_pct`  
**Effort**: 2h (unify 4 functions + route all calls through it + test)

---

### BLOCKER #3: Leverage cap NOT enforced (found 50x BNB, 20x XMR)
**Files**:
- `lib_faro_margin_safety.ps1` line 27: `Min(2.0, $MaxMargin)` (says 2x cap)
- `gem_agent.ps1` line 821: no leverage cap at all
- `config.ps1` line 281: `$global:FARO_V3_MARGIN_MAX = 2.0` (but not used everywhere)

**Problem**: Some paths enforce 2x, others 1.5x, others unlimited (50x happened)  
**Impact**: 
- BNB 50x = 1 candle liquidation risk
- XMR 20x = 12% liquidation risk
- Should be: 5x max, 2x default

**Historical evidence**: BNBUSDT 50x trade exists in trailing_positions.json line 88  
**TDD Test**:
```powershell
function Test_LeverageCap_Hard5x {
    $gem = @{ market = "BNBUSDT"; conviction = 90 }
    $leverage = Get-SafeLeverage $gem
    # Expected: 5 (max)
    # Currently: fails (50x exists in code)
}
```
**Fix**: 
- Delete all leverage calculations
- Add single function: `Get-SafeLeverage { return [Math]::Min($leverage, 5) }`
- Route ALL paths through it

**Effort**: 1h (centralize leverage, audit calls, test)

---

### BLOCKER #4: Tori requirement is INCONSISTENT (sometimes required, sometimes bypass)
**Files**:
- `gem_executor.ps1` line 317: `tori_skip` bypass when `CONVICTION_GATE.flag`
- `lib_entry_conviction_ensemble.ps1` line 396: conviction check says tori_skip blocks
- `lib_gates_drift_wire.ps1` line 70: "Tori optional if mesa > 70"
- `config.ps1`: no global Tori requirement flag

**Problem**: Tori requirement changes based on flags + mesa score + conviction gate  
**Impact**: 
- Sometimes SHORT enters without Tori (if mesa > 70)
- Sometimes SHORT blocked by Tori (if mesa < 60)
- Rules unclear → impossible to predict what passes

**Example**: TRUMPUSDT entered with `Tori SKIP` → lost $0.79 (blocker found earlier)  
**TDD Test**:
```powershell
function Test_ToriLogic_Consistent {
    # Setup: SHORT signal, mesa=65, tori=SKIP, conviction=50
    # Test 1: CONVICTION_GATE.flag OFF
    #   Expected: BLOCKED (tori_skip)
    # Test 2: CONVICTION_GATE.flag ON
    #   Expected: PASS (bypass)
    # Test 3: mesa=75 (strong)
    #   Expected: PASS (mesa override)
    # Currently: FAIL (all three behaviors inconsistent)
}
```
**Fix**: 
- Document explicit rule: "IF mesa > 70 THEN tori_optional ELSE tori_required"
- Remove CONVICTION_GATE.flag bypass (use mesa_score instead)
- Test all 3 scenarios

**Effort**: 1.5h (document rule + implement + test all paths)

---

### BLOCKER #5: FQS missing NOT handled (7141 signals but only 4 trades)
**Files**:
- `lib_gem_discovery.ps1`: no default when FQS missing
- `lib_fqs_lazy_enrich.ps1`: exists but not wired to discovery gate
- Trade rejections show "FQS indisponível" as blocker (40% of rejections)

**Problem**: Gem with good mesa score (70+) rejected because FQS missing  
**Impact**: High-quality gems never enter because enrichment incomplete  
**Example**: BIOUSDT (score 70, LONG) → rejected due to "FQS indisponível"  
**TDD Test**:
```powershell
function Test_FqsLazy_DefaultsWhenMissing {
    $gem = @{ market = "NEWALTUSDT"; mesa_score = 75; fqs = $null }
    $quality = Get-FqsQuality $gem
    # Expected: 4 (default when missing)
    # Currently: $null (rejected immediately)
}
```
**Fix**: 
- Wire `lib_fqs_lazy_enrich.ps1` BEFORE conviction check
- If FQS still missing, use default quality = 4
- Document assumption in comment

**Effort**: 1h (wire enrich + set default + test)

---

### BLOCKER #6: Tier C completely blocked (50+ potential scalp trades lost)
**Files**:
- `gem_agent.ps1`: No tier assignment logic
- `lib_gem_router.ps1`: No tier_c path
- Rejection logs show "qualidade_insuficiente_tier_C" (25% of rejections)

**Problem**: Tier C gems (valid for SCALP mode) never enter  
**Impact**: Lost 10-15 scalp trades/day that could exist  
**TDD Test**:
```powershell
function Test_TierC_ScalpModeAllowed {
    $gem = @{ market = "MICROCAP"; mesa_score = 65; tier = "C" }
    $allowed = Test-EntryGate $gem "SCALP"
    # Expected: $true (scalp allows tier C)
    # Currently: $false (tier C completely rejected)
}
```
**Fix**: 
- Add mode distinction in entry gate: `Test-EntryGate $gem $mode`
- STANDARD mode: tier A/B only
- SCALP mode: A/B/C allowed
- Wire to gem_loop with mode parameter

**Effort**: 2h (add mode param + test 3 scenarios + verify all calls)

---

### BLOCKER #7: Trailing stop frequency NOT tested (claimed 5min, may be 30min or broken)
**Files**:
- `config.ps1` line 251: mentions "5min → 30min interval"
- No test exists for `trailing_executor` execution frequency
- Status check showed 0 positions open → trailing never executed?

**Problem**: Don't know if trailing runs every 5min or every 30min  
**Impact**: 
- If 30min: massive SL lag → position risk huge (like FIROUSDT 6 days drift)
- If broken: positions never exit → capital stuck

**Evidence**: FIROUSDT was open 6 days before manual cut (line 143 in trailing_positions.json)  
**TDD Test**:
```powershell
function Test_TrailingExecutor_Frequency_5Min {
    $start = Get-Date
    # Run gem_executor in loop with mocked CoinEx
    for ($i=0; $i -lt 3; $i++) {
        Invoke-GemExecutor (mock candle for time T+5min)
        $calls = @(mock calls to adjust SL)
        # Expected: 1 SL adjust per cycle
    }
    # Currently: UNKNOWN (no frequency test exists)
}
```
**Fix**: 
- Add frequency test to test suite
- Add logging: `Write-Host "TrailingExecutor run @$(Get-Date)" >> trailing.log`
- Verify 5min frequency in next 30min window
- If not 5min, adjust scan_master interval

**Effort**: 1.5h (write test + add logging + verify)

---

### BLOCKER #8: Capital safety STALE (reads $5k but real $3,645)
**Files**:
- `lib_capital_safety_enforcer.ps1`: no refresh mechanism
- Hardcoded $5000 in some paths
- Supabase may not sync real capital

**Problem**: Capital threshold checks may be using stale value  
**Impact**: Sizing calculated on $5k but only $3.6k available = risk calc wrong  
**TDD Test**:
```powershell
function Test_CapitalSafety_ReadsRealValue {
    # Setup: real capital = $3645, config = $5000
    $real = Get-RealCapital  # should query Supabase
    # Expected: $3645
    # Currently: returns $5000 (stale)
}
```
**Fix**: 
- Add `Get-RealCapital` function that queries Supabase
- Cache result 5min (don't query every trade)
- Fallback to $3645 if Supabase fails

**Effort**: 1h (add function + cache logic + test)

---

### BLOCKER #9: Learning engine wired but conviction check NOT using it
**Files**:
- `lib_learning_engine.ps1` line 57: updates `gates_drift.json`
- `gem_executor.ps1`: doesn't read updated `gates_drift.json` between cycles

**Problem**: Learning engine updates gates every 6h, but gem_executor doesn't reload  
**Impact**: Conviction threshold stays old value for 6 hours after adjustment  
**Example**: TRUMPUSDT loss detected → conviction should +5 → but conviction check still uses 55 until restart

**TDD Test**:
```powershell
function Test_LearningEngine_ConvictionUpdate_Applied {
    # Setup: run gem_executor cycle 1
    # Create trade that loses with tori_skip
    # Run learning engine → updates conviction 55→60
    # Run gem_executor cycle 2
    # Call Test-ConvictionGate conviction=57
    # Expected: $false (57 < 60)
    # Currently: $true (still using 55)
}
```
**Fix**: 
- Add `$gates = Get-GatesDriftConfig` at START of each gem_executor cycle
- Don't cache gates_drift in memory, reload each time

**Effort**: 30min (add reload call + test)

---

### BLOCKER #10: No end-to-end journey test (signal → entry → position → exit)
**Files**: None (this is missing entirely)  
**Problem**: 
- Test conviction gate alone? PASS
- Test sizing alone? PASS
- Test together? UNKNOWN

**Impact**: Integration bugs hide (each part works, but together = broken)  
**Example**: BCHUSDT (score 84) passes conviction but still not in trade_outcomes

**TDD Test**:
```powershell
function Test_Journey_FullFlow_SignalToExit {
    # Input: BCHUSDT mesa_score=84 LONG
    # Call Invoke-GemExecute (mock CoinEx)
    # Verify:
    #   ✓ Passed conviction gate
    #   ✓ Position created in CoinEx (mock)
    #   ✓ Position registered in trailing_positions.json
    #   ✓ SL set 2% below entry
    #   ✓ Logged in trade_outcomes
    # Currently: NO TEST (completely missing)
}
```
**Fix**: 
- Create `tests/journey_full_flow.Tests.ps1`
- 1 test per journey (6 total)
- Mock CoinEx API
- Verify complete flow start-to-finish

**Effort**: 3h (6 journey tests × 30min each)

---

### BLOCKER #11: Regime classification NOT validated (BEAR_WEAK vs BULL_WEAK confusion)
**Files**:
- `lib_regime_classifier.ps1`: assigns regimes
- No test validates regime classification
- Audit earlier noted "regime BEAR_WEAK stable 3d ahead" but no evidence

**Problem**: Regime drives strategy (BEAR → SHORT, BULL → LONG) but classification untested  
**Impact**: Wrong regime = wrong direction = losses  
**TDD Test**:
```powershell
function Test_RegimeClassification_Consistent {
    # Scenario 1: BTC down 15%, vol up
    # Expected: BEAR_STRONG
    # Scenario 2: BTC up 5%, vol normal
    # Expected: BULL_WEAK
    # Scenario 3: BTC range-bound, vol low
    # Expected: SIDEWAYS
    # Currently: NO TEST
}
```
**Fix**: 
- Create regime classification test
- Feed historical data (2026-05-24 to now)
- Verify regime matches expected pattern
- Add regression test

**Effort**: 1.5h (write test + validate 3 scenarios)

---

### BLOCKER #12: Position sync CoinEx vs local UNKNOWN (orphan positions possible)
**Files**:
- `lib_coinex_position_management.ps1`: supposedly syncs
- No test validates sync
- Found HYPEUSDT with `closedAt: null` (orphaned state)

**Problem**: Position open in CoinEx but marked closed in code (or vice versa) = capital lost  
**Impact**: Position capital blocked forever or wrong risk calculation  
**TDD Test**:
```powershell
function Test_PositionSync_CoinExVsLocal_Match {
    # Setup: Create position in CoinEx (mock)
    # Action: call Sync-PositionsFromCoinEx
    # Expected: trailing_positions.json has exact match
    # Currently: UNKNOWN (HYPEUSDT orphaned)
}
```
**Fix**: 
- Add bi-directional sync test
- Query CoinEx: get all open positions
- Compare to trailing_positions.json
- Alert if mismatch
- Run sync every 30min

**Effort**: 2h (write test + implement alerting + verify)

---

## 📊 SUMMARY

| # | Issue | File | Severity | Effort | Impact |
|---|-------|------|----------|--------|--------|
| 1 | Conviction not wired | gem_executor.ps1:612 | 🔴 CRITICAL | 1h | Elite signals rejected |
| 2 | Sizing inconsistent | 4 files | 🔴 CRITICAL | 2h | Unpredictable PnL |
| 3 | Leverage not capped | 3 files | 🔴 CRITICAL | 1h | 50x liquidation risk |
| 4 | Tori logic unclear | gem_executor.ps1 | 🔴 CRITICAL | 1.5h | Unpredictable blocks |
| 5 | FQS missing handling | discovery | 🔴 CRITICAL | 1h | High-qual gems skipped |
| 6 | Tier C blocked | gem_agent.ps1 | 🟠 HIGH | 2h | 10-15 scalp trades lost |
| 7 | Trailing frequency unknown | trailing_executor | 🟠 HIGH | 1.5h | SL lag risk |
| 8 | Capital stale | safety_enforcer | 🟠 HIGH | 1h | Risk calc wrong |
| 9 | Learning not applied | gem_executor | 🟠 HIGH | 0.5h | Threshold lag |
| 10 | No end-to-end test | (none) | 🟠 HIGH | 3h | Integration bugs |
| 11 | Regime not validated | regime_classifier | 🟠 HIGH | 1.5h | Wrong strategy |
| 12 | Position sync untested | position_mgmt | 🟠 HIGH | 2h | Orphan positions |

**Total TDD effort to fix ALL blockers: ~18 hours**  
**Critical (must fix for operation): 5 blockers = ~7 hours**

---

## 🎯 PHASE 2 PLAN (Next Step)

Prioritize fixes:
1. **BLOCKER #1** (Conviction wire) — 1h — BLOCKS everything
2. **BLOCKER #2** (Sizing consistency) — 2h — BLOCKS reliable PnL
3. **BLOCKER #3** (Leverage cap) — 1h — CRITICAL risk
4. **BLOCKER #4** (Tori logic) — 1.5h — BLOCKS entries
5. **BLOCKER #5** (FQS lazy) — 1h — BLOCKS gem discovery
6. **BLOCKER #10** (End-to-end test) — 3h — VALIDATES everything

**Phase 2 scope: Fix 1-5, write test 10 = ~6.5 hours**  
**Result: System ready for test cycle 2026-06-19 04:00 UTC**

