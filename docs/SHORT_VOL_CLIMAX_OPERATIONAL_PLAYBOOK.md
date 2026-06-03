# 🎮 SHORT vol_climax — Operational Playbook (Daily + Weekly)

**For:** manuheadfund trading ops  
**Updated:** 2026-06-02  
**Frequency:** Daily checks (2min), Weekly reviews (10min)

---

## 📋 DAILY OPERATIONS (2 minutes)

### Morning (antes de iniciar trading, ~11h BRT)

```powershell
# Check if observations are flowing
$count = (Get-Content .\journal\observations.csv -Tail 100 | Where-Object { $_ -match "vol_climax" } | Measure-Object).Count
Write-Host "vol_climax signals last 24h: $count"

# Expected: 1-3 signals/day (varies with market volatility)
# RED FLAG: 0 signals 3+ days = gate might be broken or market too calm
```

### End of Day (~18h BRT)

```powershell
# Backup observations (before daily rollover)
Copy-Item .\journal\observations.csv ".\journal\backups\observations_$(Get-Date -Format 'yyyyMMdd').csv"

# Quick metric check
$lines = (Get-Content .\journal\observations.csv | Measure-Object -Line).Lines
$volSignals = @(Get-Content .\journal\observations.csv | Where-Object { $_ -match "vol_climax" })
Write-Host "📊 Daily summary: $($volSignals.Count) vol_climax | Total: $lines lines"
```

---

## 📊 WEEKLY REVIEW (10 minutes)

### Every Monday (~9h BRT)

```powershell
# Run full metrics
pwsh .\scripts\weekly_metrics_faro_short.ps1

# Output expectations by week:
# Week 1 (by 2026-06-09): 20-30+ signals total
# Week 2 (by 2026-06-16): 40-50+ signals total  
# Week 3 (by 2026-06-23): 50+ signals (ready to validate)
```

### Manual validation step

```powershell
# Read recent observations
$obs = @(Get-Content .\journal\observations.csv | ConvertFrom-Csv | Sort-Object ts -Descending | Select-Object -First 10)

# Check each signal:
foreach ($o in $obs) {
    Write-Host "🔍 $($o.market) | RSI=$($o.rsi) vol=$($o.vol_ratio)x ADX=$($o.adx)"
    # Verify: RSI in 80-90 range? vol_ratio 2.5-4x? ADX 60-75?
    # If any WAY outside these ranges → gate misconfigured
}
```

---

## 🎯 PHASE 1 CHECKLIST (Weeks 1-2: 2026-06-02 → 2026-06-16)

### Week 1 GO/NO-GO (by 2026-06-09)

- [ ] Observations flowing? (daily 1-3 signals)
- [ ] Signal count: ≥20 total?
- [ ] Gate metrics stable?
  - [ ] Avg RSI: 81-85?
  - [ ] Avg vol_ratio: 2.6-3.2x?
  - [ ] Avg ADX: 64-68?
- [ ] Any system errors in logs? (scan_master.ps1 logs)

**Decision:**
- ✅ All checks pass → Continue Phase 1
- ❌ Something odd → Investigate (see troubleshooting below)

### Week 2 MILESTONE (by 2026-06-16)

- [ ] Total signals: ≥40?
- [ ] Signal sources diversified? (BTC, ETH, alts?)
- [ ] Regime detection working? (still BEAR_WEAK?)
- [ ] Ready for Phase 2 analysis

---

## 🔍 PHASE 2: VALIDATION (Week 3: 2026-06-16 → 2026-06-23)

### Step 1: Export observations + add outcome column

```powershell
# Read observations.csv
$obs = Import-Csv .\journal\observations.csv | Where-Object { $_.signal_type -eq "vol_climax" }

# For EACH signal, manually check 24h later:
# Did price drop ≥1% from entry? YES = TRUE_POS, NO = FALSE_POS

# Create validation file:
$obs | Select-Object ts, market, rsi, vol_ratio, adx, @{
    n="outcome"
    e={
        # Check manually: did price fall post-signal?
        # Fill with: "TRUE_POS" or "FALSE_POS" or "PENDING"
        ""  # leave blank initially, fill manually
    }
} | Export-Csv .\journal\vol_climax_validation_2026_06_16.csv -NoTypeInformation
```

