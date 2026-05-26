# Layer 2 Mentor Reflection — 24h Paper Validation Checklist

**Start Date:** 2026-05-25  
**Target Duration:** 24 hours (2026-05-26 ~same time)  
**Decision Point:** 2026-05-27 08:00 UTC  
**Success Criteria:** All items ✓ green

---

## Pre-Test Checklist (Before Starting)

- [ ] Read `./docs/TASK_6_LAYER_2_COMPLETION.md` (understand 6 functions)
- [ ] Verify Layer 1 is running stable (Layer 1 tests passing)
- [ ] Confirm `./agents/lib_mentor_reflection.ps1` loaded (6 functions visible)
- [ ] Confirm `./scripts/scan_master.ps1` imports Layer 2 (line 61)
- [ ] Telegram alerts enabled (will receive Mentor notifications)
- [ ] Journal directory ready (positions will update with mentor actions)
- [ ] Log directory writable (./logs/)
- [ ] Disk space >5GB available

---

## Test Execution

### Start Command
```powershell
# Terminal 1: Run scan_master with Layer 2 active
.\scripts\scan_master.ps1

# Terminal 2: Monitor logs (optional)
Get-Content -Path './logs/mentor_*.log' -Wait
```

### Duration
- **Target:** Minimum 24 hours continuous
- **Soft:** If <5 active positions, can extend to 48h for better sample
- **Hard Stop:** If any CRITICAL error occurs (3+ consecutive crashes)

---

## Live Monitoring (During Test)

### Every 2-4 Hours: Check These Metrics

