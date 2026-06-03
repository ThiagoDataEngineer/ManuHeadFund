# 📈 SHORT vol_climax — Evolution to BEAR_STRONG Deployment

**Timeline:** 2026-06-02 → 2026-06-23 (3 semanas)  
**Current state:** OBSERVATION ONLY (827 lines in observations.csv)  
**Target:** LIVE SHORT execution when BEAR_STRONG phase detected

---

## 🎯 PHASE 1: Passive Collection + Fast Validation (Weeks 1-2)

### What we're doing NOW
- Every scan cycle: test vol_climax gate (RSI≥80, vol≥2.5x, ADX>60)
- **IF** gate passes → log to observations.csv (timestamp, market, RSI, vol_ratio, ADX, regime)
- **NO execution** (regime blocks, we're just collecting)

### Success metric for Phase 1
- **50+ signals** collected across different markets
- **Stability check**: avg RSI ≈ 82-85, vol_ratio ≈ 2.7-3.2, ADX ≈ 65-72
  - If metrics wildly vary → gate logic is noisy
  - If consistent → gate is detecting real exhaustion events

### Action (automatic, passive)
```powershell
# Already running in background via scan_master.ps1
# Every scan cycle:
if ($vol_climax_gate.passes) {
    Add-VolClimaxObservation -Path observations.csv -Market $market ...
}
```

---

## 🔍 PHASE 2: Post-Collection Analysis (Week 3, starts ~2026-06-16)

### What to do AFTER 50+ signals collected

1. **Export observations + cross-reference with trades**
   ```powershell
   # Read observations.csv
   $obs = Import-Csv .\journal\observations.csv | Where-Object { $_.signal_type -eq "vol_climax" }
   
   # For each observation, check: did price drop 1-5% in next 24h?
   # Mark as: TRUE_POSITIVE, FALSE_POSITIVE, STILL_PENDING
   ```

2. **Calculate gate reliability**
   - TRUE_POSITIVE rate: % of signals where price fell 1-5% post-signal
   - FALSE_POSITIVE rate: % where price rallied instead
   - Target: ≥60% TRUE_POSITIVE (better than random)

3. **Identify "golden markets"**
   - Which markets trigger vol_climax most reliably?
   - Example: BTCUSDT 70% hit rate vs ALTCOINXYZ 20% hit rate
   - Use golden markets for initial deployment

### Files created in Phase 2
- `journal/vol_climax_validation_2026_06_16.csv`
  - Columns: ts, market, signal_date, price_1d_later, pct_change, result (TRUE_POS/FALSE_POS)
- `journal/vol_climax_reliability_report.md`
  - Summary by market: hit rates, false pos, confidence

---

## ⚙️ PHASE 3: Prepare LIVE SHORT Execution (Week 3, starts ~2026-06-18)

### Current SHORT stack (already coded, waiting for deployment)

**Files ready:**
- `agents/lib_enhanced_short_entry.ps1` — SHORT entry logic
- `agents/lib_signal_generator_short.ps1` — signal generation
- `agents/lib_short_execution.ps1` — CoinEx SHORT order placement

**What we need to wire:**
```powershell
# Current flow (OBSERVATION ONLY):
if (vol_climax_gate.passes) {
    Add-VolClimaxObservation ...  # just logging
}

# NEW flow (LIVE execution):
if (vol_climax_gate.passes AND $currentRegime -eq "BEAR_STRONG") {
    $signal = New-ShortSignal -Market $market -EntryPrice $price -StopLoss $sl -Target $target
    $order = Invoke-ShortExecution -Signal $signal -Size (Get-SizingPercentage)
    
    # Log execution
    Add-TradeRecord -Type "SHORT_VOL_CLIMAX" -Signal $signal -ExecutionId $order.id
}
```

### Pre-deployment checklist

- [x] vol_climax gate: 10/10 tests GREEN
- [ ] SHORT entry logic: must pass tests (TDD)
- [ ] SHORT execution: must pass capital safety tests (race/retry/idempotency)
- [ ] Regime detection: confirm BEAR_STRONG trigger works
- [ ] Risk sizing: 1% per SHORT vol_climax trade
- [ ] Stop loss: automated (liquidation risk + ATR buffer)
- [ ] Target: RSI <30 exit OR 5R exit (whichever first)

---

## 🚀 PHASE 4: Deploy in BEAR_STRONG (Week 4, ~2026-06-23)

### How deployment works

**Trigger:** `Get-HalvingPhase` returns BEAR_STRONG

```powershell
# In scan_master.ps1 main loop:
$regime = Get-HalvingPhase
$vol_climax = Test-VolClimaxGate -RSI $rsi -CurrentVolume $vol ...

if ($vol_climax.passes -and $regime -eq "BEAR_STRONG") {
    # EXECUTION PATH
    $order = Invoke-ShortExecution -Signal $signal -Capital (Get-AvailableCapital)
    
    # Trailing stop auto-activates
    Start-TrailingStop -OrderId $order.id -Mode "EXHAUSTION"
}
elseif ($vol_climax.passes) {
    # OBSERVATION PATH (BEAR_WEAK, BEAR_NEUTRAL, etc.)
    Add-VolClimaxObservation ...
}
```

### Deployment steps (when BEAR_STRONG is detected)

1. **Enable flag:**
   ```powershell
   $env:SHORT_VOL_CLIMAX_LIVE = 1
   ```

2. **Verify regime detection:**
   ```powershell
   pwsh .\agents\lib_halving_phase_detector.ps1  # should return BEAR_STRONG
   ```

3. **Start trading:**
   - scan_master.ps1 begins SHORT execution on vol_climax signals
   - Trailing stop auto-engages
   - Risk: 1% capital per trade, max 5 concurrent SHORTs

4. **Monitor (hourly):**
   ```powershell
   pwsh .\scripts\weekly_metrics_faro_short.ps1  # extended with SHORT live metrics
   ```

---

## 📊 Success Metrics (BEAR_STRONG deployment)

### Week 1 of SHORTs (2026-06-23 → 2026-06-30)

- [ ] Entries: ≥2 SHORT vol_climax signals executed
- [ ] Win rate: ≥50% (price falls ≥1% post-entry)
- [ ] False positives: ≤1 (price pumps instead of dumping)
- [ ] Largest draw-down: <3% (stop loss working)
- [ ] Avg R:R: ≥1:5 (risk $30, target $150+)

### If metrics bad (win rate <40%)
- Rollback: `$env:SHORT_VOL_CLIMAX_LIVE = 0` (back to observation)
- Investigate: Is RSI≥80 too low? Volume ratio too high? Market shifted?
- Collect another 30 signals, revalidate

### If metrics good (win rate ≥50%)
- Continue SHORT collection in next cycle
- Iterate gate parameters (maybe RSI≥82 instead of 80?)
- Eventually scale to 2% per trade

---

## 🔗 Integration Points (what needs to be wired)

### Currently MISSING (need to add before deploy)

1. **Regime gating**
   ```powershell
   # In scan_master.ps1, before executing SHORT:
   $regime = Get-HalvingPhase
   if ($regime -ne "BEAR_STRONG") { return }  # skip SHORT execution
   ```

2. **Risk sizing for SHORT**
   ```powershell
   # Need function:
   function Get-ShortSizePercentage {
       param([string]$Market, [decimal]$Capital)
       return [math]::Max(0.005, [math]::Min(0.02, $Capital * 0.01))  # 1% base, 2% max
   }
   ```

3. **Trailing stop integration**
   ```powershell
   # After SHORT entry:
   Start-TrailingStop -OrderId $order.id -Mode "EXHAUSTION" `
       -RSITarget 30 `
       -TimeStop "6h"
   ```

4. **Execution logging**
   ```powershell
   # Separate from observations.csv
   # Create: journal/short_executions.csv
   # Columns: ts, market, entry_price, size, stop_loss, target, exit_reason, pnl
   ```

---

## 📅 Timeline Overview

```
2026-06-02  ✅ Observation LIVE (passive, no trades)
            └─ Collect signals daily

2026-06-09  📊 Check metrics: 10+ signals? Consistent gate?
            └─ If YES → Continue
            └─ If NO → Adjust gate parameters

2026-06-16  🔍 Analysis phase: validate true positive rate
            └─ Export observations + cross-reference with price
            └─ Calculate per-market hit rates

2026-06-23  ⚙️ Deployment prep: wire SHORT execution
            └─ Test SHORT entry/exit logic (TDD)
            └─ Confirm risk sizing + stop loss

2026-06-24  🚀 LIVE SHORT execution starts (if BEAR_STRONG active)
            └─ Real trades begin
            └─ Monitor win rate + false positives

2026-07-01  📈 Review + iterate: scale or adjust parameters
```

---

## 🛡️ Safety Guardrails (always active)

Even in BEAR_STRONG, these never break:

1. **Capital safety**
   - Max $30 per SHORT (1% of $3k capital)
   - Max 5 concurrent SHORTs ($150 at risk)
   - Stop loss MUST be set before order sent

2. **Regime gating**
   - SHORT executions ONLY in BEAR_STRONG
   - BEAR_WEAK/NEUTRAL → observation only

3. **Fail-closed**
   - If Regime detector fails → assume BEAR_WEAK → no execution
   - If vol_climax gate times out → skip signal
   - If capital check fails → block trade (no shorting borrowed capital)

4. **Idempotency**
   - Same signal won't execute twice (order ID tracking)
   - Restart safe: checks existing orders before re-entering

---

## 🎯 Next Action: Start Phase 1 NOW

**What to do this week:**

1. Monitor observations.csv growth
   ```powershell
   # Check daily:
   (Get-Content .\journal\observations.csv | Measure-Object -Line).Lines
   # Target: +10-15 new lines per day → 50+ by 2026-06-09
   ```

2. Run weekly metrics:
   ```powershell
   pwsh .\scripts\weekly_metrics_faro_short.ps1
   # Watch: "Signals collected" number should grow
   ```

3. Manual spot checks (every 2-3 days):
   ```powershell
   # Read last 5 observations
   Get-Content .\journal\observations.csv -Tail 5 | ConvertFrom-Csv
   # Check: RSI values 80+? vol_ratio 2.5+? ADX 60+?
   ```

---

**Status:** 🟢 READY FOR PHASE 1  
**Approval needed:** YES — confirm observations should start flowing (automated via scan_master.ps1)