### Step 2: Calculate hit rates

```powershell
$validated = Import-Csv .\journal\vol_climax_validation_2026_06_16.csv

$truePos = @($validated | Where-Object { $_.outcome -eq "TRUE_POS" }).Count
$falsePos = @($validated | Where-Object { $_.outcome -eq "FALSE_POS" }).Count
$pending = @($validated | Where-Object { $_.outcome -eq "PENDING" }).Count
$hitRate = [math]::Round(($truePos / ($truePos + $falsePos)) * 100, 1)

Write-Host "📈 Hit Rate: $hitRate% ($truePos/$($truePos + $falsePos))"
Write-Host "   False positives: $falsePos"
Write-Host "   Pending: $pending"

# Target: ≥60% hit rate = ready for live
# <40% hit rate = gate needs adjustment
```

### Step 3: Identify golden markets

```powershell
$validated | Group-Object market | ForEach-Object {
    $group = $_.Group
    $hits = @($group | Where-Object { $_.outcome -eq "TRUE_POS" }).Count
    $total = @($group | Where-Object { $_.outcome -in "TRUE_POS", "FALSE_POS" }).Count
    $rate = if ($total -gt 0) { [math]::Round(($hits / $total) * 100, 0) } else { 0 }
    
    if ($total -ge 3) {  # only markets with 3+ signals
        Write-Host "  $($_.Name): $rate% ($hits/$total)"
    }
}

# Golden markets (>70% hit rate) = prioritize for deployment
# Weak markets (<40% hit rate) = maybe skip or re-tune for them
```

---

## ⚙️ PHASE 3: DEPLOYMENT PREP (Week 3: 2026-06-18 → 2026-06-23)

### Pre-deployment TDD (must be 100% GREEN)

```powershell
# Test SHORT entry logic (if not already done):
Invoke-Pester .\tests\lib_enhanced_short_entry.Tests.ps1 -Verbose
# Should be: 15/15 GREEN (or whatever count)

# Test SHORT execution:
Invoke-Pester .\tests\lib_short_execution.Tests.ps1 -Verbose
# Should be: 12/12 GREEN

# Capital safety stress test:
Invoke-Pester .\tests\short_capital_safety.Tests.ps1 -Verbose
# Should be: 10/10 GREEN
```

### Regime detection validation

```powershell
# Confirm BEAR_STRONG logic works:
. .\agents\lib_halving_phase_detector.ps1
$regime = Get-HalvingPhase
Write-Host "Current regime: $regime"

# When BEAR_STRONG arrives, SHORT execution will auto-start
# Until then: observation only
```

### Risk sizing review

```powershell
# Confirm sizing function exists and works:
. .\agents\lib_risk_sizing.ps1

$capital = 3000  # current capital
$perTrade = Get-ShortSizePercentage -Capital $capital -Asset "BTCUSDT"
Write-Host "Risk per SHORT: $perTrade USD (should be ~$30 = 1%)"
```

---

## 🚀 PHASE 4: LIVE EXECUTION (Week 4+: 2026-06-23 onwards)

### Deployment trigger (when BEAR_STRONG detected)

```powershell
# Monitor regime automatically
# When Get-HalvingPhase returns "BEAR_STRONG":
# → scan_master.ps1 switches from observation → execution

# You can manually trigger testing:
$env:SHORT_VOL_CLIMAX_LIVE = 1
pwsh .\orchestrator_v6.ps1  # restarts with SHORT enabled
```

### Daily monitoring (during BEAR_STRONG)

```powershell
# Run enhanced metrics script:
pwsh .\scripts\weekly_metrics_faro_short.ps1  # expanded to show live trades

# Check SHORT trades:
# Wins? Losses? Avg R:R? Largest drawdown?

# Critical alerts:
# ❌ Win rate <40% → rollback to observation mode
# ❌ Consecutive 3 losses → increase stop loss buffer
# ❌ Regime changes to BEAR_NEUTRAL → auto-pause execution
```

### Example: First SHORT execution (manual test)

