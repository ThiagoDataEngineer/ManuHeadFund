# PHASE 3 TRACKER — Live Monitoring
**Started:** 2026-06-09 22:40 BRT  
**Duration:** 24-72 hours (continuous monitoring)  
**Goal:** Validate vol_climax edge in live market conditions  

---

## Success Criteria

| Metric | Target | Status | Notes |
|--------|--------|--------|-------|
| Signals detected | 5-10 | ⏳ 0 | Waiting for next GemScan cycle |
| Win rate | 45%+ | ⏳ N/A | Need min 5 trades to evaluate |
| Zero crashes | 100% | ⏳ Monitoring | gem_loop running |
| Audit trail | Complete | ✅ Active | trade_outcomes.jsonl logging |
| Score boost visible | Yes | ✅ Ready | [VC] markers in log |

---

## Monitoring Instructions

### Real-time Log Tail
```powershell
# Terminal 1: Watch for [VC] messages
pwsh scripts/monitor_vol_climax.ps1

# Terminal 2: Watch for GemScan cycles
Get-Content journal/gem_loop.log -Wait -Tail 20
```

### Live Report (Every 5 sec)
```powershell
# Terminal 3: Auto-refreshing report
pwsh scripts/monitor_vol_climax.ps1 -Report
```

### Manual Check
```powershell
# Check for vol_climax signals
Get-Content journal/gem_loop.log | Select-String "\[VC\]"

# Latest trades
Get-Content journal/trade_outcomes.jsonl | Select-Object -Last 5
```

---

## Timeline & Checkpoints

### Hour 1 (22:40-23:40 BRT)
- [ ] gem_loop running without crashes
- [ ] Next GemScan cycle starts (~23:27)
- [ ] Monitor for [VC] messages

### Hour 24 (22:40 BRT → 2026-06-10 22:40 BRT)
- [ ] 3-5 vol_climax signals expected
- [ ] Initial win rate visible
- [ ] Decision: continue or investigate

### Hour 72 (by 2026-06-12 22:40 BRT)
- [ ] 8-15 vol_climax signals collected
- [ ] Final win rate >= 45% or < 35%
- [ ] Decision: Phase 4 (scale) or rollback

---

## Auto-Checklist (Run hourly)

```powershell
# Copy/paste into terminal every hour:
Clear-Host
Write-Host "=== Phase 3 Checkpoint ===" -ForegroundColor Cyan
Get-Content journal/gem_loop.log -Tail 50 | Select-String "\[VC\]|GemScan:|ERROR"
Write-Host ""
Write-Host "Trades:" -ForegroundColor Cyan
(Get-Content journal/trade_outcomes.jsonl | Measure-Object -Line).Lines
```

---

## Expected Behavior

### When vol_climax Detected
```
[22:42] [CYCLE] Iniciando GemScan
[22:43] [GEM] SOMEUSDT score=50 mode=DISCOVERY
[22:43] [VC] boost +20 (50→70)  ← This line = vol_climax working!
[22:44] [GEM] signal ready for execution
```

### When Trade Executes
```
[22:45] Trade executed: SOMEUSDT LONG @ price
[22:46] new trade logged to trade_outcomes.jsonl
[2026-06-11] Exit signal (stop/target)
[2026-06-11] Trade closed: +0.5% or -1.2%
```

---

## Failure Modes & Recovery

| Failure | Signal | Recovery |
|---------|--------|----------|
| No [VC] messages | 24h+ with 0 detections | Check vol_climax code logic |
| gem_loop crashes | ERROR in log | Restart via `scripts/restart_gem_loop.ps1` |
| Win rate < 35% | Losses pile up | Investigate signal timing, rollback if <20% |
| Capital violated | Trade size > $109 | Manual cap enforcement, proceed carefully |

---

## Live Data Points

### To Collect
- Timestamp of each vol_climax detection
- Score before/after boost
- Market detected
- Trade executed? (yes/no)
- If trade: entry price, exit price, PnL
- Time from signal to exit

### To Calculate
- Detection frequency (signals per hour)
- Win rate on vol_climax trades
- Avg win vs avg loss
- Profit factor
- Slippage vs backtest

---

## Decision Tree

```
IF vol_climax signals detected (5+) THEN
  IF win_rate >= 45% THEN
    ✅ Phase 4: Scale to 60% capital
  ELSE IF win_rate >= 35% THEN
    ⏳ Continue monitoring (+24h more data)
  ELSE (win_rate < 35%) THEN
    ❌ Rollback + investigate
ELSE (0 signals in 24h) THEN
  ⚠️ Debug vol_climax logic / market conditions
```

---

## Notes to Self

- [ ] Don't panic if no signals in first cycle (market volatility)
- [ ] vol_climax is selective (1.2% detection rate) — that's OK
- [ ] Each signal should be high quality (55% backtest)
- [ ] Slippage will reduce live win rate by ~10-15pp (normal)
- [ ] Current baseline is 33% — any improvement is progress

---

## Key Metrics Dashboard

**Live Tracking:**
```
Monitoring since:    2026-06-09 22:40 BRT
Elapsed time:        [START]
vol_climax signals:  0/5-10
Win rate:            N/A (need >=5 trades)
Daemon uptime:       [CHECK]
Latest trade:        [NONE YET]
```

---

## Next Review Checkpoint

**2026-06-10 22:40 BRT** (24h from start)

Status report:
- How many vol_climax signals detected?
- How many trades executed?
- What's the win rate?
- Should we continue to 72h or decide now?

---

**Status:** 🟢 **PHASE 3 LIVE MONITORING ACTIVE**

Monitor, don't force. Let vol_climax edge show itself naturally in market conditions.

*Keep this file updated hourly with checkpoints.*