#### 1. Mentor Reviews Triggered ✓
**Location:** Telegram alerts + logs  
**Expected:** ~1-2 reviews per position per 24h (depends on # open trades)  
**Check:**
```
Search Telegram for: "Mentor] " messages
- Should see reviews starting ~6h after position entry
- Format: "[Mentor] BTCUSDT LONG: HOLD ..." or "... TIGHTEN_STOP ..."
```

#### 2. Regime Detection Accuracy ✓
**Location:** Logs, Telegram "regime=" messages  
**Expected:** Regime shifts should align with manual chart review  
**Check:**
- Watch for "regime=BEAR_STRONG" messages
- Cross-check: Is Bitcoin actually bearish at that time? (Manual chart)
- False regime detections: Should be <5%

#### 3. Stop Tightening Applied ✓
**Location:** Position journal, Telegram alerts  
**Expected:** When BEAR detected, >1 position should have stop tightened  
**Check:**
- If any Telegram: "stop tightened: XXX to YYY"
- Verify: new stop is ~50% closer to entry (math check)
- Position JSON: `lastMentorReview` field should be recent

#### 4. False Closes Rare ✓
**Location:** Position journal, Telegram  
**Expected:** <2% false CLOSE_NOW actions  
**Check:**
- Search Telegram for: "CLOSED: false breakout"
- If >1 close, check if it was actually false (price continued up after close)
- Goal: 0 false closes ideal, <2% acceptable

#### 5. Price Progress Calculations Correct ✓
**Location:** Internal logs (debug)  
**Expected:** Price progress = (current - entry) / (target - entry) makes sense  
**Check:**
- Example: entry=100, target=130, current=115
  - Progress should be 0.5 (50%)
- If you see progress <0% or >1.2%, investigate

#### 6. Early Warning Detection ✓
**Location:** Telegram, position journal  
**Expected:** False breakouts flagged (early BE)  
**Check:**
- Should see 0-2 "CLOSE_NOW" actions in 24h
- If position closed early, was it actually going to lose?
- Manual review: Did early close prevent bigger loss?

#### 7. Mentor Reviews Complete Without Crash ✓
**Location:** Logs, process running  
**Expected:** scan_master stays alive for 24h  
**Check:**
```powershell
# Terminal: Check if process still running
Get-Process | Where-Object { $_.Name -eq 'powershell' -and $_.CommandLine -like '*scan_master*' }
# Should return one process with recent start time
```

---

## End-of-Test Analysis (After 24h)

### Metrics Checklist

**A. Mentor Execution**
```
Number of positions reviewed: _____ (target: ≥2 per position)
Number of HOLD decisions: _____ (target: >80% of all decisions)
Number of TIGHTEN_STOP: _____ (target: 1-3 per position)
Number of CLOSE_NOW: _____ (target: <2, ideally 0)
```

**B. Decision Quality**
```
HOLD decisions: Were positions on-track? _____ (target: 95%+ correct)
TIGHTEN_STOP decisions: Did regime actually shift? _____ (target: 90%+ correct)
CLOSE_NOW decisions: Were they false breakouts? _____ (target: 0-1 per test, ideally 0)
```

**C. Regime Detection**
```
Regime shifts detected: _____ (e.g., BULL_STRONG → BEAR_STRONG)
Manual chart alignment: _____ (target: >90%)
False regime detections: _____ (target: <5%)
```

**D. System Stability**
```
Crashes: _____ (target: 0)
Error messages: _____ (target: <10, all recoverable)
Telegram alerts failed: _____ (target: 0)
Position journal corrupted: _____ (target: NO)
```

**E. Stop Tightening Effectiveness**
```
Stops tightened: _____ positions
Average tightening %: _____ (should be ~50% closer)
Losses prevented by tightening: _____ (manual check ~3-5 positions)
```

---

## Go/No-Go Decision Framework

### ✅ PASS CRITERIA (Go to next layer)

**All of these must be true:**
1. ✓ 0 crashes in 24h
2. ✓ ≥2 Mentor reviews per position
3. ✓ <2% false closes (CLOSE_NOW incorrect)
4. ✓ ≥90% regime detection accuracy (manual chart check)
5. ✓ ≥80% HOLD decisions when position on-track
6. ✓ ≥1 TIGHTEN_STOP applied in BEAR regime
7. ✓ >0% win rate maintained (no major drawdown)

**Recommendation:** ✅ **PROCEED to Layer 3 (Kelly Sizing)**

---

### ❌ NO-PASS CRITERIA (Fix and re-test)

**Any of these = re-test:**
1. ✗ >1 crash (indicates core bug)
2. ✗ <1 review per position (checkpoint not working)
3. ✗ >5% false closes (decision logic error)
4. ✗ <75% regime accuracy (macro detection broken)
5. ✗ >30% incorrect HOLD/CLOSE decisions (decision tree flaw)
6. ✗ 0 TIGHTEN_STOP in 24h (never triggered tightening)
7. ✗ Major drawdown >-5% (Layer 2 causing losses)

**Recommendation:** ❌ **DEBUG and re-test (1-2 day cycle)**

**Debug Checklist:**
- [ ] Review scan_master.ps1 logs for error messages
- [ ] Run `Invoke-Pester ./tests/mentor_review.Tests.ps1` (verify 24/24 still pass)
- [ ] Check if Get-MacroContext is returning valid regimes
- [ ] Verify Get-TrailingPositions has correct data
- [ ] Test Update-MentorReview in isolation (mock data)
- [ ] Check Telegram alert failures
- [ ] Verify position JSON schema matches expectations

---

## Data Collection for Analysis

### Save These Logs Before Deleting

```powershell
# After 24h test complete:

# 1. Position journal (key data)
Copy-Item -Path ".\journal\positions*.json" -Destination ".\docs\validation_24h_positions_$(Get-Date -Format 'yyyyMMdd').json"

# 2. Mentor logs
Copy-Item -Path ".\logs\mentor_*.log" -Destination ".\docs\validation_24h_mentor_$(Get-Date -Format 'yyyyMMdd').log"

# 3. Telegram export (manual screenshot/export)
# Save Telegram chat with alerts

# 4. scan_master output (if captured)
# Save terminal output for analysis
```

---

## Sample Telegram Alert Formats (What to Expect)

**Mentor Review — HOLD (Normal):**
```
[Mentor] BTCUSDT LONG: HOLD (conf=0.90, reason=normal_progression)
```

**Mentor Review — TIGHTEN_STOP (Regime Shift):**
```
Aviso [Mentor] BTCUSDT LONG stop tightened: 45000.50 to 47250.75 (regime=BEAR_STRONG)
```

**Mentor Review — CLOSE_NOW (False Breakout):**
```
[Mentor] ETHUSDT SHORT CLOSED: false breakout detected
```

**If None of Above:**
- Mentor might not be triggering (check if 6h checkpoint working)
- Or no positions open (run scanner first)

---

## Quick Troubleshooting

| Issue | Check | Fix |
|-------|-------|-----|
| No Mentor alerts | 6h threshold reached? | Wait for 6h+ trade age |
| Regime always SIDEWAYS | Is Get-MacroContext working? | Check lib_macro.ps1 |
| Too many CLOSE_NOW | Threshold too low? | Adjust confidence in Get-MentorDecision |
| Stops never tighten | BEAR regime detected? | Check if market actually bearish |
| Crashes after few reviews | Memory leak? | Restart scan_master every 12h |

---

## After Test: Archive Results

```powershell
# Create summary
@{
    testDate = Get-Date
    duration = "24 hours"
    result = "PASS" # or "NO-PASS"
    reviewsCount = <number>
    holdCount = <number>
    tightenCount = <number>
    closeNowCount = <number>
    crashCount = <number>
    notes = "..."
} | ConvertTo-Json | Out-File -Path ".\docs\LAYER_2_VALIDATION_RESULT_$(Get-Date -Format 'yyyyMMdd').json"
```

---

## Questions Before Starting?

**If unsure about any metric or decision, save the data and re-analyze with logs.**

Ready to start 24h validation? ✅

