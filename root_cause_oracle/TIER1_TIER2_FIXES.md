# Tier 1 + Tier 2 Fixes Implementation Guide

**Objective:** Enable autonomous 24/7 profitable trading  
**Status:** ✅ READY TO APPLY  
**Total time:** ~3.5h (Tier 1: 2h + Tier 2: 1.5h)

---

## TIER 1 FIXES (CRITICAL — 2h)

### Fix 1: Create Missing Tables (Bug #6, #7) — 30min

**File:** `root_cause_oracle/SETUP_AUTONOMOUS_FIXES.sql`  
**Status:** ✅ CREATED

**What to do:**
1. Run SQL script against Supabase:
```bash
# Via psql or Supabase CLI:
psql -U postgres -h db.supabaseproject.co -d postgres < root_cause_oracle/SETUP_AUTONOMOUS_FIXES.sql
```

2. Verify tables exist:
```bash
SELECT table_name FROM information_schema.tables WHERE table_schema='public' 
AND table_name IN ('capital_context', 'cron_state');
# Expected: 2 rows
```

**Impact:** Bug #6, #7 FIXED ✅

---

### Fix 2: Cache Collision — Add Direction Key (Bug #8) — 30min

**File:** `agents/lib_gem_decision_cache.ps1`

**Current code (around line 80-100):**
```powershell
function Get-CachedDecision {
    param([string]$Market)
    $cacheKey = "MARKET:$Market"  # ← PROBLEM: no direction
    return $script:DecisionCache[$cacheKey]
}

function Set-CachedDecision {
    param([string]$Market, [PSCustomObject]$Decision)
    $cacheKey = "MARKET:$Market"  # ← Same key = collision
    $script:DecisionCache[$cacheKey] = $Decision
}
```

**Fix:**
```powershell
function Get-CachedDecision {
    param([string]$Market, [string]$Direction)
    $cacheKey = "MARKET:$Market|DIR:$Direction"  # ← NOW UNIQUE
    return $script:DecisionCache[$cacheKey]
}

function Set-CachedDecision {
    param([string]$Market, [string]$Direction, [PSCustomObject]$Decision)
    $cacheKey = "MARKET:$Market|DIR:$Direction"  # ← Direction included
    $script:DecisionCache[$cacheKey] = $Decision
}

# Update all callers to pass $Direction parameter:
# OLD: Get-CachedDecision -Market $market
# NEW: Get-CachedDecision -Market $market -Direction $direction
```

**Validation:**
```powershell
# Test that XEMUSDT|LONG and XEMUSDT|SHORT have different cache entries
$cache1 = Set-CachedDecision -Market "XEMUSDT" -Direction "LONG" -Decision @{score=80}
$cache2 = Set-CachedDecision -Market "XEMUSDT" -Direction "SHORT" -Decision @{score=60}
# Expected: $cache1.score = 80, $cache2.score = 60 (NOT overwritten)
```

**Impact:** Bug #8 FIXED ✅

---

### Fix 3: Shape Mismatch — Unify Position Schema (Bug #4) — 45min

**File:** `agents/lib_position_sync_realtime.ps1` (around line 100-150 where upsert happens)

**Problem:** Writer (lib_trailing) uses `{pk_id, market, side, entry}` but Reader (position_watcher) uses `{id, symbol, direction, entry_time}` = schema conflict on Supabase upsert

**Fix:**

In the `Sync-PositionsFromCoinEx` function, normalize ALL position objects to:
```powershell
[PSCustomObject]@{
    id                 = [string]$position.position_id ?? $position.id  # Unified ID
    symbol             = [string]$position.market ?? $position.ccy     # Unified symbol
    direction          = [string]$position.side ?? "SPOT"              # Normalized direction
    entry_time         = [datetime]$position.open_timestamp            # When opened
    entry_price        = [double]$position.avg_entry_price             # Entry price
    quantity           = [double]$position.quantity                     # Current qty
    pnl_usd            = [double]$position.unrealised_value             # Unrealized PnL
    pnl_pct            = [double]($position.unrealised_value / $position.margin * 100)  # %
    status             = "open"                                         # Status
    leverage           = [double]$position.leverage ?? 1                # Leverage
    entry_source       = "position_sync_realtime"                       # Data source
    synced_at          = Get-Date                                       # When synced
}
```

**When upserting to Supabase:**
```powershell
# BEFORE (broken):
$data = @{
    pk_id = $position.position_id   # Different field names
    market = $position.market
    side = $position.side
    entry = $position.open_timestamp
}

# AFTER (unified):
$data = @{
    id = $normalizedPosition.id              # Use unified schema
    symbol = $normalizedPosition.symbol
    direction = $normalizedPosition.direction
    entry_time = $normalizedPosition.entry_time
    entry_price = $normalizedPosition.entry_price
    # ... rest of fields
}

Invoke-SupabaseUpsert -Table "open_positions" -Data $data -Key "id"
# Expected: code=0, no PGRST400 conflicts
```

**Validation:**
```powershell
# Manually check Supabase:
SELECT COUNT(*) FROM open_positions WHERE direction IN ('LONG', 'SHORT', 'SPOT');
# Expected: All positions present, no duplicates
```

**Impact:** Bug #4 FIXED ✅

---

## TIER 2 FIXES (HIGH — 1.5h)

### Fix 4: Direction Property — Read + Use Correctly (Bug #3) — 45min

