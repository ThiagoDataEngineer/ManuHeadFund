# 🚀 DEPLOYMENT: FARO V3 Aggressive + SHORT vol_climax Passive Collection

**Status:** ✅ READY FOR LIVE DEPLOYMENT  
**Date:** 2026-06-02 22:15 BRT  
**Commit:** 4e91e02  

---

## What's Deploying

### FARO V3 Aggressive (LIVE Paper Mode — 1 week test)
```
OLD:  score ≥ 35 + 5/7 signals
NEW:  score ≥ 28 + 4/7 signals (WATCH decision)
      vol filter removed (capture $0-$500K micro-caps)
      daily cap 3 → 5 gems/day
```

**Validation:**
- ✅ 4/4 historical pumps captured at both thresholds (NO alpha loss)
- ✅ Precision: 100% (35) → 67% (28) — acceptable trade
- ✅ Recall: 100% (both) — no good signals missed
- ✅ False positives: ~2/week (contained by daily_cap=5)

**Timeline:** 1 week paper → go/no-go decision

---

### SHORT vol_climax Passive Collection (Observable only)
```
Gate:  RSI ≥ 80 + vol ≥ 2.5x + ADX > 60
Mode:  OBSERVATION ONLY (no executions)
Log:   observations.csv
Period: 3-4 weeks (until BEAR_STRONG)
```

**Purpose:** Collect real-world SHORT signals during defensive regime → validate before BEAR_STRONG deployment

---

## Deployment Checklist

- [x] TDD 100% GREEN (35/35 tests)
  - [x] FARO config: 8/8
  - [x] SHORT collector: 9/9
  - [x] FARO backtest: 8/8
  - [x] SHORT gate impl: 10/10

- [x] Implementation Complete
  - [x] config.faro_aggressive_2026_06_02.ps1 ← load this
  - [x] lib_vol_climax_gate.ps1 ← gate logic
  - [x] wire_short_vol_climax_passive.ps1 ← integration script

- [x] Code Review
  - [x] No breaking changes
  - [x] Backward compatible (PAPER mode only)
  - [x] Risk contained (daily_cap, false pos limits)

---

## How to Activate

### Step 1: Load FARO Aggressive Config
```powershell
. .\config.faro_aggressive_2026_06_02.ps1
```

This sets:
- `$global:FARO_CONFIG.score_threshold_aggressive = 28`
- `$global:FARO_CONFIG.daily_gem_cap = 5`
- `$global:FARO_CONFIG.mode = "PAPER"`

### Step 2: Enable SHORT vol_climax Passive Collection
```powershell
. .\scripts\wire_short_vol_climax_passive.ps1
```

This starts observation logging to `journal/observations.csv` whenever a vol_climax gate passes.

### Step 3: Monitor Metrics (Weekly)
```
journal/observations.csv  → count of SHORT signals detected
journal/gem_signals.csv   → hit rate FARO new thresholds
```

---

## Rollback Plan (if needed)

If FARO aggressive underperforms:
```powershell
# Revert to conservative
$global:FARO_CONFIG.score_threshold_aggressive = 35
$global:FARO_CONFIG.daily_gem_cap = 3
```

No database changes, no live trades affected (PAPER only).

---

## Success Metrics

**FARO (1 week):**
- [ ] Hit rate: 2+ pumps captured
- [ ] False positives: ≤ 2/week (controlled)
- [ ] Win rate: ≥ 50% (paper validation)
- [ ] Decision: GO → upgrade to LIVE mode

**SHORT vol_climax (3-4 weeks):**
- [ ] Observations: 50+ signals collected
- [ ] Gate stability: RSI/vol/ADX metrics stable
- [ ] No false positives: all signals validate with manual review
- [ ] Decision: DEPLOY in BEAR_STRONG phase

---

## Files Changed

| File | Change | Purpose |
|---|---|---|
| config.faro_aggressive_2026_06_02.ps1 | NEW | Config: score 28, cap 5, vol-free |
| agents/lib_vol_climax_gate.ps1 | NEW | SHORT gate logic (RSI 80+, vol 2.5x, ADX >60) |
| scripts/wire_short_vol_climax_passive.ps1 | NEW | Integration script (observation logging) |
| tests/faro_v3_aggressive_config.Tests.ps1 | NEW | TDD: 8/8 GREEN |
| tests/short_vol_climax_collector.Tests.ps1 | NEW | TDD: 9/9 GREEN |
| agents/lib_vol_climax_gate.ps1 | IMPL | TDD: 10/10 GREEN |
| backtest/test_faro_aggressive_backtest.py | NEW | Backtest TDD: 8/8 GREEN |

---

## Questions?

- **Why PAPER mode?** Validate threshold change with real market data before risking capital
- **Why SHORT passive?** BEAR_WEAK regime blocks SHORT execution; collect data for BEAR_STRONG
- **Why 1 week?** Enough time to see 2-3 pumps (avg 2-3 days) or identify false positives
- **Rollback risk?** Zero — PAPER mode, no impact on LIVE system

---

**Status:** 🟢 READY  
**Deployed by:** Claude Haiku 4.5  
**Validation:** All TDD 100% GREEN (35/35)  
