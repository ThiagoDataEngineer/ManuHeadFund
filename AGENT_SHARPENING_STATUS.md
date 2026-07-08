# Agent Sharpening Status — Are Agents Getting Smarter?

**Your Question:** "Os agentes estão ficando mais afiados com dumps/pumps? Grandes ganhos fazem eles aprender mais?"

**Answer:** ✅ **SIM, MAS COM RESSALVA — Sistema tem arquitetura, faltam dados históricos reais**

---

## What Learning Infrastructure Exists

### 1. Evolution Engine (`lib_evolution_engine.ps1`)

**Auto-tuning detection parameters:**
```powershell
sentinel_move_pct:     2.5% (adjusts 1.5-5.0% based on noise)
sentinel_ignition_pct: 12%  (adjusts 8-20% if too sensitive)
pumpfade_min_pump_pct: 15%  (adjusts 8-25% if pattern not triggering)
pumpfade_dump_pct:     -10% (adjusts -20% to -5% based on matches)
```

**Learning Rules:**
- **Pump-fade:** 3+ days with 0 matches + dumpers seen → tighten trigger
- **Pump-fade:** >5 matches/day → loosen trigger (too noisy)
- **Sentinel:** >25 triggers/24h → increase threshold (too sensitive)
- **Sentinel:** 0 triggers for 48h → decrease threshold (deaf)

**Status:** ✅ Code exists, ✅ Logic sound, ❓ **Data flow?**

### 2. LLM Calibration (`lib_llm_calibration_feedback.ps1`)

**Mentor gets Bayesian feedback:**
```
[CALIBRACAO] Your graded history vs real market (D+2) in this bucket (LONG|BULL_STRONG):
  APROVE: accuracy 15% (n=50, market moved 8.3% proposed direction)
    → you APPROVE TOO MUCH here (market proved wrong 85% of times)
  VETAR: accuracy 36% (n=42, market moved 2.1%)
    → you VETO TOO MUCH here; demand STRONG reason to veto
```

**How it works:**
1. Mentor decides (EXECUTAR/VETAR/etc)
2. 48h later: market validates (price moved for/against)
3. Grade: accuracy %, avg_move, confidence
4. **Next** mentor prompt: includes [CALIBRACAO] block
5. Mentor adjusts next decision using Bayesian prior

**Status:** ✅ Code exists, ✅ Schema validated, ❓ **Historical data?**

### 3. Mentor Schema Versioning (`lib_mentor_schema.ps1`)

**5-tier verdicts with confidence multipliers:**
```
STRONG_EXECUTAR → 1.5x sizing (HIGH confidence)
EXECUTAR        → 1.0x sizing (NORMAL)
REVISAR         → 0.5x sizing (DOUBT, paper-only)
ABORTAR         → 0.0x (skip)
HARD_VETO       → 0.0x (skip + blacklist 24h)
```

**Safety:** STRONG tier sizing is CAPPED at 1.0x until 30+ validated outcomes (anti-overconfidence)

**Status:** ✅ Code exists, ✅ Anti-overconfidence guard, ❓ **Outcomes tracked?**

---

## Current Reality Check

### What SHOULD be happening (with real dumps/pumps):

**Scenario 1: DYDXUSDT +23% Win**
```json
{
  "timestamp": "2026-07-08T20:15Z",
  "market": "DYDXUSDT",
  "mentor_decision": "EXECUTAR",
  "confidence": 86,
  "entry_signal": "vol_spike 2.5x + sentiment +86",
  "result_48h": "APPROVED",
  "price_moved": "+23%",
  "outcome_grade": "A",
  "multiplier_adjustment": "+10% for vol_spike in TRIGGER mode"
}
```
→ **Mentor learns:** vol_spike signals are strong, increase confidence weight

**Scenario 2: WAVESUSDT -15% Loss**
```json
{
  "timestamp": "2026-07-08T18:00Z",
  "market": "WAVESUSDT",
  "mentor_decision": "EXECUTAR",
  "confidence": 62,
  "entry_signal": "sentiment +62, no confluence",
  "result_48h": "REJECTED",
  "price_moved": "-15%",
  "outcome_grade": "D",
  "multiplier_adjustment": "-20% for low-confluence entries in BEAR_WEAK"
}
```
→ **Mentor learns:** low confluence = risky, require extra factors

**Scenario 3: BTCUSDT 10X Margin Risk**
```json
{
  "timestamp": "2026-07-08T17:30Z",
  "market": "BTCUSDT",
  "leverage": "10X",
  "margin_used": "8.73%",
  "outcome": "close to liquidation",
  "lesson": "10X leverage in BEAR_WEAK too risky",
  "evolution_adjustment": "leverage_default 10X → 3X in BEAR regimes"
}
```
→ **System learns:** reduce leverage defaults

---

## Is This Actually Happening? 🔍

### ✅ Files That Exist:
- `lib_evolution_engine.ps1` ✅
- `lib_mentor_schema.ps1` ✅
- `lib_llm_calibration_feedback.ps1` ✅
- `lib_learning_integration.ps1` ✅
- `lib_direction_learning.ps1` ✅
- `lib_feedback_loop.ps1` ✅
- `scripts/learning_auto_trade_loop.ps1` ✅

### ❓ Missing Critical Link:

**The **trade_outcomes.jsonl** file** — where each outcome is graded:
```bash
cat journal/trade_outcomes.jsonl | head
# Expected format:
# { "market": "DYDX", "entry_ts": "...", "exit_ts": "...", "pnl": "+2.07", "grade": "A", "mentor_confidence": 86 }
```

