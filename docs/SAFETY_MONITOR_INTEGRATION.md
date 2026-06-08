# 🛡️ Safety Monitor Integration Guide

**Status**: ✅ READY FOR INTEGRATION  
**Files**: `lib_safety_monitor.ps1` + `test_safety_monitor.ps1`  
**Last Updated**: 2026-06-08

---

## Overview

The Safety Monitor runs **automatically every cycle** and:
- ✅ Checks 6 critical metrics
- ✅ Auto-switches PAPER if red flag detected
- ✅ Logs all events to `journal/safety_events.jsonl`
- ✅ Alerts via Telegram on critical issues
- ✅ Never disables BTCUSDT (our main pair)

---

## Integration into scan_master.ps1

**Add this to end of `scan_master.ps1`:**

```powershell
# ════════════════════════════════════════════════════════
# POST-CYCLE: Safety Monitor Check
# ════════════════════════════════════════════════════════

. agents/lib_safety_monitor.ps1

Write-Host "`n🛡️ Running Safety Monitor..." -ForegroundColor Cyan
$safetyResult = Invoke-SafetyMonitor -Verbose

if ($safetyResult.status -eq "CRITICAL") {
    Write-Host "❌ Critical issue detected — switched to PAPER mode" -ForegroundColor Red
    Write-Host "   Reason: $($safetyResult.reason)" -ForegroundColor Yellow
    exit 1
}

if ($safetyResult.status -eq "WARNING") {
    Write-Host "⚠️ Warning detected — paused scan temporarily" -ForegroundColor Yellow
    exit 0
}

Write-Host "✅ Safety check passed — continuing LIVE" -ForegroundColor Green
```

**Result**: Every 15 minutes (or 5 min if you scale), Safety Monitor validates your account.

---

## 6 Checks Explained

### 1️⃣ Win Rate < 30% (CRITICAL)

```
Check: Last 20 trades
Threshold: 30% win rate
Action: PAPER mode
Example: 6 wins, 14 losses = 30% WR → PAPER
```

**Why**: 2 losses per 1 win means pattern is broken. Stop trading.

---

### 2️⃣ Daily Drawdown > 10% (CRITICAL)

```
Check: Trades from today
Threshold: -10% of capital ($365)
Action: PAPER mode
Example: Started day at $3,654, now $3,289 = 10.0% loss → PAPER
```

**Why**: Cascade of losses suggests regime changed. Pause immediately.

---

### 3️⃣ Capital Discrepancy > $50 (CRITICAL)

```
Check: journal PnL vs onchain balance
Threshold: $50 difference
Action: PAPER mode
Example: Expected $3,654 but onchain shows $3,704 = +$50 discrepancy → PAPER
```

**Why**: Could be manual trade on CoinEx or system bug. Need investigation.

---

### 4️⃣ System Offline > 30min (CRITICAL)

```
Check: Latest log file timestamp
Threshold: 30 minutes old
Action: PAPER mode
Example: Last log from 14:45, now 15:20 = 35min offline → PAPER
```

**Why**: GitHub Actions crashed. Can't place trades safely.

---

### 5️⃣ Pair Quality < 40% WR (WARNING)

```
Check: Each pair's win rate (last 50 trades)
Threshold: 40% for each pair
Action: Log bad pair, suggest disabling
Example: ETHUSDT = 30% WR (3 wins, 7 losses) → suggest disable
```

**Exception**: BTCUSDT never disabled (always active).

---

### 6️⃣ Hot Streak (5+ consecutive losses) (WARNING)

```
Check: Last 10 trades sequence
Threshold: 5 or more losses in row
Action: PAUSE_SCAN for 30 minutes
Example: L, L, L, L, L, W = 5 losses → PAUSE_SCAN
```

**Why**: Revenge trading leads to bigger losses. Cool down required.

---

## How It Works (Step-by-Step)

### Every 15 minutes:

```
1. scan_master.ps1 runs
   ↓
2. Vol_Climax + Engulfing scanner detects signal
   ↓
3. PlaceOrder executes trade (or skips)
   ↓
4. Trade logged to journal/trade_outcomes.jsonl
   ↓
5. Get-DynamicCapital fetches onchain balance
   ↓
6. Invoke-SafetyMonitor runs (NEW)
   ├─ Test-WinRateCritical
   ├─ Test-DailyDrawdownCritical
   ├─ Test-CapitalDiscrepancyCritical
   ├─ Test-SystemHealthCritical
   ├─ Test-PairQuality
   └─ Test-ConsecutiveLosses
   ↓
7. If ANY critical flag → Set-TradingMode -Mode PAPER
   ↓
8. Log to journal/safety_events.jsonl
   ↓
9. Telegram alert (if critical)
   ↓
10. Done — wait 15 minutes for next cycle
```

---

## Command Line

### Run Safety Monitor standalone (test):

```powershell
. agents/lib_safety_monitor.ps1

# Run all checks with verbose output
Invoke-SafetyMonitor -Verbose

# Show safety events log
Show-SafetyReport -EventsLookback 20

# Test specific check
Test-WinRateCritical -Verbose
Test-DailyDrawdownCritical -Verbose
Test-CapitalDiscrepancyCritical -Verbose
```

### Run test suite:

```powershell
.\scripts\test_safety_monitor.ps1

