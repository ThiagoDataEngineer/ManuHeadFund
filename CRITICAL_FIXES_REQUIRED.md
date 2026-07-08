# 🔴 CRITICAL FIXES REQUIRED — Tori Daemon Production Approval

**Status:** DO NOT DEPLOY AS-IS  
**Blocking Issues:** 5  
**Estimated Fix Time:** 4-6 hours  
**Date:** 2026-07-08

---

## 🚨 BLOCKING ISSUES (Tier 1 — MUST FIX)

### Issue #1: Undefined Functions in Daemon
**File:** `agents/tori_daemon_24h.ps1` (Lines 245, 249)  
**Severity:** 🔴 CRITICAL  
**Problem:**
```powershell
$setups = Analyze-TrendlineSetup -Market $pair  # Function doesn't exist!
```

**Impact:** Daemon crashes on first scan cycle  
**Fix Required:**
```powershell
# Option A: Import from lib_tori_confluence_detector
. (Join-Path $PSScriptRoot "lib_tori_confluence_detector.ps1")

# Option B: Call correct function
$setups = Get-ConfluenceScoreEnhanced -Market $pair -Closes $closes -Volumes $volumes
```

**Verification:** Run `Get-Command Analyze-TrendlineSetup` — should NOT return null

---

### Issue #2: Function Reference Type Mismatch
**File:** `agents/lib_tori_trades_scanner.ps1` (Lines 306, 512)  
**Severity:** 🔴 CRITICAL  
**Problem:**
```powershell
function Analyze-ToriPair {
    param($Market, $CoinExFunc)  # Expects function reference
    
    # But called like:
    $setups = Analyze-ToriPair -Market $pair -CoinExFunc ${function:CoinEx-GetFuturesCandles}
    
    # Inside function:
    & $CoinExFunc -market $Market -period $tf -limit 300  # Type mismatch!
}
```

**Impact:** Scanner fails silently or throws "Cannot bind argument" error  
**Fix Required:**
```powershell
# Pass function as script block instead
$setups = Analyze-ToriPair -Market $pair -CoinExFunc { CoinEx-GetFuturesCandles @args }

# Inside:
$candles = & $CoinExFunc -market $pair -period $tf -limit 300
```

**Verification:** Unit test with real CoinEx-GetFuturesCandles call

---

### Issue #3: Race Condition in State Persistence
**File:** `agents/tori_daemon_24h.ps1` (Lines 470-495)  
**Severity:** 🔴 CRITICAL  
**Problem:**
```powershell
# Step 1: Analysis completes
$script:ActiveSetups += @($cycleSetups)  # In-memory update

# ⚠️ GAP: Process could die here!

# Step 2: Save to disk
Save-DaemonState  # File write
```

**Impact:** Setup data loss (unsynced setups disappear on crash)  
**Fix Required:**
```powershell
# Write-Ahead Logging approach:
$tempFile = "$STATE_FILE.tmp"
$backupFile = "$STATE_FILE.backup"

try {
    # Write to temp first
    $script:ActiveSetups += @($cycleSetups)
    Save-DaemonState -Path $tempFile
    
    # Only THEN update in-memory
    Move-Item $tempFile $STATE_FILE -Force
    
} catch {
    # Rollback from backup if exists
    if (Test-Path $backupFile) {
        Copy-Item $backupFile $STATE_FILE -Force
    }
}
```

**Verification:** Kill daemon during save → on restart, data should recover from backup

---

### Issue #4: Missing Error Handling in Main Loop
**File:** `agents/tori_daemon_24h.ps1` (Lines 592-614)  
**Severity:** 🔴 CRITICAL  
**Problem:**
```powershell
while ($script:IsRunning) {
    try {
        # Scan all pairs
        foreach ($pair in $pairs) {
            $candles = CoinEx-GetFuturesCandles -market $pair  # No timeout!
            # If API hangs: entire loop stalls for minutes
        }
    } catch {
        Write-Log "Error: $_"
        # ⚠️ Crashes after FIRST error, no retry!
        break
    }
}
```

**Impact:** One API timeout = daemon dies  
**Fix Required:**
```powershell
while ($script:IsRunning) {
    try {
        foreach ($pair in $pairs) {
            try {
                $candles = CoinEx-GetFuturesCandles -market $pair -TimeoutSec 10
            } catch {
                Write-Log "Pair $pair failed: $_"
                # Skip this pair, continue scanning
                continue
            }
        }
    } catch {
        Write-Log "Scan cycle failed, retrying in 30s: $_"
        Start-Sleep -Seconds 30
        # Retry instead of crashing
    }
}
```

**Verification:** Simulate API hang → daemon should recover within 30s

---

### Issue #5: Insufficient Test Coverage
**File:** `tests/` (All test files)  
**Severity:** 🔴 CRITICAL  
**Problem:**
- Only ~30% of code has tests
- Missing: daemon lifecycle, state recovery, crash scenarios
- Mock functions have bugs (candles returned in wrong order)
- No integration tests

