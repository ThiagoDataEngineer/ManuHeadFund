# 🎯 Multi-Timeframe Gate Implementation Plan

**Date:** 2026-06-08  
**Status:** PLANNING — Ready for Next Session  
**Priority:** HIGH (blocks SHORT detection in bear market)  
**Estimated Time:** 4-6 hours

---

## 📊 PROBLEM STATEMENT

**Current State:** System collects multi-TF data (1min, 5min, 1H, 4H, 1D, 1W) but **does NOT apply multi-TF validation rules**.

**Symptom:** PIPPINUSDT was bloqueado by Tori for "1D downtrend estrutural contra viés de entrada" — but this is **manual LLM analysis**, not **automated gate**.

**Impact:**
- SHORT opportunities in bear market not automatically validated against HTF
- Relies on Tori (LLM) to catch HTF misalignment
- No structured multi-TF confirmation before trade execution
- MCAP limit blocks mid-caps even when setup is perfect

**Goal:** Add **automated multi-timeframe confirmation gate** before gem_executor executes any trade.

---

## 🔍 ROOT CAUSE ANALYSIS

```
┌─ CURRENT FLOW ──────────────────────────────────────────┐
│                                                           │
│  GemAgent collects:                                      │
│  ├─ 1 DAY: 4 candles (vol spike) ✅                      │
│  ├─ 1 HOUR: 24 candles (structure) ✅                    │
│  ├─ 5 MIN: 60 candles (organic) ✅                       │
│  └─ 1 MIN: 60 candles (fingerprint) ✅                   │
│                                                           │
│  MinMax Detector:                                        │
│  └─ Uses closes (timeframe NOT specified) ❌            │
│     └─ Assumes 24h = 1D only                            │
│                                                           │
│  Resolve-BidirectionalDirection:                        │
│  └─ Detects SHORT/LONG zones (no HTF check) ❌          │
│                                                           │
│  gem_executor:                                           │
│  └─ Executes trade (no multi-TF validation) ❌          │
│                                                           │
│  Tori (tech_agent_ai):                                  │
│  └─ Reviews 4H + 1D + 1W (manual analysis) ⚠️           │
│     └─ Blocks if HTF misaligned (not gate, veto)       │
│                                                           │
└─ PROBLEM: DATA collected, LOGIC not enforced ────────────┘
```

---

## 🛠️ SOLUTION DESIGN

### Phase 1: Build Multi-TF Trend Analysis (1-2 hours)

**Create:** `agents/lib_multiframe_analysis.ps1`

```powershell
function Get-TrendDirection {
    param(
        [object[]]$Candles,      # OHLCV candles
        [string]$Timeframe       # "1min", "5min", "1H", "4H", "1D", "1W"
    )
    
    # Returns: "STRONG_UP", "UP", "NEUTRAL", "DOWN", "STRONG_DOWN"
    # Logic:
    # - Compare close vs SMA20 (direction)
    # - Check RSI (overbought/oversold)
    # - Measure trend strength (close - low) / (high - low)
    
    $closes = $Candles | ForEach-Object { [double]$_.close }
    $sma = Get-SimpleMovingAverage $closes 20
    $rsi = Get-RSI $closes 14
    $atr = Get-ATR $Candles 14
    
    # Scoring logic
    $trend = "NEUTRAL"
    if ($closes[-1] -gt $sma) {
        $trend = if ($rsi -gt 60) { "STRONG_UP" } else { "UP" }
    } else {
        $trend = if ($rsi -lt 40) { "STRONG_DOWN" } else { "DOWN" }
    }
    
    return $trend
}

function Get-TrendAlignment {
    param(
        [string]$Trend1D,
        [string]$Trend4H,
        [string]$Trend1H,
        [string]$Direction  # "LONG" or "SHORT"
    )
    
    # Returns: $true if timeframes align with direction, $false otherwise
    # LONG rules:
    #   - 1D must be UP or NEUTRAL (not DOWN)
    #   - 4H must be UP (confirm)
    #   - 1H can be anything (confirmation within sweep)
    # SHORT rules:
    #   - 1D must NOT be UP (neutral or down)
    #   - 4H must NOT be UP (confirm)
    #   - 1H can be anything (confirmation within sweep)
    
    if ($Direction -eq "LONG") {
        return ($Trend1D -ne "STRONG_DOWN" -and $Trend1D -ne "DOWN") -and 
               ($Trend4H -in @("STRONG_UP", "UP"))
    } else {
        # SHORT
        return ($Trend1D -in @("STRONG_DOWN", "DOWN", "NEUTRAL")) -and 
               ($Trend4H -in @("STRONG_DOWN", "DOWN", "NEUTRAL"))
    }
}
```