```powershell
# Load SHORT libs
. .\agents\lib_vol_climax_gate.ps1
. .\agents\lib_enhanced_short_entry.ps1
. .\agents\lib_short_execution.ps1

# Simulate signal (RSI=82, vol=3x, ADX=68):
$signal = New-ShortSignal -Market "BTCUSDT" `
    -EntryPrice 45000 `
    -StopLoss 45450 `  # 1% above entry (safety buffer)
    -Target 43500 `     # 3.3% profit (1:3 R:R minimum)
    -Regime "BEAR_STRONG"

# Dry-run execution:
$order = Invoke-ShortExecution -Signal $signal -Capital 3000 -DryRun $true
Write-Host "Would place: SELL $($order.size) BTC at $45000, SL=$45450, TP=$43500"

# If dry-run looks good:
# $order = Invoke-ShortExecution -Signal $signal -Capital 3000 -DryRun $false
```

---

## 🛠️ TROUBLESHOOTING

### Problem: No signals for 3+ days

**Diagnosis:**
```powershell
# Check gate logic:
$testResult = Test-VolClimaxGate -RSI 82 -CurrentVolume 300000 -Avg3dVolume 100000 -ADX 68
if (-not $testResult.passes) {
    Write-Host "❌ Gate FAILED — check individual metrics"
    Write-Host "   RSI pass: $($testResult.rsi_pass)"
    Write-Host "   Vol pass: $($testResult.vol_pass)"
    Write-Host "   ADX pass: $($testResult.adx_pass)"
}

# Check scan_master.ps1 is running:
Get-Process | Where-Object { $_.ProcessName -like "*scan*" }
# If nothing: restart scan_master.ps1
```

**Fix:**
- Market too calm (RSI never hits 80)? → Lower threshold to 78 (backtest first)
- Market too volatile? → Raise vol_ratio threshold to 3.0 (more stable signals)

### Problem: Too many false positives

**Diagnosis:**
```powershell
# Manual check: pick last 10 signals
$obs = Get-Content .\journal\observations.csv -Tail 10 | ConvertFrom-Csv
$obs | ForEach-Object {
    # Check manually: did $_.market price fall 1%+ in next 24h?
    # If YES → TRUE_POS
    # If NO → FALSE_POS
}
```

**Fix options:**
1. Raise RSI threshold: 80 → 82 (more extreme exhaustion)
2. Raise vol_ratio: 2.5x → 3.0x (bigger panic spikes only)
3. Raise ADX: 60 → 65 (stronger trend confirmation)

### Problem: Regime detector broken (showing BEAR_WEAK when should be BEAR_STRONG)

```powershell
# Check directly:
. .\agents\lib_halving_phase_detector.ps1
$regime = Get-HalvingPhase
Write-Host "Detected regime: $regime"

# If wrong, check inputs:
# - BTC price vs cycle start (verify halvings data)
# - Market phase detection (run manually)

# Fallback: manually override (DO NOT do this lightly!)
# $env:OVERRIDE_REGIME = "BEAR_STRONG"
```

---

## 📞 ESCALATION

### If something breaks during BEAR_STRONG execution

**Immediate (stop losses active):**
1. Run: `$env:SHORT_VOL_CLIMAX_LIVE = 0`
2. All active SHORTs stay open, stops manage exits
3. No new SHORTs initiated
4. Investigate what went wrong

**Investigation:**
```powershell
# Check last orders:
Get-Content .\journal\short_executions.csv | ConvertFrom-Csv | Sort-Object ts -Descending | Select-Object -First 5

# Check errors:
Get-Content .\logs\scan_master.log -Tail 50 | Where-Object { $_ -match "ERROR|FAIL" }

# Verify capital safety:
pwsh .\scripts\capital_safety_audit.ps1
```

**Recovery:**
- If capital issue: reduce daily gem cap + SHORT cap
- If gate broken: revert to Phase 1 (observation only)
- If regime detector broken: manually set regime

---

## ✅ READY TO START

**Current status:** Observation collection active  
**Next milestone:** 50+ signals by 2026-06-09  
**Decision point:** 2026-06-16 (validate + prep)  
**Deployment:** 2026-06-23 (when BEAR_STRONG)

**Your job this week:** Run daily 2-min check, weekly 10-min review. Everything else automated.

