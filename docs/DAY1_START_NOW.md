# 🚀 DAY 1 — START NOW (2026-06-06)

> **Status**: PRONTO PRA COMEÇAR  
> **Capital**: $3,645.89 USD liquid  
> **Duration**: ~1.5-2 horas  
> **Outcome**: Ready for Day 2 micro-trade

---

## 🎯 3 TASKS (execute in order)

### TASK 1: Validate Regime (30 min)

**What to do:**
```powershell
# Check BTC daily candle
# Is it BULL, BEAR, or SIDEWAYS?
# Record in journal/REGIME_VALIDATION_2026_06_06.txt
```

**Expected outcome:**
```
✅ Regime confirmed (BULL_WEAK, BULL, SIDEWAYS, or BEAR)
✅ Recorded in journal/
✅ Proceed to Task 2
```

---

### TASK 2: Test Capital Safety (45 min)

**What to do:**
```powershell
cd 'C:\Users\thiag\Coinex_AI_USER_API'

# Load libs
. .\agents\config.ps1
. .\agents\lib_audit_compliance.ps1
. .\agents\lib_position_sizing_dynamic.ps1
. .\agents\lib_volatility_filter.ps1
. .\agents\lib_mce_gates.ps1

# Test with example market (LINKUSDT)
$validation = Test-InputDataNormality `
    -Market "LINKUSDT" `
    -CurrentPrice 9.58 `
    -Change24hPct 2.5 `
    -VolumeUsd 50000000 `
    -AtrPct 2.0

Write-Host "Data validation: $($validation.is_valid)"

# Test vol gate
$vol = Test-VolatilityAcceptable -VolumeChangePercent 5.0
Write-Host "Volatility gate: $($vol.passed)"

# Test position sizing
$sizing = Invoke-DynamicPositionSize `
    -AccountEquityUsd 3645.89 `
    -BetaVsBtc 1.5 `
    -ConfluenceCount 1 `
    -Regime "BULL_WEAK"

Write-Host "Position size (0.1%): $([Math]::Round($sizing.final_size_usd * 0.001, 2)) USD"

# Verify logs exist
Write-Host ""
Write-Host "Checking audit logs..."
@("gate_audit_trail.jsonl", "capital_safety_checks.jsonl", "volatility_filter_audit.jsonl") | ForEach-Object {
    $path = Join-Path (Get-Location) "journal/$_"
    if (Test-Path $path) {
        Write-Host "✅ $_"
    } else {
        Write-Host "❌ $_ MISSING"
    }
}
```

**Expected outcome:**
```
✅ Data validation: True
✅ Volatility gate: pass
✅ Position size: ~$3.65 USD (0.1%)
✅ Audit logs exist
✅ Record in journal/CAPITAL_SAFETY_TEST_2026_06_06.txt
✅ Proceed to Task 3
```

---

### TASK 3: Identify Vol_Climax Setup (30 min)

**What to look for:**
```
Market with ALL 3:
  1. Volume spike (2x+ recent average)
  2. New low (vs past 5 days)
  3. Close above that low (recovery candle)

Edge: +8.6pp (validated, ONLY signal with real edge)
```

**Where to scan:**
```
CoinEx SPOT:
  - LINKUSDT
  - SOLUSDT
  - NEARUSDT
  - BTCUSDT
  - ETHUSDT
  (Your prior winning markets)
```

**How to identify:**
```
Option A: Manual charts on CoinEx
  - 1h or 4h candle
  - Look for vol spike + dip + recovery

Option B: Run scanner (if exists)
  .\scripts\vol_climax_scanner.ps1
```

**Expected outcome:**
```
✅ Found market with vol_climax pattern
✅ Entry price identified (e.g., 9.58)
✅ SL calculated (e.g., 9.51 = 2%)
✅ TP calculated (e.g., 9.70 = 2x R:R)
✅ Ready to record in journal/VOL_CLIMAX_SETUP_2026_06_06.txt
✅ DONE — Ready for Day 2 micro-trade
```

---

## ✅ DAY 1 CHECKLIST

```
□ TASK 1: Regime validated
   Write to: journal/REGIME_VALIDATION_2026_06_06.txt
   
□ TASK 2: Capital safety tested
   Write to: journal/CAPITAL_SAFETY_TEST_2026_06_06.txt
   Verify: Audit logs created (gate_audit_trail.jsonl, etc)
   
□ TASK 3: Vol_climax setup identified
   Write to: journal/VOL_CLIMAX_SETUP_2026_06_06.txt
   Format: Market, Entry, SL, TP, Entry time

□ All 3 records in journal/
□ Ready for Day 2 (tomorrow or next session)
```

---

## 📋 IF ANYTHING FAILS

### Regime check fails?
```
→ Check BTC chart manually
→ If cannot determine: assume BEAR (defensive)
→ Record uncertainty and proceed
```

### Capital safety logs don't appear?
```
→ Verify libs loaded correctly
→ Check journal/ directory exists
→ Retry with simpler test (just Test-InputDataNormality)
→ DO NOT PROCEED to micro-trade without logs
```

### Vol_climax pattern not found?
```
→ Check multiple timeframes (1h, 4h, daily)
→ Check multiple markets
→ Wait until pattern appears (can take hours)
→ If after 2h still nothing: record "no setup found yet"
→ Proceed to Day 2 anyway (ready to enter when pattern appears)
```

---

## 🎯 WHAT HAPPENS AFTER DAY 1

**If all 3 tasks pass:**
```
Day 2: Execute first micro-trade
  • Market: vol_climax setup
  • Size: 0.1% = $3.65 USD
  • Entry: exactly per setup
  • SL/TP: per calculation
  • Capture all audit logs
```

**If Day 2 trade passes:**
```
Days 3-4: Execute 2-3 more micro-trades
  • Scale to 0.5% = $18.23 USD
  • If logs clean, keep going
  • Accumulate real data
```

**Days 5-14:**
```
Recalibrate thresholds from real outcomes
Update edge assessment
Decide next phase
```

---

## 📊 REMEMBER

- **Capital**: $3,645.89 USD (only this, not $5000)
- **Signal**: Vol_climax only (ignore confluence, Tori, SHORT)
- **Size**: 0.1% = $3.65 (micro-test first)
- **Logs**: CRITICAL — every trade must generate logs
- **Coins**: Keep OPN, FIRO, PEPE2 (don't liquidate)

---

## 🚀 READY?

All systems go. Start Task 1 now.

**Expected completion**: 1.5-2 hours  
**Next milestone**: Day 2 micro-trade execution  
**Status**: GO GO GO 🚀

---

**Start time**: NOW (2026-06-06)  
**First task**: Validate regime  
**Go!**
