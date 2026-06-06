# 🚀 DAY 1 EXECUTION PLAN — 2026-06-06

## ⏱️ Today's Mission (Est. 1.5-2 hours)

```
Goal: Validate regime + test capital safety + identify vol_climax
      → KEEP stranded coins (OPN, FIRO, PEPE2)
      → KEEP MOON position (MONUSDT 3X long, trailing active)
      → Trade with $2,690 liquid USDT (after MOON margin)
      → READY for micro-trade (Day 2)
```

---

## ✅ TASK 1: Validate Regime (30 min)

### What to do:
```powershell
# Option A: Automatic check (if script exists)
$regime = Get-CurrentRegime
Write-Host "Current regime: $regime"

# Option B: Manual verification
# 1. Open CoinEx spot
# 2. Check BTC daily candle
#    - Strong uptrend = BULL_WEAK or BULL_STRONG
#    - Ranging sideways = SIDEWAYS
#    - Downtrend = BEAR_WEAK or BEAR_STRONG
# 3. Check EMA200 position
#    - Price above EMA200 = BULL bias
#    - Price below EMA200 = BEAR bias
```

### Expected result:
```
✅ BULL_WEAK   → Proceed with signal scanning
✅ BULL_STRONG → Proceed with signal scanning
✅ SIDEWAYS    → Proceed with signal scanning
⚠️  BEAR_WEAK  → Defensive (fewer opportunities expected)
❌ BEAR_STRONG → HALT (defensive, no new trades)
```

### Record:
```
Write to journal/REGIME_VALIDATION_2026_06_06.txt:
  Validated: [BULL_WEAK / BULL_STRONG / SIDEWAYS / BEAR_WEAK / BEAR_STRONG]
  Method: [automatic / manual candle inspection]
  Time: [HH:MM BRT]
```

---

## ✅ TASK 2: Test Capital Safety (PAPER mode) (45 min)

### Setup:
```powershell
cd 'C:\Users\thiag\Coinex_AI_USER_API'

# Load libs
. .\agents\config.ps1
. .\agents\lib_audit_compliance.ps1
. .\agents\lib_performance_refiner.ps1
. .\agents\lib_position_sizing_dynamic.ps1
. .\agents\lib_volatility_filter.ps1
. .\agents\lib_mce_gates.ps1
. .\agents\lib_dsr_confidence_advanced.ps1
```

### Simulate a trade (with example LINKUSDT):
```powershell
# 1. Validate input data (PAPER)
$validation = Test-InputDataNormality `
    -Market "LINKUSDT" `
    -CurrentPrice 9.58 `
    -Change24hPct 2.5 `
    -VolumeUsd 50000000 `
    -AtrPct 2.0

if ($validation.is_valid) { Write-Host "✅ Data valid" }
else { Write-Host "❌ Data invalid"; exit }

# 2. Test signal gate (vol_climax only — skip confluence)
$vol = Test-VolatilityAcceptable -VolumeChangePercent 5.0
Write-Host "✅ Volatility gate: $($vol.passed)"

# 3. Test MCE gate (BRT window)
$mce = Invoke-MceGate -Regime "BULL_WEAK" -BrtHour (Get-Date).Hour -FearGreedIndex "GREED"
Write-Host "✅ MCE gate: $($mce.allowed)"

# 4. Calculate position size
$dsr = Get-DsrConfidenceLevel -TradeHistory @()  # Empty history → LOW
$sizing = Invoke-DynamicPositionSize `
    -AccountEquityUsd 4065 `
    -BetaVsBtc 1.5 `
    -ConfluenceCount 1 `  # vol_climax only = 1 signal
    -Regime "BULL_WEAK"
    
Write-Host "✅ Position size (0.1%): $($sizing.final_size_usd * 0.001) USD"

# 5. Test SL/TP refinement
# (This would be done when actual vol_climax setup found)

