# 📋 TORI PAPER DEPLOYMENT PLAN — 30 Days Monitoring

**Data**: 2026-05-23 02:50 BRT  
**Status**: **READY FOR DEPLOYMENT** ✅  
**Mode**: PAPER (no real trades)  
**Duration**: 30 days  
**Objective**: Validate Tori optimized in production

---

## 🎯 DEPLOYMENT CHECKLIST

### PRE-DEPLOYMENT:

- [x] Integration tests passed (11/11) ✅
- [x] Configuration validated ✅
- [x] Regime filter implemented ✅
- [x] Take-profit +5% implemented ✅
- [x] Documentation complete ✅
- [ ] Monitoring dashboard created
- [ ] Alerts configured
- [ ] PAPER mode flag set

### DEPLOYMENT:

- [ ] Set `$TORI_PAPER_MODE = $true`
- [ ] Enable Tori in orchestrator
- [ ] Start monitoring cron
- [ ] Verify first signal (dry-run)
- [ ] Confirm logging working

### POST-DEPLOYMENT:

- [ ] Daily health checks
- [ ] Weekly performance reviews
- [ ] Monthly deep analysis
- [ ] Decision: LIVE or ABORT

---

## 🔧 CONFIGURATION

### TORI OPTIMIZED CONFIG:

```powershell
# Mode
$TORI_PAPER_MODE = $true  # PAPER only (no real trades)

# Trendline (VALIDATED)
$TORI_MIN_TOUCHES = 3
$TORI_SLOPE_MIN = 5.0
$TORI_SLOPE_MAX = 35.0
$TORI_PROXIMITY_MIN = -3.0
$TORI_PROXIMITY_MAX = 5.0

# Regime filter (VALIDATED: +2.50pp)
$TORI_REGIME_FILTER = "OTHER"  # Only other years
$TORI_OTHER_YEARS = @(2012, 2016, 2019, 2023, 2026, 2027, 2028)
$TORI_BULL_YEARS = @(2013, 2017, 2020, 2021, 2024, 2025)  # AVOID
$TORI_BEAR_YEARS = @(2014, 2015, 2018, 2022)  # AVOID

# Take-profit (VALIDATED: +4.30pp, p=0.0087)
$TORI_TAKE_PROFIT_PCT = 5.0  # Exit at +5%

# Stop-loss
$TORI_STOP_LOSS_PCT = 2.0  # -2% below trendline

# Max hold time
$TORI_MAX_HOLD_DAYS = 20  # h20 (20 days max)
```

---

## 📊 MONITORING PLAN (30 DAYS)

### DAILY CHECKS:

**Automated** (cron every 6h):
- [ ] System health (all agents running?)
- [ ] Signals detected (how many?)
- [ ] Signals executed (PAPER mode)
- [ ] Errors/warnings (any issues?)

**Manual** (daily review):
- [ ] Review signals (quality check)
- [ ] Review regime filter (working?)
- [ ] Review TP/SL logic (correct?)
- [ ] Review logs (any anomalies?)

### WEEKLY REVIEWS:

**Performance** (every Sunday):
- [ ] Signals count (vs expected 23.4/year = ~0.5/week)
- [ ] Win rate (vs expected 74.5%)
- [ ] Median edge (vs expected +5.00%)
- [ ] TP hit rate (how many hit +5%?)
- [ ] SL hit rate (how many hit stop?)

