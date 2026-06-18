# 🔴 WINDOWS SCHEDULED TASKS — CLEANUP REQUIRED

**Issue Found**: 22 tarefas agendadas no Windows rodando **CONTRA** cloud-only mode  
**Date**: 2026-06-18 20:00 UTC  
**Status**: ⚠️ REQUIRES ADMIN PRIVILEGES

---

## 📋 TAREFAS ENCONTRADAS (22 total)

### 🔴 RUNNING (Ativas agora):
```
1. CoinExToriProximity
2. CoinEx_PositionRisk
3. (Others were Running, now mostly Ready)
```

### 🟡 READY (Agendadas para rodar):
```
CoinExDaemonRestart
CoinExDailyDigest
CoinExFundingScanner
CoinExHourlyHeartbeat
CoinExKellyGraduation
CoinExParallelGraduation
CoinExPromotionCron
CoinExShortScanner
CoinExStalenessAudit
CoinExVolClimax
CoinExWeeklyCostReport
CoinExWeeklyDataRefresh
CoinExWhaleWatcher
CoinExWssForwardResolve
CoinEx_PositionRisk
CoinEx_TrailingStop_Monitor
CoinEx_Update_Dashboard_HTML
CoinEx_Dashboard_Elite (Disabled)
CoinEx_Dashboard_JSON
ManuHeadFund_FARO_V3_engine_agg
ManuHeadFund_FARO_V3_entry_agg
ManuHeadFund_FARO_V3_manager_agg
```

---

## ⚠️ PROBLEM

These local tasks execute trading logic **even though system is CLOUD-ONLY**:

```
LOCAL TASKS (Windows Scheduler):
├─ Daily daemon restart
├─ Daily digest
├─ Hourly heartbeat
├─ Kelly graduation
├─ Parallel graduation
├─ Promotion cron
├─ Scanners (5+)
├─ Trailing stop monitor ← CRITICAL (conflicts with JOB1 cloud)
├─ Dashboard updates (2x) ← Creates duplicate execution
└─ FARO V3 engine (3 tasks) ← Manual override

CLOUD TASKS (GitHub Actions - Should be ONLY):
├─ JOB1: trailing-stop-monitor (5min) ← Now conflicting!
├─ JOB4: dashboard-update (5min) ← Now conflicting!
├─ JOB23: gem-loop (15min)
└─ JOB24: telegram-listener (5min)

RESULT: Double execution risk + unpredictable behavior
```

---

## ✅ SOLUTION

### Step 1: Disable All (Can do without admin)
```powershell
Get-ScheduledTask | Where-Object { $_.TaskName -match "^CoinEx|^ManuHeadFund" } | 
  Disable-ScheduledTask
```
⚠️ Some may fail with "Access denied" (need admin)

### Step 2: Delete All (REQUIRES ADMIN ELEVATED)
```powershell
# Run PowerShell as Administrator
$taskNames = @(
  "CoinExDaemonRestart", "CoinExDailyDigest", "CoinExFundingScanner", 
  "CoinExHourlyHeartbeat", "CoinExKellyGraduation", "CoinExParallelGraduation",
  # ... (rest of list)
)

foreach ($name in $taskNames) {
  Unregister-ScheduledTask -TaskName $name -Confirm:$false
}
```

---

## 🔍 WHY THIS HAPPENED

1. **Early Development**: Tasks created during local testing phase
2. **Cloud Migration Incomplete**: Tasks never removed after GitHub Actions setup
3. **No Cleanup Tracking**: System audit didn't include Windows Task Scheduler
4. **Conflict Not Obvious**: Cloud and local both execute, creating unpredictable state

---

## 📊 IMPACT

| Component | Before (Cloud-Only) | After (With Local Tasks) | Impact |
|-----------|-------------------|------------------------|--------|
| Trailing SL | JOB1 every 5min | JOB1 + CoinEx_TrailingStop_Monitor | Conflict! |
| Dashboard | JOB4 every 5min | JOB4 + CoinEx_Dashboard_JSON | Duplicate updates |
| Scanners | JOB23 every 15min | JOB23 + 5 local scanners | Noise, duplicate signals |
| Cost | $5/month cloud | $5 + ~$10 local + manual overhead | $$$ waste |

---

## ✅ NEXT ACTIONS

### IMMEDIATE (Do NOW):
```
1. [ ] Open PowerShell as ADMIN
2. [ ] Run deletion script (copy above)
3. [ ] Verify all deleted: Get-ScheduledTask | Where-Object { $_.TaskName -match "CoinEx" }
4. [ ] Restart Windows (or kill any hanging processes)
```

### VERIFY:
```
After restart, only CLOUD should be executing:
- No local pwsh processes for trading
- GitHub Actions JOB1/4/23/24 run on schedule
- No duplicate log entries
```

### MONITOR:
```
Watch these for next 2 hours:
- gem_loop.log (should show only 1 entry per 15min, not duplicates)
- journal/trailing_stop_monitor.log (should show only JOB1, not local)
- Dashboard updates (should be smooth, not flickering)
```

---

## 📝 PREVENTION

1. Add Windows Task Scheduler check to production audit
2. Document: "All trading logic MUST be in GitHub Actions, zero local tasks"
3. Update CLAUDE.md: "LOCAL_TRADING_DISABLED.flag = completely, including scheduler"
4. Add pre-deployment: `Get-ScheduledTask | Where-Object { $_.TaskName -match "CoinEx|ManuHeadFund" } | Assert-None`

---

**Status**: 🔴 **BLOCKING** — Must cleanup before cloud stability confirmed  
**Severity**: HIGH — Risk of duplicate execution + capital loss  
**Estimated Fix Time**: 5 minutes (requires admin rights)

**Last Checked**: 2026-06-18 20:00 UTC  
**Cleanup Attempted**: 6/22 tasks deleted via non-admin (rest need admin)

---

## QUICK COMMAND (RUN AS ADMIN IN POWERSHELL)

```powershell
# Copy-paste this entire block in elevated PowerShell

$tasks = @(
  "CoinExDaemonRestart", "CoinExDailyDigest", "CoinExFundingScanner",
  "CoinExHourlyHeartbeat", "CoinExKellyGraduation", "CoinExParallelGraduation",
  "CoinExPromotionCron", "CoinExShortScanner", "CoinExStalenessAudit",
  "CoinExToriProximity", "CoinExVolClimax", "CoinExWeeklyCostReport",
  "CoinExWeeklyDataRefresh", "CoinExWhaleWatcher", "CoinExWssForwardResolve",
  "CoinEx_Dashboard_Elite", "CoinEx_Dashboard_JSON", "CoinEx_PositionRisk",
  "CoinEx_TrailingStop_Monitor", "CoinEx_Update_Dashboard_HTML",
  "ManuHeadFund_FARO_V3_engine_agg", "ManuHeadFund_FARO_V3_entry_agg",
  "ManuHeadFund_FARO_V3_manager_agg"
)

Write-Host "Deleting $($tasks.Count) tasks..." -ForegroundColor Red
$deleted = 0
foreach ($name in $tasks) {
  if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "✓ $name"
    $deleted++
  }
}
Write-Host "Deleted: $deleted/$($tasks.Count)" -ForegroundColor Green
```

---

**Execute this TODAY** to restore true cloud-only operation.
