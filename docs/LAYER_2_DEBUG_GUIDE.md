# Layer 2 Debug Guide — Troubleshooting Mentor Reflection Issues

**If Layer 2 validation fails or shows unexpected behavior, use this guide.**

---

## Quick Diagnostics

### 1. Check if Functions Load

```powershell
# Open PowerShell in project root
cd c:\Users\thiag\Coinex_AI_USER_API

# Test load
$agentsDir = '.\agents'
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_mentor_reflection.ps1")

# Check each function
$functions = @('Test-MentorCheckpoint', 'Invoke-EarlyWarningDetection', 'Get-RegimeShift', 'Update-StopTightening', 'Get-MentorDecision', 'Update-MentorReview')
foreach ($f in $functions) {
    $cmd = Get-Command $f -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Host "✓ $f loaded" -ForegroundColor Green
    } else {
        Write-Host "✗ $f FAILED TO LOAD" -ForegroundColor Red
    }
}
```

**Expected:** All 6 green ✓  
**If failed:** Check for syntax errors in lib_mentor_reflection.ps1 (run `Invoke-Pester ./tests/mentor_review.Tests.ps1` to validate)

---

### 2. Run Test Suite Again

```powershell
Invoke-Pester -Path './tests/mentor_review.Tests.ps1' -PassThru
```

**Expected:** 24/24 PASSING  
**If any fail:** Implementation has regression. Review what changed.

---

### 3. Check Imports in scan_master.ps1

```powershell
# Verify Line 61 exists:
Get-Content -Path '.\scripts\scan_master.ps1' -TotalCount 65 | tail -10

# Should show:
# . (Join-Path $agentsDir "lib_mentor_reflection.ps1")  # Layer 2 TDD
```

**If missing:** Edit scan_master.ps1, add line after lib_trailing_adaptive:
```powershell
. (Join-Path $agentsDir "lib_mentor_reflection.ps1")  # Layer 2 TDD: 6h checkpoint reviews
```

---

### 4. Check scan_master Call (Line ~545)

```powershell
# Find the call
Select-String -Path '.\scripts\scan_master.ps1' -Pattern 'Update-MentorReview'

# Should show line ~545:
# try { Update-MentorReview } catch { Write-MasterLog "Mentor review erro: $_" "WARN" }
```

**If missing:** Edit scan_master.ps1, add after `Show-TrailingStatus`:
```powershell
# ── Layer 2: Mentor Reflection (6h checkpoint reviews) ──────────────
try { Update-MentorReview } catch { Write-MasterLog "Mentor review erro: $_" "WARN" }
```

---

## Common Issues & Fixes

### Issue 1: "Get-MacroContext not found" (Warning)

**Symptom:**
```
[Mentor] Get-MacroContext não encontrada
```

**Root Cause:** Macro detection library not loaded

**Fix:**
```powershell
# Check if lib_macro.ps1 is imported in scan_master.ps1
Select-String -Path '.\scripts\scan_master.ps1' -Pattern 'lib_macro'

# If not found, add to scan_master.ps1 imports section (~line 45):
. (Join-Path $agentsDir "lib_macro.ps1")
```

**Fallback:** If macro unavailable, Mentor uses SIDEWAYS (conservative, safe)

---

### Issue 2: "Get-TrailingPositions not found" (Warning)

**Symptom:**
```
[Mentor] Get-TrailingPositions não encontrada
```

**Root Cause:** Trailing positions library not loaded

**Fix:**
```powershell
# Check if lib_trailing.ps1 or lib_trailing_adaptive.ps1 imported
Select-String -Path '.\scripts\scan_master.ps1' -Pattern 'lib_trailing'

# Both should exist (line 58-60):
# . (Join-Path $agentsDir "lib_trailing.ps1")
# . (Join-Path $agentsDir "lib_trailing_adaptive.ps1")
```

---

### Issue 3: "No positions active to review"

**Symptom:**
```
[Mentor] Nenhuma posição ativa para revisar
```

**Root Cause:** Normal — no open trades

**Fix:** Not a bug. Layer 2 only works when positions exist. Start trading first, then Mentor reviews after 6h.

**Debug Check:**
```powershell
# Get positions
$positions = Get-TrailingPositions
$active = $positions | Where-Object { $_.active }
Write-Host "Active positions: $(@($active).Count)"

# If 0, start a trade first
```

---

### Issue 4: "Mentor reviews never trigger"

