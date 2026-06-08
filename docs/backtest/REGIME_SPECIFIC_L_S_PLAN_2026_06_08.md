# 📊 Regime-Specific L+S Backtest Plan

**Date:** 2026-06-08  
**Purpose:** Validate LONG and SHORT separately per market regime  
**Baseline:** CHAINED_AB_V6_FINDINGS.md (SHORT +2.85% EV / LONG ≈0% in BULL_WEAK)

---

## 🎯 HYPOTHESIS

| Regime | LONG Expected | SHORT Expected | Reality Check |
|--------|---------------|-----------------|-----------------|
| **BULL_STRONG** | ✅ +5-10% | ❌ -3-5% | Need validation |
| **BULL_WEAK** | ⚠️ -0.76% | ✅ Positive? | SHORT edge confirmed +2.85pp |
| **BEAR_WEAK** (current) | ❌ -2% | ✅ +3-8% | **Priority: validate SHORT wins** |
| **BEAR_STRONG** | ❌ -5% | ❌ -2% | Both bad, stay out |

**Key Question:** In BEAR_WEAK (current regime), does SHORT systematically outperform LONG?

---

## 📈 BACKTEST STRUCTURE

### Phase 1: Regime Separation (1h)

**Data Source:** Historical CoinEx OHLCV (1d+ candles)

**Regime Classification:**
```
Input: BTC dominance, BTC price trend, vol structure, RSI
↓
Output: BULL_STRONG | BULL_WEAK | BEAR_WEAK | BEAR_STRONG
↓
Split signals dataset by regime
```

**Expected Distribution (from memory):**
- BULL_STRONG: ~15% of 7.4 years (0.5-0.8 years)
- BULL_WEAK: ~25% (1.8-2 years)
- BEAR_WEAK: ~40% (3 years) ← We are here
- BEAR_STRONG: ~20% (1.5 years)

### Phase 2: Backtest Runs (6-8h total)

#### 2a. Baseline: LONG-only per regime
```python
for regime in [BULL_STRONG, BULL_WEAK, BEAR_WEAK, BEAR_STRONG]:
    signals = filter(signals, regime)
    results = backtest(signals, direction=LONG)
    
    Report:
      - n_signals
      - hit_rate %
      - EV_net %
      - Sharpe
      - Max DD
      - Win/Loss ratio
```

**Expected:** 
- BULL_STRONG: high hit%, positive EV
- BEAR_WEAK: low hit%, negative/neutral EV
- (validates hypothesis that LONG struggles in BEAR)

#### 2b. SHORT-only per regime
```python
for regime in [BULL_STRONG, BULL_WEAK, BEAR_WEAK, BEAR_STRONG]:
    signals = filter(signals, regime)
    results = backtest(signals, direction=SHORT)
    
    Report: same metrics
```

**Expected:** 
- BULL_WEAK: positive EV (confirmed +2.85pp)
- BEAR_WEAK: positive EV (likely 3-5%)
- BULL_STRONG: negative EV (SHORT loses in bull)
- (validates SHORT as regime hedge)

#### 2c. LONG+SHORT mixed per regime
```python
for regime in [BULL_STRONG, BULL_WEAK, BEAR_WEAK, BEAR_STRONG]:
    long_signals = filter(signals, regime, direction=LONG)
    short_signals = filter(signals, regime, direction=SHORT)
    
    # Execute both, cap SHORT <= LONG risk
    results = backtest_mixed(long_signals, short_signals, risk_parity=True)
    
    Report:
      - n_long / n_short
      - combined_hit %
      - combined_EV %
      - Sharpe (vs LONG-only)
      - DD improvement vs LONG-only
      - Calmar ratio
```

**Expected:**
- BEAR_WEAK: Sharpe +20-30% vs LONG-only (SHORT offsets LONG losses)
- BULL_STRONG: Sharpe ≈ LONG-only (SHORT dilutes, caps it)
- Overall: **Consistent outperformance across regimes**

### Phase 3: Risk Parity Tuning (2h)

**Question:** What's optimal SHORT/LONG risk split per regime?

```python
for regime in [BULL_STRONG, BULL_WEAK, BEAR_WEAK]:
    for short_cap_ratio in [0.25, 0.50, 0.75, 1.0]:
        results = backtest_mixed(..., short_cap_ratio)
        metrics[regime][ratio] = {sharpe, dd, calmar}

Visualize: heatmap (regime × ratio)
```

**Expected:**
- BULL_STRONG: short_cap ≤ 0.25 (SHORT is noise)
- BEAR_WEAK: short_cap ≈ 0.75-1.0 (SHORT is profit driver)
- BULL_WEAK: short_cap ≈ 0.50 (balanced)

---

## 📋 DELIVERABLES