---

### Phase 2: Add Multi-TF Gate to gem_executor (1-2 hours)

**Location:** `agents/gem_executor.ps1` — Before order execution

```powershell
# Around line 645 (before Invoke-OrderRouted)

# 2026-06: Multi-Timeframe Confirmation Gate
if (-not (Get-Command Get-TrendDirection -ErrorAction SilentlyContinue)) {
    Write-Host "  [WARN] Multi-TF libs not loaded, skipping HTF validation" -ForegroundColor Yellow
} else {
    # Parse candles from Gem object (if available) or fetch fresh
    $candles1D = Get-CoinExCandles -Market $mkt -Period "1day" -Limit 20
    $candles4H = Get-CoinExCandles -Market $mkt -Period "4hour" -Limit 24
    $candles1H = Get-CoinExCandles -Market $mkt -Period "1hour" -Limit 24
    
    # Analyze trends
    $trend1D = Get-TrendDirection -Candles $candles1D -Timeframe "1D"
    $trend4H = Get-TrendDirection -Candles $candles4H -Timeframe "4H"
    $trend1H = Get-TrendDirection -Candles $candles1H -Timeframe "1H"
    
    # Check alignment
    $mhtfOk = Get-TrendAlignment -Trend1D $trend1D -Trend4H $trend4H -Trend1H $trend1H -Direction $direction
    
    Write-Host "  [MULTI-TF] 1D=$trend1D | 4H=$trend4H | 1H=$trend1H | Align=$mhtfOk" -ForegroundColor DarkCyan
    
    if (-not $mhtfOk) {
        Write-Host "  [GEM BLOCKED] Multi-TF confirmation failed" -ForegroundColor Red
        Write-Host "    → 1D trend: $trend1D (expected: UP for LONG, !UP for SHORT)" -ForegroundColor Red
        Write-Host "    → 4H trend: $trend4H (expected: UP for LONG, !UP for SHORT)" -ForegroundColor Red
        try { Send-TelegramAlert -Message "GEM bloqueado: $mkt | Motivo: HTF misalignment ($direction vs $trend1D/$trend4H)" | Out-Null } catch {}
        return [PSCustomObject]@{ blocked = $true; blocked_by = @("multi_timeframe_no_confirm:$trend1D/$trend4H"); market = $mkt }
    }
}
```

---

### Phase 3: Add Helper Library for Candle Fetching (30 min)

**Create:** `agents/lib_candle_fetcher.ps1`

```powershell
function Get-CoinExCandles {
    param(
        [string]$Market,
        [string]$Period = "1day",  # "1min", "5min", "1hour", "4hour", "1day", "1week"
        [int]$Limit = 50
    )
    
    try {
        $endpoint = if ($Market -match "USDT$") { "/v2/spot/kline" } else { "/v2/futures/kline" }
        $url = "$global:COINEX_BASE_URL$endpoint?market=$Market&period=$Period&limit=$Limit"
        
        $r = Invoke-RestMethod -Uri $url -Method GET -ErrorAction Stop
        if ($r.code -ne 0) { return @() }
        
        return $r.data | ForEach-Object {
            [PSCustomObject]@{
                open   = [double]$_.open
                high   = [double]$_.high
                low    = [double]$_.low
                close  = [double]$_.close
                volume = [double]$_.volume
                ts     = $_.created_at
            }
        }
    } catch {
        Write-Host "  [WARN] Failed to fetch candles for $Market/$Period: $_" -ForegroundColor Yellow
        return @()
    }
}
```

---

## 📋 IMPLEMENTATION CHECKLIST

### Phase 1: Trend Analysis (Session Start)
- [ ] Create `lib_multiframe_analysis.ps1`
  - [ ] `Get-TrendDirection()` function
  - [ ] `Get-TrendAlignment()` function
  - [ ] Test with mock data (10 min)
- [ ] Create `lib_candle_fetcher.ps1`
  - [ ] `Get-CoinExCandles()` function
- [ ] Run TDD for trend functions (15 tests)
  - [ ] Test STRONG_UP detection
  - [ ] Test STRONG_DOWN detection
  - [ ] Test NEUTRAL detection
  - [ ] Test LONG alignment rules
  - [ ] Test SHORT alignment rules