**File:** `agents/gem_executor.ps1` (around line 200-250 where trade is placed)

**Problem:**
```powershell
$gem.direction = "SHORT"  # Set
# Later...
if ($gem.direction) {     # Read ← Always fails, property ignored
    Write-Log "Direction: $($gem.direction)"  # Empty!
}
```

**Fix:**

When reading Gem object properties, use `PSObject.Properties`:
```powershell
# Read direction CORRECTLY:
$direction = $gem.PSObject.Properties["direction"].Value ?? $gem.direction

# Validate it
if ($direction -notmatch "^(LONG|SHORT)$") {
    Write-Log "ERROR: Invalid direction '$direction', skipping entry"
    return $false
}

# Use it when placing trade:
$tradeData = @{
    market = $gem.market
    direction = $direction      # ← Now correct
    entry_price = $gem.entry_price
    quantity = $gem.quantity
    # ...
}

# Log it for audit:
Write-Log "Placing trade: $market $direction @ $entry_price (confidence: $($gem.confidence)%)"
```

**Validation:**
```powershell
# Manually test:
$testGem = [PSCustomObject]@{
    market = "BTCUSDT"
    direction = "LONG"
    confidence = 75
}

$dir = $testGem.PSObject.Properties["direction"].Value
Write-Host "Direction read: $dir"  # Expected: "LONG"
```

**Impact:** Bug #3 FIXED ✅

---

### Fix 5: Config Fallback — Ensure Env Vars Never Empty (Bug #10) — 30min

**File:** `config/config.template.ps1` (or `setup_credentials_local.ps1`)

**Problem:**
```powershell
$global:COINEX_BASE_URL = ""  # ← Empty in production
# Later: API calls fail silently
```

**Fix:**

Ensure all environment variables have non-empty fallbacks:
```powershell
# BEFORE (broken):
$global:COINEX_BASE_URL = ""
$global:COINEX_ACCESS_ID = ""
$global:COINEX_SECRET_KEY = ""

# AFTER (with fallbacks):
$global:COINEX_BASE_URL = $env:COINEX_BASE_URL ?? "https://api.coinex.com"
$global:COINEX_ACCESS_ID = $env:COINEX_ACCESS_ID ?? "ERROR_NO_CREDENTIALS_SET"
$global:COINEX_SECRET_KEY = $env:COINEX_SECRET_KEY ?? "ERROR_NO_CREDENTIALS_SET"
$global:SUPABASE_URL = $env:SUPABASE_URL ?? "ERROR_NO_SUPABASE_URL"
$global:SUPABASE_ANON_KEY = $env:SUPABASE_ANON_KEY ?? "ERROR_NO_SUPABASE_KEY"

# Add startup validation:
function Test-CredentialsLoaded {
    $missing = @()
    if ($global:COINEX_BASE_URL -match "^ERROR") { $missing += "COINEX_BASE_URL" }
    if ($global:COINEX_ACCESS_ID -match "^ERROR") { $missing += "COINEX_ACCESS_ID" }
    if ($global:COINEX_SECRET_KEY -match "^ERROR") { $missing += "COINEX_SECRET_KEY" }
    
    if ($missing.Count -gt 0) {
        Write-Error "Missing credentials: $($missing -join ', ')"
        return $false
    }
    return $true
}

# Call on startup:
if (-not (Test-CredentialsLoaded)) {
    exit 1  # Fail-closed
}
```

**Validation:**
```powershell
# Test credentials loading:
. .\config\config.template.ps1
Test-CredentialsLoaded  # Expected: $true if env vars set, $false if missing
```

**Impact:** Bug #10 FIXED ✅

---

## SUMMARY TABLE

| Fix | Bug | Time | File | Status |
|-----|-----|------|------|--------|
| 1 | #6, #7 | 30min | SETUP_AUTONOMOUS_FIXES.sql | ✅ CREATED |
| 2 | #8 | 30min | lib_gem_decision_cache.ps1 | ⏳ TO APPLY |
| 3 | #4 | 45min | lib_position_sync_realtime.ps1 | ⏳ TO APPLY |
| 4 | #3 | 45min | gem_executor.ps1 | ⏳ TO APPLY |
| 5 | #10 | 30min | config/config.template.ps1 | ⏳ TO APPLY |

**Total: ~3.5h for Tier 1 + Tier 2**

---

## APPLY ORDER

1. ✅ **SQL:** Run SETUP_AUTONOMOUS_FIXES.sql
2. ⏳ **Fix 2:** Apply cache collision fix
3. ⏳ **Fix 3:** Apply schema unification fix
4. ⏳ **Fix 4:** Apply direction property fix
5. ⏳ **Fix 5:** Apply config fallback fix
6. ✅ **Test:** Verify all fixes work together
7. ✅ **Commit:** All fixes in one commit
8. ✅ **Push:** To main (GitHub Actions auto-deploys)

---

## TESTING CHECKLIST

- [ ] SQL tables created + accessible
- [ ] Cache works with direction key
- [ ] Positions sync without 400 errors
- [ ] Trades placed with correct direction
- [ ] Credentials loaded with fallbacks
- [ ] 10+ trades entered + exited correctly
- [ ] Win rate 45%+ maintained
- [ ] No logs with ERROR/CRITICAL in 1h
- [ ] System ready for 24/7 autonomous

---

**Next Step:** User confirms → I apply all fixes → Test → Commit → Ready for weekend 🚀