### Output 1: Regime-Specific Performance Table
```
| Regime | Direction | n_sig | Hit% | EV_net | Sharpe | DD_max |
|--------|-----------|-------|------|--------|--------|--------|
| BULL_STRONG | LONG | 120 | 78% | +8.1% | 2.3 | -12% |
| BULL_STRONG | SHORT | 45 | 32% | -2.4% | -0.8 | -18% |
| BULL_STRONG | L+S | 165 | 65% | +5.8% | 1.9 | -14% |
|---|---|---|---|---|---|---|
| BEAR_WEAK | LONG | 95 | 42% | -0.5% | 0.1 | -22% |
| BEAR_WEAK | SHORT | 110 | 61% | +3.2% | 1.6 | -10% |
| BEAR_WEAK | L+S | 205 | 52% | +1.5% | 1.4 | -12% |
| (etc) |
```

### Output 2: Regime Recommendation Matrix
```
IF regime = BULL_STRONG  → Execute LONG-only (avoid SHORT, cap 10% max)
IF regime = BULL_WEAK    → Execute LONG > SHORT (70/30 split, SHORT hedge)
IF regime = BEAR_WEAK    → Execute SHORT > LONG (cap SHORT=LONG, asymmetric)
IF regime = BEAR_STRONG  → SKIP both (stay cash)
```

### Output 3: Forward Testing Protocol
```
Weekly:
  - Classify current regime
  - Check which (L/S/both) approved by backtest
  - Log actual trade outcomes vs backtest expectations
  - Re-validate every 4 weeks (regime may shift)
```

---

## 🔧 IMPLEMENTATION (pseudocode)

```powershell
# Load historical signals + regime labels
$signals = Import-AllHistoricalSignals
$regimes = Import-RegimeTimeseries

# Phase 2a: LONG-only
foreach ($r in @("BULL_STRONG","BULL_WEAK","BEAR_WEAK","BEAR_STRONG")) {
    $regime_signals = $signals | Where regime -eq $r
    $results_long = Invoke-Backtest -Signals $regime_signals -Direction LONG
    Export-Results $results_long
}

# Phase 2b: SHORT-only
foreach ($r in @(...)) {
    $regime_signals = $signals | Where regime -eq $r
    $results_short = Invoke-Backtest -Signals $regime_signals -Direction SHORT
    Export-Results $results_short
}

# Phase 2c: L+S mixed
foreach ($r in @(...)) {
    $long_sigs = $signals | Where {$_.regime -eq $r -and $_.direction -eq "LONG"}
    $short_sigs = $signals | Where {$_.regime -eq $r -and $_.direction -eq "SHORT"}
    $results_mixed = Invoke-BacktestMixed -Long $long_sigs -Short $short_sigs -RiskParity
    Export-Results $results_mixed
}
```

---

## 📅 TIMELINE

| Phase | Task | Duration | Owner |
|-------|------|----------|-------|
| 1 | Regime classification algorithm | 1h | Claude |
| 2a | LONG-only backtest × 4 regimes | 2h | Claude |
| 2b | SHORT-only backtest × 4 regimes | 2h | Claude |
| 2c | L+S mixed backtest × 4 regimes | 2h | Claude |
| 3 | Risk parity optimization | 2h | Claude |
| — | **Subtotal** | **9h** | |
| 4 | Manual validation + interpretation | 1h | Thiago |
| 5 | Update trading rules (if validated) | 0.5h | Thiago |
| — | **TOTAL** | **10.5h** | |

---

## ✅ SUCCESS CRITERIA

**Must Have:**
1. ✅ SHORT EV > LONG EV in at least 2 regimes (BULL_WEAK + BEAR_WEAK)
2. ✅ L+S Sharpe improvement > 10% in at least 1 regime
3. ✅ No regime where L+S Sharpe < LONG-only (neutral OK, decline = fail)

**Should Have:**
1. 📊 Short/Long risk parity recommendation per regime
2. 📊 Hit rate differential (SHORT higher in bear, LONG higher in bull)
3. 📊 Forward-testing protocol ready

**Nice to Have:**
1. 📈 Correlation matrix (L vs S per regime)
2. 📈 Drawdown recovery patterns
3. 📈 Win/loss ratio trending

---

## 🎯 DECISION GATE

**IF success criteria met:**
→ Deploy LIVE with regime-specific rules  
→ Monitor weekly outcomes vs backtest  
→ Adjust capital allocation per regime

**IF fail (SHORT doesn't outperform):**
→ Investigate: MinMax detection working? Momentum scoring biased?  
→ Return to LONG-only  
→ File learnings in feedback loop

---

## 📝 NOTES

- **Regime classification:** Use BTC dominance + price trend + Halving phase (already in codebase)
- **Signal source:** Existing backtest dataset (should have direction field from previous runs)
- **Risk parity:** Currently `SHORT ≤ LONG` (can parameterize per regime)
- **Timeline:** Realistic 10.5h if all libs + data ready; else +3-5h for setup

---

**Status:** READY TO EXECUTE  
**Recommended Start:** Next session (after GEM_LOOP live validation completes)