**Symptom:**
- No Telegram alerts about Mentor reviews
- Positions never reviewed

**Root Cause:** 6h checkpoint not being reached (positions too young)

**Debug Check:**
```powershell
# Get a position
$pos = Get-TrailingPositions | Select-Object -First 1
if ($pos) {
    $entryTime = [DateTime]::Parse($pos.entryTime)
    $elapsed = (Get-Date) - $entryTime
    Write-Host "Position $($pos.market): $($elapsed.TotalHours) hours old"
    
    # Should be ≥5.95 hours to trigger
    if ($elapsed.TotalHours -ge 5.95) {
        Write-Host "✓ Should trigger review"
    } else {
        Write-Host "✗ Too young (need $(5.95 - $elapsed.TotalHours) more hours)"
    }
}
```

**Fix:** Wait for position to reach 6h old, OR create a test position with past entry time:
```powershell
# For testing: Create position with old entry time
$testPos = @{
    market = "BTCUSDT"
    side = "LONG"
    entry = 100000.0
    target = 105000.0
    currentPrice = 102000.0
    stop = 95000.0
    entryTime = (Get-Date).AddHours(-6.2)  # 6.2 hours ago
    active = $true
}
Update-MentorReview  # Should trigger review
```

---

### Issue 5: "Too many CLOSE_NOW actions" (False closes)

**Symptom:**
- Positions closing prematurely
- "CLOSED: false breakout detected" alerts too frequent

**Root Cause:** Early warning detection too sensitive

**Debug Fix:**
Edit lib_mentor_reflection.ps1, function `Invoke-EarlyWarningDetection`:

Current (too sensitive):
```powershell
if ($TimeSinceEntry -lt 4.0 -and $PriceProgress -ge 0) {
    $flagged = $true
    $confidence = 0.75
```

Make less sensitive (increase threshold):
```powershell
if ($TimeSinceEntry -lt 3.0 -and $PriceProgress -ge 0.05) {  # Changed < 4.0 to < 3.0, + >= 0.05
    $flagged = $true
    $confidence = 0.75
```

Then re-test: `Invoke-Pester ./tests/mentor_review.Tests.ps1` (adjust test if needed)

---

### Issue 6: "Stops never tighten" (Regime shift never detected)

**Symptom:**
- No "stop tightened" alerts
- Positions in BEAR regime but stops not moving

**Root Cause:** Get-RegimeShift not detecting BEAR

**Debug Check:**
```powershell
# Test regime shift directly
. .\agents\lib_mentor_reflection.ps1

$result = Get-RegimeShift -OldRegime "BULL_STRONG" -NewRegime "BEAR_STRONG"
Write-Host "Shift detected: $($result.shifted)"  # Should be $true

# If $false, fix in Get-RegimeShift:
# Verify: ($NewRegime -match "BEAR|CAPITULATION") works
"BEAR_STRONG" -match "BEAR|CAPITULATION"  # Should return $true
```

**Fix:** If regex not matching, update in lib_mentor_reflection.ps1:
```powershell
# Line ~180, in Get-RegimeShift function
if ($NewRegime -like "*BEAR*" -or $NewRegime -like "*CAPITULATION*") {
    $shifted = $true
```

---

### Issue 7: "Crashes during Update-MentorReview"

**Symptom:**
```
[MasterLog] Mentor review erro: Exception...
```

**Debug Fix:**
```powershell
# Test in isolation
. .\agents\lib_mentor_reflection.ps1
. .\agents\lib_trailing.ps1
. .\agents\config.ps1

# Mock a position
$global:POSITIONS = @(@{
    market = "BTCUSDT"
    side = "LONG"
    entry = 100.0
    target = 130.0
    currentPrice = 115.0
    stop = 95.0
    entryTime = (Get-Date).AddHours(-6.2)
    active = $true
    phase = 1
})

# Try to call
Update-MentorReview -Verbose

# If error, check:
# - Position JSON schema (keys match expectations?)
# - Entry/target/currentPrice are [double]?
# - entryTime is DateTime or parseable string?
```

---

### Issue 8: "Telegram alerts not sending"

**Symptom:**
- No Telegram notifications
- Send-TelegramAlert not found

**Debug Check:**
```powershell
Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue
# Should return a command object

# If not found:
Select-String -Path '.\scripts\scan_master.ps1' -Pattern 'lib_telegram'
```

**Fix:** Make sure lib_telegram.ps1 imported:
```powershell
# In scan_master.ps1 ~line 48:
. (Join-Path $agentsDir "lib_telegram.ps1")
```