# 6. Verify logs exist
Write-Host ""
Write-Host "Checking audit logs..."
$auditPath = Join-Path (Get-Location) "journal"
if (Test-Path "$auditPath/gate_audit_trail.jsonl") {
    Write-Host "✅ gate_audit_trail.jsonl: exists"
}
if (Test-Path "$auditPath/capital_safety_checks.jsonl") {
    Write-Host "✅ capital_safety_checks.jsonl: exists"
}
if (Test-Path "$auditPath/volatility_filter_audit.jsonl") {
    Write-Host "✅ volatility_filter_audit.jsonl: exists"
}
```

### Expected result:
```
✅ All gates pass
✅ Position size calculated: ~$3.65 USD (0.1%)
✅ Audit logs created with entries
```

### Record:
```
Write to journal/CAPITAL_SAFETY_TEST_2026_06_06.txt:
  Data validation: ✅ PASS
  Volatility gate: ✅ PASS
  MCE gate: ✅ PASS
  Position size: $X USD (0.1% of $2,690, MOON margin locked)
  Audit logs created: ✅ YES
  Time completed: HH:MM BRT
```

---

## ✅ TASK 3: Identify First Vol_Climax Setup (30 min)

### What to look for (vol_climax definition):
```
All 3 must be true:
  1. Volume spike: current vol > 2× recent average
  2. New low: today's low < past 5-day low
  3. Close above low: closing price > that low
  
Edge: +8.6pp (from historical validation)
Markets to scan: LINKUSDT, SOLUSDT, NEARUSDT, BTCUSDT, ETHUSDT
  (Your prior winning markets: LINK, SOL, BNB)
```

### Scan method:
```
Option A: Manual (CoinEx charts)
  - Open each market
  - Check 1h and 4h candles
  - Look for vol spike + dip + recovery pattern
  
Option B: Automated (run scanner if exists)
  .\scripts\vol_climax_scanner.ps1
```

### Expected result:
```
Find market with:
  - Vol spike detected ✅
  - New low within past 2 hours
  - Close above low (recovery candle)
  
Example: LINKUSDT vol spike to 1.5M, low 9.55, close 9.58
  → Entry: 9.58
  → SL: 9.51 (2% below)
  → TP: 9.70 (2× risk reward)
```

### Record:
```
Write to journal/VOL_CLIMAX_SETUP_2026_06_06.txt:
  Market: [MARKET]
  Vol spike: X → Y
  Entry: $X.XX
  SL: $X.XX
  TP: $X.XX
  Time of setup: HH:MM BRT
  Ready to trade: [YES / NO]
```

---

## 📋 Day 1 Checklist

```
□ Task 1: Validate regime (BULL_WEAK confirmed?)
□ Task 2: Test capital safety in PAPER (logs generated?)
□ Task 3: Identify vol_climax setup (entry/SL/TP ready?)
□ All 3 tasks recorded in journal/
□ Stranded coins KEPT (OPN, FIRO, PEPE2)
□ MOON position KEPT (MONUSDT 3X, trailing active, margin $10.556 locked)
□ Ready for Day 2 micro-trade (0.1% size on $2,690 available)
```

---

## 🚀 Day 1 Success Criteria

**If all true, proceed to Day 2:**

```
✅ Regime validated (BULL_WEAK or better)
✅ Stranded coins kept (OPN, FIRO, PEPE2 in carteira)
✅ Capital safety gates tested in PAPER (logs exist)
✅ Vol_climax setup identified (entry/SL/TP defined)
✅ Liquid capital = $3,645 USDT ready
✅ Win rate baseline = 33% (from 6 prior trades)
✅ Ready to execute micro-trade Day 2
```

**If any false, investigate before proceeding:**

```
❌ Regime is BEAR_STRONG → WAIT (defensive period)
❌ Capital safety logs don't exist → DEBUG gates
❌ Vol_climax not found → WAIT for pattern
❌ Confidence too low → EXTEND validation period
```

---

## 📞 Next Steps

### End of Day 1:
- Execute all 4 tasks
- Record status in journal/
- Report back: "Day 1 complete, ready for Day 2" or "Issue found: X"

### Day 2 (if Day 1 passed):
- Execute first vol_climax trade (0.1% size, $4 USD)
- Monitor all audit logs
- Verify capital safety functions

### Days 3-4:
- Execute 2-3 more micro-trades if Day 2 passed
- Scale to 0.5% size ($20 USD) if logs clean

### Day 5-14:
- Rebuild thresholds from 10-20 real outcomes
- Update edge assessment
- Decide next phase

---

**Estimated time: 1.5-2 hours**  
**Start time**: Now  
**Expected completion**: Before 16:00 BRT  
**Next milestone**: Day 2 micro-trade execution (vol_climax 0.1% size)