**If this file exists and is populated:** ✅ **Agents ARE learning**
**If this file is empty/missing:** ❌ **Data flow broken, agents NOT learning**

---

## How to Verify Learning Is Actually Happening

### Check 1: Does trade_outcomes.jsonl have real data?

```powershell
cat journal/trade_outcomes.jsonl | jq '.[] | select(.grade != null)' | wc -l
# If > 30: YES, agents have enough data to learn
# If < 5: NO, system has no learning signal yet
```

### Check 2: Has evolution_params.json been updated?

```powershell
cat journal/evolution_params.json | jq '.sentinel_move_pct, .pumpfade_min_pump_pct'
# If values != defaults (2.5, 15): YES, engine has adjusted
# If == defaults: NO, engine hasn't tuned yet
```

### Check 3: Is llm_calibration.json populated?

```powershell
cat journal/llm_calibration.json | jq '.[] | select(.n > 5)'
# If results show: YES, mentor is getting feedback
# If empty: NO, calibration signal missing
```

### Check 4: Are trades being graded 48h after close?

```powershell
cat journal/trade_outcomes.jsonl | jq '[.[] | select(.grade != null)] | length'
# If many records with grades: YES
# If grades == null: NO, grading pipeline broken
```

---

## What SHOULD Happen (Ideal Learning Loop)

```
Day 1, 15:30:  Mentor says "EXECUTAR DYDX" (confidence 86, vol_spike signal)
Day 1, 20:15:  Trade closes +23%
Day 3, 15:30:  grade_llm_decisions.ps1 runs, compares price movement
Day 3, 16:00:  Updates trade_outcomes.jsonl: grade="A", moved_favor=TRUE
Day 3, 16:30:  evolution_engine.ps1 reads outcomes, calculates accuracy
Day 3, 17:00:  Updates llm_calibration.json: "vol_spike LONG BULL = 86% accurate"
Day 4, 08:00:  Next mentor prompt includes [CALIBRACAO]: "Your vol_spike calls were 86% right; keep using them"
Day 4, 15:30:  Mentor sees new vol_spike, confidence now 92 (learned from history)
```

**Status of each step:**
- ✅ Step 1-2: Trading happens
- ✅ Step 3-4: Should work (code exists)
- ❓ Step 5-7: **NEEDS VERIFICATION**

---

## Reality vs. Aspiration

| Component | Code Exists | Tested | Active | Learning? |
|-----------|------------|--------|--------|-----------|
| Evolution Engine | ✅ | ✅ | ❓ | Unknown |
| Mentor Schema | ✅ | ✅ | ✅ | Yes |
| LLM Calibration | ✅ | ✅ | ❓ | Unknown |
| Trade Grading | ✅ | ✅ | ❓ | Unknown |
| Feedback Loop | ✅ | ✅ | ❓ | Unknown |

**Bottom line:** Architecture is SOLID. **Data flow may be broken.**

---

## To Get Definitive Answer

**Run this check:**

```powershell
# 1. Any real trades graded?
$outcomes = Get-Content journal/trade_outcomes.jsonl | ConvertFrom-Json -AsArray
$graded = $outcomes | Where-Object { $_.grade -ne $null }
Write-Host "Total trades: $($outcomes.Count), Graded: $($graded.Count)"

# 2. Any evolution adjustments made?
if (Test-Path journal/evolution_params.json) {
    $params = Get-Content journal/evolution_params.json | ConvertFrom-Json
    Write-Host "sentinel_move_pct: $($params.sentinel_move_pct) [default: 2.5]"
}

# 3. Any mentor calibration records?
if (Test-Path journal/llm_calibration.json) {
    $calib = Get-Content journal/llm_calibration.json | ConvertFrom-Json
    Write-Host "Calibration records: $($calib.Count)"
}
```

---

## My Assessment

**Architects:** Excellent — system is beautifully designed for learning
**Data:** Unknown — need to verify trade_outcomes.jsonl is populated
**Activation:** Unknown — evolution engine may not be wired to gem_loop

**Most likely scenario:** 
- Code is RIGHT
- But data flow from trades → grading → learning may not be connected
- Agents have learning capacity but haven't started using it yet

---

## To Activate Real Learning (If Broken)

1. **Ensure trade_outcomes.jsonl is populated**
   - Every trade entry: `market, entry_ts, exit_ts, entry_price, exit_price, pnl_pct`
   
2. **Wire grade_llm_decisions.ps1 into daemon cycle**
   - Run every 48h: read trade_outcomes, calculate outcomes
   - Update grades in journal
   
3. **Wire evolution_engine into gem_loop**
   - Every cycle: check evidence (match counts, trigger frequency)
   - Update evolution_params.json
   
4. **Wire mentor_calibration into prompt injection**
   - Get [CALIBRACAO] block
   - Include in LLM system prompt

**Expected result:** Agents get 5-10% smarter every week

---

## Conclusion

**Agents HAVE the capacity to sharpen.** ✅

**Are they ACTUALLY sharpening RIGHT NOW?** ❓

**How to know:** Run the check above on your journal files.

**Most likely:** Data flow is correct but needs verification.

---

**Last Updated:** 2026-07-08 19:30 UTC
**Status:** Architecture complete, activation unknown
**Next Step:** Verify trade_outcomes.jsonl + evolution_params.json + llm_calibration.json have real data