**Quality** (every Sunday):
- [ ] False positives (signals that shouldn't trigger)
- [ ] False negatives (missed opportunities)
- [ ] Regime filter accuracy (blocking correctly?)
- [ ] Integration issues (any bugs?)

### MONTHLY DEEP ANALYSIS:

**After 30 days**:
- [ ] Total signals (expected ~2)
- [ ] Win rate (vs expected 74.5%)
- [ ] Median edge (vs expected +5.00%)
- [ ] Statistical significance (enough sample?)
- [ ] Comparison with backtest (aligned?)

**Decision criteria**:
- ✅ **LIVE**: If median edge > +3% AND win rate > 65%
- ⚠️ **EXTEND**: If sample size < 10 signals (need more data)
- ❌ **ABORT**: If median edge < 0% OR win rate < 50%

---

## 📈 METRICS TO COLLECT

### SIGNAL METRICS:

```json
{
  "signal_id": "tori_20260523_001",
  "timestamp": "2026-05-23T02:50:00Z",
  "market": "BTCUSDT",
  "year": 2026,
  "regime": "OTHER",
  "trendline": {
    "touches": 3,
    "slope_deg": 12.5,
    "proximity_pct": 1.2,
    "action_line": 95000,
    "quality": "A"
  },
  "entry": {
    "price": 95500,
    "timestamp": "2026-05-23T03:00:00Z",
    "take_profit": 100275,  // +5%
    "stop_loss": 93100      // -2% below trendline
  },
  "exit": {
    "price": 100275,
    "timestamp": "2026-05-25T10:00:00Z",
    "reason": "TP_HIT",
    "pnl_pct": 5.00,
    "hold_days": 2.3
  },
  "outcome": "WIN"
}
```

### AGGREGATE METRICS:

```json
{
  "period": "2026-05-23 to 2026-06-23",
  "days": 30,
  "signals": {
    "total": 2,
    "wins": 1,
    "losses": 1,
    "win_rate": 50.0
  },
  "edge": {
    "mean": 2.50,
    "median": 2.50,
    "std": 3.54
  },
  "exits": {
    "tp_hit": 1,
    "sl_hit": 1,
    "h20_timeout": 0
  },
  "hold_time": {
    "mean_days": 5.5,
    "median_days": 5.5
  },
  "regime_filter": {
    "signals_blocked": 5,
    "bull_years": 3,
    "bear_years": 2
  }
}
```

---

## 🚨 ALERTS CONFIGURATION

### CRITICAL ALERTS (Immediate):

1. **System down**: Any agent crashes
2. **API error**: CoinEx API failures
3. **Data error**: Missing OHLCV data
4. **Logic error**: Invalid signal (should never happen)

### WARNING ALERTS (Daily digest):

1. **No signals**: 7+ days without signals (expected ~0.5/week)
2. **Too many signals**: 5+ signals/week (may be bug)
3. **Regime filter**: Blocking all signals (check year config)
4. **Performance**: Win rate < 50% after 10+ signals

### INFO ALERTS (Weekly digest):

1. **Signal detected**: New Tori signal (PAPER mode)
2. **TP hit**: Signal reached +5% TP
3. **SL hit**: Signal hit stop-loss
4. **Weekly summary**: Performance metrics

---

## 📁 LOGGING STRUCTURE

### LOG FILES:

```
journal/
├── tori_paper_signals_2026_05.jsonl      # All signals (one per line)
├── tori_paper_daily_2026_05_23.json      # Daily summary
├── tori_paper_weekly_2026_W21.json       # Weekly summary
└── tori_paper_monthly_2026_05.json       # Monthly summary
```

### SIGNAL LOG FORMAT:

```jsonl
{"ts":"2026-05-23T02:50:00Z","signal_id":"tori_001","market":"BTCUSDT","regime":"OTHER","entry":95500,"tp":100275,"sl":93100}
{"ts":"2026-05-25T10:00:00Z","signal_id":"tori_001","event":"TP_HIT","exit":100275,"pnl_pct":5.00,"hold_days":2.3}
```

---

## 🎯 SUCCESS CRITERIA (30 DAYS)

### MINIMUM VIABLE:

- [ ] System runs without crashes (99% uptime)
- [ ] Signals detected (at least 1 signal)
- [ ] Regime filter working (blocks bull/bear years)
- [ ] TP/SL logic working (correct calculations)
- [ ] Logging working (all data captured)

### PERFORMANCE TARGETS:

- [ ] Median edge > +3.00% (vs +5.00% expected)
- [ ] Win rate > 65% (vs 74.5% expected)
- [ ] TP hit rate > 50% (most exits at +5%)
- [ ] No false positives (all signals valid)

### DECISION CRITERIA:

**GO LIVE** if:
- ✅ Median edge > +3.00%
- ✅ Win rate > 65%
- ✅ Sample size >= 10 signals
- ✅ No critical bugs

**EXTEND PAPER** if:
- ⚠️ Sample size < 10 signals (need more data)
- ⚠️ Performance close to targets (need confirmation)

**ABORT** if:
- ❌ Median edge < 0%
- ❌ Win rate < 50%
- ❌ Critical bugs (logic errors)

---

## 🔧 DEPLOYMENT SCRIPT

### STEP 1: Enable PAPER mode

```powershell
# config.ps1 or config.local.ps1
$global:TORI_PAPER_MODE = $true
$global:TORI_ENABLED = $true
```

### STEP 2: Verify configuration

```powershell
# Test script
.\tests\test_tori_optimized_integration.ps1
# Expected: All tests pass (11/11)
```

### STEP 3: Start monitoring

```powershell
# Start monitoring cron (every 15min)
# This will check for Tori signals and log them
.\scripts\tori_monitoring_cron.ps1
```

### STEP 4: Verify first signal (dry-run)

```powershell
# Manually trigger Tori check
$result = Get-ToriProximity -Market "BTCUSDT"

if ($result.setup_ripening) {
    Write-Host "✅ Signal detected (PAPER mode)" -ForegroundColor Green
    Write-Host "  Market: $($result.market)"
    Write-Host "  Entry: $($result.price)"
    Write-Host "  TP: $($result.take_profit)"
    Write-Host "  SL: $($result.stop_loss)"
} else {
    Write-Host "⏳ No signal yet (reason: $($result.reason))" -ForegroundColor Yellow
}
```

---

## 📊 DASHBOARD (Simple)

### DAILY VIEW:

```
╔════════════════════════════════════════════════════════════╗
║           TORI PAPER MODE - DAILY DASHBOARD               ║
║                    2026-05-23                              ║
╠════════════════════════════════════════════════════════════╣
║ STATUS:        ✅ RUNNING                                  ║
║ UPTIME:        24h (100%)                                  ║
║ SIGNALS TODAY: 0                                           ║
║ SIGNALS TOTAL: 0                                           ║
╠════════════════════════════════════════════════════════════╣
║ PERFORMANCE (30 days):                                     ║
║   Signals:     0                                           ║
║   Win rate:    N/A                                         ║
║   Median edge: N/A                                         ║
║   TP hit rate: N/A                                         ║
╠════════════════════════════════════════════════════════════╣
║ REGIME FILTER:                                             ║
║   Current year: 2026 (OTHER) ✅                            ║
║   Signals blocked: 0                                       ║
╠════════════════════════════════════════════════════════════╣
║ NEXT STEPS:                                                ║
║   - Wait for first signal                                  ║
║   - Monitor daily                                          ║
║   - Review weekly                                          ║
╚════════════════════════════════════════════════════════════╝
```

---

## 🚀 DEPLOYMENT TIMELINE

### TODAY (2026-05-23):

- [x] Integration tests ✅
- [ ] Enable PAPER mode
- [ ] Start monitoring
- [ ] Verify first check

### WEEK 1 (2026-05-23 to 2026-05-30):

- [ ] Daily health checks
- [ ] Wait for first signal
- [ ] Verify regime filter
- [ ] Weekly review (Sunday)

### WEEK 2-4 (2026-05-30 to 2026-06-23):

- [ ] Continue monitoring
- [ ] Collect signals
- [ ] Weekly reviews
- [ ] Adjust if needed

### DAY 30 (2026-06-23):

- [ ] Monthly deep analysis
- [ ] Compare with backtest
- [ ] Decision: LIVE / EXTEND / ABORT

---

**Status**: READY FOR DEPLOYMENT  
**Next step**: Enable PAPER mode + Start monitoring 🚀  
**Expected**: 2 signals in 30 days, 74.5% win rate, +5.00% median edge