# Output: 4 scenarios showing different outcomes
# Scenario 1: All OK → CONTINUE
# Scenario 2: Win rate critical → SWITCH_TO_PAPER
# Scenario 3: Hot streak → PAUSE_SCAN
# Scenario 4: Pair quality issues → Log bad pair
```

---

## Safety Events Log

**File**: `journal/safety_events.jsonl`

**Example entry**:

```json
{
  "timestamp": "2026-06-08 14:30:00",
  "check_type": "SAFETY_MONITOR",
  "critical_win_rate": false,
  "critical_drawdown": false,
  "critical_discrepancy": false,
  "critical_system_health": false,
  "bad_pairs": ["ETHUSDT"],
  "hot_streak": false,
  "action_taken": "CONTINUE"
}
```

**If critical**:

```json
{
  "timestamp": "2026-06-08 15:45:00",
  "check_type": "SAFETY_MONITOR",
  "critical_win_rate": true,
  "critical_drawdown": false,
  "critical_discrepancy": false,
  "critical_system_health": false,
  "bad_pairs": [],
  "hot_streak": false,
  "action_taken": "SWITCH_TO_PAPER",
  "reason": "Win rate 20% < 30% threshold"
}
```

---

## BTCUSDT Protection

**BTCUSDT is our main pair. Rules:**

✅ Never disabled (even if WR < 40%)  
✅ Always monitored  
✅ Alerts if degrading, but stays active  
✅ Other pairs can be disabled if bad  

**Example**:
```
BTCUSDT: 35% WR → Alert "degrading" but STAY ACTIVE
ETHUSDT: 35% WR → Alert "disable this pair"
XRPUSDT: 35% WR → Alert "disable this pair"
```

---

## When It Auto-Switches PAPER

| Event | Triggers | Action |
|-------|----------|--------|
| Win Rate < 30% | Last 20 trades | PAPER immediately |
| Drawdown > 10% | Today's trades | PAPER immediately |
| Discrepancy > $50 | Journal vs onchain | PAPER immediately |
| Offline > 30min | Log file age | PAPER immediately |
| 5+ Losses | Consecutive | PAUSE_SCAN 30min |
| Pair WR < 40% | Each pair | Log warning (not PAPER) |

---

## Recovery (Getting Back to LIVE)

**After switching to PAPER:**

```powershell
# 1. Check what happened
Show-SafetyReport
# Output: Shows why it switched

# 2. Investigate
# If Win Rate issue: check logs for pattern change
# If Drawdown issue: check for cascade losses
# If Capital issue: verify no manual trades
# If Offline issue: check GitHub Actions

# 3. Fix the issue
# Example: If win rate low, wait for regime change
# Example: If discrepancy, align journal with onchain

# 4. Verify 3 clean cycles
# Run Invoke-SafetyMonitor 3 times
# If all pass → you can manually switch back

# 5. Switch back to LIVE
Set-TradingMode -Mode LIVE
Write-Host "Back to LIVE trading"
```

---

## Configuration

**Edit in `lib_safety_monitor.ps1`:**

```powershell
$script:SafetyConfig = @{
    min_win_rate = 0.30              # Change threshold (30%)
    max_daily_drawdown = 0.10        # Change threshold (10%)
    max_capital_discrepancy = 50.0   # Change threshold ($50)
    max_log_age_min = 30             # Change threshold (30 min)
    min_pair_win_rate = 0.40         # Change threshold (40%)
    max_consecutive_losses = 5       # Change threshold (5 losses)
}
```

**Example: More conservative (safer)**:

```powershell
min_win_rate = 0.50          # Only 50% WR acceptable (not 30%)
max_daily_drawdown = 0.05    # Only 5% DD allowed (not 10%)
max_capital_discrepancy = 20 # Only $20 discrepancy allowed
```

---

## Next Steps

### TODO:

- [ ] Add `Invoke-SafetyMonitor -Verbose` to end of `scan_master.ps1`
- [ ] Create `journal/safety_events.jsonl` (auto-created on first run)
- [ ] Run test: `.\scripts\test_safety_monitor.ps1`
- [ ] Verify Telegram alerts work (test critical scenario)
- [ ] Set-TradingMode -Mode LIVE when ready

### Integration Checklist:

```powershell
# 1. Load library
. agents/lib_safety_monitor.ps1

# 2. Run test
.\scripts\test_safety_monitor.ps1
# Expected: 4 scenarios showing different actions

# 3. Integrate into scan_master.ps1
# Add: $result = Invoke-SafetyMonitor -Verbose
# Add: if ($result.status -eq "CRITICAL") { exit 1 }

# 4. Set-TradingMode -Mode LIVE when ready
Set-TradingMode -Mode LIVE

# 5. First cycle runs with safety monitor active
.\scripts\scan_master.ps1 -Once
# Will see safety monitor checks at end of cycle

# Done!
```

---

## Monitoring

**Daily checklist:**

```powershell
# Morning
Show-SafetyReport
# Shows last 20 events

# Afternoon
Get-CapitalAudit
# Verify onchain vs journal consistent

# Evening
Invoke-SafetyMonitor -Verbose
# Full check with details
```

---

## FAQ

**Q: What if Safety Monitor triggers PAPER accidentally?**  
A: Check `Show-SafetyReport` to see why. Fix the issue, verify 3 clean cycles, switch back manually.

**Q: Can I disable Safety Monitor?**  
A: Not recommended. It's your safety net. If you must: comment out the `Invoke-SafetyMonitor` call in `scan_master.ps1`.

**Q: What if BTCUSDT crashes?**  
A: Monitor only. Never disabled. If it stays low-quality for 2+ weeks, consider pausing BTCUSDT trades manually (but system won't auto-disable).

**Q: How often does it check?**  
A: Every cycle of `scan_master.ps1`. Default every 15 minutes (or 5 minutes if you scale).

**Q: What if I want stricter rules?**  
A: Edit `$script:SafetyConfig` thresholds. Make them tighter (smaller %).

---

**Status**: ✅ READY FOR LIVE  
**All 6 checks**: Automated  
**Your job**: Monitor logs + Telegram alerts  
**System's job**: Protect capital automatically

Let's go! 🚀