**Impact:** Cannot validate daemon reliability  
**Fix Required:**
```powershell
# Add tests for:
1. Daemon crashes mid-scan → recovery via watchdog ✅
2. State file corruption → restore from backup ✅
3. API timeout → skip pair, continue scanning ✅
4. Telegram unreachable → log error, continue ✅
5. Disk full → graceful shutdown with cleanup ✅
6. High memory (1000+ candles) → no out-of-memory ✅
7. Concurrent scan cycles (shouldn't happen but test anyway) ✅
8. 72-hour uptime test ✅
```

**Verification:** All 20+ integration tests pass

---

## 🔧 TIER 2 ISSUES (High Impact — SHOULD FIX)

### Issue #6: Rate Limiting Calculation Wrong
**File:** `agents/tori_daemon_24h.ps1` (Line 257)  
**Problem:** Claims 4-hour scan but math says 20-30 minutes

```
150 pairs × 4 timeframes × 100ms delay = 60 sec/pair
60 sec × 150 = 2.5 hours just for delays
+ API latency (1-2 sec per request) = 600-1200 sec = 10-20 min extra
Total: 3-4 hours MINIMUM per scan
```

**Fix:** Implement parallel fetching with max 10 concurrent requests

### Issue #7: Duplicate RSI Calculation
**File:** `lib_tori_confluence_detector.ps1` AND `lib_tori_trades_scanner.ps1`  
**Problem:** Same `Get-RSI` defined in two places  
**Fix:** Create `lib_technical_indicators.ps1`, import in both

### Issue #8: Hardcoded Thresholds
**File:** Multiple files  
**Problem:** Confluence threshold (80), proximity (-3% to +5%), etc. hardcoded  
**Fix:** Move to `config/tori_daemon.json`

---

## ✅ FIX VERIFICATION CHECKLIST

- [ ] **Issue #1:** Run `Get-Command Analyze-TrendlineSetup` → returns function
- [ ] **Issue #2:** Unit test calls Analyze-ToriPair with real CoinEx-GetFuturesCandles → succeeds
- [ ] **Issue #3:** Kill daemon during scan → on restart, all setups recovered
- [ ] **Issue #4:** Simulate API timeout → daemon recovers within 30s
- [ ] **Issue #5:** Run 20+ integration tests → all pass
- [ ] **Issue #6:** Measure actual scan time → verify <= 4 hours for 150 pairs
- [ ] **Issue #7:** Grep for duplicate functions → only 1 `Get-RSI` found
- [ ] **Issue #8:** Read config from file → all thresholds configurable

---

## 📋 DEPLOYMENT TIMELINE

### **Day 1 (Today) — 3 hours**
- [ ] Fix Issues #1, #2, #4 (undefined functions, error handling)
- [ ] Unit tests for each fix
- [ ] Commit: `fix: critical daemon issues — undefined functions, error handling, timeouts`

### **Day 2 — 2 hours**
- [ ] Fix Issue #3 (race condition, atomic writes)
- [ ] Backup/restore tests
- [ ] Commit: `fix: atomic state persistence with WAL`

### **Day 3 — 3 hours**
- [ ] Fix Issues #6, #7, #8 (rate limiting, duplication, config)
- [ ] Integration tests (20+ scenarios)
- [ ] Commit: `refactor: rate limiting, consolidate utils, externalize config`

### **Day 4 — 4 hours**
- [ ] Fix Issue #5 (comprehensive test coverage)
- [ ] Run 72-hour uptime test
- [ ] Commit: `test: comprehensive integration suite (50+ tests)`

### **Day 5 — Review & Deploy**
- [ ] Code review by second pair
- [ ] Final verification checklist
- [ ] Deploy to production with operator monitoring

---

## 🎯 SUCCESS CRITERIA FOR DEPLOYMENT

- ✅ All 5 blocking issues fixed
- ✅ 50+ integration tests pass
- ✅ Daemon runs 72 hours without restart
- ✅ Actual scan cycle time confirmed <= 4 hours
- ✅ Rate limit compliance verified
- ✅ Crash recovery tested (process kill, disk full, API timeout)
- ✅ Documentation updated with operational procedures

---

## 📊 CURRENT QUALITY METRICS

| Metric | Current | Target | Gap |
|--------|---------|--------|-----|
| Code Coverage | 30% | 80% | -50% |
| Integration Tests | 5 | 50+ | -45 |
| Uptime (simulated) | 0 | 720h | 720h |
| Error Handling | Weak | Production-grade | Major |
| Rate Limit Compliance | ❌ | ✅ | Critical |

---

## 💡 RECOMMENDATION

**DO NOT DEPLOY until:**
1. All Tier 1 issues fixed + verified
2. Integration tests reach 50+ passing
3. 72-hour uptime test completes successfully
4. Rate limiting math validated

**Current Status:** 🔴 **NOT READY**  
**Estimated Readiness:** 4-5 days if fixes are prioritized

---

**Next Action:** Acknowledge these issues and start fixing Tier 1 today.
