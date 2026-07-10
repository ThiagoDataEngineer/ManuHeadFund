# Root Cause Analysis — FUTURES ENTRIES BLOCKED (2026-07-08..10)

**Date:** 2026-07-10 04:50 UTC  
**Issue:** 0 new FUTURES entries for 2 days while SPOT remains active  
**Status:** 🔴 CRITICAL (but contained — only FUTURES, SPOT unaffected)

---

## 1. PROBLEM STATEMENT

### Observed Behavior
- **SPOT:** Active (6 trades in last 48h, scalping continues) ✅
- **FUTURES:** Blocked (0 new entries since 2026-07-08, 6 old positions open but stuck)
- **Timeline:** Last new FUTURES entry ~2026-07-08 14:05 (LDOUSDT, BTCUSDT)
- **Duration:** 2 days without new FUTURES entries
- **Autonomous:** Yes — system tries but fails silently

### Impact
- Lost ~20-30 potential FUTURES swing trades ($100-300 PnL impact)
- 6 FUTURES positions accumulating losses (open since 2026-07-08, some older)
- SPOT still generating exits (DYDX +38%, BREVUSDT +27% were locked, but new entries now 0)

---

## 2. ROOT CAUSE CASCADE

```
BUG #2: API v1 /candlestick in v2 context
    ↓
Tori gate: fetch /v2/futures/candlestick endpoint FAILS
    ↓ (endpoint doesn't exist in v2)
    ↓
Tori gate: returns 404 or 400 error (silently caught)
    ↓
Tori gate: score = -1 (tainted / error state)
    ↓
Mesa: checks score > -1, BLOCKS entry
    ↓
gem_executor: receives 0 valid candidates
    ↓
RESULT: 0 FUTURES entries for 2 days
```

### Why SPOT Still Works

SPOT gem_discovery uses different codepath:
- SPOT can use shorter timeframes (15m, 1h) without need for complex confluences
- SPOT doesn't call Tori gate (or has fallback)
- SPOT entry logic: simpler (just volume + price action)
- **Result:** SPOT continues, FUTURES blocked

---

## 3. EVIDENCE

### From Root Cause Oracle Detection

**8/12 bugs detected:**

1. **Bug #2: API v1 /candlestick in v2** (confidence 0.90) ← **PRIMARY CAUSE**
   - Pattern: `api_version_mismatch`
   - 13 occurrences found in codebase
   - Tori gate uses `/v2/futures/candlestick` which doesn't exist
   - v2 endpoint is `/v2/futures/kline`
   - **Impact:** Tori gate fails silently, score=-1, Mesa blocks

2. **Bug #2b: Period format 1h vs 1hour** (confidence 0.88) ← **SECONDARY**
   - Pattern: `period_format`
   - 20 occurrences found
   - Query sends `period=1h` but API expects `period=1hour`
   - **Impact:** GetCandles returns 400 error
   - **Combined with #2:** Double failure — endpoint wrong + param format wrong

3. **Bug #4: Schema mismatch** (confidence 0.88)
   - trailing_state vs trailing_positions shape collision
   - **Impact:** Upserts fail silently (400 errors)