**Workaround:** If Telegram not available, Layer 2 still works (just no alerts):
```powershell
# Update-MentorReview catches Send-TelegramAlert errors, so it won't crash
# Positions will still be updated, just silently
```

---

## Advanced Debugging

### Step-Through Test

```powershell
# 1. Load
. .\agents\config.ps1
. .\agents\lib_mentor_reflection.ps1

# 2. Test each function in sequence
Write-Host "--- Testing Test-MentorCheckpoint ---"
$entryTime = (Get-Date).AddHours(-6.2)
$result = Test-MentorCheckpoint -EntryTime $entryTime
Write-Host "Result (should be $true): $result"

Write-Host "`n--- Testing Invoke-EarlyWarningDetection ---"
$warning = Invoke-EarlyWarningDetection -TimeSinceEntry 3.5 -PriceProgress 0.05
Write-Host "Flagged: $($warning.flagged) (expect $false for normal progress)"

Write-Host "`n--- Testing Get-RegimeShift ---"
$shift = Get-RegimeShift -OldRegime "BULL_STRONG" -NewRegime "BEAR_STRONG"
Write-Host "Shifted: $($shift.shifted) (expect $true)"

Write-Host "`n--- Testing Update-StopTightening ---"
$newStop = Update-StopTightening -Entry 100 -CurrentStop 95 -Side "LONG"
Write-Host "New stop: $newStop (expect 97.5)"

Write-Host "`n--- Testing Get-MentorDecision ---"
$pos = @{
    entry = 100
    target = 130
    currentPrice = 115
    stop = 95
    side = "LONG"
    entryTime = (Get-Date).AddHours(-6.2)
}
$decision = Get-MentorDecision -Position $pos -CurrentRegime "BULL_STRONG" -OldRegime "BULL_STRONG"
Write-Host "Decision: $($decision.action) (expect HOLD)"
```

**Expected Output:** All tests pass with expected values

---

## Log Analysis

### Find Mentor Logs

```powershell
# Mentor logs usually in:
Get-ChildItem -Path '.\logs\' -Filter '*mentor*' | Sort-Object LastWriteTime -Descending | head -5

# Or search scan_master output:
Select-String -Path '.\logs\scan_master*.log' -Pattern '\[Mentor\]'
```

### Analyze Log Pattern

```powershell
# Extract Mentor decisions
Select-String -Path '.\logs\scan_master*.log' -Pattern '\[Mentor\].*:.*\(' | 
    ForEach-Object { 
        $_.Line -match '\[Mentor\] (\w+) (\w+): (\w+)' | Out-Null
        @{
            Market = $matches[1]
            Side = $matches[2]
            Action = $matches[3]
        }
    } | Group-Object Action -NoElement | Sort-Object Count -Descending
```

**Expected pattern:**
```
Action      Count
------      -----
HOLD        25
TIGHTEN_STOP 3
CLOSE_NOW   0
```

---

## Test Coverage Check

```powershell
# Make sure all 24 tests still pass
$results = Invoke-Pester -Path './tests/mentor_review.Tests.ps1' -PassThru

Write-Host "Total: $($results.TotalCount)"
Write-Host "Passed: $($results.PassedCount)"
Write-Host "Failed: $($results.FailedCount)"

# Show any failures
if ($results.FailedCount -gt 0) {
    $results.TestResult | Where-Object { -not $_.Passed } | ForEach-Object {
        Write-Host "FAILED: $($_.Name)" -ForegroundColor Red
        Write-Host "  $($_.FailureMessage)" -ForegroundColor Red
    }
}
```

---

## Rollback if Needed

```powershell
# Option 1: Disable Layer 2 in scan_master.ps1
# Comment out line ~545:
# # try { Update-MentorReview } catch { ... }

# Option 2: Disable all trailing (Layer 1+2)
.\scripts\scan_master.ps1 -SkipTrailing

# Option 3: Restore from git (if committed)
git checkout -- ./agents/lib_mentor_reflection.ps1
git checkout -- ./scripts/scan_master.ps1
```

---

## When to Contact Support

If after trying these fixes:
- 24/24 tests still pass ✓
- Functions load correctly ✓
- But behavior unexpected during paper run

Then:
1. Save logs + position journal
2. Note exact behavior (e.g., "stopped 2 winners in 24h")
3. Describe expected behavior
4. Share for detailed analysis

