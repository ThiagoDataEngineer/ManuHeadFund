# Data Sync Strategy - ManuHeadFund Trading System
**Date**: 2026-06-01  
**Status**: PLANNING → IMPLEMENTATION  
**Problem**: 0 trades executing due to data fragmentation between GitHub Actions and local

---

## Current Problem

### Symptoms
- ✅ System running (3+ cycles completed)
- ✅ No syntax errors
- ❌ **0 trades EXECUTED** (all ABORTAR or CANCELADO)
- ❌ Data files exist locally but NOT synchronized with GitHub

### Root Cause
Data is stored in JSON files that are:
1. **Local-only**: `journal/*.json` files not synced to GitHub
2. **GitHub Actions-only**: Files created in cloud but not pulled locally
3. **Fragmented**: Different data sources (coin_registry, tier_a_drawdown, tori_proximity, beta_vs_btc, etc.)
4. **Stale**: No real-time updates between cloud and local

### Why Trades Are Rejected
Logs show gates failing:
- `FQS indisponível` - Pair not in coin_registry.json
- `TORI ABSENT` - Pair not in tori_proximity_state.json
- `ALPHA_HIST ABSENT` - Pair not in alpha_hist.json
- `DRAWDOWN ABSENT` - Pair not in tier_a_drawdown_*.json
- `BETA ABSENT` - Pair not in beta_vs_btc.json

---

## Solution: Supabase as Single Source of Truth

### Architecture
```
┌─────────────────────────────────────────────────────────┐
│                    SUPABASE (Cloud)                     │
│  ┌──────────────────────────────────────────────────┐   │
│  │  manuheadfund schema                             │   │
│  │  ├─ fqs_registry (50+ pairs)                     │   │
│  │  ├─ tori_proximity (12+ pairs)                   │   │
│  │  ├─ alpha_history (14+ pairs)                    │   │
│  │  ├─ beta_history (100+ pairs)                    │   │
│  │  ├─ drawdown_history (4+ pairs)                  │   │
│  │  ├─ regime_state (1 row)                         │   │
│  │  └─ dsr_global (per-market performance)          │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
         ↑                                    ↑
         │ Read (state_store)                 │ Write (GitHub Actions)
         │                                    │
    ┌────────────────┐              ┌────────────────┐
    │  Local App     │              │ GitHub Actions │
    │  (scan_master) │              │ (cron jobs)    │
    │  (orchestrator)│              │ (24/7)         │
    └────────────────┘              └────────────────┘
```

### Benefits
- ✅ **Single source of truth**: All data in Supabase
- ✅ **Real-time sync**: No file sync delays
- ✅ **Cloud + Local**: Works offline (fallback to local JSON)
- ✅ **Scalable**: Supports 1000+ pairs
- ✅ **Audit trail**: created_at, updated_at timestamps
- ✅ **RLS security**: Service role (GitHub) vs Anon (local)

---

## Implementation Plan

### Phase 1: Schema Setup (TODAY)
**Files created**:
- `SUPABASE_SCHEMA_SETUP.md` - SQL schema definition
- `scripts/init_supabase_schema.ps1` - Initialization script

**Action**:
```powershell
# Set environment variables
$env:SUPABASE_URL = "https://your-project.supabase.co"
$env:SUPABASE_SERVICE_KEY = "eyJhbGc..."  # Service role key
$env:SUPABASE_PROJECT_REF = "abc123"
$env:SUPABASE_PAT = "sbp_xxx"  # Personal access token

# Run initialization
.\scripts\init_supabase_schema.ps1
```

### Phase 2: Data Migration (NEXT)
**Migrate from JSON to Supabase**:
1. Read `coin_registry.json` → Insert into `fqs_registry`
2. Read `tori_proximity_state.json` → Insert into `tori_proximity`
3. Read `alpha_hist.json` → Insert into `alpha_history`
4. Read `beta_vs_btc.json` → Insert into `beta_history`
5. Read `tier_a_drawdown_*.json` → Insert into `drawdown_history`
6. Read `regime_state.json` → Insert into `regime_state`
7. Read `dsr_global.json` → Insert into `dsr_global`

