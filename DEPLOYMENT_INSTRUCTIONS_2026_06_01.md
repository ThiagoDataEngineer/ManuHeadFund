# 🚀 Deployment Instructions - Supabase Integration

**Date:** June 1, 2026  
**Status:** Ready for Deployment  
**Estimated Time:** 15 minutes

---

## Prerequisites

- [ ] Supabase account created
- [ ] Supabase project created
- [ ] Service key generated
- [ ] Project URL obtained
- [ ] GitHub repository access
- [ ] PowerShell 5.0+ installed locally

---

## Step 1: Get Supabase Credentials

### 1.1 Get Project URL
1. Go to [Supabase Dashboard](https://app.supabase.com)
2. Select your project
3. Click "Settings" → "API"
4. Copy the **Project URL** (looks like: `https://xxxxx.supabase.co`)

### 1.2 Get Service Key
1. In the same "Settings" → "API" page
2. Under "Project API keys"
3. Copy the **Service Role Key** (starts with `eyJ...`)

⚠️ **IMPORTANT:** Keep these credentials secret! Never commit them to GitHub.

---

## Step 2: Set GitHub Secrets

### 2.1 Add SUPABASE_URL
1. Go to GitHub repository
2. Settings → Secrets and variables → Actions
3. Click "New repository secret"
4. Name: `SUPABASE_URL`
5. Value: Paste the Project URL from Step 1.1
6. Click "Add secret"

### 2.2 Add SUPABASE_SERVICE_KEY
1. Click "New repository secret" again
2. Name: `SUPABASE_SERVICE_KEY`
3. Value: Paste the Service Key from Step 1.2
4. Click "Add secret"

✅ Verify both secrets are created in the Secrets list

---

## Step 3: Initialize Supabase Schema (Local)

### 3.1 Set Environment Variables
```powershell
# Open PowerShell and set environment variables
$env:SUPABASE_URL = "https://xxxxx.supabase.co"
$env:SUPABASE_SERVICE_KEY = "eyJ..."
```

### 3.2 Run Schema Initialization
```powershell
cd "c:\Users\thiag\Coinex_AI_USER_API"
.\scripts\init_supabase_schema.ps1
```

**Expected Output:**
```
Creating manuheadfund schema...
✓ SQL executed successfully
Creating fqs_registry table...
✓ SQL executed successfully
Creating tori_proximity table...
✓ SQL executed successfully
...
✅ Schema initialization complete!
Tables created: fqs_registry, tori_proximity, alpha_history, beta_history, drawdown_history, regime_state, dsr_global
```

### 3.3 Verify Schema in Supabase
1. Go to Supabase Dashboard
2. Click "SQL Editor"
3. Run: `SELECT table_name FROM information_schema.tables WHERE table_schema = 'manuheadfund';`
4. Should see 7 tables listed

---

## Step 4: Migrate Data (Local)

### 4.1 Run Data Migration
```powershell
.\scripts\migrate_json_to_supabase.ps1
```

**Expected Output:**
```
Migrating FQS Registry...
✓ Migrated 50 FQS records
Migrating TORI Proximity...
✓ Migrated 12 TORI records
Migrating Alpha History...
✓ Migrated 14 Alpha records
Migrating Beta History...
✓ Migrated 14 Beta records
Migrating Drawdown History...
✓ Migrated 14 Drawdown records
Migrating Regime State...
✓ Migrated 1 Regime records
Migrating DSR Global...
✓ Migrated 50 DSR records

✅ Migration complete!
Total records migrated: 155
Tables processed: 7
```

### 4.2 Verify Data in Supabase
1. Go to Supabase Dashboard
2. Click "Table Editor"
3. Select each table and verify data is present:
   - `manuheadfund.fqs_registry` - Should have 50+ rows
   - `manuheadfund.tori_proximity` - Should have 12+ rows
   - `manuheadfund.alpha_history` - Should have 14+ rows
   - `manuheadfund.beta_history` - Should have 14+ rows
   - `manuheadfund.drawdown_history` - Should have 14+ rows
   - `manuheadfund.regime_state` - Should have 1 row
   - `manuheadfund.dsr_global` - Should have 50+ rows

---

## Step 5: Run Tests (Local)

### 5.1 Run All Tests
```powershell
Invoke-Pester tests/supabase_schema_init.Tests.ps1, tests/supabase_data_migration.Tests.ps1 -PassThru
```

**Expected Output:**
```
Tests completed in X.XXs
Passed: 41
Failed: 0
Skipped: 0
```

### 5.2 If Tests Fail
1. Check Supabase connection: `$env:SUPABASE_URL` and `$env:SUPABASE_SERVICE_KEY`
2. Verify schema was created: Check Supabase Dashboard
3. Verify data was migrated: Check table row counts
4. Run individual test: `Invoke-Pester tests/supabase_schema_init.Tests.ps1 -Verbose`

---

## Step 6: Update GitHub Actions

### 6.1 Update trading-pipeline.yml
Edit `.github/workflows/trading-pipeline.yml` and add environment variables:

```yaml
name: Trading Pipeline

on:
  schedule:
    - cron: '*/15 * * * *'  # Every 15 minutes
  workflow_dispatch:

env:
  SUPABASE_URL: ${{ secrets.SUPABASE_URL }}
  SUPABASE_SERVICE_KEY: ${{ secrets.SUPABASE_SERVICE_KEY }}

jobs:
  trading:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run Trading Pipeline
        run: |
          powershell -Command ".\scripts\scan_master.ps1"
```

### 6.2 Commit and Push
```powershell
git add .github/workflows/trading-pipeline.yml
git commit -m "chore: Add Supabase environment variables to GitHub Actions"
git push origin main
```

---

## Step 7: Monitor First Cycle

### 7.1 Wait for Next Scheduled Run
- GitHub Actions runs every 15 minutes
- Or manually trigger: Go to Actions → Trading Pipeline → Run workflow

### 7.2 Check GitHub Actions Logs
1. Go to GitHub repository
2. Click "Actions"
3. Click "Trading Pipeline"
4. Click the latest run
5. Expand "Run Trading Pipeline" step
6. Look for:
   - ✅ No errors
   - ✅ Data loaded from Supabase
   - ✅ Trades executed (or ABORTAR with valid reasons)

### 7.3 Check Local Logs
```powershell
Get-Content "c:\Users\thiag\Coinex_AI_USER_API\logs\master_*.log" -Tail 50
```

Look for:
- ✅ `[INFO] Ciclo concluido` - Cycle completed
- ✅ `[TRADE] MARKET: EXECUTAR` - Trade executed
- ❌ `[ERROR]` - Any errors

### 7.4 Expected Results
After first cycle, you should see:
- Trades being evaluated (not just ABORTAR)
- Some trades executing (EXECUTAR status)
- Data gates satisfied (FQS, TORI, ALPHA_HIST, DRAWDOWN all present)

---

## Step 8: Troubleshooting

### Issue: "SUPABASE_URL environment variable not set"
**Solution:**
```powershell
# Set environment variables
$env:SUPABASE_URL = "https://xxxxx.supabase.co"
$env:SUPABASE_SERVICE_KEY = "eyJ..."

# Verify
Write-Host $env:SUPABASE_URL
Write-Host $env:SUPABASE_SERVICE_KEY
```

### Issue: "Connection refused" or "Network error"
**Solution:**
1. Verify Supabase project is active
2. Check internet connection
3. Verify Project URL is correct (no typos)
4. Check if Supabase is experiencing outages

### Issue: "Table does not exist"
**Solution:**
1. Run schema initialization again: `.\scripts\init_supabase_schema.ps1`
2. Verify tables in Supabase Dashboard
3. Check schema name is `manuheadfund`

### Issue: "No data in tables"
**Solution:**
1. Run data migration again: `.\scripts\migrate_json_to_supabase.ps1`
2. Verify JSON files exist in `journal/` directory
3. Check migration logs for errors

### Issue: Tests failing
**Solution:**
1. Run tests with verbose output: `Invoke-Pester tests/supabase_schema_init.Tests.ps1 -Verbose`
2. Check specific test failure
3. Verify Supabase connection
4. Check schema and data in Supabase Dashboard

### Issue: Trades still not executing
**Solution:**
1. Check mentor_agent.ps1 logs for specific ABORTAR reasons
2. Verify all data gates are satisfied (FQS, TORI, ALPHA_HIST, DRAWDOWN)
3. Check if data in Supabase is complete and recent
4. Verify regime and phase are correct

---

## Step 9: Rollback (If Needed)

### 9.1 Disable Supabase (Keep Local JSON)
```powershell
# Unset environment variables
$env:SUPABASE_URL = ""
$env:SUPABASE_SERVICE_KEY = ""

# System will automatically fallback to local JSON files
```

### 9.2 Revert GitHub Actions
```powershell
git revert HEAD  # Revert last commit
git push origin main
```

### 9.3 Delete Supabase Tables (Optional)
```sql
DROP SCHEMA IF EXISTS manuheadfund CASCADE;
```

---

## Step 10: Verification Checklist

- [ ] Supabase credentials obtained
- [ ] GitHub Secrets created (SUPABASE_URL, SUPABASE_SERVICE_KEY)
- [ ] Schema initialized (7 tables created)
- [ ] Data migrated (155+ records)
- [ ] All tests passing (41/41)
- [ ] GitHub Actions updated with env vars
- [ ] First cycle monitored
- [ ] Trades executing (or valid ABORTAR reasons)
- [ ] Logs show no errors
- [ ] System stable for 24 hours

---

## Success Indicators

✅ **Schema Created**
- 7 tables visible in Supabase Dashboard
- All tables have correct columns and indexes

✅ **Data Migrated**
- 155+ records in Supabase tables
- Data matches local JSON files

✅ **Tests Passing**
- 41/41 tests passing
- No errors or warnings

✅ **GitHub Actions Running**
- Workflow runs every 15 minutes
- No errors in logs
- Environment variables accessible

✅ **Trades Executing**
- First trade within 15 minutes of next cycle
- Logs show trade execution
- No data gate failures

---

## Support

If you encounter issues:

1. **Check Logs**
   - Local: `logs/master_*.log`
   - GitHub: Actions → Trading Pipeline → Run logs

2. **Verify Configuration**
   - Supabase credentials correct
   - GitHub Secrets set
   - Environment variables accessible

3. **Run Tests**
   - `Invoke-Pester tests/supabase_*.Tests.ps1`
   - Check specific test failures

4. **Check Supabase**
   - Dashboard → Table Editor
   - Verify tables and data exist
   - Check for any errors

5. **Fallback to Local JSON**
   - Unset environment variables
   - System automatically uses local JSON files

---

## Timeline

| Step | Duration | Status |
|------|----------|--------|
| Get Credentials | 5 min | ⏳ |
| Set GitHub Secrets | 2 min | ⏳ |
| Initialize Schema | 3 min | ⏳ |
| Migrate Data | 2 min | ⏳ |
| Run Tests | 2 min | ⏳ |
| Update GitHub Actions | 2 min | ⏳ |
| Monitor First Cycle | 15 min | ⏳ |
| **Total** | **31 min** | **⏳** |

---

## Next Steps After Deployment

1. Monitor for 24 hours
2. Verify trades are executing consistently
3. Check data freshness in Supabase
4. Set up alerts for failures
5. Document any issues
6. Plan for data retention/cleanup

---

**Ready to Deploy!** 🚀

Follow these steps in order and you should have the system running with Supabase integration within 30 minutes.

If you have any questions or issues, refer to the troubleshooting section or check the logs.

Good luck! 🎯