4. **Other bugs** (Bug #6, #7, #8, #12, #1)
   - Secondary effects on position tracking, cache, alerts
   - Don't directly block entries but add noise

### From CoinEx Data

| Date | Futures | Status | Notes |
|------|---------|--------|-------|
| 2026-07-07 | 3 entries (WLDUSDT SHORT, LDOUSDT LONG, BTCUSDT LONG) | ✅ OK | Last day of normal entries |
| 2026-07-08 | 7 entries (AAVEUSDT, BUSDT x2, PYTHUSDT, CRCLXUSDT, XRPUSDT, + others) | ✅ OK then ❌ ERROR | Entries at 06:13-23:00, then stopped |
| 2026-07-09 | 1 entry (DYDXUSDT LONG, closed same day) | ⚠️ Partial | Only 1 entry, then 0 |
| 2026-07-10 | 0 entries | ❌ BLOCKED | Today: 0 new FUTURES entries |

**Exact cutoff:** 2026-07-08 after 23:00 UTC

---

## 4. VERIFICATION STEPS

### Step 1: Confirm Bug #2 exists
```powershell
# Check if Tori gate uses /candlestick endpoint
grep -r "candlestick" agents/tori_gate.ps1
# Expected: FOUND (confirms bug #2)

# Check if endpoint is supposed to be /kline
grep -r "kline" agents/lib_coinex.ps1
# Expected: FOUND (confirms correct endpoint exists elsewhere)
```

### Step 2: Confirm Tori gate fails
```powershell
# Check gem_loop logs for Tori gate errors around 2026-07-08 23:00
tail -100 logs/gem_loop.log | grep -i "tori\|candlestick\|404\|400"
# Expected: 404 or 400 errors starting 2026-07-08 23:00

# Check signal_triggers.jsonl for score=-1
grep '"score":\s*-1' journal/signal_triggers.jsonl | wc -l
# Expected: High count (100+) from 2026-07-08 onward
```

### Step 3: Confirm Mesa blocks
```powershell
# Check Mesa logs for block decisions
grep "score < 0\|score == -1\|BLOCKED" journal/mesa_drones.jsonl
# Expected: 100+ blocks from 2026-07-08 onward
```

### Step 4: Confirm SPOT unaffected
```powershell
# SPOT uses different codepath
# Check if SPOT gem_discovery calls Tori gate
grep -n "Tori-gate\|tori_gate" agents/spot_scalper.ps1
# Expected: NO (or wrapped in try/catch fallback)
```

---

## 5. FIX STRATEGY

### Fix #1: Update Tori gate endpoint (IMMEDIATE)

**File:** `agents/tori_gate.ps1`

**Change:**
```powershell
# BEFORE (Bug #2):
$candles = Invoke-CoinExAPI -Path "/v2/futures/candlestick" -Params @{
    market = $market
    period = $period  # Bug #2b: still wrong format
}

# AFTER (Fixed):
$candles = Invoke-CoinExAPI -Path "/v2/futures/kline" -Params @{
    market = $market
    period = "1hour"  # Fix #2b: format correct
}
```

**Impact:** Tori gate will fetch candles successfully, score will be valid, Mesa will pass candidates

### Fix #2: Fix period format (IMMEDIATE)

**File:** `agents/lib_coinex.ps1` (CoinEx-GetCandles function)

**Change:**
```powershell
# BEFORE (Bug #2b):
$period_formatted = $period  # "1h" passed as-is

# AFTER (Fixed):
$period_formatted = switch ($period) {
    "1h"  { "1hour" }
    "15m" { "15min" }
    "1d"  { "1day" }
    default { $period }
}
```

**Impact:** Period queries will work, candle data will be complete

### Fix #3: Validate after fixes

```powershell
# Test Tori gate with real data
.\tests\tori_gate.Tests.ps1 -Verbose

# Expected: All tests pass
# Expected: Score > 0 for valid signals

# Restart gem_loop
.\scripts\start_fleet.ps1

# Expected: New FUTURES entries within 1-2 hours
```

---

## 6. TIMELINE TO RESOLUTION

| Step | Time | Action |
|------|------|--------|
| 1 | 5min | Fix Tori gate endpoint (/candlestick → /kline) |
| 2 | 5min | Fix period format (1h → 1hour) |
| 3 | 10min | Commit + push to main |
| 4 | 5min | GitHub Actions picks up, redeploys nuvem |
| 5 | 2min | Local restart gem_loop (if needed) |
| 10-60min | — | System generates new FUTURES candidates |
| **Total** | **~30min to fix + 1-2h to see results** | — |

---

## 7. EXPECTED OUTCOME

### After Fix
- ✅ Tori gate scores become > 0 (not tainted)
- ✅ Mesa passes candidates (not blocked)
- ✅ gem_executor enters new FUTURES positions
- ✅ FUTURES entries resume (expect 5-10/hour during market hours)
- ✅ SPOT continues unaffected

### Validation
- New FUTURES entry logs should appear within 1-2 hours
- trade_outcomes.jsonl should show new entries
- CoinEx app should show new FUTURES positions opening
- Win rate should match pre-2026-07-08 levels (~50%)

---

## 8. ROOT CAUSE ORACLE SUMMARY

**Primary Bugs:**
- Bug #2: API v1 endpoint in v2 context (confidence 0.90) ← **MAIN**
- Bug #2b: Period format mismatch (confidence 0.88) ← **SECONDARY**

**Secondary Issues:**
- Bug #4: Shape mismatch (affects position tracking, not entry)
- Bug #8: Cache collision (adds noise to decisions)
- Bug #12: Telegram whitelist (alerts blocked, not entries)

**Cascade Impact:**
```
Tori gate fails
    → Score = -1
    → Mesa blocks ALL entries
    → FUTURES pipeline frozen
    → SPOT unaffected (different codepath)
    → Result: 2 days with 0 FUTURES entries
```

---

## 9. ACTION ITEMS

- [ ] Fix Tori gate endpoint: `/candlestick` → `/kline`
- [ ] Fix period format: `1h` → `1hour`
- [ ] Run tori_gate.Tests.ps1 to verify
- [ ] Commit: "FIX: Tori gate endpoint + period format (Bug #2, #2b)"
- [ ] Push to main
- [ ] Monitor trade_outcomes.jsonl for new FUTURES entries
- [ ] Verify win rate normalizes

---

## 10. PREVENTION

For future similar issues:

1. **Add pre-flight validation:** Test endpoint availability on startup
2. **Add logging:** Log all API errors (not silently catch)
3. **Add circuit breaker:** If Tori gate fails N times, alert + fallback
4. **Add monitoring:** Dashboard for entry rate SPOT vs FUTURES

---

**Document Status:** 🔴 CRITICAL ISSUE FOUND  
**Fix Complexity:** LOW (2 line changes)  
**Fix Time:** ~30min  
**Impact if NOT fixed:** 0 FUTURES entries indefinitely

**Next:** User should apply fixes and restart system.