**Script**: `scripts/migrate_json_to_supabase.ps1` (to be created)

### Phase 3: Code Updates (AFTER MIGRATION)
**Update PowerShell code**:
1. Modify `Build-MentorFullContext` to read from Supabase
2. Update `Get-FundamentalScore` to use state_store
3. Update `Get-ToriProximityForMarket` to use state_store
4. Update `Get-ATHDrawdown` to use state_store
5. Update `Get-BetaForMarket` to use state_store

**Key change**: Use `Get-StateRecords` instead of `Get-Content *.json`

### Phase 4: GitHub Actions Updates (AFTER CODE)
**Update workflow jobs**:
1. `initialize-data` job → Write to Supabase instead of JSON
2. `capital-snapshot` job → Already uses state_store ✓
3. `layers-review` jobs → Already use state_store ✓
4. Other jobs → Update to write to Supabase

---

## Current Data Files → Supabase Tables

| JSON File | Supabase Table | Pairs | Status |
|-----------|----------------|-------|--------|
| `coin_registry.json` | `fqs_registry` | 50+ | ✓ Ready |
| `tori_proximity_state.json` | `tori_proximity` | 12 | ✓ Ready |
| `alpha_hist.json` | `alpha_history` | 14 | ✓ Ready |
| `beta_vs_btc.json` | `beta_history` | 100+ | ✓ Ready |
| `tier_a_drawdown_*.json` | `drawdown_history` | 4+ | ✓ Ready |
| `regime_state.json` | `regime_state` | 1 | ✓ Ready |
| `dsr_global.json` | `dsr_global` | Per-market | ✓ Ready |

---

## Why This Solves the Problem

### Before (Current)
```
GitHub Actions creates JSON → Not synced to local
Local reads stale JSON → Gates fail → 0 trades
```

### After (Supabase)
```
GitHub Actions writes to Supabase → Real-time
Local reads from Supabase → Fresh data → Gates pass → Trades execute
```

---

## Timeline

| Phase | Task | Duration | Start | End |
|-------|------|----------|-------|-----|
| 1 | Schema setup | 5 min | Now | 16:10 |
| 2 | Data migration | 10 min | 16:10 | 16:20 |
| 3 | Code updates | 30 min | 16:20 | 16:50 |
| 4 | GitHub Actions | 15 min | 16:50 | 17:05 |
| 5 | Testing | 10 min | 17:05 | 17:15 |
| **Total** | | **70 min** | | |

---

## Success Criteria

✅ **Phase 1**: Schema created in Supabase  
✅ **Phase 2**: All data migrated from JSON to Supabase  
✅ **Phase 3**: Code reads from Supabase (fallback to JSON)  
✅ **Phase 4**: GitHub Actions writes to Supabase  
✅ **Phase 5**: First trade EXECUTES (not ABORTAR)  

---

## Rollback Plan

If issues occur:
1. Keep JSON files as fallback
2. Update code to try Supabase first, then JSON
3. No data loss (both sources maintained)
4. Can revert to JSON-only if needed

---

## Next Steps

1. **Confirm Supabase credentials** in environment
2. **Run schema initialization**: `.\scripts\init_supabase_schema.ps1`
3. **Create migration script**: `scripts/migrate_json_to_supabase.ps1`
4. **Update PowerShell code** to use state_store
5. **Test with one pair** (BTCUSDT)
6. **Monitor logs** for successful trade execution

---

## Questions?

- **Why Supabase?** Already integrated via `lib_state_store.ps1`
- **What about offline?** Fallback to local JSON files
- **Cost?** Free tier supports 500K rows (plenty for 1000+ pairs)
- **Security?** RLS policies + Service role for GitHub Actions