### Phase 2: Integration (Mid-session)
- [ ] Update `gem_executor.ps1` (lines ~645)
  - [ ] Add multi-TF check before order
  - [ ] Load trend analysis libs
  - [ ] Handle missing candles gracefully
- [ ] Update `config.ps1` (load new libs)
- [ ] Run 20 integration tests
  - [ ] PIPPIN case (1D downtrend should block)
  - [ ] Normal LONG (1D+4H uptrend should pass)
  - [ ] Normal SHORT (1D+4H downtrend should pass)

### Phase 3: Validation (Session End)
- [ ] Test with live market data
  - [ ] Scan for next GEM
  - [ ] Validate multi-TF check fires
  - [ ] Verify Tori + multi-TF agree
- [ ] Create 5 test cases in `tests/lib_multiframe_analysis.Tests.ps1`
- [ ] Document in README

---

## 🧪 TEST CASES

### Test 1: PIPPIN Case (Historical)
```
Setup:
  - Direction: SHORT
  - 1D trend: STRONG_DOWN (bear downtrend)
  - 4H trend: DOWN
  - 1H trend: UP (local reversal)

Expected: PASS (both 1D and 4H align for SHORT)
```

### Test 2: False LONG Signal
```
Setup:
  - Direction: LONG
  - 1D trend: DOWN (macro bearish)
  - 4H trend: UP (local relief)
  - 1H trend: STRONG_UP

Expected: FAIL (1D must be UP for LONG)
```

### Test 3: Perfect SHORT Setup
```
Setup:
  - Direction: SHORT
  - 1D trend: STRONG_DOWN
  - 4H trend: STRONG_DOWN
  - 1H trend: DOWN

Expected: PASS (all aligned)
```

---

## 📈 EXPECTED IMPROVEMENTS

| Metric | Before | After |
|--------|--------|-------|
| **False positives** | ~15% (Tori veto) | ~5% (gate auto-blocks) |
| **HTF aligned trades** | ~70% (Tori analysis) | ~95% (enforced gate) |
| **PIPPIN case** | BLOCKED (Tori manual) | BLOCKED (auto-gate) ✓ |
| **SHORT in bear** | Manual check | Automated validation |
| **Execution speed** | Slight slowdown (fetch candles) | +200ms per trade |

---

## 🎯 ACCEPTANCE CRITERIA

✅ Multi-TF gate blocks false positives (1D downtrend LONG)  
✅ Multi-TF gate allows valid signals (1D uptrend LONG)  
✅ SHORT validation works in bear market  
✅ Gate is AUTOMATED (not LLM-dependent)  
✅ Tori + multi-TF gate AGREE on PIPPIN case  
✅ 20+ tests passing  
✅ <500ms latency impact on execution  

---

## 📚 REFERENCE IMPLEMENTATION

**Similar systems:**
- Trading View: Higher timeframe confirmation before entry
- Professional traders: "Never trade against HTF trend"
- This system: Tori validates HTF, but not automated

---

## 💡 FOLLOW-ON PHASES (Post-session)

### Phase 4: MCAP Limit Fix (30 min)
- Increase `GEM_MCAP_DISCOVERY` from $2M to $5M
- OR create `GEM_MCAP_SHORT_SPECIAL` tier

### Phase 5: Cascade Confirmation (1-2 hours)
- Enforce: Entry TF + 4H + 1D all confirm
- Cascade levels: 1W veto > 1D gate > 4H confirm > 1H entry

### Phase 6: Optimize Candle Caching (30 min)
- Cache 1D/4H candles for 5 min (reduce API calls)
- Only fetch fresh on entry

---

## 📝 GIT COMMIT STRUCTURE

```
Commit 1: 🧪 Multi-TF Analysis Libraries + TDD (20 tests)
Commit 2: 🔌 Multi-TF Gate Integration in gem_executor
Commit 3: 📊 Documentation + test cases + README update
```

---

## ⏱️ TIMELINE (Next Session)

| Phase | Duration | Status |
|-------|----------|--------|
| 1. Trend Analysis | 1.5h | Planning |
| 2. Integration | 1.5h | Planning |
| 3. Validation | 1h | Planning |
| **TOTAL** | **4h** | **Ready to execute** |

---

**Status:** ✅ **READY FOR NEXT SESSION**  
**Created:** 2026-06-08 16:45 BRT  
**Files to create:** lib_multiframe_analysis.ps1, lib_candle_fetcher.ps1  
**Files to modify:** gem_executor.ps1, config.ps1  

